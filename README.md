# EventHub

EventHub je MariaDB baza za rezervaciju i prodaju karata za događaje sa sjedećim i stajaćim mjestima. Podržava rezervacije, izdavanje karata, provjeru na ulazu, otkazivanja i povrate novca.

Poslovna logika nalazi se u procedurama, triggerima i ograničenjima baze. Projekt sadrži shemu, početne podatke, SQL izvještaje i testove; nema web aplikaciju ni integraciju s platnim sustavom.

## Dijagram baze

![EventHub ER dijagram](eventhub-diagram.png)

Događaj pripada organizatoru i lokaciji te ima kategorije karata. Veza `buyer → reservation → reservation_item → ticket` povezuje kupca s rezervacijom i izdanim kartama, dok `ticket_category → seat → reservation_seat` prati sjedala i njihova zauzeća.

## Preduvjeti

- Git
- Docker s Compose v2
- Bash terminal (na Windowsu WSL)
- Slobodan lokalni port `3306`
- Python 3 za testove; dovoljna je standardna biblioteka

DBeaver ili drugi SQL klijent je opcionalan. MariaDB i Liquibase preuzimaju se i pokreću kroz Docker; ne treba ih zasebno instalirati.

## Pokretanje

1. Kloniraj repozitorij:

   ```bash
   git clone https://github.com/pkrvavacATMC/EventHub.git
   cd EventHub
   ```

   Sve sljedeće naredbe pokreći iz korijena projekta.

2. Pripremi lokalnu konfiguraciju:

   ```bash
   cp .env.example .env
   ```

   U `.env` postavi tri različite lozinke: `MARIADB_ROOT_PASSWORD`, `EVENTHUB_APP_PASSWORD` i `EVENTHUB_REPORT_PASSWORD`. Datoteka `.env` ostaje lokalno i ne sprema se u Git.

3. Pokreni bazu:

   ```bash
   docker compose up -d
   docker compose ps -a
   ```

   Liquibase automatski postavlja shemu i ovlasti. Pričekaj da `db` bude `healthy`, a `liquibase` završi sa statusom `Exited (0)`. Ako migracije ne uspiju, provjeri `docker compose logs liquibase`.

4. Nakon uspješnih migracija jednom učitaj početne podatke u praznu poslovnu bazu:

   ```bash
   docker compose exec -T db sh -c 'MYSQL_PWD="$MARIADB_ROOT_PASSWORD" mariadb -uroot eventhub' < seed/01_seed.sql
   ```

5. Provjeri da su podaci učitani i brojači zauzeća usklađeni:

   ```bash
   docker compose exec -T db sh -c 'MYSQL_PWD="$MARIADB_ROOT_PASSWORD" mariadb -uroot eventhub -e "SELECT COUNT(*) AS rezervacije FROM reservation; SELECT COUNT(*) AS neuskladeni_brojaci FROM v_reserved_check;"'
   ```

   Nakon učitavanja početnih podataka očekuje se `175` rezervacija i `0` neusklađenih brojača.

Za zaustavljanje koristi `docker compose down`, a za nastavak rada `docker compose up -d`. Podaci ostaju na Docker volumenu, pa početne podatke ne učitavaj ponovno. `docker compose down -v` briše volumen i sve baze na njemu.

## Spajanje

Baza je dostupna na `127.0.0.1:3306`, pod nazivom `eventhub`. Lozinke su vrijednosti koje si postavio u `.env`.

| Korisnik | Lozinka iz `.env` | Namjena |
| --- | --- | --- |
| `root` | `MARIADB_ROOT_PASSWORD` | Administracija i učitavanje podataka |
| `eventhub_app` | `EVENTHUB_APP_PASSWORD` | Poslovne procedure i izvještajni pogledi |
| `eventhub_report` | `EVENTHUB_REPORT_PASSWORD` | Čitanje tablica i pogleda |

U SQL klijentu uključi **Autocommit** za pozive poslovnih procedura i koristi UTC zonu veze:

```sql
SET time_zone = '+00:00';
SELECT DATABASE(), @@session.time_zone;
```

Očekivani rezultat je baza `eventhub` i zona `+00:00`.

## Testiranje

Pokreni automatske testove:

```bash
python3 tests/test_database.py
```

Testovi provjeravaju migracije, integritet podataka, poslovne procedure, konkurentne kupnje, ovlasti te backup i restore. Koriste vlastiti izolirani Compose projekt i ne mijenjaju glavnu bazu. Pri završetku automatski uklanjaju svoje kontejnere, mrežu i volumen.
