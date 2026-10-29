# EventHub

EventHub je MariaDB baza za prodaju karata za događaje: rezervacije, sjedeća i stajaća mjesta, izdavanje karata, check-in, otkazivanja i povrate.
Poslovna logika nalazi se u procedurama, triggerima i ograničenjima baze, a Liquibase postavlja shemu, korisnike i ovlasti.
Repozitorij sadrži testne podatke, izvještaje i ponovljive provjere; web aplikacija i platni sustav nisu implementirani.

## Dijagram baze

![EventHub ERD](eventhub-diagram.png)

Veza `buyer → reservation → reservation_item → ticket` prikazuje kupca, njegovu rezervaciju, stavke i izdane karte.
Za sjedeća mjesta slijedi `ticket_category → seat → reservation_seat`: hold (privremeno zauzeće) povezuje odabrano sjedalo sa stavkom rezervacije.
Jedan događaj ima više kategorija, a jedna rezervacija može obuhvatiti više kategorija istog događaja, ukupno najviše četiri karte.
Kompozitni strani ključevi povezuju te cjeline i sprječavaju miješanje događaja, kategorija, sjedala i holdova.

[Otvori dijagram](eventhub-diagram.png) · [Model i odluke](docs/02_database_structure.md)

## Tehnologije i preduvjeti

- **MariaDB 10.11**, InnoDB; shema zahtijeva MariaDB **10.6+** zbog korištenih mogućnosti, uključujući `JSON_TABLE`.
- **Liquibase 4.33.0**, formatted SQL migracije i XML master changelog.
- **Docker i Docker Compose v2**, dostupni iz terminala; za naredbe koristi Bash, na Windowsu primjerice WSL.
- **Python 3 i paket `bcrypt`** za automatske testove; instaliraj paket u Python okruženje iz kojeg pokrećeš testove.
- **DBeaver** je opcionalan. Lokalni port **3306** mora biti slobodan.

MariaDB i Liquibase izvršavaju se u kontejnerima; lokalna instalacija tih alata nije potrebna.
Compose objavljuje bazu samo na `127.0.0.1:3306` i čuva podatke u volumenu `db_data`.
Sve naredbe u ovom README-u pokreću se **iz korijena repozitorija**.

Za Python provjere pripremi zasebno okruženje (na Linuxu može biti potreban paket `python3-venv`):

```bash
python3 -m venv .venv
source .venv/bin/activate
python3 -m pip install bcrypt==3.2.2
```

Paket `bcrypt` 3.2.2 korišten je u provjeri; ostali Python moduli dolaze sa standardnom bibliotekom.
U novom terminalu prije testiranja ponovno pokreni `source .venv/bin/activate`.

## Brzi start

### 1. Postavi konfiguraciju

Ako `.env` još ne postoji, napravi kopiju predloška:

```bash
cp .env.example .env
```

U `.env` postavi **tri različite lozinke** za `MARIADB_ROOT_PASSWORD`, `EVENTHUB_APP_PASSWORD` i `EVENTHUB_REPORT_PASSWORD`.
Postojeći `.env` uredi bez prepisivanja. Stvarne lozinke ne upisuj u SQL ni Git; `.env` je u `.gitignore`.

Compose iz varijabli aplikacijskog i izvještajnog korisnika stvara secrets `eventhub_app_password` i `eventhub_report_password`.
MariaDB ih vidi kao `/run/secrets/eventhub_app_password` i `/run/secrets/eventhub_report_password`; migracija `005-users.sql` čita ih preko `LOAD_FILE`.
Root lozinku MariaDB i Liquibase dobivaju iz `MARIADB_ROOT_PASSWORD`. Promjena `.env` ne mijenja lozinke već postojećih korisnika baze.

### 2. Pokreni bazu i migracije

```bash
docker compose up -d
docker compose ps -a
docker compose logs liquibase
```

