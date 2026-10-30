# Rezultati transakcijskih testova

Provjereno **2026-10-29T16:35:25.403418+00:00**, na novoj shemi. Dokazi: [manifest](../tests/results/manifest.json).

**7/7 PASS.** PASS u prvom scenariju znači da je namjerni problem bez transakcije reproduciran i zatim popravljen.

| n | test | očekivano | dobiveno | rezultat |
| --- | --- | --- | --- | --- |
| 1 | 1 bez transakcije, placanje palo | reserved=3, karte=0, NEKONZISTENTNO | reserved=3, karte=0, NEKONZISTENTNO | PASS |
| 2 | 1b rucni popravak | reserved=0, OK | reserved=0, OK | PASS |
| 3 | 2 transakcija, placanje palo -> ROLLBACK | reserved=0, rezervacija=1, karte=0 | reserved=0, rezervacija=1, karte=0 | PASS |
| 4 | 3 transakcija, placanje uspjelo -> COMMIT | reserved=3, karte=3 | reserved=3, karte=3 | PASS |
| 5 | 4 procedure, placanje palo | reserved=3, karte=3, cancelled | reserved=3, karte=3, cancelled/buyer | PASS |
| 6 | 5 procedure, placanje uspjelo | reserved=6, karte=6, confirmed | reserved=6, karte=6, confirmed | PASS |
| 7 | 6 procedure, 5 karata -> nista upisano | reserved=6, rezervacija=4 | reserved=6, rezervacija=4 | PASS |

[Sirovi rezultat](../tests/results/transactions.tsv). Dodatno je provjereno šest zaštita transakcije i pet vraćanja vremenske zone veze nakon greške: [dokaz](../tests/results/transaction_guards.txt).
