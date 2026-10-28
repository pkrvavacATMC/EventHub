# TASK 7 - Analiza performansi

## Sazetak

| Medijani (ms) | Q1 | Q2 | Q3 | Q4 | Q5 | INSERT |
| --- | --- | --- | --- | --- | --- | --- |
| A | 82.37 | 804.00 | 116.81 | 0.12 | 30.97 | 90.49 |
| B | 73.57 | 321.98 | 0.08 | 0.05 | 0.32 | 97.33 |

Zadrzavamo uske indekse (B); A je stanje bez analiziranih indeksa.
Indeks kupca odbacujemo: mala usteda Q4 prati +50.9 % INSERT-a u reservation.
Pokrivajuci indeks povrata odbacujemo radi prostora i jednostavnosti; njegova cijena pisanja nije izmjerena.

Konacni izbor ostaje uski `idx_res_confirmed_at(confirmed_at)` i
`idx_ticket_cancelled_at(cancelled_at)`. FK/UNIQUE i ostali postojeci operativni
indeksi ostaju. Sve usporedbe u ovom dokumentu potjecu iskljucivo iz jednog novog
niza mjerenja; stara neusporediva mjerenja su obrisana.

## Skup podataka i okruzenje

MariaDB 10.11.19-MariaDB-ubu2204, InnoDB, Docker `eventhub-db`, buffer pool
134217728 bajtova. `eventhub_perf` sadrzi 100.175 rezervacija i
189.133 karte: kopirani seed i 100.000 rezervacija iz `perf/01_generate_100k.sql`.
Postojeci skup zadovoljava prag; u ovoj reviziji nije regeneriran niti obnovljen.
`v_reserved_check` na kraju vraca 0 odstupanja. Perf scheduler je iskljucen.

## Postupak i ponavljanje

Iz korijena projekta, uz vec pripremljeni eventhub_perf:

```bash
# Prije novog pokretanja sacuvaj prethodni series.tsv i series_manifest.json
# u zasebnu mapu; runner odbija prepisati postojeci series.tsv.
python3 perf/run_series.py
python3 perf/summarize.py --document > docs/07_performanse.md
```

Ako performance baza nedostaje, prvo `bash perf/00_create_perf_db.sh` pa
`perf/01_generate_100k.sql` prema uputama generatora. To nije potrebno za ponavljanje
samih mjerenja i zamjenjuje postojecu performance kopiju.

Runner koristi jedan `docker exec` i jedan `mariadb --batch` proces/vezu. U toj
istoj sesiji redom izvrsava A, B, C, D, pa cijeli niz ponavlja ukupno tri puta:

| Konfiguracija | Skripte i stanje |
| --- | --- |
| A | 02_baseline.sql: bez analiziranih indeksa |
| B | 03_add_indexes.sql + 04_after.sql: dva konacna uska indeksa |
| C | 07_rejected_indexes.sql + 04_after.sql: uski datum potvrde, indeks kupca i pokrivajuci povrati |
| D | 06_rejected_cover.sql: siri datum potvrde uz iste ostale kandidate kao C |

Nakon treceg D runner izvrsava **02 -> 03** za povrat konacnog stanja. Mjerenja
koja se zbog sadrzaja 02 izvrse tijekom povrata oznacena su SERIES_RESTORE i
iskljucena iz statistike. Upiti, indeksi konfiguracija i SQL datoteke 02/03/04/06/07
nisu mijenjani u ovoj reviziji.

Sesija CONNECTION_ID=308; pocetak 2026-10-28 13:11:37.080835, kraj
2026-10-28 13:13:01.086351 (vrijeme servera). `series.tsv` sadrzi oznake svakog kruga,
iste CONNECTION_ID vrijednosti, sve sirove planove i popis indeksa svake
konfiguracije. `series_manifest.json` biljezi SHA-256 izvrsenih SQL datoteka,
rezultata, UTC vrijeme pokretanja i izlazni kod. `summarize.py` provjerava hash
rezultata, istu sesiju, redoslijed 12 konfiguracija, broj uzoraka i stvarne indekse.

Za svaki upit i INSERT u svakom krugu izvrsava se jedno zagrijavanje i pet
mjerenja. Konacna vrijednost je **medijan svih 15 pojedinacnih mjerenja**, a ne
medijan triju medijana. Prikazan je min-max svih 15 uzoraka. Query cache je OFF,
SELECT koristi SQL_NO_CACHE; InnoDB buffer pool nije praznjen. To je usporedba
zagrijanog rada, ne hladnog diska. U fiksnom A-D redoslijedu mogu ostati vremenski
trendovi i utjecaj OS-a; tri kruga i rasponi ih pokazuju, ali ih potpuno ne uklanjaju.