Pričekaj da je `db` **healthy**, a `liquibase` **Exited (0)**.
MariaDB stvara praznu bazu `eventhub`; Liquibase zatim stvara poslovne objekte i ovlasti.
Ako pokretanje nije uspješno, pregledaj i `docker compose logs db`; healthy baza sama ne potvrđuje uspješne migracije.

Za validaciju i izričitu primjenu migracija na pokrenutoj bazi:

```bash
docker compose run --rm --no-deps liquibase validate
docker compose run --rm --no-deps liquibase update
```

Ponovljeni `update` nad usklađenom bazom izvršava **0 changesetova**. Sam restart MariaDB-a ne primjenjuje migracije.

### 3. Jednom učitaj testni seed

Na praznoj poslovnoj bazi, nakon uspješnih migracija:

```bash
docker compose exec -T db sh -c 'MYSQL_PWD="$MARIADB_ROOT_PASSWORD" mariadb -uroot eventhub' < seed/01_seed.sql
```

Seed daje **8 događaja, 40 kupaca, 175 rezervacija i 290 karata**; devet tipova događaja već je uneseno migracijom.
Rezervacije nastaju kroz procedure, uz simulirano vrijeme u 2026.; skripta na kraju vraća stvarno vrijeme i uključuje event za istek rezervacija.
Ne pokreći seed ponovno nad popunjenom bazom: nije reset skripta. Nisu potrebni context ni label filteri.

Seed postavlja i testne web račune: Ana je verificirana, Ivan nije, a ostali kupci ostaju bez web računa.
To su zapisi tablice `buyer`, odvojeni od korisnika baze `eventhub_app` i `eventhub_report`; nisu implementacija web prijave.

## Reset testne baze

**Sljedeći postupak briše sve podatke i Liquibase evidenciju samo baze `eventhub`.**
Koristi ga za ponovno postavljanje ove testne sheme, osobito nakon izmjene početnih migracija.
Ostale baze i Docker volumen ostaju sačuvani; postojeća performance kopija mora se zasebno obnoviti ako treba pratiti novu shemu.

Uz pokrenuti `db`, izvršavaj korake redom i nastavi samo nakon uspjeha prethodnog:

```bash
docker compose exec -T db sh -c 'MYSQL_PWD="$MARIADB_ROOT_PASSWORD" mariadb -uroot -e "DROP DATABASE IF EXISTS eventhub; CREATE DATABASE eventhub CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"'
docker compose run --rm --no-deps liquibase update
docker compose exec -T db sh -c 'MYSQL_PWD="$MARIADB_ROOT_PASSWORD" mariadb -uroot eventhub' < seed/01_seed.sql
```

Ovdje nema adoption guarda ni prijelaznih ALTER lanaca; početne migracije stvaraju konačnu shemu na praznoj bazi.
Checksum neslaganje nakon izmjene testne sheme rješava se resetom, ne prikrivanjem kroz `clear-checksums` ili `changelog-sync`.

`docker compose down` zadržava podatke. **`docker compose down -v` briše volumen i sve baze na njemu**, uključujući `eventhub_perf` i eventualne restore kopije.
Detalji: [Liquibase](docs/liquibase.md) i [lokalno postavljanje](docs/setup_reference_hr.md).

## Spajanje: DBeaver i CLI

| Postavka | Vrijednost |
| --- | --- |
| Host / port | `127.0.0.1` / `3306` |
| Glavna baza | `eventhub` |
| Poslovni pristup | `eventhub_app`, lozinka iz `EVENTHUB_APP_PASSWORD` |
| Čitanje svih tablica | `eventhub_report`, lozinka iz `EVENTHUB_REPORT_PASSWORD` |
| Administracija | `root`, lozinka iz `MARIADB_ROOT_PASSWORD` |

U DBeaveru za poslovne procedure uključi **Autocommit** i pozivaj ih izvan vanjske transakcije.
Provjeri aktivnu bazu i zonu veze:

```sql
SELECT DATABASE(), @@session.time_zone;
```

