"""Dodatne funkcionalne provjere i trajni dokazi za dokumentaciju."""
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess

ROOT=Path(__file__).resolve().parents[1]
RESULTS=ROOT/'tests/results'
ARTIFACTS={}


def capture(name,text):
    RESULTS.mkdir(exist_ok=True)
    text=re.sub(r"IDENTIFIED BY PASSWORD '[^']*'","IDENTIFIED BY PASSWORD '[REDACTED]'",text)
    (RESULTS/name).write_text(text.rstrip()+'\n')
    ARTIFACTS[name]=hashlib.sha256((RESULTS/name).read_bytes()).hexdigest()


def manifest(status,started):
    files=sorted(set(ROOT.glob('migrations/*')) | set(ROOT.glob('seed/*')) | set(ROOT.glob('tests/*.py')) | set(ROOT.glob('tests/*.sql')) | set(ROOT.glob('tests/*.sh')) | set(ROOT.glob('reports/*.sql')))
    sources={str(p.relative_to(ROOT)):hashlib.sha256(p.read_bytes()).hexdigest() for p in files if p.is_file()}
    (RESULTS/'manifest.json').write_text(json.dumps({'status':status,'started_utc':started,'finished_utc':datetime.now(timezone.utc).isoformat(),'source_sha256':sources,'artifacts':ARTIFACTS},indent=2)+'\n')


def constraints(h):
    cases=[
        ("UPDATE event SET event_type_id=2147483647 WHERE id=1;",'fk_event_type'),
        ("INSERT INTO event_type(code,name) VALUES ('INVALID','Invalid');",'chk_event_type_code'),
        ("INSERT INTO event_type(code,name) VALUES ('bad-code','Invalid');",'chk_event_type_code'),
        ("INSERT INTO event_type(code,name) VALUES ('concert','Duplicated');",'uq_event_type_code'),
        ("INSERT INTO event_type(code,name) VALUES ('new_type','Koncert');",'uq_event_type_name'),
        ("INSERT INTO event_type(code,name) VALUES ('new_type','   ');",'chk_event_type_name'),
        ("INSERT INTO city(name,time_zone) VALUES ('Invalid','Invalid/Zone');",'Nepoznata vremenska zona'),
        ("UPDATE city SET time_zone='Invalid/Zone' WHERE name='Zagreb';",'Nepoznata vremenska zona'),
        ("UPDATE city SET time_zone='Europe/London' WHERE name='Zagreb';",'Zona grada s postojecim eventima'),
        ("SELECT local_to_utc('2027-01-01','Invalid/Zone');",'Nepoznata vremenska zona'),
    ]
    raw=[]
    for sql,error in cases:
        raw.append(h.db(sql,fail=error))
    raw.append(h.db("INSERT INTO event_type(code,name) VALUES ('newline\n','Invalid');",fail='chk_event_type_code'))
    # Provjeri UUID i u NO_BACKSLASH_ESCAPES nacinu; ne mijenjaj poslovne podatke.
    for mode in ['', 'NO_BACKSLASH_ESCAPES']:
        h.db(f"SET sql_mode='{mode}'; START TRANSACTION; UPDATE buyer SET external_id='01234567-89ab-cdef-0123-456789abcdef' WHERE id=1; ROLLBACK;")
        raw.append(h.db(f"SET sql_mode='{mode}'; UPDATE buyer SET external_id='01234567-89AB-cdef-0123-456789abcdef' WHERE id=1;",fail='chk_buyer_external_id'))
        raw.append(h.db(f"SET sql_mode='{mode}'; UPDATE buyer SET external_id='01234567-89ab-cdef-0123-456789abcde\n' WHERE id=1;",fail='chk_buyer_external_id'))
    assert h.db("SELECT COUNT(*) FROM event_type;")=='9'
    assert h.db("SELECT COLUMN_DEFAULT IS NULL FROM information_schema.COLUMNS WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME='reservation' AND COLUMN_NAME='expires_at';")=='1'
    assert h.db("SELECT COLLATION_NAME FROM information_schema.COLUMNS WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME='ticket' AND COLUMN_NAME='ticket_code';")=='ascii_bin'
    assert h.db("SELECT COUNT(*) FROM information_schema.TABLES WHERE TABLE_SCHEMA=DATABASE() AND TABLE_TYPE='BASE TABLE' AND TABLE_COLLATION<>'utf8mb4_unicode_ci';")=='0'
    capture('constraints.txt','\n'.join(raw)+'\nPASS: 15 odbijenih nevaljanih unosa, UUID u oba SQL nacina, defaults i collation.')


