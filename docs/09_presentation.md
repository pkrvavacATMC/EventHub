# Vodič za prezentaciju

Naredbe pokreći iz korijena repozitorija nakon postavljanja prema [README-u](../README.md). Najprije pročitaj [opis baze](02_database_structure.md). Spremljeni rezultati ponovno su generirani za aktualnu shemu; pogledaj [manifest provjere](../tests/results/manifest.json).

## 1. Priprema izvještaja i podataka za mjerenje performansi

Pokreni nad čistim početnim skupom podataka, prije demonstracija koje dodaju zapise:

```bash
docker compose exec -T db sh -c 'MYSQL_PWD="$MARIADB_ROOT_PASSWORD" mariadb -uroot eventhub' < reports/01_reports.sql
docker compose exec -T db sh -c 'MYSQL_PWD="$MARIADB_ROOT_PASSWORD" mariadb -uroot eventhub' < reports/02_verify_reports.sql
bash perf/00_create_perf_db.sh
docker compose exec -T db sh -c 'MYSQL_PWD="$MARIADB_ROOT_PASSWORD" mariadb -uroot' < perf/01_generate_100k.sql
```

Provjera izvještaja treba dati 18 PASS i 0 FAIL. Priprema podataka za performanse **zamjenjuje eventhub_perf**, a `eventhub` ostavlja netaknutim. Kopija čistog početnog skupa proširena generatorom ima 100.175 rezervacija.

Pomoću izvještajnih SQL upita objasni kapacitet, prihod i mjesečne trendove. Objasni zašto LEFT JOIN zadržava događaje bez kupnji, zašto se naknada zaštite broji jednom po rezervaciji te kako se otkazivanje razlikuje od isteka pri izračunu stope otkazivanja.

## 2. Objašnjenje ER dijagrama

Otvori dijagram iz README-a. Prati vezu `buyer → reservation → reservation_item → ticket`, zatim `ticket_category → seat → reservation_seat`. Objasni kompozitne strane ključeve, povijesni zapis cijene i generirani ključ aktivnog zauzeća sjedala.

## 3. Uspješna i odbijena rezervacija

```bash
docker compose exec -T db sh -c 'MYSQL_PWD="$MARIADB_ROOT_PASSWORD" mariadb -uroot eventhub' < tests/09_presentation.sql
```

Očekuje se potvrđena rezervacija, četiri izdane karte i `reserved=4`. Druga kupnja povećava zauzeće na osam. Završni zahtjev za tri karte premašuje preostala dva mjesta, pa se očekuju SQL greška i nenulti izlazni kod klijenta. Poslovne poruke grešaka su na hrvatskom.

Kopiraj ispisani identifikator demo kategorije i provjeri ga u novoj administratorskoj vezi: `SELECT capacity, reserved FROM ticket_category WHERE id = <demo_category>;`. Očekivano je `capacity=10` i `reserved=8`. Za ispisani identifikator događaja trebaju postojati samo dvije rezervacije. Odbijeni poziv ne smije ostaviti djelomičnu rezervaciju. Objasni zašto je količina tri sama po sebi dopuštena, ali ovdje nema dovoljno mjesta. Svako ponovno pokretanje stvara nove demo podatke.

## 4. Transakcije i konkurentne kupnje

```bash
docker compose exec -T db sh -c 'MYSQL_PWD="$MARIADB_ROOT_PASSWORD" mariadb -uroot eventhub' < tests/05_transactions.sql
bash tests/06_concurrency.sh
```

Očekuje se 7/7 transakcijskih provjera i četiri uspješne provjere konkurentnosti. PASS u namjerno nesigurnom scenariju znači da je nedosljednost reproducirana. Objasni neuspjelo plaćanje, otkazivanje i ROLLBACK kao zasebne operacije.

Scenarij A reproducira prodaju iznad kapaciteta bez zaključavanja; B serijalizira dvije sesije pomoću FOR UPDATE; C odbija relativno povećanje brojača preko CHECK ograničenja; D dopušta točno jednoj od deset sesija kupnju zadnje karte kroz stvarne procedure. Objasni što druga sesija vidi nakon čekanja i zašto ispravan brojač sam po sebi ne dokazuje usklađenost podataka. Testovi dodaju nove demo događaje i zahtijevaju administratorske ovlasti.

Spremljeni dokazi: [transakcije](05_transactions_output.md), [konkurentnost](06_concurrency_output.md).

## 5. Optimizacija

Koristi [izmjerene planove i rezultate](07_performanse.md), uz njihov datum i verziju sheme. Prije novog mjerenja pripremi bazu prema aktualnoj shemi; manifest bilježi hashove sheme, generatora i SQL upita. Prethodnu seriju arhiviraj izvan `perf/results`. Stara vremena ne predstavljaj kao rezultate nove verzije baze.

```bash
python3 perf/run_series.py
python3 docs/render_docs.py --with-performance
```

Četiri konfiguracije izvode se u tri kruga kroz jednu sesiju, a na kraju se vraćaju uski indeksi. Objasni stvarno pročitane retke, odabir indeksa, zauzeće prostora, trošak pisanja i ograničenja mjerenja. Širi indeksi mogu ubrzati čitanje; konačni odabir ovisi o opterećenju.

## Dodatne pojedinačne provjere

Nakon migracija i seeda pokreni kao administrator; test neispravnih podataka poništava svoje upise, a provjera ovlasti očekuje odbijene naredbe:

```bash
docker compose exec -T db sh -c 'MYSQL_PWD="$MARIADB_ROOT_PASSWORD" mariadb -uroot eventhub' < tests/01_invalid_data.sql
docker compose exec -T db sh -c 'MYSQL_PWD="$EVENTHUB_REPORT_PASSWORD" mariadb --force -ueventhub_report eventhub' < tests/08_readonly_user.sql
```

Potpuni backup/restore i rollback provjerava izolirani `python3 tests/test_database.py`; ručni backup je u [administraciji](08_administracija.md).

## Završna priprema

Samostalno objasni svaku opaženu promjenu: koji se redak zaključava, što se poništava, kada se izdaju karte i kako pogled za provjeru usklađenosti otkriva odstupanja. Razlikuj očekivane zbrojeve čistog početnog skupa od podataka proširenih demonstracijama. Neočekivani rezultat provjeri izravno; stara tablica s oznakama PASS nije dokaz trenutačnog stanja.

Stvarni odbijeni prezentacijski poziv i prethodne uspješne kupnje zabilježeni su u [presentation.txt](../tests/results/presentation.txt).