Očekivano je `eventhub` i `+00:00`. Ako SQL klijent ima vlastitu inicijalizaciju veze, ona mora zadržati UTC.
Nakon reseta osvježi metapodatke preko Refresh i ponovno otvori dijagram.

Primjer pristupa ograničenim poslovnim korisnikom kroz CLI kontejnera:

```bash
docker compose exec -T db sh -c 'MYSQL_PWD="$EVENTHUB_APP_PASSWORD" mariadb -ueventhub_app eventhub -e "SELECT DATABASE(), @@session.time_zone; SELECT * FROM v_event_capacity LIMIT 5;"'
```

Za administraciju otvori root CLI pomoću `docker compose exec db sh -c 'MYSQL_PWD="$MARIADB_ROOT_PASSWORD" mariadb -uroot eventhub'`.
Za `eventhub_perf` koristi isti host i port, drugo ime baze i administrativni račun; grantovi aplikacijskih korisnika odnose se na `eventhub`.

## Struktura repozitorija

```text
migrations/             Šest SQL datoteka i master changelog stvaraju konačnu shemu.
seed/                   Deterministički poslovni primjeri, testni računi i generator seeda.
reports/                Osam izvještajnih upita i provjere poznatih seed rezultata.
tests/                  Integracijski runner, negativni, transakcijski i konkurentni scenariji.
tests/results/          Sirovi funkcionalni dokazi i manifest s hashovima izvora i rezultata.
perf/                   Generator velikog skupa, konfiguracije indeksa i alati za mjerenje.
perf/results/           Sirovi planovi, vremena, manifest mjerenja i seed regresijske provjere.
docs/                   Model, upute, rezultati provjera i generator dokumentacije.
```

U korijenu su još `docker-compose.yml`, `.env.example`, `.gitignore` i `eventhub-diagram.png`.
[Master changelog](migrations/db.changelog-master.xml) uključuje SQL datoteke ovim redom:

| Datoteka | Sadržaj | Changesetova |
| --- | --- | --- |
| [001-tables.sql](migrations/001-tables.sql) | Tablice, ograničenja, indeksi i šifrarnik tipova | 13 |
| [002-functions-triggers.sql](migrations/002-functions-triggers.sql) | Funkcije i triggeri | 23 |
| [003-procedures-event.sql](migrations/003-procedures-event.sql) | Procedure i zakazani istek rezervacija | 9 |
| [004-views.sql](migrations/004-views.sql) | Pogledi | 7 |
| [005-users.sql](migrations/005-users.sql) | Dva korisnika baze | 2 |
| [005-grants.sql](migrations/005-grants.sql) | Ovlasti nakon stvaranja objekata | 1 |

Ukupno je **55 changesetova**, svaki s eksplicitnim rollbackom.
MariaDB DDL nije transakcijski; pojedini objekti imaju odvojene changesetove, a potpuni rollback provjerava automatski test.

## Model podataka i poslovna pravila

Shema ima **12 tablica, 2 funkcije, 8 procedura, 21 trigger, 7 pogleda i 1 zakazani event**.
Dva aplikacijska korisnika baze stvaraju se zasebno; root je administratorski račun MariaDB-a.
Tablice koriste **InnoDB, utf8mb4 / utf8mb4_unicode_ci**; `ticket_code` je `CHAR(32)` s `CHARACTER SET ascii COLLATE ascii_bin`.

| Cjelina | Tablice |
| --- | --- |
| Mjesto i organizacija | `city`, `organizer`, `location` |
| Kupac i događaj | `buyer`, `event_type`, `event` |
| Kategorije i sjedala | `ticket_category`, `seat` |
| Rezervacija i karte | `reservation`, `reservation_item`, `reservation_seat`, `ticket` |

`event_type` sadrži devet tipova: `concert`, `standup`, `theatre`, `festival`, `sport`, `conference`, `exhibition`, `kids`, `other`.
`buyer` podržava opcionalni hash lozinke, verifikaciju i stanje računa; email je jedinstven, a NULL hash označava kupca bez web računa.

