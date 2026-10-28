#!/bin/bash
# =====================================================================
# EventHub - perf/00_create_perf_db.sh
#
# Napravi bazu eventhub_perf kao tocnu kopiju baze eventhub (seed podaci,
# tablice, procedure, triggeri, viewovi, event). Nad tom kopijom se zatim
# generira 100k rezervacija (perf/01_generate_100k.sql) i radi task 7.
# Baza "eventhub" se pritom ne mijenja.
#
# Pokretanje iz korijena projekta (kontejner mora biti podignut):
#   bash perf/00_create_perf_db.sh
#
# Ponovno pokretanje brise staru eventhub_perf i radi svjezu kopiju.
# Ovo je ujedno primjer logickog backupa (mariadb-dump) i restorea u novu
# praznu bazu (task 8).
# =====================================================================
set -euo pipefail

CONTAINER="${CONTAINER:-eventhub-db}"

docker exec -i "$CONTAINER" sh -c '
  set -e
  export MYSQL_PWD="$MARIADB_ROOT_PASSWORD"     # lozinka ne ide u naredbeni redak

  SEED=$(mariadb -uroot -N -e "SELECT COUNT(*) FROM eventhub.reservation")
  if [ "$SEED" -eq 0 ]; then
    echo "Baza eventhub nema rezervacija - prvo pokreni seed/01_seed.sql" >&2
    exit 1
  fi

  echo "1/3 Nova prazna baza eventhub_perf..."
  mariadb -uroot -e "DROP DATABASE IF EXISTS eventhub_perf;
                     CREATE DATABASE eventhub_perf CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"

  echo "2/3 Kopija eventhub -> eventhub_perf (dump + restore)..."
  mariadb-dump -uroot --single-transaction --routines --triggers --events eventhub \
    | mariadb -uroot eventhub_perf

  echo "3/3 Iskljucivanje schedulera u kopiji..."
  mariadb -uroot eventhub_perf -e "ALTER EVENT ev_expire_reservations DISABLE;"

  mariadb -uroot -t -e "
    SELECT \"eventhub\"      AS baza, COUNT(*) AS rezervacije FROM eventhub.reservation
    UNION ALL
    SELECT \"eventhub_perf\",          COUNT(*)                FROM eventhub_perf.reservation;"
  echo "Gotovo. Sljedeci korak: perf/01_generate_100k.sql"
'
