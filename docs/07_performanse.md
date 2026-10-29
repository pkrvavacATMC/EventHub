# Povijesna analiza performansi prije migracije 006

Ovo mjerenje pripada shemi prije Keycloak migracije 006 (12 TIMESTAMP stupaca). Aktualna shema ima devet takvih stupaca. Rezultati nisu ponovno mjereni nakon 006; sacuvani manifest opisuje tadasnje izvore. Za novo mjerenje arhiviraj stare dokaze, pripremi aktualnu perf bazu i ponovi cijelu seriju.

Mjerenje zavrseno 2026-10-29T15:22:43.337401+00:00. MariaDB 10.11.19-MariaDB-ubu2204; session UTC; 100175 rezervacija i 189133 karata. Buffer pool: 134217728 bajtova.

Performance baza je ponovno stvorena iz tada aktualnog cistog seeda i prosirena za 100.000 rezervacija. Koristi 12 TIMESTAMP stupaca, lokalni event_date, IANA zone i ASCII kod karte. Stara mjerenja nisu ukljucena u ove rezultate.

## Postupak

Jedna MariaDB sesija, tri A-D kruga; jedno zagrijavanje i pet mjerenja po upitu/krugu. Medijan je iz svih 15 uzoraka, uz min-max. Query cache OFF, SQL_NO_CACHE; buffer pool nije praznjen. Fiksni redoslijed i OS sum ostaju ogranicenja. ANALYZE instrumentacija ulazi u vrijeme.

| Konfiguracija | Opis |
| --- | --- |
| A | Bez analiziranih indeksa |
| B | Konacni uski |
| C | Kupac + pokrivajuci povrati |
| D | Siri indeks potvrda + C |

A uklanja samo kandidate; PK/UNIQUE/FK i operativni indeksi ostaju. B koristi dva uska datumska indeksa. C dodaje povijest kupca i pokrivajuce povrate; D prosiruje i indeks potvrda. Na kraju se vraca B.

Q3 i Q5 koriste UTC datumske granice jer je session UTC; Q2 koristi poslovne mjesece u Europe/Zagreb. Za lokalni dan ili mjesec granice se prvo pretvore u UTC, a indeksirani stupac ostaje bez funkcije.

Manifest biljezi hash sheme, generatora, upita i rezultata te stvarne tipove stupaca. Parser provjerava iste podatke u svim krugovima i stvarne indekse konfiguracija.

## Izmjerena vremena

Samo series.tsv: jedna MariaDB sesija, tri uzastopna A-D kruga. Svaka celija: medijan [min-max] u ms svih 15 mjerenja (5 po krugu); vremena >= 1 ms imaju jednu decimalu, manja tri; tri zagrijavanja po konfiguraciji/upitu su iskljucena. Arhiva nije ukljucena.

| Upit | A: Bez analiziranih indeksa | B: Konacni uski | C: Kupac + pokrivajuci povrati | D: Siri indeks potvrda + C |
| --- | --- | --- | --- | --- |
| Q1 | 130.4 [99.1-173.8] | 109.1 [90.9-149.6] | 110.6 [95.9-149.0] | 120.7 [93.7-171.6] |
| Q2 | 1246.7 [1110.7-1389.0] | 524.0 [457.6-594.7] | 499.4 [451.5-606.6] | 593.1 [530.7-758.7] |
| Q3 | 206.3 [165.3-285.0] | 0.144 [0.097-0.278] | 0.107 [0.093-0.142] | 0.206 [0.117-0.348] |
| Q4 | 0.079 [0.061-0.162] | 0.075 [0.061-0.141] | 0.034 [0.025-0.040] | 0.067 [0.033-0.077] |
| Q5 | 58.2 [41.3-75.6] | 0.709 [0.376-1.2] | 0.096 [0.091-0.117] | 0.180 [0.101-0.278] |

### Medijani pojedinih krugova

