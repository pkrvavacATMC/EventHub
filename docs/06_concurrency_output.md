# Rezultati konkurentnih kupnji

Provjereno **2026-10-29T16:35:25.403418+00:00**, na novoj shemi. Dokazi: [manifest](../tests/results/manifest.json).

| rezultat | scenarij | stanje |
| --- | --- | --- |
| PASS | A: problem reproduciran (prodano > kapacitet) | kapacitet=10, brojac=10, stvarno=11, kupili zadnju=2 |
| PASS | B: FOR UPDATE - zadnju kartu kupila tocno 1 sesija | kapacitet=10, brojac=10, stvarno=10, kupili zadnju=1 |
| PASS | C: CHECK odbio drugi upis, nema prekoracenja | kapacitet=10, brojac=10, stvarno=10, kupili zadnju=1 |
| PASS | D: procedure - potvrdena tocno 1 od 10 kupnji zadnje karte | kapacitet=10, brojac=10, stvarno=10, kupili zadnju=1 |

A namjerno reproducira oversell (11/10), zatim ga popravlja. B zakljucava red, C odbija drugi relativni upis, D koristi 10 zasebnih veza i stvarne procedure. Svi scenariji prolaze i zavrsni v_reserved_check je prazan. Skripta sada vraca neuspjesan izlazni kod ako provjera padne.

[Potpun novi ispis svih sesija](../tests/results/concurrency.txt). Reprodukcija: `bash tests/06_concurrency.sh`, nad testnom bazom; dodaje demo podatke.
