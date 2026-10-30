# Liquibase i nadogradnje baze

Projekt koristi MariaDB 10.11 i Liquibase 4.33.0 Open Source. Formatted SQL
migracije izvršavaju se redom iz `migrations/db.changelog-master.xml`.
Izvršene migracije se ne mijenjaju: promjene idu u novu datoteku na kraj mastera.
Liquibase pamti checksum svakog changeseta u `DATABASECHANGELOG`.

| Datoteka | Sadržaj |
| --- | --- |
| `001-tables.sql` | Početne tablice, ograničenja, indeksi i tipovi događaja |
| `002-functions-triggers.sql` | Funkcije i triggeri |
| `003-procedures-event.sql` | Procedure i UTC event za istek rezervacija |
| `004-views.sql` | Sedam pogleda |
| `005-users.sql` | Dva korisnika s lozinkama iz Compose secrets |
| `005-grants.sql` | Ovlasti |
| `006-buyer-keycloak.sql` | Uklanja šest login polja i njihova dva CHECK-a; dodaje nullable UUID `external_id`, UNIQUE i CHECK |

Ukupno: sedam SQL datoteka, 56 changesetova s rollbackom. Početni 001 i ostale
primijenjene migracije ostaju nepromijenjene.

## Postojeća baza nakon pulla

Prvo napravi backup prema [administraciji](08_administracija.md), zatim:

```bash
docker compose down
docker compose up -d
docker compose ps -a
docker compose logs liquibase
```

`db` mora biti healthy, `liquibase` Exited (0). Ako je ranijih 55 changesetova već
izvršeno, pokreće se samo 006. Podaci kupaca, rezervacija i karata se čuvaju;
uklanjaju se samo navedeni login atributi. Seed se NE pokreće ponovno.
`down` čuva volumen; ne koristiti `down -v`.

Rollback 006 vraća staru strukturu, zadane vrijednosti i CHECK-ove, ali izgubljene
login vrijednosti može vratiti samo backup. Rollback uklanja i Keycloak poveznice.
Ne izvoditi ga nad poslovnom bazom bez plana povrata podataka.

Compose automatski migrira samo `eventhub`. Postojeću perf kopiju sa starim
changesetovima možeš nadograditi zasebno, nakon backupa:

```bash
docker compose run --rm --no-deps liquibase --url='jdbc:mariadb://db:3306/eventhub_perf?connectionTimeZone=UTC&forceConnectionTimeZoneToSession=true&preserveInstants=true' update
```

Kopirani event za istek mora ostati DISABLED. Za nova performance mjerenja prvo
pripremi kopiju iz čistog seeda po performance uputama; ne ponavljaj generator na
već popunjenoj kopiji. Spremljena mjerenja pripadaju shemi prije 006; novi dokument zahtijeva novu seriju mjerenja.

## Nova instalacija i provjere

Na novoj praznoj bazi `docker compose up -d` primjenjuje svih 56 changesetova.
Tek zatim jednom učitaj seed prema README-u; `external_id` ostaje NULL.

```bash
docker compose run --rm --no-deps liquibase validate
python3 tests/test_database.py
python3 docs/render_docs.py
```

Runner koristi vlastiti Compose projekt bez host portova. Provjerava instalaciju,
ponovljeni update, Keycloak ograničenja, seed, procedure, ovlasti, backup/restore,
UTC/DST, scheduler i potpuni rollback pa novu instalaciju. Glavnu bazu ne mijenja.
Na kraju automatski uklanja testne kontejnere, mrežu i volumen.
Generator dokumentacije provjerava manifest i hashove funkcionalnih dokaza.
Performance dokument se osvježava zasebno, tek nakon novog mjerenja:
`python3 docs/render_docs.py --with-performance`.

[Rezultati](10_schema_validation.md).

## Lokalni reset

Postupak u [README-u](../README.md#ponovno-postavljanje-od-nule) briše samo `eventhub`. S bazom nestaje `DATABASECHANGELOG`, pa se svi changesetovi ponovno izvršavaju. `005-users.sql` koristi `CREATE USER IF NOT EXISTS`, a `005-grants.sql` ponovno dodjeljuje ovlasti nakon stvaranja procedura i pogleda. Postojeće lozinke korisnika ostaju iste: izmjena `.env` nije promjena lozinke u bazi.