| Krug | Konfiguracija | Q1 | Q2 | Q3 | Q4 | Q5 | INSERT ms |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | A | 149.1 | 1302.1 | 225.3 | 0.085 | 60.7 | 182.0 |
| 1 | B | 108.9 | 536.9 | 0.107 | 0.082 | 0.709 | 163.6 |
| 1 | C | 116.9 | 471.2 | 0.105 | 0.037 | 0.098 | 243.2 |
| 1 | D | 125.6 | 671.6 | 0.122 | 0.037 | 0.173 | 248.0 |
| 2 | A | 148.9 | 1276.9 | 199.8 | 0.075 | 52.6 | 156.5 |
| 2 | B | 137.3 | 519.8 | 0.150 | 0.094 | 0.902 | 153.0 |
| 2 | C | 107.6 | 478.2 | 0.105 | 0.029 | 0.096 | 207.9 |
| 2 | D | 113.6 | 583.9 | 0.206 | 0.067 | 0.177 | 202.3 |
| 3 | A | 109.4 | 1206.3 | 201.5 | 0.078 | 54.7 | 146.9 |
| 3 | B | 109.1 | 518.9 | 0.182 | 0.066 | 0.409 | 149.3 |
| 3 | C | 109.6 | 505.6 | 0.108 | 0.032 | 0.095 | 218.3 |
| 3 | D | 131.6 | 580.3 | 0.229 | 0.068 | 0.180 | 199.1 |

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
| 1 | SIMPLE | b | ALL | NULL | 5085 | Using temporary; Using filesort |
| 1 | SIMPLE | r | ref | fk_res_buyer | 9 | Using index |

ANALYZE, krug 1, mjerenje 1:

| tablica | access_type | key | r_loops | r_rows |
| --- | --- | --- | --- | --- |
| b | ALL | - | 1 | 5040 |
| r | ref | fk_res_buyer | 5040 | 19.87599206 |

15 vremena (ms), redom krugovi 1-3: 105.0, 128.1, 157.5, 165.9, 149.1, 157.7, 130.5, 148.9, 113.7, 173.8, 109.4, 99.1, 112.2, 130.4, 104.1.

**B: Konacni uski - EXPLAIN, krug 1**

| id | select_type | tablica | type | key | rows | Extra |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | SIMPLE | b | ALL | NULL | 5085 | Using temporary; Using filesort |
| 1 | SIMPLE | r | ref | fk_res_buyer | 9 | Using index |

ANALYZE, krug 1, mjerenje 1:

| tablica | access_type | key | r_loops | r_rows |
| --- | --- | --- | --- | --- |
| b | ALL | - | 1 | 5040 |
| r | ref | fk_res_buyer | 5040 | 19.87599206 |

15 vremena (ms), redom krugovi 1-3: 90.9, 108.9, 149.6, 125.1, 97.9, 142.1, 137.3, 101.2, 142.4, 101.4, 109.1, 96.9, 112.7, 134.5, 101.1.

**C: Kupac + pokrivajuci povrati - EXPLAIN, krug 1**

| id | select_type | tablica | type | key | rows | Extra |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | SIMPLE | b | ALL | NULL | 5085 | Using temporary; Using filesort |
| 1 | SIMPLE | r | ref | fk_res_buyer | 9 | Using index |

ANALYZE, krug 1, mjerenje 1:

| tablica | access_type | key | r_loops | r_rows |
| --- | --- | --- | --- | --- |
| b | ALL | - | 1 | 5040 |
| r | ref | fk_res_buyer | 5040 | 19.87599206 |

15 vremena (ms), redom krugovi 1-3: 116.9, 108.0, 149.0, 126.2, 110.6, 135.0, 128.3, 106.9, 97.9, 107.6, 95.9, 109.6, 148.4, 100.5, 112.3.

**D: Siri indeks potvrda + C - EXPLAIN, krug 1**

| id | select_type | tablica | type | key | rows | Extra |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | SIMPLE | b | ALL | NULL | 5085 | Using temporary; Using filesort |
| 1 | SIMPLE | r | ref | fk_res_buyer | 10 | Using index |

