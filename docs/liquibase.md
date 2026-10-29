# Liquibase i nadogradnje baze

Projekt koristi MariaDB 10.11 i Liquibase 4.33.0 Open Source. Formatted SQL
migracije izvrsavaju se redom iz `migrations/db.changelog-master.xml`.
Izvrsene migracije se ne mijenjaju: promjene idu u novu datoteku na kraj mastera.
Liquibase pamti checksum svakog changeseta u `DATABASECHANGELOG`.

| Datoteka | Sadrzaj |
| --- | --- |
| `001-tables.sql` | Pocetne tablice, ogranicenja, indeksi i tipovi dogadjaja |
| `002-functions-triggers.sql` | Funkcije i triggeri |
| `003-procedures-event.sql` | Procedure i UTC event za istek rezervacija |
| `004-views.sql` | Sedam pogleda |
| `005-users.sql` | Dva korisnika s lozinkama iz Compose secrets |
| `005-grants.sql` | Ovlasti |
| `006-buyer-keycloak.sql` | Uklanja sest login polja i njihova dva CHECK-a; dodaje nullable UUID `external_id`, UNIQUE i CHECK |

Ukupno: sedam SQL datoteka, 56 changesetova s rollbackom. Pocetni 001 i ostale
primijenjene migracije ostaju nepromijenjeni. Nema adoption guarda u aktualnom checkoutu.

## Postojeca baza nakon pulla

Prvo napravi backup prema [administraciji](08_administracija.md), zatim:

```bash
docker compose down
docker compose up -d
docker compose ps -a
docker compose logs liquibase
```

`db` mora biti healthy, `liquibase` Exited (0). Ako je ranijih 55 changesetova vec
izvrseno, pokrece se samo 006. Podaci kupaca, rezervacija i karata se cuvaju;
uklanjaju se samo navedeni login atributi. Seed se NE pokrece ponovno.
`down` cuva volumen; ne koristiti `down -v`.

Rollback 006 vraca staru strukturu, zadane vrijednosti i CHECK-ove, ali izgubljene
login vrijednosti moze vratiti samo backup. Rollback uklanja i Keycloak poveznice.
Ne izvoditi ga nad poslovnom bazom bez plana povrata podataka.

Compose automatski migrira samo `eventhub`. Postojecu perf kopiju sa starim
changesetovima mozes nadograditi zasebno, nakon backupa:

```bash
docker compose run --rm --no-deps liquibase --url='jdbc:mariadb://db:3306/eventhub_perf?connectionTimeZone=UTC&forceConnectionTimeZoneToSession=true&preserveInstants=true' update
```

Kopirani event za istek mora ostati DISABLED. Za nova performance mjerenja prvo
pripremi kopiju iz cistog seeda po performance uputama; ne ponavljaj generator na
vec popunjenoj kopiji. Stari rezultati ostaju povijesni dokaz prije 006.

## Nova instalacija i provjere

Na novoj praznoj bazi `docker compose up -d` primjenjuje svih 56 changesetova.
Tek zatim jednom ucitaj seed prema README-u; `external_id` ostaje NULL.

```bash
docker compose run --rm --no-deps liquibase validate
python3 tests/test_database.py
python3 docs/render_docs.py
```

Runner koristi vlastiti Compose projekt bez host portova. Provjerava instalaciju,
ponovljeni update, Keycloak ogranicenja, seed, procedure, ovlasti, backup/restore,
UTC/DST, scheduler i potpuni rollback pa novu instalaciju. Glavnu bazu ne mijenja.
Na kraju uklanja testne kontejnere i mrezu; testni volumen ostaje sacuvan.
Generator dokumentacije provjerava manifest i hashove funkcionalnih dokaza.
Performance dokument se osvjezava zasebno, tek nakon novog mjerenja:
`python3 docs/render_docs.py --with-performance`.

[Rezultati](10_schema_validation.md).
