# EventHub — lokalna MariaDB baza

Potrebni su Docker s Compose dodatkom i SQL klijent (npr. DBeaver).
Naredbe pokreni iz korijena projekta; primjeri koriste Bash/WSL.

## Pokretanje

```bash
cp .env.example .env
```

U `.env` postavi tri vlastite, različite lozinke:
`MARIADB_ROOT_PASSWORD`, `EVENTHUB_APP_PASSWORD` i `EVENTHUB_REPORT_PASSWORD`.
Ako `.env` već postoji, uredi ga bez ponovnog kopiranja.

```bash
docker compose up -d --wait --wait-timeout 120
docker compose ps
```

Servis `db` treba imati status `healthy`. Port `3306` mora biti slobodan.
Za dijagnostiku: `docker compose logs db`.
Na prvom pokretanju skripte iz `init/` automatski stvaraju bazu `eventhub`,
tablice, funkcije, triggere, procedure, viewove i korisnike.

## Spajanje i provjera

U DBeaveru napravi MariaDB vezu:

| Postavka | Vrijednost |
|---|---|
| Host | `127.0.0.1` |
| Port | `3306` |
| Database | `eventhub` |
| Username | `eventhub_app` |
| Password | vrijednost `EVENTHUB_APP_PASSWORD` iz `.env` |

Izvrši:

```sql
SELECT CURRENT_USER();
SELECT * FROM v_event_capacity LIMIT 5;
```

Na praznoj bazi drugi upit vraća prazan rezultat. `eventhub_app` smije pozivati
poslovne procedure i čitati izvještajne viewove. Za čitanje svih tablica koristi
`eventhub_report` i `EVENTHUB_REPORT_PASSWORD`; za administraciju `root` i
`MARIADB_ROOT_PASSWORD`.

Ista provjera kroz SQL klijent unutar kontejnera:

```bash
docker compose exec -T db sh -c 'MYSQL_PWD="$EVENTHUB_APP_PASSWORD" mariadb -ueventhub_app eventhub -e "SELECT CURRENT_USER(); SELECT * FROM v_event_capacity LIMIT 5;"'
```

## Testni podaci (opcionalno)

Na praznoj bazi jednom pokreni realni seed (8 događaja i 175 rezervacija):

```bash
docker compose exec -T db sh -c 'MYSQL_PWD="$MARIADB_ROOT_PASSWORD" mariadb -uroot eventhub' < seed/01_seed.sql
```

Za zasebnu performance bazu:

```bash
bash perf/00_create_perf_db.sh
docker compose exec -T db sh -c 'MYSQL_PWD="$MARIADB_ROOT_PASSWORD" mariadb -uroot' < perf/01_generate_100k.sql
```

Prva naredba briše postojeću `eventhub_perf` i kopira glavnu bazu u nju.
Druga dodaje 100.000 rezervacija (uz 175 kopiranih iz realnog seeda).
Glavna baza ostaje nepromijenjena. Za vezu na `eventhub_perf` koristi isti
host, port i root pristup; mijenja se samo naziv baze.

## Pohrana i zaustavljanje

Podaci su u Docker volumenu `db_data` i ostaju nakon restarta ili
`docker compose down`. Zaustavljanje i ponovno pokretanje:

```bash
docker compose down
docker compose up -d --wait --wait-timeout 120
```

Za provjeru postojanosti nakon seeda zabilježi rezultat
`SELECT COUNT(*) FROM reservation;` kroz korisnika `eventhub_report`, pokreni
`docker compose restart db`, pričekaj status `healthy` i ponovi upit.

**Nemoj koristiti `docker compose down -v` ako želiš sačuvati podatke:**
briše volumen s obje baze. Init skripte izvršavaju se samo na praznom volumenu;
promjena `.env` ne mijenja već stvorene lozinke.

`.env` je ignoriran Gitom. Commitaj samo `.env.example` bez stvarnih lozinki.

## Izvještaji

Osam izvještaja i PASS/FAIL provjere za realni seed nalaze se u `reports/`.
Naredbe, definicije i očekivani rezultati: [Task 4 — Izvještaji](docs/04_izvjestaji.md).