ANALYZE, krug 1, mjerenje 1:

| tablica | access_type | key | r_loops | r_rows |
| --- | --- | --- | --- | --- |
| b | ALL | - | 1 | 5040 |
| r | ref | fk_res_buyer | 5040 | 19.87599206 |

15 vremena (ms), redom krugovi 1-3: 124.9, 150.4, 100.0, 171.6, 125.6, 116.9, 113.6, 105.0, 120.7, 108.7, 93.7, 101.0, 152.1, 145.9, 131.6.

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
| 1 | PRIMARY | <derived2> | ALL | NULL | 173367 | Using temporary; Using filesort |
| 2 | DERIVED | e | ALL | NULL | 58 | Using temporary; Using filesort |
| 2 | DERIVED | <derived3> | ref | key0 | 2989 |  |
| 3 | DERIVED | ri | ALL | NULL | 100152 | Using temporary; Using filesort |
| 3 | DERIVED | r | eq_ref | PRIMARY | 1 | Using where |
| 4 | UNION | r | ALL | NULL | 99379 | Using where; Using temporary; Using filesort |
| 5 | UNION | r | index | idx_res_event_status | 99379 | Using index; Using temporary; Using filesort |
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

15 vremena (ms), redom krugovi 1-3: 1233.5, 1218.5, 1387.4, 1389.0, 1302.1, 1276.9, 1295.9, 1278.4, 1110.7, 1217.1, 1146.9, 1206.3, 1246.7, 1121.8, 1251.2.

**B: Konacni uski - EXPLAIN, krug 1**

| id | select_type | tablica | type | key | rows | Extra |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | PRIMARY | <derived2> | ALL | NULL | 59898 | Using temporary; Using filesort |
| 2 | DERIVED | e | ALL | NULL | 58 | Using temporary; Using filesort |
| 2 | DERIVED | <derived3> | ref | key0 | 1032 |  |
| 3 | DERIVED | r | ALL | NULL | 99287 | Using where; Using temporary; Using filesort |
| 3 | DERIVED | ri | ref | fk_item_reservation | 1 |  |
| 4 | UNION | r | ALL | NULL | 99287 | Using where; Using temporary; Using filesort |
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

15 vremena (ms), redom krugovi 1-3: 524.0, 482.9, 536.9, 594.1, 566.3, 562.1, 479.3, 519.8, 457.6, 594.7, 502.9, 524.4, 518.9, 577.5, 479.6.

**C: Kupac + pokrivajuci povrati - EXPLAIN, krug 1**

| id | select_type | tablica | type | key | rows | Extra |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | PRIMARY | <derived2> | ALL | NULL | 59864 | Using temporary; Using filesort |
| 2 | DERIVED | e | ALL | NULL | 58 | Using temporary; Using filesort |
| 2 | DERIVED | <derived3> | ref | key0 | 1032 |  |
| 3 | DERIVED | r | ALL | NULL | 99226 | Using where; Using temporary; Using filesort |
| 3 | DERIVED | ri | ref | fk_item_reservation | 1 |  |
| 4 | UNION | r | ALL | NULL | 99226 | Using where; Using temporary; Using filesort |
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

15 vremena (ms), redom krugovi 1-3: 540.1, 471.2, 470.9, 591.0, 453.5, 461.5, 478.2, 606.6, 546.2, 451.5, 582.1, 534.6, 495.8, 499.4, 505.6.

**D: Siri indeks potvrda + C - EXPLAIN, krug 1**

| id | select_type | tablica | type | key | rows | Extra |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | PRIMARY | <derived2> | ALL | NULL | 59898 | Using temporary; Using filesort |
| 2 | DERIVED | e | ALL | NULL | 58 | Using temporary; Using filesort |
| 2 | DERIVED | <derived3> | ref | key0 | 1032 |  |
| 3 | DERIVED | r | range | idx_res_confirmed_cover | 49643 | Using where; Using index; Using temporary; Using filesort |
| 3 | DERIVED | ri | ref | fk_item_reservation | 1 |  |
| 4 | UNION | r | range | idx_res_confirmed_cover | 49643 | Using where; Using index; Using temporary; Using filesort |
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

