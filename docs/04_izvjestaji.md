# Izvjestaji i provjera

Provjereno **2026-10-29T15:09:40.017760+00:00**, na novoj shemi. Dokazi: [manifest](../tests/results/manifest.json).

Nad cistim seedom: **8 evenata, 40 kupaca, 175 rezervacija, 290 karata**. Rezultat: **18 PASS, 0 FAIL**.

```bash
docker compose exec -T db sh -c 'MYSQL_PWD="$MARIADB_ROOT_PASSWORD" mariadb -uroot eventhub' < reports/02_verify_reports.sql
```

Osam upita je u [reports/01_reports.sql](../reports/01_reports.sql), definicije u [004-views.sql](../migrations/004-views.sql). Q1 broji potvrdene karte; Q2 rangira kupce; Q3 nalazi manje od 10 % mjesta; Q4 prihod po eventu; Q5 evente bez rezervacija; Q6 stopu otkazivanja bez isteka u nazivniku; Q7 organizatore; Q8 poslovne mjesece u Europe/Zagreb.

| provjera | rezultat |
| --- | --- |
| Seed: 8 evenata, 40 kupaca, 175 rezervacija, 290 karata | PASS |
| Q1: potvrdene karte = 267 i neovisni broj vazecih karata | PASS |
| Q1/Q4/Q6: svi eventi su ukljuceni | PASS |
| Q2: svi kupci, ukupno 175 rezervacija | PASS |
| Q3: samo Jesenski indie koncert, 19/20 prodano, 5 % slobodno | PASS |
| Q5: samo Kazalisna premijera bez rezervacija | PASS |
| Q4: Kazalisna premijera postoji i prihod je 0 | PASS |
| Q4/Q7/Q8: prihod jednak neovisnom izracunu iz tablica | PASS |
| Q7: svaki organizator ukljucen, cak i bez prihoda | PASS |
| Q6: Kazalisna premijera ima NULL stopu (nema rezerviranih karata) | PASS |
| Q6: stopa svakog eventa odgovara neovisnom izracunu | PASS |
| Q2: kupac 35 (Ema Radic) ima najvise rezervacija: 10 | PASS |
| Q4/Q7/Q8: poznati ukupni neto prihod 14436.60 EUR | PASS |
| Q7: Adria Live ima 11120.00 EUR i najveci prihod | PASS |
| Q8: sijecanj 2026: 567 + 14 - 25 = 556 EUR | PASS |
| Q6: Zimska jazz vecer: 15 / (50 - 7) = 34.9 % | PASS |
| Regresija Q1: direktno otkazivanje s vazecim kartama je odbijeno | PASS |
| Q1: svaki event odgovara kartama confirmed rezervacija | PASS |

[Sirovi dokaz](../tests/results/reports.tsv). Provjera se izvrsava prije demonstracija koje dodaju podatke; poznate seed brojke poslije toga nisu primjenjive.
