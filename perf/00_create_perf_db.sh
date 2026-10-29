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

docker exec -i "$CONTAINER" sh <<'SCRIPT'
set -e
export MYSQL_PWD="$MARIADB_ROOT_PASSWORD"
seed_count=$(mariadb -uroot -N -e "SELECT COUNT(*) FROM eventhub.reservation")
if [ "$seed_count" -ne 175 ]; then
  echo "Za usporediva mjerenja eventhub mora imati cisti seed (175 rezervacija)." >&2
  exit 1
fi
perf_dump=$(mktemp)
perf_disabled="$perf_dump.disabled"
trap 'rm -f "$perf_dump" "$perf_disabled"' EXIT
mariadb-dump -uroot --single-transaction --routines --triggers --events eventhub > "$perf_dump"
sed '/EVENT `ev_expire_reservations` ON SCHEDULE/s/ ENABLE DO / DISABLE DO /' "$perf_dump" > "$perf_disabled"
echo "1/3 Nova prazna baza eventhub_perf..."
mariadb -uroot -e "DROP DATABASE IF EXISTS eventhub_perf; CREATE DATABASE eventhub_perf CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
echo "2/3 Kopija nove sheme i podataka..."
mariadb -uroot eventhub_perf < "$perf_disabled"
echo "3/3 Provjera da je kopirani scheduler iskljucen..."
status=$(mariadb -uroot -N -e "SELECT STATUS FROM information_schema.EVENTS WHERE EVENT_SCHEMA='eventhub_perf' AND EVENT_NAME='ev_expire_reservations'")
[ "$status" = DISABLED ]
mariadb -uroot -t -e "SELECT 'eventhub' AS baza, COUNT(*) AS rezervacije FROM eventhub.reservation UNION ALL SELECT 'eventhub_perf', COUNT(*) FROM eventhub_perf.reservation;"
SCRIPT