15 vremena (ms), redom krugovi 1-3: 737.3, 671.6, 758.7, 668.5, 591.3, 583.9, 553.3, 530.7, 607.8, 596.8, 593.1, 652.4, 580.3, 556.4, 567.8.

### Q3 - Bruto prodaja u jednom UTC danu

Selektivni dnevni pregled u UTC-u. Poluotvoreni raspon datuma ostaje sargable. Ovo je bruto cijena karata i service fee, bez zastite i povrata. COUNT(DISTINCT r.id) sprjecava visestruko brojanje rezervacije s vise stavki. Datumski indeks izdvaja mali skup umjesto obilaska svih stavki.

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

15 vremena (ms), redom krugovi 1-3: 213.0, 225.3, 285.0, 271.4, 216.5, 188.6, 205.8, 236.2, 165.3, 199.8, 195.6, 170.1, 215.0, 206.3, 201.5.

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

15 vremena (ms), redom krugovi 1-3: 0.127, 0.107, 0.097, 0.103, 0.178, 0.132, 0.144, 0.168, 0.150, 0.187, 0.278, 0.212, 0.123, 0.182, 0.105.

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

15 vremena (ms), redom krugovi 1-3: 0.115, 0.105, 0.107, 0.095, 0.093, 0.112, 0.105, 0.109, 0.105, 0.101, 0.142, 0.106, 0.108, 0.107, 0.114.

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

15 vremena (ms), redom krugovi 1-3: 0.134, 0.127, 0.117, 0.118, 0.122, 0.206, 0.218, 0.194, 0.315, 0.193, 0.229, 0.268, 0.219, 0.211, 0.348.

### Q4 - Povijest jednog kupca

Ekran zadnjih 10 rezervacija jednog kupca u generiranom skupu. A/B koriste fk_res_buyer uz filesort malog skupa. C/D koriste indeks buyer_id,created_at,id, uklanjaju filesort i prekidaju nakon 10 redaka. Isplativost se procjenjuje prema apsolutnoj ustedi, prostoru i INSERT-u u ovom nizu.

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

15 vremena (ms), redom krugovi 1-3: 0.162, 0.083, 0.083, 0.117, 0.085, 0.076, 0.075, 0.094, 0.065, 0.061, 0.087, 0.065, 0.079, 0.078, 0.071.

**B: Konacni uski - EXPLAIN, krug 1**

| id | select_type | tablica | type | key | rows | Extra |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | SIMPLE | reservation | ref | fk_res_buyer | 22 | Using where; Using filesort |

ANALYZE, krug 1, mjerenje 1:

| tablica | access_type | key | r_loops | r_rows |
| --- | --- | --- | --- | --- |
| reservation | ref | fk_res_buyer | 1 | 22 |

15 vremena (ms), redom krugovi 1-3: 0.129, 0.061, 0.073, 0.116, 0.082, 0.094, 0.075, 0.067, 0.104, 0.141, 0.079, 0.067, 0.066, 0.062, 0.066.

**C: Kupac + pokrivajuci povrati - EXPLAIN, krug 1**

| id | select_type | tablica | type | key | rows | Extra |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | SIMPLE | reservation | ref | idx_res_buyer_created | 22 | Using where |

ANALYZE, krug 1, mjerenje 1:

| tablica | access_type | key | r_loops | r_rows |
| --- | --- | --- | --- | --- |
| reservation | ref | idx_res_buyer_created | 1 | 10 |

15 vremena (ms), redom krugovi 1-3: 0.037, 0.037, 0.030, 0.038, 0.034, 0.036, 0.029, 0.026, 0.025, 0.036, 0.032, 0.040, 0.036, 0.029, 0.027.

**D: Siri indeks potvrda + C - EXPLAIN, krug 1**

