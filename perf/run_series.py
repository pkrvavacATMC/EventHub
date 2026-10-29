#!/usr/bin/env python3
"""Tri A-D kruga u jednom mariadb procesu/vezi; ne mijenja SQL upite."""
import hashlib
import json
import os
from pathlib import Path
import subprocess
from datetime import datetime, timezone

ROOT = Path(__file__).resolve().parent
RESULTS = ROOT / 'results'
FILES = ['02_baseline.sql', '03_add_indexes.sql', '04_after.sql',
         '07_rejected_indexes.sql', '06_rejected_cover.sql']

def main():
    RESULTS.mkdir(exist_ok=True)
    if (RESULTS / 'series.tsv').exists():
        raise SystemExit('Prvo arhiviraj postojeci series.tsv i series_manifest.json.')
    source = {name: (ROOT / name).read_text() for name in FILES}
    manifest = {
        'started_utc': datetime.now(timezone.utc).isoformat(),
        'rounds': 3, 'order': ['A', 'B', 'C', 'D'],
        'source_sha256': {name: hashlib.sha256(text.encode()).hexdigest()
                          for name, text in source.items()},
    }
    sql = ["SET time_zone='+00:00'; SELECT 'SERIES_BEGIN' AS marker, CONNECTION_ID() AS connection_id, VERSION() AS version, SYSDATE(6) AS started, @@innodb_buffer_pool_size AS buffer_pool;\n"]
    configs = {'A': ['02_baseline.sql'],
               'B': ['03_add_indexes.sql', '04_after.sql'],
               'C': ['07_rejected_indexes.sql', '04_after.sql'],
               'D': ['06_rejected_cover.sql']}
    for round_no in range(1, 4):
        for config, names in configs.items():
            sql.append(f"SELECT 'SERIES_CONFIG' AS marker, {round_no} AS round_no, '{config}' AS config, CONNECTION_ID() AS connection_id, SYSDATE(6) AS started;\n")
            sql.extend(source[name] + '\n' for name in names)
            sql.append("SELECT 'INDEX_STATE' AS marker, TABLE_NAME, INDEX_NAME, GROUP_CONCAT(COLUMN_NAME ORDER BY SEQ_IN_INDEX) AS columns_in_order FROM information_schema.STATISTICS WHERE TABLE_SCHEMA='eventhub_perf' GROUP BY TABLE_NAME,INDEX_NAME ORDER BY TABLE_NAME,INDEX_NAME;\n")
    # 02 ukljucuje mjerenja; parser ih namjerno ne ubraja u tri A-D kruga.
    sql.append("SELECT 'SERIES_RESTORE' AS marker, CONNECTION_ID() AS connection_id;\n")
    sql.extend(source[name] + '\n' for name in ['02_baseline.sql', '03_add_indexes.sql'])
    sql.append("""SELECT 'TICKET_DISTRIBUTION' AS marker, COUNT(*) AS total,
SUM(cancelled_at IS NOT NULL) AS refunded, SUM(cancelled_at IS NULL) AS not_refunded
FROM eventhub_perf.ticket;
SELECT 'FINAL_INDEX' AS marker, TABLE_NAME, INDEX_NAME,
GROUP_CONCAT(COLUMN_NAME ORDER BY SEQ_IN_INDEX) AS columns_in_order
FROM information_schema.STATISTICS WHERE TABLE_SCHEMA='eventhub_perf'
GROUP BY TABLE_NAME,INDEX_NAME ORDER BY TABLE_NAME,INDEX_NAME;
SELECT 'FINAL_COUNTS' AS marker,
(SELECT COUNT(*) FROM eventhub_perf.reservation) AS reservations,
(SELECT COUNT(*) FROM eventhub_perf.ticket) AS tickets,
(SELECT COUNT(*) FROM eventhub_perf.v_reserved_check) AS inconsistent;
SELECT 'SERIES_END' AS marker, CONNECTION_ID() AS connection_id, SYSDATE(6) AS finished;
""")
    command = ['docker', 'exec', '-i', os.environ.get('CONTAINER', 'eventhub-db'),
               'sh', '-c', 'MYSQL_PWD="$MARIADB_ROOT_PASSWORD" mariadb --batch -uroot eventhub_perf']
    metadata_sql = """SELECT JSON_OBJECT(
      'version',VERSION(),'session_time_zone',@@session.time_zone,
      'reservations',(SELECT COUNT(*) FROM reservation),
      'tickets',(SELECT COUNT(*) FROM ticket),
      'system_timestamp_columns',(SELECT COUNT(*) FROM information_schema.COLUMNS WHERE TABLE_SCHEMA=DATABASE() AND DATA_TYPE='timestamp'),
      'ticket_code_collation',(SELECT COLLATION_NAME FROM information_schema.COLUMNS WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME='ticket' AND COLUMN_NAME='ticket_code'),
      'revenue_view_sha256',(SELECT SHA2(VIEW_DEFINITION,256) FROM information_schema.VIEWS WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME='v_revenue_monthly'))"""
    metadata=subprocess.run(command,input=metadata_sql,text=True,capture_output=True,check=True)
    manifest['database']=json.loads(metadata.stdout.splitlines()[-1])
    assert manifest['database']['system_timestamp_columns']==12
    assert manifest['database']['session_time_zone']=='+00:00'
    assert manifest['database']['ticket_code_collation']=='ascii_bin'
    manifest['schema_sha256']={str(p.relative_to(ROOT.parent)):hashlib.sha256(p.read_bytes()).hexdigest()
        for p in sorted((ROOT.parent/'migrations').glob('*')) if p.is_file()}
    manifest['generator_sha256']=hashlib.sha256((ROOT/'01_generate_100k.sql').read_bytes()).hexdigest()
    with (RESULTS / 'series.tsv').open('w') as out, (RESULTS / 'series.stderr').open('w') as err:
        result = subprocess.run(command, input='\n'.join(sql), text=True, stdout=out, stderr=err)
    manifest['finished_utc'] = datetime.now(timezone.utc).isoformat()
    manifest['exit_code'] = result.returncode
    samples = [float(line.split('\t')[2]) for line in (RESULTS / 'series.tsv').read_text().splitlines() if line.startswith('WRITE\t')]
    manifest['timings_valid'] = bool(samples) and all(value >= 0 for value in samples)
    manifest['result_sha256'] = hashlib.sha256((RESULTS / 'series.tsv').read_bytes()).hexdigest()
    (RESULTS / 'series_manifest.json').write_text(json.dumps(manifest, indent=2)+'\n')
    if result.returncode:
        # Greska prekida batch; sigurnosni povrat nije dio uspjesnog mjernog niza.
        subprocess.run(command, input=source['02_baseline.sql']+'\n'+source['03_add_indexes.sql'],
                       text=True, stdout=subprocess.DEVNULL, check=True)
        raise SystemExit('Mjerenje nije uspjelo; vidi series.stderr. Uski indeksi vraceni.')
    if not manifest['timings_valid']:
        raise SystemExit('Nevaljano trajanje mjerenja; serija nije prihvacena. Ponovi cijeli niz nakon arhiviranja dokaza.')
    print('Zavrsena 3 A-D kruga i povrat 02 -> 03; rezultati: perf/results/series.tsv')

if __name__ == '__main__':
    main()
