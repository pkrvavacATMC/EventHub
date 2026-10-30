# Testovi neispravnih podataka i očekivano ponašanje

Provjereno **2026-10-29T16:35:25.403418+00:00**, na novoj shemi. Dokazi: [manifest](../tests/results/manifest.json).

Skripta `tests/01_invalid_data.sql` izvršava se nakon migracija i seeda. Svaki test provjerava očekivani kod greške i dio poruke; pozitivni testovi očekuju uspjeh. Direktni upisi izvode se u transakciji koju `t_expect` poništava, a nedopušteni pozivi procedura moraju biti odbijeni. Brojači zauzeća na kraju moraju biti usklađeni.

| Kod | Zaštita |
| --- | --- |
| 1048 | NOT NULL |
| 1062 | UNIQUE |
| 1451 / 1452 | FOREIGN KEY |
| 4025 | CHECK |
| 1644 | Poslovno pravilo u triggeru ili proceduri |

## Keycloak poveznica

`external_id` je NULL ili UUID malim slovima s crticama. UNIQUE odbija duplikat, CHECK odbija pogrešan format, velika slova, nedostajuće crtice i neheksadekadske znakove. Dva nova kupca s NULL vrijednošću i upis valjanog UUID-a prolaze; svi upisi se poništavaju. Dodatne provjere u `tests/suite_checks.py` pokrivaju newline i NO_BACKSLASH_ESCAPES.

## Rezultati

Svi scenariji i njihovi rezultati nalaze se u [tablici rezultata](01_invalid_data_output.md).

**88 PASS, 0 FAIL.** [Sirovi ispis](../tests/results/invalid_data.tsv). [Dodatne provjere](../tests/results/constraints.txt), [završna validacija](10_schema_validation.md).
