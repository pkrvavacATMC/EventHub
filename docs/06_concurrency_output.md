# Task 6 — Rezultati testova konkurentnosti

Skripta: [06_concurrency.sh](../tests/06_concurrency.sh).

## Sažetak

**4 PASS · 0 FAIL**. Testovi prikazuju istovremenu kupnju zadnje karte, zaštitu zaključavanjem, zaštitu `CHECK` ograničenjem i ponašanje poslovnih procedura s deset sesija.

U scenariju A rezultat `PASS` potvrđuje reprodukciju prekoračenja kapaciteta. U scenarijima B, C i D zadnju kartu kupuje točno jedna sesija.

## A) BEZ ZAKLJUCAVANJA - reprodukcija problema

Event 16: kapacitet 10, prodano 9, ostaje 1 karta. Sesije A i B krecu istovremeno.

| Sesija | Događaj | Vrijeme |
| --- | --- | --- |
| A | START, citam slobodna mjesta | 14:16:21.021339 |
| A | vidim slobodnih: 1 | 14:16:21.029151 |
| B | START, citam slobodna mjesta | 14:16:21.356616 |
| B | vidim slobodnih: 1 | 14:16:21.362303 |
| A | KUPIO zadnju kartu (COMMIT) | 14:16:23.037319 |
| B | KUPIO zadnju kartu (COMMIT) | 14:16:23.376779 |

### A

| kapacitet | brojac_reserved | stvarno_prodano | izdanih_karata | v_reserved_check |
| --- | --- | --- | --- | --- |
| 10 | 10 | 11 | 9 | NEKONZISTENTNO |

### A - rucni popravak (visak otkazan)

| kapacitet | brojac_reserved | stvarno_prodano | izdanih_karata | v_reserved_check |
| --- | --- | --- | --- | --- |
| 10 | 10 | 10 | 9 | OK |

## B) RJESENJE: SELECT ... FOR UPDATE (pesimisticko zakljucavanje)

Event 17: kapacitet 10, prodano 9, ostaje 1 karta. Sesije A i B krecu istovremeno.

| Sesija | Događaj | Vrijeme |
| --- | --- | --- |
| A | START, citam slobodna mjesta | 14:16:24.272689 |
| A | vidim slobodnih: 1 | 14:16:24.273316 |
| B | START, citam slobodna mjesta | 14:16:24.585198 |
| B | vidim slobodnih: 0 | 14:16:26.304011 |
| A | KUPIO zadnju kartu (COMMIT) | 14:16:26.306066 |
| B | ODBIJENO: nema slobodnih mjesta | 14:16:28.309737 |

### B

| kapacitet | brojac_reserved | stvarno_prodano | izdanih_karata | v_reserved_check |
| --- | --- | --- | --- | --- |
| 10 | 10 | 10 | 9 | OK |

## C) ZADNJA LINIJA OBRANE: CHECK chk_category_reserved (bez locka)

Event 18: obje sesije vide 1 slobodno mjesto, ali upis reserved+1 druge sesije krsi CHECK.

| Sesija | Događaj | Vrijeme |
| --- | --- | --- |
| A | START, citam slobodna mjesta | 14:16:28.951160 |
| A | vidim slobodnih: 1 | 14:16:28.952531 |
| B | START, citam slobodna mjesta | 14:16:29.250843 |
| B | vidim slobodnih: 1 | 14:16:29.251367 |
| A | KUPIO zadnju kartu (COMMIT) | 14:16:30.955751 |
| B | ODBIJENO (greska baze): CONSTRAINT `chk_category_reserved` failed for `eventhub`.`ticket_category` | 14:16:31.252478 |

### C

| kapacitet | brojac_reserved | stvarno_prodano | izdanih_karata | v_reserved_check |
| --- | --- | --- | --- | --- |
| 10 | 10 | 10 | 9 | OK |

## D) STVARNE PROCEDURE: 10 sesija istovremeno, create + confirm

Event 19: 10 neovisnih sesija istovremeno trazi zadnju kartu.

| Sesija | Rezultat |
| --- | --- |
| 1 | ODBIJENO - Nema dovoljno slobodnih mjesta |
| 2 | KUPILA zadnju kartu (rezervacija 224, confirmed) |
| 3 | ODBIJENO - Nema dovoljno slobodnih mjesta |
| 4 | ODBIJENO - Nema dovoljno slobodnih mjesta |
| 5 | ODBIJENO - Nema dovoljno slobodnih mjesta |
| 6 | ODBIJENO - Nema dovoljno slobodnih mjesta |
| 7 | ODBIJENO - Nema dovoljno slobodnih mjesta |
| 8 | ODBIJENO - Nema dovoljno slobodnih mjesta |
| 9 | ODBIJENO - Nema dovoljno slobodnih mjesta |
| 10 | ODBIJENO - Nema dovoljno slobodnih mjesta |

### D

| kapacitet | brojac_reserved | stvarno_prodano | izdanih_karata | v_reserved_check |
| --- | --- | --- | --- | --- |
| 10 | 10 | 10 | 10 | OK |

## Detaljni sažetak

| Rezultat | Scenarij | Zabilježeno stanje |
| --- | --- | --- |
| PASS | A: problem reproduciran (prodano > kapacitet) | kapacitet=10, brojac=10, stvarno=11, kupili zadnju=2 |
| PASS | B: FOR UPDATE - zadnju kartu kupila tocno 1 sesija | kapacitet=10, brojac=10, stvarno=10, kupili zadnju=1 |
| PASS | C: CHECK odbio drugi upis, nema prekoracenja | kapacitet=10, brojac=10, stvarno=10, kupili zadnju=1 |
| PASS | D: procedure - potvrdena tocno 1 od 10 kupnji zadnje karte | kapacitet=10, brojac=10, stvarno=10, kupili zadnju=1 |

UKUPNO: 4 PASS, 0 FAIL
