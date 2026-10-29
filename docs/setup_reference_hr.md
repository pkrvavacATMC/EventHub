# EventHub: lokalno testno okruzenje

Aktualna shema koristi sedam SQL datoteka i 56 changesetova. Izvrsene migracije
se ne mijenjaju; promjene idu u novu datoteku. Postojeca baza se nadogradjuje
bez reseta: `docker compose down`, `docker compose up -d`, zatim pregled loga
Liquibasea. Seed se nad postojecim podacima ne ponavlja.

## Pokretanje

1. U korijenu projekta kopiraj `.env.example` u `.env` ako datoteka jos ne postoji.
2. Postavi tri razlicite lozinke, bez spremanja stvarnih lozinki u Git.
3. Pokreni `docker compose up -d` i provjeri da je db healthy, a liquibase Exited (0).
4. Jednom ucitaj `seed/01_seed.sql` na praznoj bazi prema README-u.

Seed daje 8 evenata, 40 kupaca, 175 rezervacija i 290 karata; external_id svih seed kupaca je NULL. Za nastavak
rada ne pokrece se ponovno seed; Liquibase update se moze ponoviti i ne mijenja
vec primijenjenu shemu.

## DBeaver

| Postavka | Vrijednost |
| --- | --- |
| Host i port | 127.0.0.1:3306 |
| Baza | eventhub |
| Poslovni korisnik | eventhub_app / EVENTHUB_APP_PASSWORD |
| Citanje svih tablica | eventhub_report / EVENTHUB_REPORT_PASSWORD |
| Administracija | root / MARIADB_ROOT_PASSWORD |

Za poslovne CALL-ove ukljuci **Autocommit**; nemoj ih omotati vanjskom
transakcijom. Na konekciji provjeri `SELECT DATABASE(), @@session.time_zone;`:
baza eventhub, zona +00:00. Server i projektna JDBC konekcija forsiraju UTC;
ako SQL klijent ima vlastitu inicijalizaciju, ona takodjer treba postaviti UTC.

Sistemski datumi su TIMESTAMP. Samo event.event_date ostaje lokalni DATETIME,
a zona dolazi iz grada lokacije. Nakon migracije koristi Refresh i ponovno otvori
ERD. Performance baza se prije novih mjerenja obnavlja iz iste sheme, pa i u njoj
sistemski stupci moraju biti TIMESTAMP.

[Struktura](02_database_structure.md), [migracije](liquibase.md),
[zadnja validacija](10_schema_validation.md), [performanse](07_performanse.md).

## Reprodukcija provjera

Prvo pripremi Python 3 prema [preduvjetima u README-u](../README.md#tehnologije-i-preduvjeti).
Automatski test stvara vlastitu praznu bazu i ne treba lokalni `.env`.

```bash
python3 tests/test_database.py
# Cisti eventhub seed, zatim novi performance skup:
bash perf/00_create_perf_db.sh
docker compose exec -T db sh -c 'MYSQL_PWD="$MARIADB_ROOT_PASSWORD" mariadb -uroot' < perf/01_generate_100k.sql
# Stari series.tsv i manifest prvo arhiviraj izvan perf/results.
python3 perf/run_series.py
python3 docs/render_docs.py --with-performance
```

Docker volumen cuva podatke pri `down`/`up`. `down -v` brise sve baze na volumenu.
Za novi performance skup zamjenjuje se samo eventhub_perf. Povrat backupa i
ovlasti opisani su u [administraciji](08_administracija.md).