Vremena SELECT-a su korijenski `query_block.r_total_time_ms` iz ANALYZE JSON-a:
ukljucuju instrumentaciju, ne pokretanje Dockera ni prijenos rezultata klijentu.
Podcvorovi se ne zbrajaju jer vec ulaze u roditelja. `EXPLAIN.rows` je procjena,
`r_rows` prosjecan stvarni broj po petlji; ukupni dohvati ovise i o `r_loops`.
[MariaDB: ANALYZE FORMAT=JSON](https://mariadb.com/docs/server/reference/sql-statements/administrative-sql-statements/analyze-and-explain-statements/analyze-format-json).

Baseline ne uklanja PK/UNIQUE/FK indekse. `idx_res_event_status` je ujedno potporni
indeks fk_res_event, a fk_res_buyer se osigurava prije brisanja kandidata s istim
lijevim prefiksom. idx_res_status_expires i idx_event_date nisu kandidati ovog testa.
Q1/Q2 ovdje su Task 4 Q2/Q8; Q3-Q5 su dodatni selektivni upiti. Viewovi, triggeri,
procedure, podaci i SQL upiti ostaju isti.

Stara neusporediva mjerenja su obrisana. Jedini izvor usporedbi je
**perf/results/series.tsv** s tri A-D kruga u istoj sesiji.

## Izmjerena vremena

Samo series.tsv: jedna MariaDB sesija, tri uzastopna A-D kruga. Svaka celija: medijan [min-max] u ms svih 15 mjerenja (5 po krugu); vremena >= 1 ms imaju jednu decimalu, manja tri; tri zagrijavanja po konfiguraciji/upitu su iskljucena. Arhiva nije ukljucena.

| Upit | A: Bez analiziranih indeksa | B: Konacni uski | C: Kupac + pokrivajuci povrati | D: Siri indeks potvrda + C |
| --- | --- | --- | --- | --- |
| Q1 | 82.4 [69.2-88.0] | 73.6 [61.8-95.4] | 70.0 [61.0-102.7] | 82.2 [66.8-94.1] |
| Q2 | 804.0 [710.4-874.1] | 322.0 [270.1-374.9] | 293.4 [267.5-316.6] | 365.1 [291.1-441.4] |
| Q3 | 116.8 [101.9-131.2] | 0.077 [0.062-0.149] | 0.072 [0.058-0.223] | 0.086 [0.061-0.123] |
| Q4 | 0.123 [0.064-0.299] | 0.052 [0.040-0.121] | 0.026 [0.021-0.057] | 0.029 [0.020-0.038] |
| Q5 | 31.0 [27.9-42.7] | 0.317 [0.259-0.633] | 0.072 [0.062-0.157] | 0.082 [0.061-0.092] |

### Medijani pojedinih krugova

| Krug | Konfiguracija | Q1 | Q2 | Q3 | Q4 | Q5 | INSERT ms |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | A | 78.4 | 795.9 | 128.3 | 0.150 | 31.8 | 83.6 |
| 1 | B | 72.4 | 345.6 | 0.083 | 0.052 | 0.508 | 115.0 |
| 1 | C | 68.9 | 296.5 | 0.072 | 0.024 | 0.070 | 145.5 |
| 1 | D | 82.2 | 359.9 | 0.088 | 0.029 | 0.088 | 162.9 |
| 2 | A | 82.4 | 804.0 | 110.7 | 0.101 | 30.1 | 89.1 |
| 2 | B | 74.3 | 297.0 | 0.066 | 0.045 | 0.278 | 100.6 |
| 2 | C | 69.1 | 281.6 | 0.069 | 0.035 | 0.076 | 156.3 |
| 2 | D | 82.5 | 394.6 | 0.090 | 0.029 | 0.089 | 151.3 |
| 3 | A | 83.4 | 818.5 | 117.4 | 0.151 | 31.0 | 101.6 |
| 3 | B | 65.8 | 328.1 | 0.077 | 0.053 | 0.317 | 95.3 |
| 3 | C | 93.6 | 293.4 | 0.120 | 0.023 | 0.118 | 146.8 |
| 3 | D | 79.7 | 345.6 | 0.066 | 0.027 | 0.063 | 161.1 |

## SQL, EXPLAIN i stvarni redci

Potpuni EXPLAIN i JSON planovi sva tri kruga ostaju u series.tsv. Ovdje su planovi prvog kruga svih konfiguracija; rows je procjena, r_rows prosjek stvarnih redaka po petlji, r_loops broj petlji.

### Q1 - Kupci s najvise rezervacija (Task 4 Q2)

Cest rang izvjestaj i kontrola citanja cijelog skupa. FK indeks pokriva COUNT, ali sve rezervacije i dalje treba brojiti, uz agregaciju i filesort. Dodatni indeks povijesti ne uklanja taj posao.

```sql
SELECT SQL_NO_CACHE b.id AS buyer_id, b.name, b.surname, COUNT(r.id) AS reservations
FROM buyer b LEFT JOIN reservation r ON r.buyer_id = b.id
GROUP BY b.id, b.name, b.surname
ORDER BY reservations DESC, buyer_id;
```

**A: Bez analiziranih indeksa - EXPLAIN, krug 1**

| id | select_type | tablica | type | key | rows | Extra |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | SIMPLE | b | ALL | NULL | 5043 | Using temporary; Using filesort |
| 1 | SIMPLE | r | ref | fk_res_buyer | 9 | Using index |

ANALYZE, krug 1, mjerenje 1:

| tablica | access_type | key | r_loops | r_rows |
| --- | --- | --- | --- | --- |
| b | ALL | - | 1 | 5040 |
| r | ref | fk_res_buyer | 5040 | 19.87599206 |

15 vremena (ms), redom krugovi 1-3: 83.4, 78.4, 77.3, 69.3, 84.4, 75.2, 84.6, 87.8, 82.4, 69.2, 83.4, 88.0, 80.6, 83.5, 75.3.

**B: Konacni uski - EXPLAIN, krug 1**

| id | select_type | tablica | type | key | rows | Extra |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | SIMPLE | b | ALL | NULL | 5043 | Using temporary; Using filesort |
| 1 | SIMPLE | r | ref | fk_res_buyer | 10 | Using index |

ANALYZE, krug 1, mjerenje 1:

| tablica | access_type | key | r_loops | r_rows |
| --- | --- | --- | --- | --- |
| b | ALL | - | 1 | 5040 |
| r | ref | fk_res_buyer | 5040 | 19.87599206 |

15 vremena (ms), redom krugovi 1-3: 73.6, 69.3, 71.7, 72.4, 73.6, 74.3, 74.1, 82.1, 88.9, 68.4, 61.8, 74.0, 63.8, 65.8, 95.4.

**C: Kupac + pokrivajuci povrati - EXPLAIN, krug 1**

| id | select_type | tablica | type | key | rows | Extra |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | SIMPLE | b | ALL | NULL | 5043 | Using temporary; Using filesort |
| 1 | SIMPLE | r | ref | fk_res_buyer | 10 | Using index |

ANALYZE, krug 1, mjerenje 1:

| tablica | access_type | key | r_loops | r_rows |
| --- | --- | --- | --- | --- |
| b | ALL | - | 1 | 5040 |
| r | ref | fk_res_buyer | 5040 | 19.87599206 |

15 vremena (ms), redom krugovi 1-3: 69.4, 68.9, 68.6, 74.4, 61.0, 102.7, 65.7, 69.1, 62.9, 70.0, 76.4, 77.2, 94.6, 93.6, 95.0.

**D: Siri indeks potvrda + C - EXPLAIN, krug 1**

| id | select_type | tablica | type | key | rows | Extra |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | SIMPLE | b | ALL | NULL | 5043 | Using temporary; Using filesort |
| 1 | SIMPLE | r | ref | fk_res_buyer | 10 | Using index |

ANALYZE, krug 1, mjerenje 1:

| tablica | access_type | key | r_loops | r_rows |
| --- | --- | --- | --- | --- |
| b | ALL | - | 1 | 5040 |
| r | ref | fk_res_buyer | 5040 | 19.87599206 |

15 vremena (ms), redom krugovi 1-3: 66.8, 77.7, 93.1, 82.2, 87.0, 76.7, 94.1, 89.6, 79.1, 82.5, 74.7, 73.0, 79.7, 88.2, 83.3.

### Q2 - Mjesecni trend prihoda (Task 4 Q8)

Najskuplji izvjestaj: UNION ALL prodaje, zastite i povrata te vise agregacija. B omogucuje range rijetkih povrata; C pokriva njihov SUM/JOIN. D pokriva i datum/event/naknadu zastite. Sve konfiguracije i dalje obradjuju velik dio rezervacija; temporary/filesort ne nestaju.

```sql
SELECT SQL_NO_CACHE month, SUM(ticket_gross) AS ticket_gross,
       SUM(protection_fees) AS protection_fees, SUM(refunds) AS refunds,
       SUM(net_revenue) AS net_revenue
FROM v_revenue_monthly
GROUP BY month ORDER BY month;
```

**A: Bez analiziranih indeksa - EXPLAIN, krug 1**

| id | select_type | tablica | type | key | rows | Extra |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | PRIMARY | <derived2> | ALL | NULL | 173888 | Using temporary; Using filesort |
| 2 | DERIVED | e | ALL | NULL | 58 | Using temporary; Using filesort |
| 2 | DERIVED | <derived3> | ref | key0 | 2998 |  |
| 3 | DERIVED | ri | ALL | NULL | 100152 | Using temporary; Using filesort |
| 3 | DERIVED | r | eq_ref | PRIMARY | 1 | Using where |
| 4 | UNION | r | ALL | NULL | 99828 | Using where; Using temporary; Using filesort |
| 5 | UNION | r | index | idx_res_event_status | 99828 | Using index; Using temporary; Using filesort |
| 5 | UNION | ri | ref | fk_item_reservation | 1 | Using index |
| 5 | UNION | tk | ref | fk_ticket_item | 1 | Using where |

ANALYZE, krug 1, mjerenje 1:

| tablica | access_type | key | r_loops | r_rows |
| --- | --- | --- | --- | --- |
| <derived2> | ALL | - | 1 | 211 |
| e | ALL | - | 1 | 58 |
| <derived3> | ref | key0 | 58 | 10.5862069 |
| ri | ALL | - | 1 | 100229 |
| r | eq_ref | PRIMARY | 100229 | 1 |
| r | ALL | - | 1 | 100175 |
| r | index | idx_res_event_status | 1 | 100175 |
| ri | ref | fk_item_reservation | 100175 | 1.000539057 |
| tk | ref | fk_ticket_item | 100229 | 1.88700875 |

15 vremena (ms), redom krugovi 1-3: 795.9, 844.4, 710.4, 748.1, 874.1, 848.9, 804.0, 870.1, 778.9, 756.3, 818.5, 762.2, 831.0, 788.1, 827.0.

**B: Konacni uski - EXPLAIN, krug 1**

| id | select_type | tablica | type | key | rows | Extra |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | PRIMARY | <derived2> | ALL | NULL | 60213 | Using temporary; Using filesort |
| 2 | DERIVED | e | ALL | NULL | 58 | Using temporary; Using filesort |
| 2 | DERIVED | <derived3> | ref | key0 | 1038 |  |
| 3 | DERIVED | r | ALL | NULL | 99828 | Using where; Using temporary; Using filesort |
| 3 | DERIVED | ri | ref | fk_item_reservation | 1 |  |
| 4 | UNION | r | ALL | NULL | 99828 | Using where; Using temporary; Using filesort |
| 5 | UNION | tk | range | idx_ticket_cancelled_at | 3988 | Using index condition; Using temporary; Using filesort |
| 5 | UNION | ri | eq_ref | PRIMARY | 1 |  |
| 5 | UNION | r | eq_ref | PRIMARY | 1 |  |

ANALYZE, krug 1, mjerenje 1:

| tablica | access_type | key | r_loops | r_rows |
| --- | --- | --- | --- | --- |
| <derived2> | ALL | - | 1 | 211 |
| e | ALL | - | 1 | 58 |
| <derived3> | ref | key0 | 58 | 10.5862069 |
| r | ALL | - | 1 | 100175 |
| ri | ref | fk_item_reservation | 75015 | 1.000533227 |
| r | ALL | - | 1 | 100175 |
| tk | range | idx_ticket_cancelled_at | 1 | 3988 |
| ri | eq_ref | PRIMARY | 3988 | 1 |
| r | eq_ref | PRIMARY | 3988 | 1 |

15 vremena (ms), redom krugovi 1-3: 300.8, 359.7, 339.7, 345.6, 372.8, 307.9, 297.0, 288.6, 281.5, 305.9, 374.9, 371.7, 328.1, 322.0, 270.1.

**C: Kupac + pokrivajuci povrati - EXPLAIN, krug 1**

| id | select_type | tablica | type | key | rows | Extra |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | PRIMARY | <derived2> | ALL | NULL | 60202 | Using temporary; Using filesort |
| 2 | DERIVED | e | ALL | NULL | 58 | Using temporary; Using filesort |
| 2 | DERIVED | <derived3> | ref | key0 | 1037 |  |
| 3 | DERIVED | r | ALL | NULL | 99810 | Using where; Using temporary; Using filesort |
| 3 | DERIVED | ri | ref | fk_item_reservation | 1 |  |
| 4 | UNION | r | ALL | NULL | 99810 | Using where; Using temporary; Using filesort |
| 5 | UNION | tk | range | idx_ticket_refund_cover | 3988 | Using where; Using index; Using temporary; Using filesort |
| 5 | UNION | ri | eq_ref | PRIMARY | 1 |  |
| 5 | UNION | r | eq_ref | PRIMARY | 1 |  |

ANALYZE, krug 1, mjerenje 1:

| tablica | access_type | key | r_loops | r_rows |
| --- | --- | --- | --- | --- |
| <derived2> | ALL | - | 1 | 211 |
| e | ALL | - | 1 | 58 |
| <derived3> | ref | key0 | 58 | 10.5862069 |
| r | ALL | - | 1 | 100175 |
| ri | ref | fk_item_reservation | 75015 | 1.000533227 |
| r | ALL | - | 1 | 100175 |
| tk | range | idx_ticket_refund_cover | 1 | 3988 |
| ri | eq_ref | PRIMARY | 3988 | 1 |
| r | eq_ref | PRIMARY | 3988 | 1 |

15 vremena (ms), redom krugovi 1-3: 277.0, 297.6, 312.3, 285.8, 296.5, 309.7, 280.2, 267.5, 281.6, 305.5, 292.0, 303.9, 293.4, 316.6, 280.7.

**D: Siri indeks potvrda + C - EXPLAIN, krug 1**

| id | select_type | tablica | type | key | rows | Extra |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | PRIMARY | <derived2> | ALL | NULL | 60213 | Using temporary; Using filesort |
| 2 | DERIVED | e | ALL | NULL | 58 | Using temporary; Using filesort |
| 2 | DERIVED | <derived3> | ref | key0 | 1038 |  |
| 3 | DERIVED | r | range | idx_res_confirmed_cover | 49914 | Using where; Using index; Using temporary; Using filesort |
| 3 | DERIVED | ri | ref | fk_item_reservation | 1 |  |
| 4 | UNION | r | range | idx_res_confirmed_cover | 49914 | Using where; Using index; Using temporary; Using filesort |
| 5 | UNION | tk | range | idx_ticket_refund_cover | 3988 | Using where; Using index; Using temporary; Using filesort |
| 5 | UNION | ri | eq_ref | PRIMARY | 1 |  |
| 5 | UNION | r | eq_ref | PRIMARY | 1 |  |

ANALYZE, krug 1, mjerenje 1:

| tablica | access_type | key | r_loops | r_rows |
| --- | --- | --- | --- | --- |
| <derived2> | ALL | - | 1 | 211 |
| e | ALL | - | 1 | 58 |
| <derived3> | ref | key0 | 58 | 10.5862069 |
| r | range | idx_res_confirmed_cover | 1 | 75015 |
| ri | ref | fk_item_reservation | 75015 | 1.000533227 |
| r | range | idx_res_confirmed_cover | 1 | 75015 |
| tk | range | idx_ticket_refund_cover | 1 | 3988 |
| ri | eq_ref | PRIMARY | 3988 | 1 |
| r | eq_ref | PRIMARY | 3988 | 1 |

15 vremena (ms), redom krugovi 1-3: 359.9, 426.0, 354.6, 357.2, 371.6, 441.4, 342.5, 394.6, 365.1, 410.4, 389.7, 367.7, 345.6, 301.3, 291.1.

### Q3 - Bruto prodaja u jednom danu

Tipican dnevni financijski pregled. Poluotvoreni raspon datuma ostaje sargable. Ovo je bruto cijena karata i service fee, bez zastite i povrata. COUNT(DISTINCT r.id) sprjecava visestruko brojanje rezervacije s vise stavki. Datumski indeks izdvaja mali skup umjesto obilaska svih stavki.

```sql
SELECT SQL_NO_CACHE COUNT(DISTINCT r.id) AS reservations,
       SUM(ri.quantity * (ri.price_per_ticket + ri.service_fee_per_ticket)) AS ticket_gross
FROM reservation r JOIN reservation_item ri ON ri.reservation_id = r.id
WHERE r.confirmed_at >= '2026-06-01' AND r.confirmed_at < '2026-06-02';
```

**A: Bez analiziranih indeksa - EXPLAIN, krug 1**

| id | select_type | tablica | type | key | rows | Extra |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | SIMPLE | ri | ALL | NULL | 100152 |  |
| 1 | SIMPLE | r | eq_ref | PRIMARY | 1 | Using where |

ANALYZE, krug 1, mjerenje 1:

| tablica | access_type | key | r_loops | r_rows |
| --- | --- | --- | --- | --- |
| ri | ALL | - | 1 | 100229 |
| r | eq_ref | PRIMARY | 100229 | 1 |

15 vremena (ms), redom krugovi 1-3: 128.3, 130.5, 109.2, 108.0, 130.8, 101.9, 110.7, 105.9, 116.8, 131.2, 125.2, 118.8, 114.5, 117.4, 109.8.

**B: Konacni uski - EXPLAIN, krug 1**

| id | select_type | tablica | type | key | rows | Extra |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | SIMPLE | r | range | idx_res_confirmed_at | 22 | Using where; Using index |
| 1 | SIMPLE | ri | ref | fk_item_reservation | 1 |  |

ANALYZE, krug 1, mjerenje 1:

| tablica | access_type | key | r_loops | r_rows |
| --- | --- | --- | --- | --- |
| r | range | idx_res_confirmed_at | 1 | 22 |
| ri | ref | fk_item_reservation | 22 | 1 |

15 vremena (ms), redom krugovi 1-3: 0.083, 0.081, 0.075, 0.131, 0.116, 0.075, 0.119, 0.066, 0.062, 0.064, 0.078, 0.074, 0.077, 0.065, 0.149.

**C: Kupac + pokrivajuci povrati - EXPLAIN, krug 1**

| id | select_type | tablica | type | key | rows | Extra |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | SIMPLE | r | range | idx_res_confirmed_at | 22 | Using where; Using index |
| 1 | SIMPLE | ri | ref | fk_item_reservation | 1 |  |

ANALYZE, krug 1, mjerenje 1:

| tablica | access_type | key | r_loops | r_rows |
| --- | --- | --- | --- | --- |
| r | range | idx_res_confirmed_at | 1 | 22 |
| ri | ref | fk_item_reservation | 22 | 1 |

15 vremena (ms), redom krugovi 1-3: 0.085, 0.112, 0.072, 0.062, 0.059, 0.097, 0.069, 0.065, 0.090, 0.065, 0.223, 0.120, 0.131, 0.061, 0.058.

**D: Siri indeks potvrda + C - EXPLAIN, krug 1**

| id | select_type | tablica | type | key | rows | Extra |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | SIMPLE | r | range | idx_res_confirmed_cover | 22 | Using where; Using index |
| 1 | SIMPLE | ri | ref | fk_item_reservation | 1 |  |

ANALYZE, krug 1, mjerenje 1:

| tablica | access_type | key | r_loops | r_rows |
| --- | --- | --- | --- | --- |
| r | range | idx_res_confirmed_cover | 1 | 22 |
| ri | ref | fk_item_reservation | 22 | 1 |

15 vremena (ms), redom krugovi 1-3: 0.073, 0.100, 0.088, 0.091, 0.067, 0.087, 0.123, 0.094, 0.086, 0.090, 0.073, 0.073, 0.066, 0.064, 0.061.

### Q4 - Povijest jednog kupca

Cest ekran zadnjih 10 rezervacija. @buyer=41 ima 22 rezervacije. A/B koriste fk_res_buyer uz filesort malog skupa. C/D koriste indeks buyer_id,created_at,id, uklanjaju filesort i prekidaju nakon 10 redaka. Isplativost se procjenjuje prema apsolutnoj ustedi, prostoru i INSERT-u u ovom nizu.

```sql
SELECT SQL_NO_CACHE id, event_id, status, created_at
FROM reservation WHERE buyer_id = @buyer
ORDER BY created_at DESC, id DESC LIMIT 10;
```

**A: Bez analiziranih indeksa - EXPLAIN, krug 1**

| id | select_type | tablica | type | key | rows | Extra |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | SIMPLE | reservation | ref | fk_res_buyer | 22 | Using where; Using filesort |

ANALYZE, krug 1, mjerenje 1:

| tablica | access_type | key | r_loops | r_rows |
| --- | --- | --- | --- | --- |
| reservation | ref | fk_res_buyer | 1 | 22 |

15 vremena (ms), redom krugovi 1-3: 0.153, 0.150, 0.171, 0.114, 0.123, 0.105, 0.064, 0.101, 0.179, 0.091, 0.299, 0.161, 0.118, 0.151, 0.100.

**B: Konacni uski - EXPLAIN, krug 1**

| id | select_type | tablica | type | key | rows | Extra |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | SIMPLE | reservation | ref | fk_res_buyer | 22 | Using where; Using filesort |

ANALYZE, krug 1, mjerenje 1:

| tablica | access_type | key | r_loops | r_rows |
| --- | --- | --- | --- | --- |
| reservation | ref | fk_res_buyer | 1 | 22 |

15 vremena (ms), redom krugovi 1-3: 0.052, 0.041, 0.062, 0.121, 0.044, 0.065, 0.045, 0.063, 0.040, 0.040, 0.092, 0.049, 0.075, 0.053, 0.050.

**C: Kupac + pokrivajuci povrati - EXPLAIN, krug 1**

| id | select_type | tablica | type | key | rows | Extra |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | SIMPLE | reservation | ref | idx_res_buyer_created | 22 | Using where |

ANALYZE, krug 1, mjerenje 1:

| tablica | access_type | key | r_loops | r_rows |
| --- | --- | --- | --- | --- |
| reservation | ref | idx_res_buyer_created | 1 | 10 |

15 vremena (ms), redom krugovi 1-3: 0.024, 0.021, 0.022, 0.056, 0.027, 0.037, 0.035, 0.026, 0.022, 0.057, 0.023, 0.022, 0.055, 0.023, 0.031.

**D: Siri indeks potvrda + C - EXPLAIN, krug 1**

| id | select_type | tablica | type | key | rows | Extra |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | SIMPLE | reservation | ref | idx_res_buyer_created | 22 | Using where |

ANALYZE, krug 1, mjerenje 1:

| tablica | access_type | key | r_loops | r_rows |
| --- | --- | --- | --- | --- |
| reservation | ref | idx_res_buyer_created | 1 | 10 |

15 vremena (ms), redom krugovi 1-3: 0.029, 0.027, 0.037, 0.025, 0.034, 0.030, 0.028, 0.038, 0.029, 0.028, 0.027, 0.020, 0.020, 0.036, 0.038.

### Q5 - Povrati u mjesecu

Tipican selektivan financijski pregled. A cita cijelu tablicu ticket. B range cita mjesec povrata i dohvaca refund_amount iz tablice; C/D pokrivaju SUM indeksom. Uzi indeks vec uklanja full scan; dodatna pokrivenost ima dodatni trosak.

```sql
SELECT SQL_NO_CACHE COUNT(*) AS refunded_tickets, SUM(refund_amount) AS refunds
FROM ticket WHERE cancelled_at >= '2026-06-01' AND cancelled_at < '2026-07-01';
```

**A: Bez analiziranih indeksa - EXPLAIN, krug 1**

| id | select_type | tablica | type | key | rows | Extra |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | SIMPLE | ticket | ALL | NULL | 188450 | Using where |

ANALYZE, krug 1, mjerenje 1:

| tablica | access_type | key | r_loops | r_rows |
| --- | --- | --- | --- | --- |
| ticket | ALL | - | 1 | 189133 |

15 vremena (ms), redom krugovi 1-3: 32.4, 31.8, 36.1, 28.4, 29.8, 29.9, 30.1, 38.7, 29.8, 39.7, 27.9, 32.8, 30.6, 31.0, 42.7.

**B: Konacni uski - EXPLAIN, krug 1**

| id | select_type | tablica | type | key | rows | Extra |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | SIMPLE | ticket | range | idx_ticket_cancelled_at | 206 | Using index condition |

ANALYZE, krug 1, mjerenje 1:

| tablica | access_type | key | r_loops | r_rows |
| --- | --- | --- | --- | --- |
| ticket | range | idx_ticket_cancelled_at | 1 | 206 |

15 vremena (ms), redom krugovi 1-3: 0.633, 0.508, 0.565, 0.442, 0.402, 0.317, 0.301, 0.274, 0.261, 0.278, 0.408, 0.317, 0.292, 0.259, 0.325.

**C: Kupac + pokrivajuci povrati - EXPLAIN, krug 1**

| id | select_type | tablica | type | key | rows | Extra |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | SIMPLE | ticket | range | idx_ticket_refund_cover | 206 | Using where; Using index |

ANALYZE, krug 1, mjerenje 1:

| tablica | access_type | key | r_loops | r_rows |
| --- | --- | --- | --- | --- |
| ticket | range | idx_ticket_refund_cover | 1 | 206 |

15 vremena (ms), redom krugovi 1-3: 0.127, 0.072, 0.070, 0.065, 0.063, 0.063, 0.062, 0.120, 0.079, 0.076, 0.157, 0.118, 0.127, 0.064, 0.072.

**D: Siri indeks potvrda + C - EXPLAIN, krug 1**

| id | select_type | tablica | type | key | rows | Extra |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | SIMPLE | ticket | range | idx_ticket_refund_cover | 206 | Using where; Using index |

ANALYZE, krug 1, mjerenje 1:

| tablica | access_type | key | r_loops | r_rows |
| --- | --- | --- | --- | --- |
| ticket | range | idx_ticket_refund_cover | 1 | 206 |

15 vremena (ms), redom krugovi 1-3: 0.062, 0.064, 0.091, 0.089, 0.088, 0.090, 0.088, 0.089, 0.082, 0.092, 0.063, 0.064, 0.064, 0.062, 0.061.

## Prostor i INSERT

Bajtovi iz information_schema.TABLES nakon ANALYZE. Prikaz svih krugova izbjegava skrivanje promjena alokacije; ovo su procjene alociranih stranica, ne tocne logicke velicine indeksa.

| Krug | Konfiguracija | Tablica | DATA_LENGTH | INDEX_LENGTH | INDEX prema A |
| --- | --- | --- | --- | --- | --- |
| 1 | A | reservation | 6832128 | 11599872 | 0 |
| 1 | A | ticket | 14172160 | 22118400 | 0 |
| 1 | B | reservation | 6832128 | 14237696 | 2637824 |
| 1 | B | ticket | 14172160 | 24756224 | 2637824 |
| 1 | C | reservation | 6832128 | 16875520 | 5275648 |
| 1 | C | ticket | 14172160 | 25804800 | 3686400 |
| 1 | D | reservation | 6832128 | 17924096 | 6324224 |
| 1 | D | ticket | 14172160 | 25804800 | 3686400 |
| 2 | A | reservation | 6832128 | 11599872 | 0 |
| 2 | A | ticket | 14172160 | 22118400 | 0 |
| 2 | B | reservation | 6832128 | 14237696 | 2637824 |
| 2 | B | ticket | 14172160 | 24756224 | 2637824 |
| 2 | C | reservation | 6832128 | 16875520 | 5275648 |
| 2 | C | ticket | 14172160 | 25804800 | 3686400 |
| 2 | D | reservation | 6832128 | 17924096 | 6324224 |
| 2 | D | ticket | 14172160 | 25804800 | 3686400 |
| 3 | A | reservation | 6832128 | 11599872 | 0 |
| 3 | A | ticket | 14172160 | 22118400 | 0 |
| 3 | B | reservation | 6832128 | 14237696 | 2637824 |
| 3 | B | ticket | 14172160 | 24756224 | 2637824 |
| 3 | C | reservation | 6832128 | 16875520 | 5275648 |
| 3 | C | ticket | 14172160 | 25804800 | 3686400 |
| 3 | D | reservation | 6832128 | 17924096 | 6324224 |
| 3 | D | ticket | 14172160 | 25804800 | 3686400 |

INSERT 10.000 redaka u privremenu InnoDB kopiju reservation. Pocetni podaci su isti, svako mjerenje se ponisti; zagrijavanje, priprema kopije i ROLLBACK nisu u vremenu. Medijan/min-max svih 15 uzoraka po konfiguraciji.

| Konfiguracija | Medijan [min-max] ms | Promjena prema A |
| --- | --- | --- |
| A | 90.5 [74.6-109.1] | +0.00 % |
| B | 97.3 [89.0-132.7] | +7.55 % |
| C | 146.8 [111.5-174.3] | +62.26 % |
| D | 161.1 [127.5-194.0] | +78.06 % |

A, svih 15 INSERT vremena (ms): 91.8, 92.2, 83.6, 83.6, 82.6, 89.1, 74.6, 89.1, 96.6, 83.0, 101.6, 95.4, 109.1, 102.0, 90.5.

B, svih 15 INSERT vremena (ms): 115.0, 131.7, 132.7, 96.0, 96.1, 90.1, 100.6, 110.1, 108.2, 97.3, 89.0, 93.9, 106.9, 97.3, 95.3.

C, svih 15 INSERT vremena (ms): 114.4, 111.5, 163.8, 151.0, 145.5, 117.7, 156.3, 174.3, 156.8, 126.9, 172.9, 138.9, 146.8, 164.6, 120.3.

D, svih 15 INSERT vremena (ms): 129.9, 162.9, 174.9, 166.5, 136.8, 127.5, 168.9, 194.0, 151.3, 139.5, 161.1, 128.0, 172.1, 145.6, 165.4.

Ticket: 189133 karata, 3988 s povratom (2.1086 %), 185145 s NULL cancelled_at. Uski idx_ticket_cancelled_at povecava INDEX_LENGTH prema A za 2637824-2637824 bajtova (oko 2.6 MB). Indeks sadrzi i NULL vrijednosti svih neotkazanih karata.

## Odluke o indeksima

**idx_res_confirmed_at(confirmed_at)** ostaje: Q3 s 116.8 ms u A pada
na 0.077 ms u B. Datum omogucuje selektivni range, a implicitni InnoDB
PK id pokriva JOIN na stavke. Siri datum nije potreban samo za taj upit.

**idx_ticket_cancelled_at(cancelled_at)** ostaje: Q5 s 31.0 ms u A pada
na 0.317 ms u B. Za rijetke povrate Q2 takodjer moze koristiti range.
Iznos i item jos se dohvacaju iz tablice; prihvacamo tu cijenu uz manji indeks.

**fk_res_buyer(buyer_id)** vec postoji i dovoljan je za oko 20 rezervacija kupca.
B zadrzava filesort malog skupa. Ostali FK/UNIQUE/operativni indeksi ostaju:
idx_res_status_expires odgovara jednakosti statusa i rasponu isteka u proceduri,
a idx_res_event_status podupire FK/event upite. Ovaj niz ne dokazuje njihovu
beskorisnost i ne sluzi njihovu brisanju.

## Odbaceni kandidati

C naspram B: Q4 medijan je 0.052 -> 0.026 ms,
razlika 26.6 mikrosekundi u korist C (negativno znaci sporije).
idx_res_buyer_created(buyer_id,created_at,id) uklanja filesort i rano staje,
ali apsolutna usteda ostaje mala za 22 rezervacije kupca. Ne zadrzavamo ga.

idx_ticket_refund_cover(cancelled_at,reservation_item_id,refund_amount) u C
pokriva SUM/JOIN: Q5 je 0.317 -> 0.072 ms,
Q2 322.0 -> 293.4 ms. To su stvarni dobitci/gubitci novog
niza, a ne povijesne brojke. Promjena medijana Q2 je -8.87 %; ne odbacujemo
stvaran dobitak citanja kao da ga nema. Dobitak citanja usporedjuje cijele konfiguracije B/C.
Za INSERT je atribucija drukcija: test unosi samo u privremenu kopiju reservation,
a B i C na toj tablici razlikuju se samo po idx_res_buyer_created.
C prema B povecava medijan INSERT-a s 97.3 na 146.8 ms
(+50.9 %): to je izmjerena cijena dodatnog
idx_res_buyer_created u ovom testu, uz prikazani raspon i moguci sum.
Cijena pisanja idx_ticket_refund_cover NIJE izmjerena jer test ne upisuje u ticket.
Taj indeks odbacujemo zbog dodatnog prostora i jednostavnosti, a ne na temelju
ovog INSERT usporenja. Razlika INDEX_LENGTH u svakom krugu je
2637824 bajtova na reservation i
1048576 na ticket.
Za ovaj studentski workload biramo manje indekse i jeftiniji unos, uz prihvaceno
sporije izvjestavanje nego u C. Bez definiranog produkcijskog omjera citanja i
pisanja ne tvrdimo da je B optimalan za svaki moguci workload.

D naspram C izolira zamjenu uskog datuma potvrde s
idx_res_confirmed_cover(confirmed_at,event_id,refund_protection_fee).
Q2: 293.4 -> 365.1 ms; Q3:
0.072 -> 0.086 ms. Pokrivenost ne uklanja agregacije
velikog skupa. Rasponi svih konfiguracija prikazani su gore; ne tvrdimo da je
svaka razlika medijana statisticki znacajna.

## Zasto ne indeksirati svaki stupac

**Pisanje.** B prema A: INSERT medijan 90.5 -> 97.3 ms,
+7.55 %. C prema A: 90.5 -> 146.8 ms,
+62.26 %. Usporedbe su iz istog niza i istog testa.
Svaki dodatni B-tree trazi rad pri INSERT-u i promjeni indeksiranih vrijednosti.
Razlike vremena mogu biti pod utjecajem prikazanog suma i redoslijeda.

**Prostor i NULL.** Uski idx_ticket_cancelled_at zauzima oko 2,6 MB, iako samo
oko 2 % karata ima povrat: InnoDB indeks sadrzi i NULL cancelled_at vrijednosti
za sve preostale karte. Tocan broj/pct i izmjerena INDEX razlika prikazani su gore.
Niska ucestalost povrata ne znaci da je indeks djelomican ili da sadrzi samo povrate.
Dodatni indeksi povecavaju buffer pool/I/O, backup, izgradnju i odrzavanje statistika.

**Zasto su DATA/INDEX velicine drukcije nego u obrisanim starim mjerenjima?** Tablice su prije ovog niza
obnovljene iz logickog dumpa tijekom prethodne obnove baze. Dump prenosi retke i
DDL, ne stari fizicki raspored stranica. Restore ponovno gradi klasterirane i
sekundarne indekse, mijenja popunjenost i slobodne stranice; kasniji DROP/CREATE
indeksa takodjer utjece na alokaciju. Zato jednaki logicki podaci ne jamce jednak
DATA_LENGTH/INDEX_LENGTH. To nije dokaz nestanka redaka niti se stari i novi
apsolutni brojevi prostora koriste kao usporedba kandidata. Usporedba je sada
medju A-D unutar istog kruga, a u tablici su sve tri vrijednosti.

**Q4 i preklapanje.** Uklanjanje filesort nije samo po sebi dovoljan razlog za
indeks: sortiranje 22 redaka je jeftino. Kandidat ponavlja buyer_id prefiks vec
postojeceg FK indeksa. Uski i pokrivajuci datum povrata takodjer dijele prefiks;
ne zadrzavamo oba. Pojedinacni indeksi na svakom stupcu ne zamjenjuju smislen
redoslijed slozenog indeksa, ali ni svaki slozeni indeks nije isplativ.

**Optimizator i selektivnost.** Vise mogucih pristupnih puteva ne jamci bolji plan.
Status ima malo vrijednosti, dok datum moze izdvojiti mali raspon. Q1 mora brojiti
cijeli skup bez obzira na indeks; Q2 mora agregirati mnogo rezervacija. Temporary
i filesort u takvom izvjestaju nisu sami po sebi pogreska.

**Kompozitni FK.** uq_reservation_id_event, uq_category_id_event,
uq_item_id_category, uq_seat_id_category i uq_rs_id_item vec trose prostor i rad
provjere jedinstvenosti, ali jamce konzistentnu pripadnost eventu/kategoriji/stavci.
Ostaju u A-D i kopiraju se u INSERT mikrobenchmark; ne uklanjaju se zbog
preklapanja s PK.

## Kompromisi i zakljucak

Izbor indeksa nije promijenjen: uski indeksi su dovoljni za demonstrirane
selektivne upite, a C/D ostaju odbaceni kandidati. To je odluka o apsolutnoj koristi,
prostoru i pisanju, a ne tvrdnja da su B vremena najbolja za svaki upit.
C ima bolji Q2 medijan i znatno bolji Q5 od B; D ima losiji Q2 medijan od C.
Novi niz zato ne podrzava staru tvrdnju da C nema mjerljiv dobitak u citanju:
podrzava odbacivanje indeksa kupca prema kompromisu s INSERT-om i prostorom,
a indeksa povrata zbog prostora i jednostavnosti; njegova cijena pisanja nije izmjerena.
Q1 i B-Q4 imaju iste pristupne puteve kao A; razlike vremena nisu dokaz poboljsanja.
Q2 ostaje skup i ne postaje selektivan samo dodavanjem indeksa. Q5 prihvaca dodatni
dohvat iz tablice u zamjenu za uzi indeks.

INSERT je mikrobenchmark reservation indeksa: CREATE TEMPORARY TABLE LIKE kopira
stupce, CHECK/UNIQUE i indekse, ali ne FK/triggere. Nema poslovnih procedura,
trajnog COMMIT-a, ni upisa u ticket. Priprema i rollback nisu u vremenu.
Zato cijena pisanja ticket indeksa i puna poslovna transakcija nisu izmjerene.
[MariaDB: CREATE TABLE LIKE](https://mariadb.com/docs/server/server-usage/tables/create-table).

## Zavrsno stanje i samoprovjera

Nakon niza stvarno je izvrsen 02 -> 03. FINAL_INDEX/FINAL_COUNTS u series.tsv
potvrdjuju dva uska indeksa, odsutnost tri kandidata, 100.175 rezervacija,
189.133 karte i 0 odstupanja brojacima. Mala baza eventhub nije mijenjana.
Regresije prethodne revizije 81/81 i 18/18 sacuvane su u
`perf/results/checks/invalid_data.tsv` i `verify_reports.tsv`. To su provjere
ispravnosti, a ne stara mjerenja performansi; nisu predstavljene kao nova izvrsavanja.

| Acceptance kriterij | Gdje |
| --- | --- |
| Najmanje 100.000 rezervacija | Skup podataka; ENV i FINAL_COUNTS u series.tsv; perf/01_generate_100k.sql |
| Spori izvjestaji i EXPLAIN za najmanje dva upita | SQL, EXPLAIN i stvarni redci: svih pet upita, sve cetiri konfiguracije |
| Opravdane odluke o indeksima | Odluke o indeksima i Odbaceni kandidati; konfiguracije B/C/D |
| Mjerenja prije i poslije | Izmjerena vremena: medijan/min-max 15 uzoraka; sirovi series.tsv |
| Trade-off dodatnih indeksa | Prostor i INSERT; Zasto ne indeksirati svaki stupac; Kompromisi |
| Ponovljivost | perf/run_series.py, series_manifest.json; tri A-D kruga i zavrsni povrat |