| id | select_type | tablica | type | key | rows | Extra |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | SIMPLE | reservation | ref | idx_res_buyer_created | 22 | Using where |

ANALYZE, krug 1, mjerenje 1:

| tablica | access_type | key | r_loops | r_rows |
| --- | --- | --- | --- | --- |
| reservation | ref | idx_res_buyer_created | 1 | 10 |

15 vremena (ms), redom krugovi 1-3: 0.053, 0.037, 0.045, 0.035, 0.033, 0.077, 0.067, 0.063, 0.070, 0.059, 0.076, 0.068, 0.067, 0.068, 0.077.

### Q5 - Povrati u UTC mjesecu

Selektivni pregled UTC mjeseca. A cita cijelu tablicu ticket. B range cita mjesec povrata i dohvaca refund_amount iz tablice; C/D pokrivaju SUM indeksom. Uzi indeks vec uklanja full scan; dodatna pokrivenost ima dodatni trosak.

```sql
SELECT SQL_NO_CACHE COUNT(*) AS refunded_tickets, SUM(refund_amount) AS refunds
FROM ticket WHERE cancelled_at >= '2026-06-01' AND cancelled_at < '2026-07-01';
```

**A: Bez analiziranih indeksa - EXPLAIN, krug 1**

| id | select_type | tablica | type | key | rows | Extra |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | SIMPLE | ticket | ALL | NULL | 188468 | Using where |

ANALYZE, krug 1, mjerenje 1:

| tablica | access_type | key | r_loops | r_rows |
| --- | --- | --- | --- | --- |
| ticket | ALL | - | 1 | 189133 |

15 vremena (ms), redom krugovi 1-3: 46.9, 59.4, 75.6, 67.6, 60.7, 41.3, 58.2, 52.6, 60.9, 49.8, 62.2, 46.5, 54.7, 59.3, 50.8.

**B: Konacni uski - EXPLAIN, krug 1**

| id | select_type | tablica | type | key | rows | Extra |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | SIMPLE | ticket | range | idx_ticket_cancelled_at | 206 | Using index condition |

ANALYZE, krug 1, mjerenje 1:

| tablica | access_type | key | r_loops | r_rows |
| --- | --- | --- | --- | --- |
| ticket | range | idx_ticket_cancelled_at | 1 | 206 |

15 vremena (ms), redom krugovi 1-3: 0.541, 0.654, 0.803, 1.2, 0.709, 0.787, 0.725, 0.902, 1.1, 1.1, 0.505, 0.525, 0.409, 0.376, 0.400.

**C: Kupac + pokrivajuci povrati - EXPLAIN, krug 1**

| id | select_type | tablica | type | key | rows | Extra |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | SIMPLE | ticket | range | idx_ticket_refund_cover | 206 | Using where; Using index |

ANALYZE, krug 1, mjerenje 1:

| tablica | access_type | key | r_loops | r_rows |
| --- | --- | --- | --- | --- |
| ticket | range | idx_ticket_refund_cover | 1 | 206 |

15 vremena (ms), redom krugovi 1-3: 0.098, 0.097, 0.097, 0.102, 0.106, 0.091, 0.092, 0.096, 0.096, 0.096, 0.099, 0.095, 0.094, 0.094, 0.117.

**D: Siri indeks potvrda + C - EXPLAIN, krug 1**

| id | select_type | tablica | type | key | rows | Extra |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | SIMPLE | ticket | range | idx_ticket_refund_cover | 206 | Using where; Using index |

ANALYZE, krug 1, mjerenje 1:

| tablica | access_type | key | r_loops | r_rows |
| --- | --- | --- | --- | --- |
| ticket | range | idx_ticket_refund_cover | 1 | 206 |

15 vremena (ms), redom krugovi 1-3: 0.105, 0.278, 0.173, 0.216, 0.101, 0.177, 0.175, 0.180, 0.172, 0.182, 0.180, 0.180, 0.257, 0.179, 0.181.

