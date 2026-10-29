"""Konacna testna shema: UTC, procedure, DST, seed, ovlasti i rollback."""
from datetime import datetime, timezone
import json
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import time
from suite_checks import capture, manifest, constraints, backup_restore, permissions, concurrency, presentation, dst_expiry, app_and_guards

COLUMNS = {
    'reservation': ['created_at', 'confirmed_at', 'cancelled_at', 'expires_at'],
    'reservation_seat': ['released_at'],
    'ticket': ['checked_in_at', 'cancelled_at'],
    'buyer': ['email_verified_at', 'locked_until', 'last_login_at', 'created_at', 'updated_at'],
}

ROOT = Path(__file__).resolve().parents[1]
LOG = Path('/tmp/eventhub-database-test.log')
ZONES = ['+00:00', 'Europe/Zagreb', 'America/New_York']


def epoch(text):
    return int(datetime.fromisoformat(text).replace(tzinfo=timezone.utc).timestamp())


def run(args, sql=None, ok=True):
    result = subprocess.run(args, input=sql, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    clean = re.sub(r"IDENTIFIED BY PASSWORD '[^']*'", "IDENTIFIED BY PASSWORD '[REDACTED]'", result.stdout)
    with LOG.open('a') as out:
        out.write(clean)
    if ok and result.returncode:
        raise RuntimeError(clean)
    return result


class Harness:
    def __init__(self, tmp):
        self.tmp = tmp
        shutil.copytree(ROOT / 'migrations', tmp / 'migrations')
        self.url = 'jdbc:mariadb://db:3306/eventhub?connectionTimeZone=UTC&forceConnectionTimeZoneToSession=true&preserveInstants=true'
        self.cfg = {'services': {
            'db': {'image': 'mariadb:10.11', 'environment': {'TZ': 'Europe/Zagreb', 'MARIADB_ROOT_PASSWORD': 'time-test-root', 'MARIADB_DATABASE': 'eventhub'},
                'command': ['--event-scheduler=OFF', '--default-time-zone=+00:00', '--character-set-server=utf8mb4', '--collation-server=utf8mb4_unicode_ci'],
                'volumes': ['data:/var/lib/mysql'], 'secrets': ['eventhub_app_password', 'eventhub_report_password'],
                'healthcheck': {'test': ['CMD', 'healthcheck.sh', '--connect', '--innodb_initialized'], 'interval': '1s', 'timeout': '5s', 'retries': 60}},
            'liquibase': {'image': 'liquibase:4.33.0', 'environment': {
                'LIQUIBASE_COMMAND_URL': self.url, 'LIQUIBASE_COMMAND_USERNAME': 'root',
                'LIQUIBASE_COMMAND_PASSWORD': 'time-test-root', 'LIQUIBASE_COMMAND_CHANGELOG_FILE': 'migrations/db.changelog-master.xml',
                'LIQUIBASE_SEARCH_PATH': '/liquibase/changelog'}, 'volumes': [f'{tmp / "migrations"}:/liquibase/changelog/migrations:ro']}},
            'volumes': {'data': {}}, 'secrets': {}}
        for name in ['eventhub_app_password', 'eventhub_report_password']:
            (tmp / name).write_text('time-test-' + name)
            self.cfg['secrets'][name] = {'file': str(tmp / name)}
        self.compose = tmp / 'compose.json'
        self.dc = ['docker', 'compose', '-p', 'eventhub-database-test', '-f', str(self.compose)]
        self.save()

    def save(self):
        self.compose.write_text(json.dumps(self.cfg))

    def db(self, sql, zone='+00:00', fail=None, app=False, force=False, report=False, database='eventhub'):
        cli = ['mariadb', '--batch', '--skip-column-names', database]
        cli += ['-ueventhub_app', '-ptime-test-eventhub_app_password'] if app else ['-uroot', '-ptime-test-root']
        if report:
            cli = ['mariadb','--batch','--skip-column-names',database,'-ueventhub_report','-ptime-test-eventhub_report_password']
        if force:
            cli += ['--force']
        sql = f"SET time_zone='{zone}'; SET autocommit=1;\n" + sql
        result = run(self.dc + ['exec', '-T', 'db', *cli], sql, not (fail or force))
        if fail:
            assert fail in result.stdout and result.returncode, result.stdout
        return result.stdout.strip()

    def lb(self, *args):
        return run(self.dc + ['run', '--rm', '--no-deps', 'liquibase', *args]).stdout

    def up(self):
        run(self.dc + ['up', '-d', '--wait', 'db'])

    def down(self):
        run(self.dc + ['down', '-v'], ok=False)

    def seed(self):
        # Seed je definiran lokalnim zagrebackim vremenima; NOW sprema TIMESTAMP trenutke.
        self.db((ROOT / 'seed/01_seed.sql').read_text())

    def schema(self):
        for table, columns in COLUMNS.items():
            rows = self.db(f"SELECT COLUMN_NAME,DATA_TYPE FROM information_schema.COLUMNS WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME='{table}' AND COLUMN_NAME IN ({','.join(repr(c) for c in columns)}) ORDER BY COLUMN_NAME;")
            assert len(rows.splitlines()) == len(columns) and all(line.endswith('\ttimestamp') for line in rows.splitlines()), rows
            self.db(f'SHOW CREATE TABLE {table};')
        assert self.db("SELECT CONCAT(TABLE_NAME,'.',COLUMN_NAME) FROM information_schema.COLUMNS WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME IN ('reservation','reservation_seat','ticket','buyer') AND EXTRA LIKE '%on update%';") == 'buyer.updated_at'
        assert self.db("SELECT COUNT(*) FROM information_schema.TABLE_CONSTRAINTS WHERE CONSTRAINT_SCHEMA=DATABASE() AND CONSTRAINT_NAME IN ('chk_res_status_dates','chk_res_expires','uq_active_seat','uq_ticket_code','chk_ticket_code');") == '5'
        assert self.db("SELECT COUNT(DISTINCT INDEX_NAME) FROM information_schema.STATISTICS WHERE TABLE_SCHEMA=DATABASE() AND INDEX_NAME IN ('idx_res_status_expires','idx_res_confirmed_at','idx_ticket_cancelled_at');") == '3'
        assert self.db("SELECT COUNT(*) FROM reservation_seat WHERE NOT (active_seat_id <=> IF(released_at IS NULL,seat_id,NULL));") == '0'
        assert self.db("SELECT TIME_ZONE FROM information_schema.EVENTS WHERE EVENT_SCHEMA=DATABASE() AND EVENT_NAME='ev_expire_reservations';") == '+00:00'
        for view in ['v_event_capacity', 'v_attendance']:
            assert self.db(f"SELECT COLUMN_NAME FROM information_schema.COLUMNS WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME='{view}' ORDER BY ORDINAL_POSITION DESC LIMIT 1;") == 'event_time_zone'
        self.db("SHOW GRANTS FOR 'eventhub_app'@'%';")
        assert self.db("SELECT COUNT(*) FROM mysql.procs_priv WHERE User='eventhub_app' AND Host='%' AND Db=DATABASE() AND FIND_IN_SET('Execute',Proc_priv)>0;") == '5'
        self.db('SELECT * FROM v_event_capacity LIMIT 1; SELECT * FROM v_attendance LIMIT 1; SELECT * FROM v_revenue_monthly LIMIT 1;', app=True)
        assert self.db('SELECT * FROM v_reserved_check;') == ''

    def fixtures(self):
        self.db("""
SET timestamp=1767225600;
INSERT IGNORE INTO city(name,time_zone) VALUES ('London','Europe/London');
SET @london=(SELECT id FROM city WHERE name='London');
INSERT INTO location(name,city_id,capacity) VALUES ('Time London',@london,10000);
SET @loc=LAST_INSERT_ID();
SET @org=(SELECT MIN(id) FROM organizer);
SET @type=(SELECT id FROM event_type WHERE code='other');
SET @zg=(SELECT MIN(l.id) FROM location l JOIN city c ON c.id=l.city_id WHERE c.name='Zagreb');
INSERT INTO event(name,event_date,capacity,location_id,organizer_id,event_type_id) VALUES
 ('Time Zagreb','2027-02-15 20:00:00',1000,@zg,@org,@type),
 ('Time London','2027-02-15 20:00:00',1000,@loc,@org,@type),
 ('Time spring','2027-03-28 04:00:00',1000,@zg,@org,@type),
 ('Time autumn','2027-10-31 04:00:00',1000,@zg,@org,@type);
""")
        rows = self.db("SELECT e.id,UNIX_TIMESTAMP(local_to_utc(e.event_date,city.time_zone)),e.name FROM event e JOIN location l ON l.id=e.location_id JOIN city ON city.id=l.city_id WHERE e.name IN ('Time Zagreb','Time London','Time spring','Time autumn') ORDER BY e.id;")
        self.cases = []
        for line in rows.splitlines():
            event,start,name = line.split('\t')
            category=self.db(f"SET timestamp=1767225600; INSERT INTO ticket_category(event_id,name,price,service_fee,capacity,seating_type) VALUES ({int(event)},'Time standing',100,0,1000,'standing'); SELECT LAST_INSERT_ID();")
            self.cases.append((int(event),int(category),int(start),name))
        self.buyer = int(self.db('SELECT MIN(id) FROM buyer;'))

    def purchase_sql(self, event, category, start, quantity=1):
        return f"""
SET timestamp={start};
CALL create_reservation({self.buyer},{event},'[{{"category_id":{category},"quantity":{quantity}}}]',0,@r);
CALL confirm_reservation(@r);
SET @t=(SELECT MIN(t.id) FROM ticket t JOIN reservation_item ri ON ri.id=t.reservation_item_id WHERE ri.reservation_id=@r);
SET @code=(SELECT ticket_code FROM ticket WHERE id=@t);
"""

    def matrix(self):
        counts = {'create':0,'confirm':0,'refund':0,'check_in':0,'clock':0}
        for event,category,start,name in self.cases:
            for zone in ZONES:
                simulated = start-1800
                probe = self.db(f"SET timestamp={simulated}; SELECT UNIX_TIMESTAMP(NOW()),TIMESTAMPDIFF(SECOND,'1970-01-01',UTC_TIMESTAMP());", zone)
                assert probe == f'{simulated}\t{simulated}', (name,zone,probe)
                counts['clock'] += 1
                result = self.db(self.purchase_sql(event,category,simulated) + 'SELECT UNIX_TIMESTAMP(expires_at)-UNIX_TIMESTAMP(created_at) FROM reservation WHERE id=@r;',zone)
                assert result == '900', (name,zone,result)
                self.db(f"SET timestamp={start+1800}; CALL create_reservation({self.buyer},{event},'[{{\"category_id\":{category},\"quantity\":1}}]',0,@r);",zone,fail='Event je vec poceo ili prosao')
                counts['create'] += 2
                # Potvrda nakon pocetka, ali prije isteka rezervacije.
                self.db(f"SET timestamp={start-60}; CALL create_reservation({self.buyer},{event},'[{{\"category_id\":{category},\"quantity\":1}}]',0,@r); SET timestamp={start+1}; CALL confirm_reservation(@r);",zone,fail='Event je vec poceo ili prosao')
                counts['confirm'] += 1
                for seconds,expected in [(168*3600+1,'80.00'),(168*3600,'80.00'),(168*3600-1,'50.00'),(48*3600+1,'50.00'),(48*3600,'50.00'),(48*3600-1,'0.00')]:
                    sql = self.purchase_sql(event,category,start-200*3600) + f'SET timestamp={start-seconds}; CALL cancel_ticket(@t,@refund); SELECT @refund;'
                    actual = self.db(sql,zone)
                    assert actual == expected, (name,zone,seconds,actual,expected)
                    counts['refund'] += 1
                for offset,success in [(-86401,False),(-86400,True),(86400,True),(86401,False)]:
                    sql = self.purchase_sql(event,category,start-200*3600) + f'SET timestamp={start+offset}; CALL check_in_ticket({event},LOWER(@code));'
                    if success:
                        actual = self.db(sql+'SELECT checked_in_at IS NOT NULL FROM ticket WHERE id=@t;',zone)
                        assert actual == '1', (name,zone,offset,actual)
                    else:
                        self.db(sql,zone,fail='Check-in nije moguc u ovom terminu')
                    counts['check_in'] += 1
        print('PASS matrica: '+json.dumps(counts),flush=True)
        # Namjerni poslovni mjesec: UTC jos ozujak, Zagreb vec travanj.
        e,c,start,_ = self.cases[-1]
        self.db(self.purchase_sql(e,c,epoch('2027-03-31 22:30:00')))
        results = [self.db('SELECT * FROM v_revenue_monthly ORDER BY event_id,month;',zone) for zone in ZONES]
        assert results[0] == results[1] == results[2]
        assert '\t2027-04\t' in results[0]
        print('PASS: poslovni mjeseci isti u tri zone, ukljucujuci granicu mjeseca',flush=True)
        self.db("INSERT INTO city(name,time_zone) VALUES ('Invalid time city','Invalid/Zone');",fail='Nepoznata vremenska zona')
        self.db("UPDATE city SET time_zone='Europe/London' WHERE name='Zagreb';",fail='Zona grada s postojecim eventima')
        self.db("SELECT local_to_utc('2027-01-01','Invalid/Zone');",fail='Nepoznata vremenska zona')
        # Lokacija se ne moze promijeniti nakon pocetka, cak ni uz isti lokalni datum.
        self.db(f"SET timestamp={start+1}; SET @loc=(SELECT id FROM location WHERE name='Time London'); UPDATE event SET location_id=@loc WHERE id={e};",fail='Datum eventa koji je poceo ili prosao')
        # Vanjski guard iz 011 i dalje cuva pozivateljevu transakciju.
        result=self.db(f"START TRANSACTION; UPDATE buyer SET failed_login_attempts=17 WHERE id={self.buyer}; CALL create_reservation({self.buyer},{e},'[]',0,@r); SELECT CONCAT('TX=',@@in_transaction),failed_login_attempts FROM buyer WHERE id={self.buyer}; ROLLBACK; SELECT failed_login_attempts FROM buyer WHERE id={self.buyer};",force=True)
        assert 'izvan transakcije (autocommit=1)' in result and 'TX=1\t17' in result and result.endswith('0'),result
        assert self.db('SELECT * FROM v_reserved_check;') == ''

    def scheduler(self):
        # Simuliraj kreiranje prije 16 min, a sam istek prepusti stvarnom scheduleru.
        self.db('SET GLOBAL event_scheduler=ON;')
        e,c,_,_ = self.cases[-1]
        rid=self.db(f"SET timestamp=UNIX_TIMESTAMP()-960; CALL create_reservation({self.buyer},{e},'[{{\"category_id\":{c},\"quantity\":1}}]',0,@r); SELECT @r;")
        assert self.db(f'SELECT UNIX_TIMESTAMP(expires_at)-UNIX_TIMESTAMP(created_at) FROM reservation WHERE id={int(rid)};') == '900'
        until=time.monotonic()+75
        while time.monotonic()<until:
            if self.db(f"SELECT CONCAT(status,'/',COALESCE(cancel_reason,'')) FROM reservation WHERE id={int(rid)};")=='cancelled/expired':
                break
            time.sleep(2)
        else:
            raise AssertionError('Scheduler nije istekao rezervaciju')
        self.db('SET GLOBAL event_scheduler=OFF;')
        assert self.db('SELECT * FROM v_reserved_check;') == ''
        print('PASS: stvarni UTC event scheduler, trajanje rezervacije 900 sekundi',flush=True)

    def auth(self):
        import bcrypt
        h=self.db("SELECT password_hash FROM buyer WHERE email='ana.horvat1@example.com';")
        assert bcrypt.checkpw(b'EventHub-dev-2026!',h.encode())
        assert self.db("SELECT COUNT(*) FROM buyer WHERE password_hash IS NOT NULL;") == '2'
        assert self.db("SELECT email_verified_at IS NULL FROM buyer WHERE email='ivan.knezevic2@example.com';") == '1'
        assert self.db("SELECT password_hash IS NULL FROM buyer WHERE email='marija.bozic3@example.com';") == '1'
        assert self.db('SELECT COUNT(*) FROM event WHERE event_type_id IS NULL;') == '0'


def main():
    LOG.write_text('')
    with tempfile.TemporaryDirectory(prefix='eventhub-test-') as directory:
        h=Harness(Path(directory))
        started=datetime.now(timezone.utc).isoformat()
        status='failed'
        try:
            h.up()
            capture('version.txt',h.db('SELECT VERSION(),@@global.time_zone,@@session.time_zone;'))
            h.lb('validate')
            jdbc=h.lb('execute-sql','--sql=SELECT @@session.time_zone AS jdbc_zone')
            assert '+00:00' in jdbc,jdbc
            h.lb('update')
            assert 'Run:                          0' in h.lb('update')
            h.schema()
            h.seed(); h.auth()
            reports=h.db((ROOT/'reports/02_verify_reports.sql').read_text())
            assert reports.endswith('18\t0') and 'FAIL' not in reports,reports
            capture('reports.tsv',reports)
            constraints(h); permissions(h); backup_restore(h)
            negative=h.db((ROOT/'tests/01_invalid_data.sql').read_text())
            capture('invalid_data.tsv',negative)
            assert 'FAIL' not in negative and 'UKUPNO\t81\t0' in negative,negative
            transactions=h.db((ROOT/'tests/05_transactions.sql').read_text())
            capture('transactions.tsv',transactions)
            assert '7/7 PASS' in transactions,transactions
            app_and_guards(h); concurrency(h); presentation(h)
            h.fixtures(); h.matrix(); dst_expiry(h); h.scheduler(); h.schema(); h.auth()
            print('PASS: prazna baza, seed s loginom, 81 negativni i 7 transakcijskih testova',flush=True)
            count=int(h.db('SELECT COUNT(*) FROM DATABASECHANGELOG;'))
            h.lb('rollback-count','--count='+str(count))
            assert h.db('SELECT COUNT(*) FROM DATABASECHANGELOG;')=='0'
            assert h.db("SELECT COUNT(*) FROM information_schema.TABLES WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME NOT IN ('DATABASECHANGELOG','DATABASECHANGELOGLOCK');")=='0'
            h.lb('update'); h.seed(); h.schema(); h.auth()
            assert 'Run:                          0' in h.lb('update')
            print(f'PASS: rollback svih {count} changesetova, ponovni update i seed',flush=True)
            capture('summary.txt',f'PASS: 18 reports, 81 invalid data, 7 transactions, 4 concurrency; auth/type/zone constraints; permissions; backup/restore; presentation; UTC/DST matrix; scheduler; rollback {count}.')
            status='passed'
        finally:
            h.down()
            manifest(status,started)


if __name__=='__main__':
    main()
