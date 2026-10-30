# Završna provjera nove baze

Provjereno **2026-10-29T16:35:25.403418+00:00**, na novoj shemi. Dokazi: [manifest](../tests/results/manifest.json).

Sedam SQL datoteka, 56 changesetova; 006 nadograđuje buyer bez promjene prethodnih changesetova. Shema je testirana od praznog volumena i ponovnim updateom, zatim potpunim rollbackom svih 56 changesetova, ponovnim updateom i seedom.

| Područje | Rezultat |
| --- | --- |
| Ograničenja izvornih poslovnih pravila | 88/88 |
| Novi UUID/type/zone unosi | 15 odbijenih nevaljanih unosa; UUID testiran u oba SQL načina |
| Izvještaji čistog seeda | 18/18 |
| Transakcijski scenariji | 7/7 |
| Konkurentnost | 4/4; 10 veza za zadnju kartu |
| UTC/DST matrica | 24 create, 12 confirm, 72 refund, 48 check-in, 12 simulacija sata |
| Rok preko samog DST prijelaza | 6/6; 900 sekundi u tri zone |
| Zaštite transakcije / povrat zone nakon greške | 6/6 i 5/5 |
| Ovlasti i stvarni app pozivi | Pet procedura prolazi; nedopušteni upisi/čitanje odbijeni |
| Sigurnosna kopija i povrat podataka | 12 tablica; svi checksumovi i epoch vrijednosti isti |
| Scheduler | Stvarni UTC event otkazao isteklu rezervaciju; rok 900 sekundi |
| Seed | 8 događaja, 40 kupaca, 175 rezervacija; external_id je NULL |
| Potpuni rollback i ponovna instalacija | 56/56 |

## Reprodukcija

```bash
python3 tests/test_database.py
# Obnovi i izmjeri eventhub_perf prema docs/07_performanse.md.
python3 docs/render_docs.py
```

Test koristi vlastiti Compose projekt i volumen; glavnu i performance bazu ne mijenja. Vremenski model i poslovna pravila opisani su u [strukturi baze](02_database_structure.md).

[EXPLAIN check-ina](../tests/results/check_in_explain.tsv) koristi uq_ticket_code, const i jedan redak. [Mjerenja indeksa](07_performanse.md) imaju zaseban manifest i datum; čitanje/pisanje cijelog produkcijskog workload-a, aplikacija i gateway nisu predmet ovih testova. Ovo je dokaz navedenih provjera na MariaDB 10.11, ne tvrdnja da nijedna moguća greška ne postoji.

## Nadogradnja postojećih baza na 006

Provjereno 2026-10-29T16:30:43.633091+00:00. U obje baze primijenjena je samo 006; prethodnih 55 changesetova i njihovi checksumi ostali su isti. Usporedba svih poslovnih stupaca kupaca i svih redaka rezervacija i karata daje identične SHA-256 prije i poslije migracije.

| baza | kupci | rezervacije | karte |
| --- | --- | --- | --- |
| eventhub | 40 | 175 | 290 |
| eventhub_perf | 5040 | 100175 | 189133 |

Na postojećem eventhubu: 88/88 podataka, 18/18 izvještaja, 7/7 transakcija, 4/4 konkurentnost i sve očekivane read-only zabrane. Seed nije ponovno pokrenut. Transakcijske i konkurentne demonstracije dodaju podatke; navedene brojke čistog seeda vrijede prije demonstracija. Obje baze imaju usklađene brojače. [Očuvanje podataka](../tests/results/keycloak_migration.json), [manifest provjere postojeće baze](../tests/results/keycloak_live_manifest.json).