## Prostor i INSERT

Bajtovi iz information_schema.TABLES nakon ANALYZE. Prikaz svih krugova izbjegava skrivanje promjena alokacije; ovo su procjene alociranih stranica, ne tocne logicke velicine indeksa.

| Krug | Konfiguracija | Tablica | DATA_LENGTH | INDEX_LENGTH | INDEX prema A |
| --- | --- | --- | --- | --- | --- |
| 1 | A | reservation | 12058624 | 11632640 | 0 |
| 1 | A | ticket | 13123584 | 23183360 | 0 |
| 1 | B | reservation | 12058624 | 13221888 | 1589248 |
| 1 | B | ticket | 13123584 | 25821184 | 2637824 |
| 1 | C | reservation | 12058624 | 15859712 | 4227072 |
| 1 | C | ticket | 13123584 | 26869760 | 3686400 |
| 1 | D | reservation | 12058624 | 16908288 | 5275648 |
| 1 | D | ticket | 13123584 | 26869760 | 3686400 |
| 2 | A | reservation | 12058624 | 11632640 | 0 |
| 2 | A | ticket | 13123584 | 23183360 | 0 |
| 2 | B | reservation | 12058624 | 13221888 | 1589248 |
| 2 | B | ticket | 13123584 | 25821184 | 2637824 |
| 2 | C | reservation | 12058624 | 15859712 | 4227072 |
| 2 | C | ticket | 13123584 | 26869760 | 3686400 |
| 2 | D | reservation | 12058624 | 16908288 | 5275648 |
| 2 | D | ticket | 13123584 | 26869760 | 3686400 |
| 3 | A | reservation | 12058624 | 11632640 | 0 |
| 3 | A | ticket | 13123584 | 23183360 | 0 |
| 3 | B | reservation | 12058624 | 13221888 | 1589248 |
| 3 | B | ticket | 13123584 | 25821184 | 2637824 |
| 3 | C | reservation | 12058624 | 15859712 | 4227072 |
| 3 | C | ticket | 13123584 | 26869760 | 3686400 |
| 3 | D | reservation | 12058624 | 16908288 | 5275648 |
| 3 | D | ticket | 13123584 | 26869760 | 3686400 |

INSERT 10.000 redaka u privremenu InnoDB kopiju reservation. Pocetni podaci su isti, svako mjerenje se ponisti; zagrijavanje, priprema kopije i ROLLBACK nisu u vremenu. Medijan/min-max svih 15 uzoraka po konfiguraciji. Negativno trajanje odbacuje cijelu seriju prije generiranja dokumentacije; svi prikazani uzorci prosli su provjeru.

| Konfiguracija | Medijan [min-max] ms | Promjena prema A |
| --- | --- | --- |
| A | 156.5 [112.6-194.9] | +0.00 % |
| B | 158.0 [125.0-233.9] | +0.94 % |
| C | 216.6 [165.4-246.2] | +38.40 % |
| D | 203.7 [167.9-285.2] | +30.16 % |

A, svih 15 INSERT vremena (ms): 162.6, 182.0, 194.9, 183.1, 112.6, 173.5, 156.5, 135.9, 127.9, 157.9, 146.9, 143.0, 150.0, 140.6, 176.3.

B, svih 15 INSERT vremena (ms): 163.6, 170.2, 162.3, 177.6, 147.3, 145.7, 153.0, 152.9, 158.0, 202.4, 233.9, 149.3, 125.0, 162.6, 134.9.

C, svih 15 INSERT vremena (ms): 172.8, 246.2, 203.2, 243.2, 245.7, 165.4, 242.6, 209.9, 176.1, 207.9, 227.1, 186.6, 216.6, 218.3, 222.4.

D, svih 15 INSERT vremena (ms): 263.7, 230.7, 236.7, 285.2, 248.0, 169.8, 205.5, 224.1, 202.3, 183.2, 203.7, 167.9, 197.8, 199.1, 203.0.

