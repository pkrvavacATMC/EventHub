# Sigurnosna kopija, povrat podataka i ovlasti

Provjereno **2026-10-29T16:35:25.403418+00:00**, na novoj shemi. Dokazi: [manifest](../tests/results/manifest.json).

Izrada sigurnosne kopije i povrat podataka provjereni su u izoliranom Compose okruzenju na novoj shemi, bez promjena glavne baze. Uspoređeni su svi reci preko CHECKSUM TABLE EXTENDED te UNIX_TIMESTAMP svih devet vremenskih stupaca.

| tablica | redaka | checksum jednak | epoch jednak |
| --- | --- | --- | --- |
| buyer | 40 | 1 | 1 |
| city | 5 | 1 | 1 |
| event | 8 | 1 | 1 |
| event_type | 9 | 1 | 1 |
| location | 5 | 1 | 1 |
| organizer | 3 | 1 | 1 |
| reservation | 175 | 1 | 1 |
| reservation_item | 229 | 1 | 1 |
| reservation_seat | 170 | 1 | 1 |
| seat | 240 | 1 | 1 |
| ticket | 290 | 1 | 1 |
| ticket_category | 13 | 1 | 1 |

Vraćeno je 10 rutina, 21 trigger, 7 pogleda i event. Provjereno je da pogledi čitaju restore bazu, ne izvor. Scheduler je isključen već u ulaznom dumpu. [Dokaz](../tests/results/restore.tsv).

## Ručni postupak

```bash
mkdir -p backup
docker compose exec -T db sh -c 'MYSQL_PWD="$MARIADB_ROOT_PASSWORD" mariadb-dump -uroot --single-transaction --routines --triggers --events eventhub' > backup/eventhub_backup.sql
docker compose exec -T db sh -c 'MYSQL_PWD="$MARIADB_ROOT_PASSWORD" mariadb -uroot -e "CREATE DATABASE eventhub_restore CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"'
set -o pipefail
sed '/EVENT `ev_expire_reservations` ON SCHEDULE/s/ ENABLE DO / DISABLE DO /' backup/eventhub_backup.sql | docker compose exec -T db sh -c 'MYSQL_PWD="$MARIADB_ROOT_PASSWORD" mariadb -uroot eventhub_restore'
```

Svaki korak mora završiti uspješno. CREATE namjerno staje ako cilj već postoji. Backup ne sadrzi korisnike/grantove; oni su u 005. Prije usporedbe izvor ne smije biti mijenjan. Izvornu bazu ne brisati. Dump sadrzi podatke i ne ide u Git; za stvarne podatke čuvati i kopiju izvan racunala.

## Ovlasti

Korisniku s ovlastima samo za čitanje prolazi čitanje; pet DML/DDL pokušaja odbijeno je s 1142, CALL s 1370. [Stvarni ispis](../tests/results/readonly.txt). Kao eventhub_app uspješno je pozvano svih pet dopuštenih procedura, a SELECT buyer i direktni UPDATE su odbijeni. [Pozivi](../tests/results/app_calls.txt), [SHOW GRANTS](../tests/results/grants.txt). Root se koristi za administraciju, ne za aplikaciju.

Automatska reprodukcija ukljucuje sve provjere: `python3 tests/test_database.py`. Postupak provjerava podatke i ovlasti u zasebnom okruženju.
