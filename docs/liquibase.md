# Liquibase — SQL migracije

Projekt koristi MariaDB 10.11 i Liquibase Open Source 4.33.0 s uključenim
MariaDB JDBC driverom. Nije potrebno lokalno instalirati Javu ili Liquibase.
SQL definicije iz starog `init/` premještene su u `migrations/`; Compose više
ne montira `docker-entrypoint-initdb.d`. Podaci postojećeg volumena ostaju.

## Pokretanje i nadogradnja

Iz korijena projekta, uz tri postavljene lozinke u `.env`:

```bash
docker compose up -d
```

Vrijedi za novu i za postojeću bazu. Compose čeka spremnost MariaDB-a,
a zatim pokreće Liquibase `update`, uključujući stvaranje korisnika.
Nova baza nema demo podatke; `seed/01_seed.sql` pokreće se zasebno, jednom.
Performance skripte nisu dio automatskih migracija.

Za dijagnostiku pri pokretanju cijelog Compose lanca:

```bash
docker compose ps -a
docker compose logs liquibase
```

`db` ostaje pokrenut; `liquibase` završava s izlaznim kodom 0.
Ako migracija padne, dostupnost MariaDB-a sama po sebi ne znači uspješnu nadogradnju.

## Postojeća baza kolege

Prije prvog prijelaza napravi backup po [uputama](08_administracija.md).
Ne briši volumen i ne pokreći stare početne SQL skripte nad postojećom bazom.

Podržana je dosadašnja struktura 11 tablica, uključujući bazu na kojoj je ručno
izvršena migracija `trg_reservation_bu` i `v_ticket_stats` koju smo ranije dijelili.
Početni guard uspoređuje metapodatke postojećih tablica s poznatom shemom:
stupce, tipove, NULL/default/generated postavke, indekse, ključeve i CHECK izraze.
Potpisi su vezani uz MariaDB 10.11. Ne uključuju podatke ni AUTO_INCREMENT brojače.

Ako struktura odgovara, postojeće tablice označavaju se `MARK_RAN`, bez ponovnog
stvaranja. Funkcije, triggeri, procedure i viewovi zatim se postavljaju na aktualne
definicije. To je sigurno i kad je kolegina ručna migracija već izvršena.
Postojećem zakazanom eventu čuvaju se raspored i uključenost.

Tablica `job_error_log`, ako još postoji, ostaje sa svim podacima; aktualna
procedura je više ne koristi. Druge dodatne tablice također se ne brišu.
Prethodno uvedene prilagođene poslovne procedure/triggere istog imena treba
pregledati prije prijelaza jer ih početne migracije zamjenjuju.

Ako guard prijavi grešku, usporedi stvarnu strukturu s `001-tables.sql`.
Primjer su dodatni performance indeksi na glavnoj bazi ili drugačiji stupci.
Za detalje tablice pregledaj `SHOW CREATE TABLE naziv_tablice;`.
Nemoj zaobilaziti provjeru s `changelog-sync`, `clear-checksums` ili brisanjem
Liquibase evidencije. Prvo treba razumjeti razliku i pripremiti ciljanu nadogradnju.
Liquibase prije guarda može stvoriti svoje dvije evidencijske tablice; poslovne
tablice i poslovni objekti tada još nisu promijenjeni.

## Datoteke i redoslijed

| Datoteka | Sadržaj |
|---|---|
| `000-adoption-guard.sql` | Jednokratna provjera kompatibilnosti pri prvom prijelazu |
| `001-tables.sql` | Svih 11 tablica, ograničenja i indeksi |
| `002-functions-triggers.sql` | Funkcija za povrat i svi poslovni triggeri |
| `003-procedures-event.sql` | Sve procedure i automatski istek rezervacija |
| `004-views.sql` | Svih sedam viewova |
| `005-users.sql` | Korisnici i lozinke iz Compose secrets datoteka |
| `005-grants.sql` | Ovlasti aplikacijskog i izvještajnog korisnika |

`db.changelog-master.xml` samo uključuje SQL datoteke u zadanom redoslijedu.
XML je ovdje popis datoteka za Open Source izdanje; sve definicije baze ostaju SQL.
Svaka funkcija, trigger i procedura ima zaseban changeset s `splitStatements:false`;
`DELIMITER` se ne šalje preko JDBC-a.

Liquibase stvara korisnike kroz `005-users.sql`. Compose prenosi lozinke iz
postojećih `.env` varijabli u secrets datoteke dostupne MariaDB-u. Lozinke se
ne zapisuju u migracije niti Git; postojeći korisnici zadržavaju lozinke.
Ovlasti dodjeljuje `005-grants.sql`. Za migracije se koristi root pristup ovog
lokalnog laboratorija; `eventhub_app` nema pravo mijenjati shemu.

## Dodavanje sljedeće migracije

Izvršene datoteke nemoj mijenjati, preimenovati ni premještati. Dodaj novu, npr.
`006-neka-promjena.sql`, i uključi je na kraj master datoteke:

```sql
--liquibase formatted sql

--changeset eventhub:006-neka-promjena dbms:mariadb
ALTER TABLE city ADD COLUMN postal_code VARCHAR(20) NULL;
```

Ovo je samo primjer; nije dio implementirane sheme. Zatim pokreni
`docker compose up -d`. Liquibase pamti identitet changeseta i checksum u
`DATABASECHANGELOG`; već izvršene migracije ne ponavlja.
Početni guard ne služi otkrivanju svih naknadnih ručnih promjena nakon usvajanja.

MariaDB DDL radi implicitne commitove. Migracija koja padne nije automatski
poništena; nema generičkog sigurnog rollbacka cijele baze. Zato su changesetovi
uglavnom po jednom objektu, a promjene se prvo provjeravaju na kopiji baze.

## Status i provjera

Dok je servis `db` spreman:

```bash
docker compose run --rm --no-deps liquibase validate
docker compose run --rm --no-deps liquibase status --verbose
docker compose exec -T db sh -c 'MYSQL_PWD="$MARIADB_ROOT_PASSWORD" mariadb -uroot eventhub -e "SELECT ID, EXECTYPE FROM DATABASECHANGELOG ORDER BY ORDEREXECUTED;"'
```

Za ponovljenu provjeru nad već spremnom bazom pokreni
`docker compose run --rm --no-deps liquibase update`; već izvršene migracije preskače.
Integracijska provjera koristi vlastiti Compose projekt, testne lozinke i volumen,
bez objave portova i bez pristupa postojećem `eventhub-db`:

```bash
python3 tests/test_liquibase.py
```

Provjerava novu bazu, seed, postojeće regresijske provjere, ponovljeni update,
prijelaz postojeće baze s očuvanim podacima i odbijanje nepoznate strukture.
Nakon provjere briše isključivo vlastiti testni volumen.