Ticket: 189133 karata, 3988 s povratom (2.1086 %), 185145 s NULL cancelled_at. Uski idx_ticket_cancelled_at povecava INDEX_LENGTH prema A za 2637824-2637824 bajtova (oko 2.6 MB). Indeks sadrzi i NULL vrijednosti svih neotkazanih karata.

## Procjena indeksa

| Usporedba | Prije ms | Poslije ms | Tumacenje |
| --- | --- | --- | --- |
| A/B, Q3 | 206.3 | 0.144 | Uski confirmed_at izdvaja datumski raspon |
| A/B, Q5 | 58.2 | 0.709 | Uski cancelled_at izdvaja povrate |
| B/C, Q4 | 0.075 | 0.034 | Indeks kupca izbjegava sortiranje |
| B/C, Q2 | 524.0 | 499.4 | Pokrivajuci povrati mijenjaju dio izvjestaja |
| C/D, Q2 | 499.4 | 593.1 | Siri indeks potvrda |
| B/C, INSERT | 158.0 | 216.6 | Samo trosak reservation indeksa |

Q4 razlika B/C je 40.6 mikrosekundi. INSERT C/B promjena je +37.1 %. To su izmjereni smjerovi promjene, bez tvrdnje da je svaka razlika statisticki znacajna.

Konacni izbor za ovaj testni workload ostaje B: uski confirmed_at i cancelled_at uz postojece FK/UNIQUE/operativne indekse. C/D ostaju kandidati za opterecenje s vise citanja. Prednost u izvjestaju ne odbacujemo ako postoji: tablice iznad pokazuju stvaran dobitak i trosak. Bez omjera citanja/pisanja i ciljne latencije ne tvrdimo da je B univerzalno optimalan.

idx_res_status_expires(status,expires_at) odgovara jednakosti statusa i rasponu isteka; uq_ticket_code sluzi pojedinacnom check-in lookupu. Kompozitni UNIQUE indeksi sluze i FK konzistentnosti pa se ne brisu samo zbog preklapanja s PK. Indeks event_date opisuje lokalni kalendar, ne globalno UTC sortiranje vise zona.

## Ogranicenja mjerenja

INSERT koristi CREATE TEMPORARY TABLE LIKE reservation: kopira stupce, CHECK/UNIQUE i indekse, ali ne FK ni triggere. Ne mjeri poslovne procedure, trajni COMMIT ni pisanje ticket tablice. Zato ovim testom nije izmjerena cijena pisanja pokrivajuceg ticket indeksa. INDEX_LENGTH su procjene alociranih stranica, ne precizne logicke velicine; NULL vrijednosti takodjer ulaze u InnoDB indekse. Mjesecno grupiranje ima CONVERT_TZ/UNIX_TIMESTAMP obradu pa se stari DATETIME rezultati ne prenose.

Izvori: [MariaDB ANALYZE FORMAT=JSON](https://mariadb.com/docs/server/reference/sql-statements/administrative-sql-statements/analyze-and-explain-statements/analyze-format-json), [CREATE TABLE LIKE](https://mariadb.com/docs/server/server-usage/tables/create-table), [izbor indeksa](https://mariadb.com/docs/server/ha-and-performance/optimization-and-tuning/optimization-and-indexes/building-the-best-index-for-a-given-select).

## Reprodukcija

```bash
bash perf/00_create_perf_db.sh
docker compose exec -T db sh -c 'MYSQL_PWD="$MARIADB_ROOT_PASSWORD" mariadb -uroot' < perf/01_generate_100k.sql
# Arhiviraj stari series.tsv i series_manifest.json izvan perf/results.
python3 perf/run_series.py
python3 perf/summarize.py --document > docs/07_performanse.md
```

Glavna baza treba imati cisti seed od 175 rezervacija; performance kopija se zamjenjuje. Funkcionalni dokazi nove sheme su u tests/results/manifest.json, a nezavisne seed provjere u perf/results/checks. FINAL_COUNTS potvrduje 0 neuskladjenih brojaca.

