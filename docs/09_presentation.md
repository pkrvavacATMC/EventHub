# Presentation walkthrough

Run commands from the repository root after following the [README](../README.md). Read the [database guide](02_database_structure.md) first. Historical outputs are evidence of earlier runs, not a substitute for explaining live behavior.

## 1. Prepare reports and performance data

Run on the clean seed before demonstrations add records:

```bash
docker compose exec -T db sh -c 'MYSQL_PWD="$MARIADB_ROOT_PASSWORD" mariadb -uroot eventhub' < reports/01_reports.sql
docker compose exec -T db sh -c 'MYSQL_PWD="$MARIADB_ROOT_PASSWORD" mariadb -uroot eventhub' < reports/02_verify_reports.sql
bash perf/00_create_perf_db.sh
docker compose exec -T db sh -c 'MYSQL_PWD="$MARIADB_ROOT_PASSWORD" mariadb -uroot' < perf/01_generate_100k.sql
```

Report verification expects 18 PASS and 0 FAIL. The performance setup **replaces eventhub_perf**, leaving eventhub intact. Expect 100,175 reservations when copied directly from the clean seed.

Explain capacity, revenue and monthly trends using the reporting SQL. Why use LEFT JOIN for events with no purchases? Why must protection fees be counted once per reservation? Explain cancellation versus expiration in cancellation-rate reporting.

## 2. Explain the ERD

Open the diagram from the README. Trace buyer → reservation → item → ticket, then category → seat → hold. Explain composite foreign keys, the price snapshot and the generated active-seat key without reading a prepared explanation.

## 3. Successful and failed reservation

```bash
docker compose exec -T db sh -c 'MYSQL_PWD="$MARIADB_ROOT_PASSWORD" mariadb -uroot eventhub' < tests/09_presentation.sql
```

Expect a confirmed reservation, four issued tickets and reserved=4. A second booking raises occupancy to eight. The final request for three exceeds the remaining two places and produces an expected SQL error and nonzero client exit. Business error messages remain in Croatian.

Copy the printed demo category ID and inspect it in a new root connection: `SELECT capacity, reserved FROM ticket_category WHERE id = <demo_category>;`. Expect capacity=10 and reserved=8. Inspect reservations for the printed event ID: only two were created. The rejected call must leave no partial booking. Explain why quantity three is valid by itself but unavailable here. Each rerun creates fresh demo data.

## 4. Transactions and concurrent booking

```bash
docker compose exec -T db sh -c 'MYSQL_PWD="$MARIADB_ROOT_PASSWORD" mariadb -uroot eventhub' < tests/05_transactions.sql
bash tests/06_concurrency.sh
```

Expect 7/7 transaction checks and 4 concurrency PASS results. A PASS in an intentionally unsafe scenario means the inconsistency was reproduced. Explain failed payment, cancellation and ROLLBACK as distinct operations.

Concurrency A reproduces overselling without locking; B serializes two sessions with FOR UPDATE; C rejects a relative counter increment through CHECK; D lets exactly one of ten sessions buy the last ticket through real procedures. Explain what the second session sees after waiting and why a valid counter alone cannot prove aggregate consistency. These tests add new demo events and require administrative privileges.

Recorded evidence: [transactions](05_transactions_output.md), [concurrency](06_concurrency_output.md).

## 5. Optimization

Review [complete measurements](07_performanse.md) alongside `perf/results/series.tsv`. Recorded A/B medians include Q2 804.00 → 321.98 ms and Q3 116.81 → approximately 0.08 ms. These are historical warm-workload measurements, not guaranteed timings on another machine.

To reproduce, move the existing `perf/results/series.tsv` and `series_manifest.json` to a separate archive directory first; the runner refuses to overwrite the series. Then run:

```bash
python3 perf/run_series.py
python3 perf/summarize.py --document
```

The second command prints the report; redirect only if intentionally replacing the historical document. The runner compares four configurations over three rounds and restores the final narrow indexes. Explain estimated EXPLAIN rows versus actual ANALYZE timing, warm caches, index selectivity and INSERT cost. Explain why the buyer index and covering refund index were rejected rather than claiming every added index is beneficial.

## Final rehearsal

Explain every observed change independently: which row is locked, what rolls back, when tickets are issued, and how the consistency view detects drift. Distinguish seed-only expected totals from demo-enriched data. Stop and inspect unexpected results rather than treating an old PASS table as a live test.
