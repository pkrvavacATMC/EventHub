# Rezultati konkurentnih kupnji

Provjereno **2026-10-29T16:35:25.403418+00:00**, na novoj shemi. Dokazi: [manifest](../tests/results/manifest.json).

| rezultat | scenarij | stanje |
| --- | --- | --- |
| PASS | A: problem reproduciran (prodano > kapacitet) | kapacitet=10, brojac=10, stvarno=11, kupili zadnju=2 |
| PASS | B: FOR UPDATE - zadnju kartu kupila tocno 1 sesija | kapacitet=10, brojac=10, stvarno=10, kupili zadnju=1 |
| PASS | C: CHECK odbio drugi upis, nema prekoracenja | kapacitet=10, brojac=10, stvarno=10, kupili zadnju=1 |
| PASS | D: procedure - potvrdena tocno 1 od 10 kupnji zadnje karte | kapacitet=10, brojac=10, stvarno=10, kupili zadnju=1 |

A prikazuje prodaju 11 karata uz kapacitet 10 i ispravak transakcijom. B zaključava redak, C odbija prekoračenje brojača, a D koristi 10 zasebnih veza i poslovne procedure. Sva četiri scenarija prolaze; završni v_reserved_check je prazan.

[Potpun ispis svih sesija](../tests/results/concurrency.txt). Reprodukcija: `bash tests/06_concurrency.sh`, nad testnom bazom; dodaje demo podatke.
