# Liquibase: testna baza

Projekt koristi MariaDB 10.11 i Liquibase 4.33.0. Migracije stvaraju konacnu shemu
izravno na praznoj bazi; nema adoption guarda, naknadnih ALTER lanaca, contexta ni
label filtera. Svi SQL changesetovi imaju rollback.

| Datoteka | Sadrzaj |
| --- | --- |
| `001-tables.sql` | 12 tablica, svi stupci, ogranicenja, indeksi i devet tipova dogadjaja |
| `002-functions-triggers.sql` | refund_percent, local_to_utc i svi triggeri |
| `003-procedures-event.sql` | Sve procedure i UTC event za istek rezervacija |
| `004-views.sql` | Svih sedam pogleda |
| `005-users.sql` | Dva korisnika s lozinkama iz Compose secrets |
| `005-grants.sql` | Ovlasti nakon stvaranja procedura i pogleda |

Redoslijed odredjuje `db.changelog-master.xml`. Svaki objekt definiran je jednom.
Za procedure i triggere JDBC dobiva cijelu definiciju, bez DELIMITER naredbe.
Tablice eksplicitno koriste utf8mb4 / utf8mb4_unicode_ci, a kod karte ascii_bin.

## Postavljanje i reset

```bash
docker compose up -d
docker compose run --rm --no-deps liquibase update
docker compose exec -T db sh -c 'MYSQL_PWD="$MARIADB_ROOT_PASSWORD" mariadb -uroot eventhub' < seed/01_seed.sql
```

Seed je izricita testna inicijalizacija: ucitava poslovne primjere i dev web
racune. Ne koristi Liquibase context i ne ponavlja se nad postojecim podacima.
Ponovljeni Liquibase update ne izvrsava nista.

Za vec postojecu bazu s prethodnim changelogom koristi reset naredbe iz README-a:
DROP DATABASE eventhub, CREATE DATABASE s utf8mb4_unicode_ci, update i seed.
Stari checksumi i evidencija time se uklanjaju zajedno s testnom bazom; ne koriste
se clear-checksums niti changelog-sync. Ostale baze i Docker volumen ostaju.

## Provjera

```bash
docker compose run --rm --no-deps liquibase validate
python3 tests/test_database.py
```

Integracija koristi vlastiti Compose projekt, mrezu i volumen, bez host portova.
Provjerava praznu bazu, ponovljeni update, seed s loginom, ogranicenja, poslovne
procedure, tri session zone, DST granice, stvarni scheduler i rollback cijelog
changeloga pa ponovnu instalaciju. Brise samo vlastiti testni volumen.

[Rezultati provjere](10_schema_validation.md).

Pri daljnjem radu na ovoj testnoj bazi moze se urediti pocetna shema i ponovno
resetirati bazu. Ako projekt kasnije bude koristio stvarne podatke, od tog
trenutka promjene treba dodavati novim migracijama umjesto mijenjanja primijenjenih.