### Pravila rezervacija, povrata i check-ina

- Jedna rezervacija pripada jednom događaju i ukupno ima **1–4 karte**, kroz jednu ili više kategorija.
- Cijena i service fee određeni su kategorijom; besplatna karta dolazi iz kategorije s cijenom **0**.
- `pending` rezervacija zauzima mjesta **15 minuta**. Event `ev_expire_reservations` radi svake minute i otkazuje istekle kao `expired`; oslobađanje slijedi u ciklusu schedulera, a potvrda nakon isteka već je odbijena.
- `pending` se otkazuje samo cijela; `confirmed` se otkazuje po karti. Istekle rezervacije ne ulaze u stopu otkazivanja kupaca.
- Refund protection iznosi **10 % zbroja cijena karata** i vraća **100 % cijene karte**. Bez zaštite: najmanje 7 dana prije početka **80 %**, najmanje 48 h **50 %**, inače **0 %**. Service fee i fee zaštite ne vraćaju se.
- Nakon početka događaja nema rezervacija ni otkazivanja. Check-in je dopušten od **24 h prije do 24 h nakon** početka, samo za događaj na čijem se ulazu karta skenira.
- Kod karte je nepredvidljiv **`HEX(RANDOM_BYTES(16))`**. Check-in normalizira mala slova i rubne razmake.
- Za sjedeću kategoriju kapacitet mora odgovarati broju sjedala stvorenih kroz `generate_seats`.
- Transakcijska povijest se zadržava: DELETE je zabranjen triggerima na transakcijskim tablicama.
- Datum i lokacija događaja provjeravaju se pri promjeni; već započeti događaj ne može se premjestiti niti mu se može pomaknuti početak.

### Vrijeme

Svi sistemski trenuci poslovnih tablica su **TIMESTAMP**, a konekcije rade u **UTC-u**.
Jedini poslovni DATETIME je **`event.event_date`**: lokalni početak na mjestu održavanja, u IANA zoni `city.time_zone`, preko `event → location → city`.
`local_to_utc` pretvara taj početak u UTC; refund i check-in prozori uspoređuju stvarne UTC trenutke.
Procedure koje obrađuju te trenutke privremeno koriste UTC i vraćaju prethodnu zonu sessiona, uključujući put greške.
Samo `buyer.updated_at` ima `ON UPDATE CURRENT_TIMESTAMP`; `reservation.created_at` ga nema.
Mjesečni prihod koristi poslovni kalendar **Europe/Zagreb**, ne zonu SQL klijenta.

Compose postavlja `--default-time-zone=+00:00`, a JDBC URL sadrži `connectionTimeZone=UTC&forceConnectionTimeZoneToSession=true&preserveInstants=true`.
IANA tablice moraju biti učitane; provjera `CONVERT_TZ('2026-07-01 12:00:00','Europe/Zagreb','+00:00')` mora vratiti `2026-07-01 10:00:00`.
Ne uključuj `MARIADB_INITDB_SKIP_TZINFO`; učitavanje tzinfo pripada inicijalizaciji MariaDB-a, ne Liquibase migracijama.

### Integritet i konkurentnost

Namjerno redundantni `event_id` i `category_id` omogućuju kompozitne FK-ove: stavka i kategorija moraju pripadati događaju rezervacije, sjedalo kategoriji stavke, a hold stavci izdane karte.
`reservation_seat.active_seat_id` je **STORED generirani stupac**: aktivni hold izlaže `seat_id`, oslobođeni NULL; UNIQUE dopušta najviše jedan aktivan hold po sjedalu, uz očuvanu povijest.
`ticket_category.reserved` je denormalizirani brojač. CHECK štiti `0 <= reserved <= capacity`, a transakcije zaključavaju kategorije pomoću `SELECT ... FOR UPDATE` uzlazno po ID-u.
Sam CHECK brojača ne sprječava svaki izgubljeni upis; usklađenost sa stvarnim rezervacijama provjerava `v_reserved_check`, koji mora biti **prazan**.

