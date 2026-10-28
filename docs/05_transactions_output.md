# Task 5 — Rezultati testova transakcija

Skripta: [05_transactions.sql](../tests/05_transactions.sql).

## Sažetak

**7/7 PASS** — svi zabilježeni testovi su prošli. Provjereni su neuspjelo i uspješno plaćanje, `ROLLBACK`, `COMMIT` i ponašanje poslovnih procedura.

`PASS` u scenariju bez transakcije znači da je očekivana nekonzistentnost uspješno reproducirana.

## Rezultati scenarija

| n | test | ocekivano | dobiveno | rezultat |
| --- | --- | --- | --- | --- |
| 1 | 1 bez transakcije, placanje palo | reserved=3, karte=0, NEKONZISTENTNO | reserved=3, karte=0, NEKONZISTENTNO | PASS |
| 2 | 1b rucni popravak | reserved=0, OK | reserved=0, OK | PASS |
| 3 | 2 transakcija, placanje palo -> ROLLBACK | reserved=0, rezervacija=1, karte=0 | reserved=0, rezervacija=1, karte=0 | PASS |
| 4 | 3 transakcija, placanje uspjelo -> COMMIT | reserved=3, karte=3 | reserved=3, karte=3 | PASS |
| 5 | 4 procedure, placanje palo | reserved=3, karte=3, cancelled | reserved=3, karte=3, cancelled/buyer | PASS |
| 6 | 5 procedure, placanje uspjelo | reserved=6, karte=6, confirmed | reserved=6, karte=6, confirmed | PASS |
| 7 | 6 procedure, 5 karata -> nista upisano | reserved=6, rezervacija=4 | reserved=6, rezervacija=4 | PASS |

| sazetak | status |
| --- | --- |
| 7/7 PASS | SVI TESTOVI PROSLI |

## Zabilježena otkazana rezervacija

| rezervacija | status | cancel_reason | created_at | cancelled_at |
| --- | --- | --- | --- | --- |
| 197 | cancelled | buyer | 2026-10-28 13:58:46 | 2026-10-28 13:58:46 |
