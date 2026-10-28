#!/bin/bash
# =====================================================================
# EventHub - 05: korisnici baze
# Lozinke dolaze iz varijabli okruzenja (.env), nikad iz Gita.
# Docker entrypoint pokrece ovu skriptu kod prvog pokretanja (prazan volumen).
#
#  eventhub_app    - aplikacija: smije SAMO pozivati poslovne procedure i citati
#                    izvjestajne viewove; ne moze direktno mijenjati tablice
#                    niti pozivati admin procedure (generate_seats, expire_...).
#  eventhub_report - izvjestaji: samo citanje (task 8).
# =====================================================================

: "${EVENTHUB_APP_PASSWORD:?EVENTHUB_APP_PASSWORD nije postavljen u .env}"
: "${EVENTHUB_REPORT_PASSWORD:?EVENTHUB_REPORT_PASSWORD nije postavljen u .env}"

# escape jednostrukih navodnika za SQL string
APP_PW=${EVENTHUB_APP_PASSWORD//\'/\'\'}
REPORT_PW=${EVENTHUB_REPORT_PASSWORD//\'/\'\'}

mariadb -uroot -p"${MARIADB_ROOT_PASSWORD}" <<EOSQL
CREATE USER IF NOT EXISTS 'eventhub_app'@'%' IDENTIFIED BY '${APP_PW}';
GRANT EXECUTE ON PROCEDURE eventhub.create_reservation  TO 'eventhub_app'@'%';
GRANT EXECUTE ON PROCEDURE eventhub.confirm_reservation TO 'eventhub_app'@'%';
GRANT EXECUTE ON PROCEDURE eventhub.cancel_reservation  TO 'eventhub_app'@'%';
GRANT EXECUTE ON PROCEDURE eventhub.cancel_ticket       TO 'eventhub_app'@'%';
GRANT EXECUTE ON PROCEDURE eventhub.check_in_ticket     TO 'eventhub_app'@'%';
GRANT SELECT ON eventhub.v_category_capacity     TO 'eventhub_app'@'%';
GRANT SELECT ON eventhub.v_event_capacity        TO 'eventhub_app'@'%';
GRANT SELECT ON eventhub.v_reservations_by_event TO 'eventhub_app'@'%';
GRANT SELECT ON eventhub.v_ticket_stats          TO 'eventhub_app'@'%';
GRANT SELECT ON eventhub.v_attendance            TO 'eventhub_app'@'%';
GRANT SELECT ON eventhub.v_revenue_monthly       TO 'eventhub_app'@'%';

CREATE USER IF NOT EXISTS 'eventhub_report'@'%' IDENTIFIED BY '${REPORT_PW}';
GRANT SELECT, SHOW VIEW ON eventhub.* TO 'eventhub_report'@'%';

FLUSH PRIVILEGES;
EOSQL