Vlastite transakcije koriste `generate_seats`, `create_reservation`, `confirm_reservation`, `release_reservation` i `cancel_ticket`: traže poziv izvan aktivne vanjske transakcije, rade u **READ COMMITTED** i na grešku izvode ROLLBACK.
Provjera vanjske transakcije nalazi se izvan ROLLBACK handlera pa odbijanje ne poništava pozivateljevu transakciju; `cancel_reservation` delegira `release_reservation`.
`check_in_ticket` ima jedan UPDATE i ne otvara vlastitu transakciju; `expire_reservations` prolazi istekle rezervacije i nastavlja nakon pojedinačne greške.
Detaljno obrazloženje: [struktura i odluke](docs/02_database_structure.md).

## Procedure, pogledi i ovlasti

Poslovne poruke grešaka su na hrvatskom, tipično **SQLSTATE `45000` / errno `1644`**.
Povrede CHECK, UNIQUE, FK i ovlasti imaju zasebne MariaDB kodove; pregled je u [opisu negativnih testova](docs/03_testovi_neispravnih_podataka.md).
Funkcije su `refund_percent(hours)` i `local_to_utc(local_datetime, time_zone)`.

| Procedura | Uloga |
| --- | --- |
| `create_reservation(buyer_id, event_id, items, refund_protection, OUT reservation_id)` | Atomski stvara pending rezervaciju, stavke i holdove; `items` je JSON niz u SQL parametru `LONGTEXT` |
| `confirm_reservation(reservation_id)` | Simulira uspješno plaćanje, potvrđuje i izdaje karte |
| `cancel_reservation(reservation_id)` | Otkazuje cijelu pending rezervaciju |
| `cancel_ticket(ticket_id, OUT refund_amount)` | Otkazuje potvrđenu kartu i računa povrat |
| `check_in_ticket(event_id, ticket_code)` | Provjerava događaj, vremenski prozor i iskorištenost karte |
| `generate_seats(category_id, rows, per_row)` | Administratorski stvara sjedala sjedeće kategorije |
| `release_reservation(reservation_id, reason)` | Interno oslobađa pending rezervaciju za razlog `buyer` ili `expired` |
| `expire_reservations()` | Interna obrada koju poziva scheduler |

Primjer JSON formata: jedna stajaća i dvije sjedeće karte, ukupno tri.
Prije poziva odaberi ID-jeve iz svoje baze: kupac i budući događaj moraju postojati, obje kategorije pripadati istom događaju, a sjedala biti slobodna i pripadati sjedećoj kategoriji.
Brojevi u primjeru ilustriraju format; raspoloživost konkretnih ID-jeva ovisi o stanju baze.

```sql
CALL create_reservation(
  1, 6,
  '[{"category_id":9,"quantity":1},{"category_id":10,"seats":[201,202]}]',
  TRUE, @reservation_id
);
SELECT @reservation_id;
```

Za stajaću stavku šalje se `quantity`; za sjedeću `seats` s ID-jevima sjedala, a količina se izvodi iz duljine niza.
OUT vrijednost i sljedeće pozive koristi u istoj vezi. Plaćanje nije integrirano: tek poziv `confirm_reservation` predstavlja uspješnu potvrdu.

Sedam pogleda: `v_category_capacity`, `v_event_capacity`, `v_reservations_by_event`, `v_ticket_stats`, `v_attendance`, `v_revenue_monthly`, `v_reserved_check`.

| Korisnik | Ovlasti |
| --- | --- |
| `eventhub_app` | EXECUTE na prvih pet javnih procedura i SELECT na prvih šest izvještajnih pogleda; nema direktnog SELECT/UPDATE nad tablicama ni pristup `v_reserved_check` |
| `eventhub_report` | SELECT i SHOW VIEW na cijeloj bazi `eventhub`; bez poslovnih upisa i EXECUTE ovlasti |
| `root` | Administracija, migracije, seed i provjere koje zahtijevaju šire ovlasti |

