# Zavrsna provjera nove baze

Provjereno **2026-10-29T15:09:40.017760+00:00**, na novoj shemi. Dokazi: [manifest](../tests/results/manifest.json).

Sest SQL datoteka, 55 changesetova; svaki objekt definiran jednom. Shema je testirana od praznog volumena i ponovnim updateom, zatim potpunim rollbackom svih 55 changesetova, ponovnim updateom i seedom.

| Podrucje | Rezultat |
| --- | --- |
| Ogranicenja izvornih poslovnih pravila | 81/81 |
| Novi auth/type/zone unosi | 16 odbijenih nevaljanih unosa; bcrypt 2a/2b/2y i stvarni argon2id prihvaceni u oba SQL nacina |
| Izvjestaji cistog seeda | 18/18 |
| Transakcijski scenariji | 7/7 |
| Konkurentnost | 4/4; 10 veza za zadnju kartu |
| UTC/DST matrica | 24 create, 12 confirm, 72 refund, 48 check-in, 12 simulacija sata |
| Rok preko samog DST prijelaza | 6/6; 900 sekundi u tri zone |
| Guardovi / povrat zone na gresci | 6/6 i 5/5 |
| Ovlasti i stvarni app pozivi | Pet procedura prolazi; nedopusteni upisi/citanje odbijeni |
| Backup/restore | 12 tablica; svi checksumovi i epoch vrijednosti isti |
| Scheduler | Stvarni UTC event otkazao isteklu rezervaciju; rok 900 sekundi |
| Seed | 8 evenata, 40 kupaca, 175 rezervacija; login primjeri rade |
| Potpuni rollback i ponovna instalacija | 55/55 |

## Ispravljeno tijekom ove provjere

- Regex provjere vise ne prihvacaju zavrsni newline u hashu i event_type.code.
- Procedure vremenske izracune i TIMESTAMP upise izvrsavaju u UTC-u pa vracaju izvornu zonu; rok ne upada u nepostojeci DST sat. Guard ostaje izvan ROLLBACK handlera i lock redoslijed je sacuvan.
- Performance generator pretvara lokalni event_date u UTC prije generiranja sistemskih trenutaka.
- Performance kopija ima scheduler DISABLED vec pri uvozu.
- Dokumentacija se generira iz provjerenih dokaza; manifest otkriva promjenu izvora ili rezultata.

## Reprodukcija

```bash
python3 tests/test_database.py
# Obnovi i izmjeri eventhub_perf prema docs/07_performanse.md.
python3 docs/render_docs.py
```

Test koristi vlastiti Compose projekt i volumen. Glavna baza ostaje cisti seed, performance baza ima novu shemu. Svi sistemski trenuci su TIMESTAMP; jedini poslovni DATETIME je lokalni event_date. Samo buyer.updated_at ima ON UPDATE.

[EXPLAIN check-ina](../tests/results/check_in_explain.tsv) koristi uq_ticket_code, const i jedan redak. [Mjerenja indeksa](07_performanse.md) su nova; citanje/pisanje cijelog produkcijskog workload-a, aplikacija i gateway nisu predmet ovih testova. Ovo je dokaz navedenih provjera na MariaDB 10.11, ne tvrdnja da nijedna moguca greska ne postoji.

## Zavrsno performance mjerenje

Cijela A/B/C/D serija ponovljena je 2026-10-29T15:22:43.337401+00:00: 300 mjerenja upita i 60 INSERT mjerenja, sva trajanja valjana. Sva tri kruga zavrsena su nad istim skupom; na kraju je vracena konfiguracija B, uz 0 neuskladjenih brojaca. Negativno trajanje odbacuje seriju prije objave dokumentacije. [Dokazi i ogranicenja](07_performanse.md), [manifest](../perf/results/series_manifest.json).