def backup_restore(h):
    result=subprocess.run(h.dc+['exec','-T','db','mariadb-dump','-uroot','-ptime-test-root','--single-transaction','--routines','--triggers','--events','eventhub'],text=True,capture_output=True,check=True)
    dump=result.stdout
    disabled,count=re.subn(r'(EVENT `ev_expire_reservations` ON SCHEDULE[^\n]*) ENABLE DO ',r'\1 DISABLE DO ',dump)
    assert count==1,'Nije prepoznata definicija schedulera u dumpu'
    h.db('CREATE DATABASE eventhub_restore CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;')
    h.db(disabled,database='eventhub_restore')
    tables=h.db("SELECT TABLE_NAME FROM information_schema.TABLES WHERE TABLE_SCHEMA=DATABASE() AND TABLE_TYPE='BASE TABLE' AND TABLE_NAME NOT LIKE 'DATABASECHANGELOG%' ORDER BY TABLE_NAME;").splitlines()
    evidence=['table\trows\tchecksum_equal\tepoch_equal']
    from test_database import COLUMNS
    for table in tables:
        source=h.db(f'SELECT COUNT(*) FROM `{table}`;')
        restored=h.db(f'SELECT COUNT(*) FROM `{table}`;',database='eventhub_restore')
        assert source==restored,table
        checksum=lambda database:h.db(f'CHECKSUM TABLE `{database}`.`{table}` EXTENDED;').split('\t')[-1]
        assert checksum('eventhub')==checksum('eventhub_restore'),table
        for col in COLUMNS.get(table,[]):
            sql=f'SELECT id,UNIX_TIMESTAMP({col}) FROM `{table}` ORDER BY id;'
            assert h.db(sql)==h.db(sql,database='eventhub_restore'),(table,col)
        evidence.append(f'{table}\t{source}\t1\t1')
    for kind,expected in [('ROUTINES',10),('TRIGGERS',21),('VIEWS',7),('EVENTS',1)]:
        field={'ROUTINES':'ROUTINE_SCHEMA','TRIGGERS':'TRIGGER_SCHEMA','VIEWS':'TABLE_SCHEMA','EVENTS':'EVENT_SCHEMA'}[kind]
        assert h.db(f"SELECT COUNT(*) FROM information_schema.{kind} WHERE {field}='eventhub_restore';")==str(expected),(kind,expected)
    assert h.db("SELECT STATUS FROM information_schema.EVENTS WHERE EVENT_SCHEMA='eventhub_restore';")=='DISABLED'
    assert h.db('SELECT * FROM v_reserved_check;',database='eventhub_restore')==''
    assert h.db('SELECT * FROM v_revenue_monthly ORDER BY event_id,month;')==h.db('SELECT * FROM v_revenue_monthly ORDER BY event_id,month;',database='eventhub_restore')
    for view in h.db("SELECT TABLE_NAME FROM information_schema.VIEWS WHERE TABLE_SCHEMA='eventhub_restore';").splitlines():
        ddl=h.db(f'SHOW CREATE VIEW `{view}`;',database='eventhub_restore')
        assert '`eventhub`.' not in ddl,(view,'Pogled cita izvornu bazu')
    capture('restore.tsv','\n'.join(evidence)+'\nPASS: 12 tablica, 9 epoch stupaca, 10 rutina, 21 trigger, 7 pogleda, UTC scheduler DISABLED.')
    h.db('DROP DATABASE eventhub_restore;')


def permissions(h):
    script=(ROOT/'tests/08_readonly_user.sql').read_text()
    output=h.db(script,report=True,force=True)
    errors=re.findall(r'ERROR (\d+)',output)
    assert errors==['1142']*5+['1370'],errors
    capture('readonly.txt',output)
    for sql in ['SELECT * FROM buyer LIMIT 1;','UPDATE reservation SET status=status WHERE 1=0;']:
        h.db(sql,app=True,fail='1142')
    capture('grants.txt',h.db("SHOW GRANTS FOR 'eventhub_app'@'%'; SHOW GRANTS FOR 'eventhub_report'@'%';"))


def concurrency(h):
    # Odvojene CLI veze na isti izolirani Compose server.
    client=h.tmp/'client.sh'
    client.write_text('#!/bin/sh\nexec '+ ' '.join(h.dc) +' exec -T db mariadb -uroot -ptime-test-root "$@" eventhub\n')
    client.chmod(0o700)
    env=os.environ.copy();env['DB_CMD']=str(client)+' $OPTS'
    result=subprocess.run(['bash',str(ROOT/'tests/06_concurrency.sh')],env=env,text=True,capture_output=True)
    capture('concurrency.txt',result.stdout+'\n'+result.stderr)
    assert result.returncode==0 and 'UKUPNO: 4 PASS, 0 FAIL' in result.stdout,result.stdout+result.stderr
    assert h.db('SELECT * FROM v_reserved_check;')==''


def presentation(h):
    result=h.db((ROOT/'tests/09_presentation.sql').read_text(),fail='Nema dovoljno slobodnih mjesta')
    capture('presentation.txt',result)
    assert h.db("SELECT c.reserved FROM ticket_category c JOIN event e ON e.id=c.event_id WHERE e.name LIKE 'Presentation %' ORDER BY e.id DESC LIMIT 1;")=='8'
    assert h.db('SELECT * FROM v_reserved_check;')==''