Web prijava treba budući kontrolirani dohvat hasha; `eventhub_app` nema direktan pristup tablici `buyer`.
Definicije: [procedure](migrations/003-procedures-event.sql), [pogledi](migrations/004-views.sql), [grantovi](migrations/005-grants.sql).

## Testiranje i dokazi

Glavna provjera svih funkcionalnih područja:

```bash
python3 tests/test_database.py
```

Runner stvara vlastiti Compose projekt `eventhub-database-test`, mrežu i volumen, bez host portova, koristi testne lozinke te na kraju uklanja svoje resurse.
Provjerava instalaciju od nule, ponovljeni update, seed, poslovne procedure, ovlasti, backup/restore, konkurentnost, UTC/DST i potpuni rollback pa ponovnu instalaciju.
Ne zamjenjuje glavnu ni performance bazu, ali osvježava `tests/results/`; ne pokreći više instanci istog runnera istodobno.
[Spremljeni manifest](tests/results/manifest.json) ima `status: passed`, završetak **2026-10-29** i hashove izvora i sirovih dokaza.

| Područje | Zabilježeni rezultat | Dokument |
| --- | --- | --- |
| Neispravni podaci | 81/81; dodatno 16 odbijenih auth/type/zone unosa | [ispis](docs/01_invalid_data_output.md), [opis](docs/03_testovi_neispravnih_podataka.md) |
| Izvještaji čistog seeda | 18/18 | [izvještaji](docs/04_izvjestaji.md) |
| Transakcije | 7/7 | [transakcije](docs/05_transactions_output.md) |
| Konkurentnost | 4/4; deset veza za zadnju kartu | [konkurentnost](docs/06_concurrency_output.md) |
| UTC/DST matrica | 24 create, 12 confirm, 72 refund, 48 check-in i 12 simulacija sata | [završna validacija](docs/10_schema_validation.md) |
| Rok preko DST prijelaza | 6/6; 900 sekundi u tri zone | [validacija](docs/10_schema_validation.md), [dokaz](tests/results/dst_expiry.txt) |
| Backup/restore | 12 tablica, isti checksumi i epoch vrijednosti vremenskih stupaca | [administracija](docs/08_administracija.md) |
| Potpuni rollback i ponovna instalacija | 55/55 | [validacija](docs/10_schema_validation.md) |
| Prezentacijski neuspješan poziv | Očekivani 1644, zauzeće ostaje 8/10 | [prezentacija](docs/09_presentation.md) |
| Indeksi i performanse | Zasebno mjerenje na 100.175 rezervacija | [performanse](docs/07_performanse.md) |

A scenarij konkurentnosti namjerno reproducira oversell; PASS znači da je problem prikazan i zatim popravljen, a ne da je takav način kupnje ispravan.
Pojedinačne skripte nad glavnom testnom bazom pokreći ovim redom; izvještaje i performance pripremu radi na čistom seedu **prije** demonstracija koje dodaju podatke:

```bash
docker compose exec -T db sh -c 'MYSQL_PWD="$EVENTHUB_REPORT_PASSWORD" mariadb -ueventhub_report eventhub' < reports/01_reports.sql
docker compose exec -T db sh -c 'MYSQL_PWD="$MARIADB_ROOT_PASSWORD" mariadb -uroot eventhub' < reports/02_verify_reports.sql
docker compose exec -T db sh -c 'MYSQL_PWD="$MARIADB_ROOT_PASSWORD" mariadb -uroot eventhub' < tests/01_invalid_data.sql
docker compose exec -T db sh -c 'MYSQL_PWD="$MARIADB_ROOT_PASSWORD" mariadb -uroot eventhub' < tests/05_transactions.sql
bash tests/06_concurrency.sh
docker compose exec -T db sh -c 'MYSQL_PWD="$EVENTHUB_REPORT_PASSWORD" mariadb --force -ueventhub_report eventhub' < tests/08_readonly_user.sql
docker compose exec -T db sh -c 'MYSQL_PWD="$MARIADB_ROOT_PASSWORD" mariadb -uroot eventhub' < tests/09_presentation.sql
```

