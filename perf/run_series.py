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
    sql = ["SELECT 'SERIES_BEGIN' AS marker, CONNECTION_ID() AS connection_id, VERSION() AS version, SYSDATE(6) AS started, @@innodb_buffer_pool_size AS buffer_pool;\n"]
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
    with (RESULTS / 'series.tsv').open('w') as out, (RESULTS / 'series.stderr').open('w') as err:
        result = subprocess.run(command, input='\n'.join(sql), text=True, stdout=out, stderr=err)
    manifest['finished_utc'] = datetime.now(timezone.utc).isoformat()
    manifest['exit_code'] = result.returncode
    manifest['result_sha256'] = hashlib.sha256((RESULTS / 'series.tsv').read_bytes()).hexdigest()
    (RESULTS / 'series_manifest.json').write_text(json.dumps(manifest, indent=2)+'\n')
    if result.returncode:
        # Greska prekida batch; sigurnosni povrat nije dio uspjesnog mjernog niza.
        subprocess.run(command, input=source['02_baseline.sql']+'\n'+source['03_add_indexes.sql'],
                       text=True, stdout=subprocess.DEVNULL, check=True)
        raise SystemExit('Mjerenje nije uspjelo; vidi series.stderr. Uski indeksi vraceni.')
    print('Zavrsena 3 A-D kruga i povrat 02 -> 03; rezultati: perf/results/series.tsv')

if __name__ == '__main__':
    main()