def dst_expiry(h):
    # Rok od 15 minuta mora ostati 900 stvarnih sekundi i preko promjene sata.
    event,category,_,_=h.cases[-1]
    for zone in ['+00:00','Europe/Zagreb','America/New_York']:
        for instant in ['2027-03-28 00:55:00','2027-10-31 00:55:00']:
            value=int(datetime.fromisoformat(instant).replace(tzinfo=timezone.utc).timestamp())
            result=h.db(f"SET timestamp={value}; CALL create_reservation({h.buyer},{event},'[{{\"category_id\":{category},\"quantity\":1}}]',0,@r); SELECT UNIX_TIMESTAMP(expires_at)-UNIX_TIMESTAMP(created_at),@@session.time_zone FROM reservation WHERE id=@r;",zone)
            assert result==f'900\t{zone}',(instant,zone,result)
    capture('dst_expiry.txt','PASS: rok 900 sekundi preko oba DST prijelaza u tri zone; zona pozivatelja sacuvana.')


def app_and_guards(h):
    # Stvarni pozivi kao ograniceni korisnik, bez prava SELECT nad tablicama.
    ids=h.db("""
SET @loc=(SELECT MIN(id) FROM location); SET @org=(SELECT MIN(id) FROM organizer);
SET @type=(SELECT id FROM event_type WHERE code='other');
INSERT INTO event(name,event_date,capacity,location_id,organizer_id,event_type_id)
VALUES ('App permissions',CONVERT_TZ(UTC_TIMESTAMP()+INTERVAL 1 HOUR,'+00:00','Europe/Zagreb'),10,@loc,@org,@type);
SET @e=LAST_INSERT_ID();
INSERT INTO ticket_category(event_id,name,price,service_fee,capacity,seating_type) VALUES (@e,'App test',100,0,10,'standing');
SELECT @e,LAST_INSERT_ID();
""")
    event,category=map(int,ids.split('\t'))
    args=f"1,{event},'[{{\"category_id\":{category},\"quantity\":2}}]',0,@r"
    rid=int(h.db(f'CALL create_reservation({args}); CALL confirm_reservation(@r); SELECT @r;',app=True))
    cards=h.db(f'SELECT t.id,t.ticket_code FROM ticket t JOIN reservation_item ri ON ri.id=t.reservation_item_id WHERE ri.reservation_id={rid} ORDER BY t.id;').splitlines()
    first=int(cards[0].split('\t')[0]); code=cards[1].split('\t')[1]
    assert h.db(f"CALL cancel_ticket({first},@refund); CALL check_in_ticket({event},LOWER('{code}')); SELECT @refund;",app=True)=='0.00'
    pending=int(h.db(f"CALL create_reservation(1,{event},'[{{\"category_id\":{category},\"quantity\":1}}]',0,@r); CALL cancel_reservation(@r); SELECT @r;",app=True))
    assert h.db(f"SELECT status FROM reservation WHERE id={pending};")=='cancelled'
    capture('app_calls.txt','PASS: svih pet aplikacijskih procedura pozvano kao eventhub_app; lowercase check-in, refund=0 i pending cancel.')
    results=[]
    calls=[f'CALL create_reservation({args});','CALL confirm_reservation(0);',"CALL release_reservation(0,'buyer');",'CALL cancel_ticket(0,@refund);','CALL generate_seats(0,1,1);','CALL cancel_reservation(0);']
    for call in calls:
        output=h.db('SET @guard_address=(SELECT address FROM buyer WHERE id=1); START TRANSACTION; UPDATE buyer SET address="guard-probe" WHERE id=1;'+call+'SELECT CONCAT("TX=",@@in_transaction),address FROM buyer WHERE id=1; ROLLBACK; SELECT address <=> @guard_address FROM buyer WHERE id=1;',force=True)
        assert 'izvan transakcije (autocommit=1)' in output and 'TX=1\tguard-probe' in output and output.endswith('1'),output
        results.append(output)
    # Nakon poslovne greske session zona se takodjer mora vratiti.
    for call in ['CALL confirm_reservation(0);',"CALL release_reservation(0,'buyer');",'CALL cancel_ticket(0,@refund);',"CALL check_in_ticket(0,'00000000000000000000000000000000');",'CALL create_reservation(0,0,NULL,0,@r);']:
        output=h.db(call+'SELECT @@session.time_zone;',zone='America/New_York',force=True)
        assert 'ERROR ' in output and output.endswith('America/New_York'),output
    capture('transaction_guards.txt','\n'.join(results)+'\nPASS: 6 guard provjera cuva transakciju i podatke; 5 poslovnih gresaka vraca zonu pozivatelja.')
    explain=h.db(f"EXPLAIN SELECT e.id,e.event_date FROM ticket t JOIN reservation_item ri ON ri.id=t.reservation_item_id JOIN event e ON e.id=ri.event_id WHERE t.ticket_code='{code}';")
    rows=[line.split('\t') for line in explain.splitlines()]
    assert any(len(row)>5 and row[2]=='t' and row[3]=='const' and row[5]=='uq_ticket_code' for row in rows),explain
    capture('check_in_explain.tsv',explain)