`tests/08_readonly_user.sql` namjerno daje greške 1142/1370; `--force` omogućuje provjeru svih pokušaja.
`tests/09_presentation.sql` završava očekivanom greškom zbog nedostatka mjesta i nenultim izlaznim kodom; to je planirani kraj demonstracije.
Transakcijski, konkurentni i prezentacijski scenariji dodaju demo zapise; za ponavljanje poznatih seed ukupnih iznosa vrati čisti seed resetom.

## Performanse i indeksi

`eventhub_perf` je zasebna kopija nove sheme s **100.175 rezervacija i 189.133 karte**; scheduler u kopiji je DISABLED.
Mjerenje iz [performance manifesta](perf/results/series_manifest.json), završeno **2026-10-29**, uspoređuje A/B/C/D u tri kruga, po pet mjerenja nakon zagrijavanja: medijani imaju po 15 uzoraka.
Konačna konfiguracija **B** zadržava uske `idx_res_confirmed_at(confirmed_at)` i `idx_ticket_cancelled_at(cancelled_at)`, uz postojeće PK/UNIQUE/FK i operativne indekse.

| Mjerenje | A: bez analiziranih indeksa | B: uski indeksi |
| --- | --- | --- |
| Q3: bruto prodaja u UTC danu | oko 206,3 ms | oko 0,144 ms |
| Q5: povrati u UTC mjesecu | oko 58,2 ms | oko 0,709 ms |
| INSERT mikrobenchmark: medijan | oko 156,5 ms | oko 158,0 ms, odnosno približno 0,94 % sporije u ovom nizu |

To je kompromis ovog opterećenja između čitanja, prostora i održavanja indeksa, ne univerzalni optimum.
INSERT test koristi privremenu kopiju `reservation`, bez FK-ova i triggera; ne mjeri cijelu poslovnu transakciju ni pisanje `ticket` indeksa.
Cijeli A/B/C/D niz ponovljen je; svih 60 mjerenih INSERT uzoraka ima valjano trajanje. Runner i generator odbijaju negativna trajanja. Mala razlika INSERT medijana A/B podložna je šumu mjerenja.
Q3/Q5 koriste UTC granice; poslovni mjesečni izvještaj Q2 koristi Europe/Zagreb. Planovi i ograničenja: [analiza performansi](docs/07_performanse.md).

Za ponavljanje kreni od čistog `eventhub` seeda sa 175 rezervacija. **Prvi korak zamjenjuje postojeću bazu `eventhub_perf`**, ne glavnu bazu.
Prije novog mjerenja arhiviraj postojeće `perf/results/series.tsv` i `perf/results/series_manifest.json` izvan `perf/results/`: runner odbija prepisati seriju.

```bash
bash perf/00_create_perf_db.sh
docker compose exec -T db sh -c 'MYSQL_PWD="$MARIADB_ROOT_PASSWORD" mariadb -uroot' < perf/01_generate_100k.sql
python3 perf/run_series.py
python3 perf/summarize.py --document
```

Zadnja naredba ispisuje analizu; sirovi EXPLAIN/ANALYZE planovi i vremena su u [series.tsv](perf/results/series.tsv).
Runner nakon mjerenja vraća konfiguraciju B, a manifest bilježi hashove sheme, generatora i upita te stvarne tipove stupaca.

## Backup i restore

Logički backup uključuje strukturu, podatke, poglede, procedure, funkcije, triggere i zakazane evente:

```bash
mkdir -p backup
docker compose exec -T db sh -c 'MYSQL_PWD="$MARIADB_ROOT_PASSWORD" mariadb-dump -uroot --single-transaction --routines --triggers --events eventhub' > backup/eventhub_backup.sql
```

