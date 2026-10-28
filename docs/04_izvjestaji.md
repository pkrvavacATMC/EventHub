# Task 4 — Izvještaji

Izvještaji se izvršavaju nad **`eventhub` nakon realnog seeda** (175 rezervacija),
a ne nad `eventhub_perf`. Ne mijenjaju podatke.

## Pokretanje

Iz korijena projekta:

```bash
docker compose exec -T db sh -c 'MYSQL_PWD="$EVENTHUB_REPORT_PASSWORD" mariadb -ueventhub_report eventhub' < reports/01_reports.sql
docker compose exec -T db sh -c 'MYSQL_PWD="$MARIADB_ROOT_PASSWORD" mariadb -uroot eventhub' < reports/02_verify_reports.sql
```

Izvještaje možeš otvoriti i izvršiti u DBeaveru kao `eventhub_report`.
Provjera koristi `root` jer stvara privremene tablice; trajne tablice ne mijenja.
Očekivani rezultat provjere: **18 PASS, 0 FAIL**. Na izmijenjenim seed podacima
provjere poznatih vrijednosti mogu opravdano pasti.

## Definicije i upiti

Metrike su definirane u [`migrations/004-views.sql`](../migrations/004-views.sql), a osam
konkretnih odgovora u [`reports/01_reports.sql`](../reports/01_reports.sql).
Za prikaz JOIN-ova i agregacija treba pogledati i definicije viewova.

| Upit | Definicija i način izračuna | Rezultat na seedu |
|---|---|---|
| Q1 — najviše potvrđenih karata | `v_ticket_stats`, sortiranje silazno. Potvrđene karte su karte potvrđenih rezervacija bez `cancelled_at`. | Proljetni rock festival: 63; ukupno 267 važećih karata. |
| Q2 — kupci s najviše rezervacija | `buyer LEFT JOIN reservation`, `COUNT(r.id)` i grupiranje po kupcu; svi statusi, uključeni kupci s nulom. | Ema Radic, ID 35: 10; sljedeći kupci ID 11, 16 i 30 imaju po 9. |
| Q3 — manje od 10 % slobodno | `v_event_capacity`; slobodno prema zbroju kapaciteta kategorija, ne kapacitetu dvorane. Filtrira se nezaokružen omjer; događaji bez prodajnog kapaciteta izostaju. | Samo Jesenski indie koncert: 19/20 zauzeto, 1 mjesto slobodno (5 %). |
| Q4 — prihod po eventu | `event LEFT JOIN v_revenue_monthly`, zbroj `net_revenue`; bez prodaje 0 €. | Svih 8 evenata; iznosi su niže. |
| Q5 — eventi bez rezervacija | `v_reservations_by_event WHERE total_reservations = 0`; bez ijedne rezervacije, bilo kojeg statusa. | Samo Kazalisna premijera. |
| Q6 — stopa otkazivanja | `v_ticket_stats`; po kartama: otkazao kupac / (sve rezervirane − istekle) × 100. Uključuje vraćene karte i karte pending rezervacija koje je kupac otkazao. | Zimska jazz vecer: 15 / (50 − 7) = 34,9 %. Bez nazivnika rezultat je NULL. |
| Q7 — organizatori s najvećim prihodom | `organizer LEFT JOIN v_revenue_monthly`, zbroj po organizatoru; uključeni organizatori bez prodaje s 0 €. | Adria Live d.o.o.: 11.120,00 €; Zvuk Grada j.d.o.o.: 2.165,10 €; Kultura Plus: 1.151,50 €. |
| Q8 — mjesečni trend | `v_revenue_monthly`, zbroj po mjesecu. Prodaja i zaštita prema `confirmed_at`, povrati prema `cancelled_at`. | Siječanj–listopad 2026.; ukupno 14.436,60 €. Mjeseci bez transakcija nisu generirani. |

Prihod znači **cijene karata + service fee + refund protection fee − povrati**.
Uključuju se sve nekad potvrđene kupnje (`confirmed_at IS NOT NULL`), čak i ako
su poslije otkazane. Naknade se ne vraćaju. Zaštita se zbraja jednom po
rezervaciji, odvojeno od stavki, kako JOIN ne bi umnožio iznose.
Prihod ovdje nije porezni ili računovodstveni obračun dobiti.

### Prihod po eventu (Q4)

| Event | EUR |
|---|---:|
| Novogodisnji koncert | 5.200,00 |
| Proljetni rock festival | 4.870,00 |
| Zimska jazz vecer | 1.174,50 |
| Klasika pod zvijezdama | 1.151,50 |
| Ljetni festival Split | 1.050,00 |
| Stand-up vecer | 525,80 |
| Jesenski indie koncert | 464,80 |
| Kazalisna premijera | 0,00 |
| **Ukupno** | **14.436,60** |

### Mjesečni neto prihod (Q8)

| Mjesec 2026. | EUR |
|---|---:|
| 01 | 556,00 |
| 02 | 2.464,50 |
| 03 | 2.844,00 |
| 04 | 180,00 |
| 05 | 568,00 |
| 06 | 518,50 |
| 07 | 241,40 |
| 08 | 2.331,90 |
| 09 | 2.757,30 |
| 10 | 1.975,00 |

## Kad je potreban LEFT JOIN

`INNER JOIN` vraća samo retke koji imaju par. Kazalisna premijera nema
rezervacija niti redaka u `v_revenue_monthly`: unutarnji JOIN bi je izostavio.
`LEFT JOIN` zadržava početni event, a nedostajuće vrijednosti daje kao NULL.

Q5 to koristi unutar `v_reservations_by_event`: `COUNT(r.id)` broji samo stvarne
rezervacije i za premijeru daje 0. `COUNT(*)` bi za taj event pogrešno dao 1.
Alternativni prikaz istog pitanja:

```sql
SELECT e.id, e.name
FROM event e LEFT JOIN reservation r ON r.event_id = e.id
WHERE r.id IS NULL;
```

Q4 kreće od svih evenata i radi `LEFT JOIN` na prihod; `COALESCE(SUM(...), 0)`
daje premijeri 0 €. Q7 analogno zadržava sve organizatore, čak i bez prodaje.
Q2 istim postupkom zadržava kupce bez rezervacija.

## Dokaz točnosti

[`reports/02_verify_reports.sql`](../reports/02_verify_reports.sql) materijalizira
rezultate istih osam upita u privremene tablice unutar zajedničkog snapshota.
Ispisuje pojedinačni PASS/FAIL i završni zbroj: **18 PASS, 0 FAIL**.

Provjere uključuju poznate seed slučajeve, sva tri zbroja prihoda (event,
organizator, mjesec), neovisan obračun prihoda iz osnovnih tablica, 267 važećih
karata i neovisan obračun stope otkazivanja za svaki event. Za jazz večer
provjerava se i ručni račun 15/43 = 34,9 %. Poznati siječanjski račun je
567 + 14 − 25 = 556 €. Time se ne provjerava samo da se dva izvještaja slažu,
nego i da odgovaraju unaprijed poznatim iznosima.

## Regresija otkazivanja

Provjera dodatno pokušava direktno otkazati potvrđenu rezervaciju s važećim
kartama: trigger mora odbiti operaciju s 1644 i odgovarajućom porukom.
SAVEPOINT i ROLLBACK štite podatke čak i ako bi zaštita nedostajala.
Q1 se provjerava i zasebno po svakom eventu prema osnovnim tablicama.
View dodatno eksplicitno provjerava `r.status = 'confirmed'` pri brojanju
važećih karata; broj otkazanih karata za Q6 ostaje nepromijenjen.
