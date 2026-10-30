# DBeaver i ponavljanje mjerenja

Postavi projekt prema [README-u](../README.md#pokretanje-od-nule); ovdje su samo dodatne postavke klijenta i priprema mjerenja.

## DBeaver

Odaberi MariaDB vezu i unesi host, port i korisnika iz [uputa za spajanje](../README.md#spajanje). Uključi Autocommit za poslovne procedure i nemoj ih omotati vanjskom transakcijom.
U inicijalizaciji veze postavi `SET time_zone = '+00:00';`, zatim provjeri:

```sql
SELECT DATABASE(), @@session.time_zone;
```

Očekivano je `eventhub` i `+00:00`. Nakon migracija osvježi navigator i ponovno otvori ER dijagram; JDBC parametri i model vremena opisani su u [strukturi baze](02_database_structure.md#model-vremena).

## Ponovno mjerenje performansi

Pripremi glavnu bazu s čistim seedom prije demonstracija koje dodaju podatke. Sljedeća priprema zamjenjuje samo `eventhub_perf`; stari `perf/results/series.tsv` i `perf/results/series_manifest.json` prethodno arhiviraj izvan `perf/results/`.

```bash
bash perf/00_create_perf_db.sh
docker compose exec -T db sh -c 'MYSQL_PWD="$MARIADB_ROOT_PASSWORD" mariadb -uroot' < perf/01_generate_100k.sql
python3 perf/run_series.py
python3 docs/render_docs.py --with-performance
```

Očekuje se uspješna serija mjerenja i provjera hashova prije osvježavanja dokumentacije. [Analiza performansi](07_performanse.md) čuva brojke i ograničenja; rezultati prethodne sheme nisu mjerenje aktualne sheme.