Za novi backup odaberi novo ime ako postojeću datoteku želiš zadržati; prikazana redirekcija prepisuje istoimeni dump.
Dump sadrži podatke i hashove kupaca, ne ide u Git; `.gitignore` isključuje `backup/*.sql` i `backup/*.sql.gz`.
Tijekom konzistentnog InnoDB backupa ne izvodi DDL promjene. Korisnici i grantovi nisu dio backupa jedne aplikacijske baze.
Restore radi u novu praznu bazu i isključi kopirani scheduler već pri uvozu, bez gašenja originalnog eventa.
Postupak i usporedbe svih tablica/checksuma/vremenskih vrijednosti: [backup, restore i ovlasti](docs/08_administracija.md).

## Pretpostavke i ograničenja

- Ovo je resetabilno testno okruženje. Za stvarne podatke potrebni su plan nadogradnje bez prepisivanja primijenjenih migracija i odvojena politika backupa.
- Nema payment gatewaya: `confirm_reservation` simulira uspješno plaćanje; stvarna integracija i kompenzacija pripadaju aplikaciji.
- Web autentikacija, sesije, reset lozinke i isporuka karata nisu implementirani; login atributi sami nisu gotova autentikacija.
- Oslobađanje isteklih holdova ovisi o uključenom scheduleru i njegovu minutnom ciklusu.
- Transakcijska povijest se ne briše; politika zadržavanja i arhiviranja podataka još nije definirana.
- Buduća aplikacija treba retry za deadlock **1213**, uz kratki odmak i najviše tri pokušaja po CALL-u; u repozitoriju nema aplikacijskog sloja ni connection poola.
- Dokazi se odnose na navedene provjere i MariaDB okruženje; ne predstavljaju produkcijski stress test niti jamstvo za svako moguće opterećenje.

## Dokumentacija

| Datoteka | Što sadrži |
| --- | --- |
| [02_database_structure.md](docs/02_database_structure.md) | Entitete, veze, integritet, vremenski model i obrazloženja odluka. |
| [setup_reference_hr.md](docs/setup_reference_hr.md) | Lokalno postavljanje, DBeaver i ponavljanje provjera. |
| [liquibase.md](docs/liquibase.md) | Redoslijed migracija, reset, validaciju i rollback testne sheme. |
| [01_invalid_data_output.md](docs/01_invalid_data_output.md) | Stvarni ispis 81 testa neispravnih podataka. |
| [03_testovi_neispravnih_podataka.md](docs/03_testovi_neispravnih_podataka.md) | Namjeru negativnih testova, kodove grešaka i očekivane zaštite. |
| [04_izvjestaji.md](docs/04_izvjestaji.md) | Osam izvještaja i 18 provjera njihovih rezultata. |
| [05_transactions_output.md](docs/05_transactions_output.md) | Rezultate uspješnih i neuspješnih kupnji, COMMIT-a i ROLLBACK-a. |
| [06_concurrency_output.md](docs/06_concurrency_output.md) | Četiri scenarija zadnje karte i dokaze konkurentnih sesija. |
| [07_performanse.md](docs/07_performanse.md) | EXPLAIN/ANALYZE planove, vremena, prostor i kompromise odabranih indeksa. |
| [08_administracija.md](docs/08_administracija.md) | Backup/restore, usporedbe podataka i provjeru ovlasti. |
| [09_presentation.md](docs/09_presentation.md) | Redoslijed demonstracije za prezentaciju projekta. |
| [10_schema_validation.md](docs/10_schema_validation.md) | Završnu pokrivenost nove sheme, ispravke i reprodukciju provjera. |
| [render_docs.py](docs/render_docs.py) | Generator dokumenata iz provjerenih dokaza; provjerava hashove izvora i rezultata te čuva postojeći PNG dijagram. |

`docs/render_docs.py` osvježava dokumente iz rezultata provjera; ne mijenja ovaj README ni postojeći dijagram.
README i dokumentacija koriste `eventhub-diagram.png`.
