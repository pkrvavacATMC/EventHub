-- EventHub TASK 7. Pokretati samo nad eventhub_perf; komentari bez dijakritika.
-- Klijent: mariadb -uroot eventhub_perf < perf/02_baseline.sql (ili 04_after.sql).
-- Sve odabrane SELECT naredbe su identicne prije i poslije.
USE eventhub_perf;
SET SESSION query_cache_type = OFF;
SET @buyer = (SELECT MIN(id) FROM buyer WHERE email LIKE 'perf.kupac%');
SELECT 'ENV' AS marker, VERSION() AS version, @@query_cache_type AS query_cache,
       (SELECT COUNT(*) FROM reservation) AS reservations,
       (SELECT COUNT(*) FROM ticket) AS tickets, @buyer AS buyer_id;

ANALYZE TABLE buyer, event, reservation, reservation_item, ticket;
-- Velicine prije privremenog INSERT testa; procjene alociranih InnoDB stranica.
SELECT 'SPACE' AS marker, TABLE_NAME, DATA_LENGTH, INDEX_LENGTH
FROM information_schema.TABLES
WHERE TABLE_SCHEMA = 'eventhub_perf' AND TABLE_TYPE = 'BASE TABLE'
ORDER BY TABLE_NAME;

-- Q1: Task 4 Q2: kupci s najvise rezervacija. Jedno zagrijavanje (0) i pet mjerenja (1-5).
SELECT 'PLAN Q1' AS marker;
EXPLAIN SELECT SQL_NO_CACHE b.id AS buyer_id, b.name, b.surname, COUNT(r.id) AS reservations
FROM buyer b LEFT JOIN reservation r ON r.buyer_id = b.id
GROUP BY b.id, b.name, b.surname
ORDER BY reservations DESC, buyer_id;
SELECT 'RUN Q1 0' AS marker;
ANALYZE FORMAT=JSON SELECT SQL_NO_CACHE b.id AS buyer_id, b.name, b.surname, COUNT(r.id) AS reservations
FROM buyer b LEFT JOIN reservation r ON r.buyer_id = b.id
GROUP BY b.id, b.name, b.surname
ORDER BY reservations DESC, buyer_id;
SELECT 'RUN Q1 1' AS marker;
ANALYZE FORMAT=JSON SELECT SQL_NO_CACHE b.id AS buyer_id, b.name, b.surname, COUNT(r.id) AS reservations
FROM buyer b LEFT JOIN reservation r ON r.buyer_id = b.id
GROUP BY b.id, b.name, b.surname
ORDER BY reservations DESC, buyer_id;
SELECT 'RUN Q1 2' AS marker;
ANALYZE FORMAT=JSON SELECT SQL_NO_CACHE b.id AS buyer_id, b.name, b.surname, COUNT(r.id) AS reservations
FROM buyer b LEFT JOIN reservation r ON r.buyer_id = b.id
GROUP BY b.id, b.name, b.surname
ORDER BY reservations DESC, buyer_id;
SELECT 'RUN Q1 3' AS marker;
ANALYZE FORMAT=JSON SELECT SQL_NO_CACHE b.id AS buyer_id, b.name, b.surname, COUNT(r.id) AS reservations
FROM buyer b LEFT JOIN reservation r ON r.buyer_id = b.id
GROUP BY b.id, b.name, b.surname
ORDER BY reservations DESC, buyer_id;
SELECT 'RUN Q1 4' AS marker;
ANALYZE FORMAT=JSON SELECT SQL_NO_CACHE b.id AS buyer_id, b.name, b.surname, COUNT(r.id) AS reservations
FROM buyer b LEFT JOIN reservation r ON r.buyer_id = b.id
GROUP BY b.id, b.name, b.surname
ORDER BY reservations DESC, buyer_id;
SELECT 'RUN Q1 5' AS marker;
ANALYZE FORMAT=JSON SELECT SQL_NO_CACHE b.id AS buyer_id, b.name, b.surname, COUNT(r.id) AS reservations
FROM buyer b LEFT JOIN reservation r ON r.buyer_id = b.id
GROUP BY b.id, b.name, b.surname
ORDER BY reservations DESC, buyer_id;

-- Q2: Task 4 Q8: mjesecni trend prihoda. Jedno zagrijavanje (0) i pet mjerenja (1-5).
SELECT 'PLAN Q2' AS marker;
EXPLAIN SELECT SQL_NO_CACHE month, SUM(ticket_gross) AS ticket_gross,
       SUM(protection_fees) AS protection_fees, SUM(refunds) AS refunds,
       SUM(net_revenue) AS net_revenue
FROM v_revenue_monthly
GROUP BY month ORDER BY month;
SELECT 'RUN Q2 0' AS marker;
ANALYZE FORMAT=JSON SELECT SQL_NO_CACHE month, SUM(ticket_gross) AS ticket_gross,
       SUM(protection_fees) AS protection_fees, SUM(refunds) AS refunds,
       SUM(net_revenue) AS net_revenue
FROM v_revenue_monthly
GROUP BY month ORDER BY month;
SELECT 'RUN Q2 1' AS marker;
ANALYZE FORMAT=JSON SELECT SQL_NO_CACHE month, SUM(ticket_gross) AS ticket_gross,
       SUM(protection_fees) AS protection_fees, SUM(refunds) AS refunds,
       SUM(net_revenue) AS net_revenue
FROM v_revenue_monthly
GROUP BY month ORDER BY month;
SELECT 'RUN Q2 2' AS marker;
ANALYZE FORMAT=JSON SELECT SQL_NO_CACHE month, SUM(ticket_gross) AS ticket_gross,
       SUM(protection_fees) AS protection_fees, SUM(refunds) AS refunds,
       SUM(net_revenue) AS net_revenue
FROM v_revenue_monthly
GROUP BY month ORDER BY month;
SELECT 'RUN Q2 3' AS marker;
ANALYZE FORMAT=JSON SELECT SQL_NO_CACHE month, SUM(ticket_gross) AS ticket_gross,
       SUM(protection_fees) AS protection_fees, SUM(refunds) AS refunds,
       SUM(net_revenue) AS net_revenue
FROM v_revenue_monthly
GROUP BY month ORDER BY month;
SELECT 'RUN Q2 4' AS marker;
ANALYZE FORMAT=JSON SELECT SQL_NO_CACHE month, SUM(ticket_gross) AS ticket_gross,
       SUM(protection_fees) AS protection_fees, SUM(refunds) AS refunds,
       SUM(net_revenue) AS net_revenue
FROM v_revenue_monthly
GROUP BY month ORDER BY month;
SELECT 'RUN Q2 5' AS marker;
ANALYZE FORMAT=JSON SELECT SQL_NO_CACHE month, SUM(ticket_gross) AS ticket_gross,
       SUM(protection_fees) AS protection_fees, SUM(refunds) AS refunds,
       SUM(net_revenue) AS net_revenue
FROM v_revenue_monthly
GROUP BY month ORDER BY month;

-- Q3: Bruto prodaja u jednom danu (bez zastite i povrata). Jedno zagrijavanje (0) i pet mjerenja (1-5).
SELECT 'PLAN Q3' AS marker;
EXPLAIN SELECT SQL_NO_CACHE COUNT(DISTINCT r.id) AS reservations,
       SUM(ri.quantity * (ri.price_per_ticket + ri.service_fee_per_ticket)) AS ticket_gross
FROM reservation r JOIN reservation_item ri ON ri.reservation_id = r.id
WHERE r.confirmed_at >= '2026-06-01' AND r.confirmed_at < '2026-06-02';
SELECT 'RUN Q3 0' AS marker;
ANALYZE FORMAT=JSON SELECT SQL_NO_CACHE COUNT(DISTINCT r.id) AS reservations,
       SUM(ri.quantity * (ri.price_per_ticket + ri.service_fee_per_ticket)) AS ticket_gross
FROM reservation r JOIN reservation_item ri ON ri.reservation_id = r.id
WHERE r.confirmed_at >= '2026-06-01' AND r.confirmed_at < '2026-06-02';
SELECT 'RUN Q3 1' AS marker;
ANALYZE FORMAT=JSON SELECT SQL_NO_CACHE COUNT(DISTINCT r.id) AS reservations,
       SUM(ri.quantity * (ri.price_per_ticket + ri.service_fee_per_ticket)) AS ticket_gross
FROM reservation r JOIN reservation_item ri ON ri.reservation_id = r.id
WHERE r.confirmed_at >= '2026-06-01' AND r.confirmed_at < '2026-06-02';
SELECT 'RUN Q3 2' AS marker;
ANALYZE FORMAT=JSON SELECT SQL_NO_CACHE COUNT(DISTINCT r.id) AS reservations,
       SUM(ri.quantity * (ri.price_per_ticket + ri.service_fee_per_ticket)) AS ticket_gross
FROM reservation r JOIN reservation_item ri ON ri.reservation_id = r.id
WHERE r.confirmed_at >= '2026-06-01' AND r.confirmed_at < '2026-06-02';
SELECT 'RUN Q3 3' AS marker;
ANALYZE FORMAT=JSON SELECT SQL_NO_CACHE COUNT(DISTINCT r.id) AS reservations,
       SUM(ri.quantity * (ri.price_per_ticket + ri.service_fee_per_ticket)) AS ticket_gross
FROM reservation r JOIN reservation_item ri ON ri.reservation_id = r.id
WHERE r.confirmed_at >= '2026-06-01' AND r.confirmed_at < '2026-06-02';
SELECT 'RUN Q3 4' AS marker;
ANALYZE FORMAT=JSON SELECT SQL_NO_CACHE COUNT(DISTINCT r.id) AS reservations,
       SUM(ri.quantity * (ri.price_per_ticket + ri.service_fee_per_ticket)) AS ticket_gross
FROM reservation r JOIN reservation_item ri ON ri.reservation_id = r.id
WHERE r.confirmed_at >= '2026-06-01' AND r.confirmed_at < '2026-06-02';
SELECT 'RUN Q3 5' AS marker;
ANALYZE FORMAT=JSON SELECT SQL_NO_CACHE COUNT(DISTINCT r.id) AS reservations,
       SUM(ri.quantity * (ri.price_per_ticket + ri.service_fee_per_ticket)) AS ticket_gross
FROM reservation r JOIN reservation_item ri ON ri.reservation_id = r.id
WHERE r.confirmed_at >= '2026-06-01' AND r.confirmed_at < '2026-06-02';

-- Q4: Zadnjih 10 rezervacija jednog kupca. Jedno zagrijavanje (0) i pet mjerenja (1-5).
SELECT 'PLAN Q4' AS marker;
EXPLAIN SELECT SQL_NO_CACHE id, event_id, status, created_at
FROM reservation WHERE buyer_id = @buyer
ORDER BY created_at DESC, id DESC LIMIT 10;
SELECT 'RUN Q4 0' AS marker;
ANALYZE FORMAT=JSON SELECT SQL_NO_CACHE id, event_id, status, created_at
FROM reservation WHERE buyer_id = @buyer
ORDER BY created_at DESC, id DESC LIMIT 10;
SELECT 'RUN Q4 1' AS marker;
ANALYZE FORMAT=JSON SELECT SQL_NO_CACHE id, event_id, status, created_at
FROM reservation WHERE buyer_id = @buyer
ORDER BY created_at DESC, id DESC LIMIT 10;
SELECT 'RUN Q4 2' AS marker;
ANALYZE FORMAT=JSON SELECT SQL_NO_CACHE id, event_id, status, created_at
FROM reservation WHERE buyer_id = @buyer
ORDER BY created_at DESC, id DESC LIMIT 10;
SELECT 'RUN Q4 3' AS marker;
ANALYZE FORMAT=JSON SELECT SQL_NO_CACHE id, event_id, status, created_at
FROM reservation WHERE buyer_id = @buyer
ORDER BY created_at DESC, id DESC LIMIT 10;
SELECT 'RUN Q4 4' AS marker;
ANALYZE FORMAT=JSON SELECT SQL_NO_CACHE id, event_id, status, created_at
FROM reservation WHERE buyer_id = @buyer
ORDER BY created_at DESC, id DESC LIMIT 10;
SELECT 'RUN Q4 5' AS marker;
ANALYZE FORMAT=JSON SELECT SQL_NO_CACHE id, event_id, status, created_at
FROM reservation WHERE buyer_id = @buyer
ORDER BY created_at DESC, id DESC LIMIT 10;

-- Q5: Povrati u mjesecu. Jedno zagrijavanje (0) i pet mjerenja (1-5).
SELECT 'PLAN Q5' AS marker;
EXPLAIN SELECT SQL_NO_CACHE COUNT(*) AS refunded_tickets, SUM(refund_amount) AS refunds
FROM ticket WHERE cancelled_at >= '2026-06-01' AND cancelled_at < '2026-07-01';
SELECT 'RUN Q5 0' AS marker;
ANALYZE FORMAT=JSON SELECT SQL_NO_CACHE COUNT(*) AS refunded_tickets, SUM(refund_amount) AS refunds
FROM ticket WHERE cancelled_at >= '2026-06-01' AND cancelled_at < '2026-07-01';
SELECT 'RUN Q5 1' AS marker;
ANALYZE FORMAT=JSON SELECT SQL_NO_CACHE COUNT(*) AS refunded_tickets, SUM(refund_amount) AS refunds
FROM ticket WHERE cancelled_at >= '2026-06-01' AND cancelled_at < '2026-07-01';
SELECT 'RUN Q5 2' AS marker;
ANALYZE FORMAT=JSON SELECT SQL_NO_CACHE COUNT(*) AS refunded_tickets, SUM(refund_amount) AS refunds
FROM ticket WHERE cancelled_at >= '2026-06-01' AND cancelled_at < '2026-07-01';
SELECT 'RUN Q5 3' AS marker;
ANALYZE FORMAT=JSON SELECT SQL_NO_CACHE COUNT(*) AS refunded_tickets, SUM(refund_amount) AS refunds
FROM ticket WHERE cancelled_at >= '2026-06-01' AND cancelled_at < '2026-07-01';
SELECT 'RUN Q5 4' AS marker;
ANALYZE FORMAT=JSON SELECT SQL_NO_CACHE COUNT(*) AS refunded_tickets, SUM(refund_amount) AS refunds
FROM ticket WHERE cancelled_at >= '2026-06-01' AND cancelled_at < '2026-07-01';
SELECT 'RUN Q5 5' AS marker;
ANALYZE FORMAT=JSON SELECT SQL_NO_CACHE COUNT(*) AS refunded_tickets, SUM(refund_amount) AS refunds
FROM ticket WHERE cancelled_at >= '2026-06-01' AND cancelled_at < '2026-07-01';

-- Izolirani mikrobenchmark: isti podaci i indeksi kao reservation.
-- CREATE LIKE NE kopira triggere ni FK: mjerimo B-tree unos, ne cijeli poslovni tok.
-- Izvorne tablice i AUTO_INCREMENT ostaju netaknuti. UNIQUE indeksi se kopiraju.
DROP TEMPORARY TABLE IF EXISTS perf_write;
CREATE TEMPORARY TABLE perf_write LIKE reservation;
INSERT INTO perf_write SELECT * FROM reservation;
START TRANSACTION;
SET @write_start = SYSDATE(6);
INSERT INTO perf_write
(id, event_id, buyer_id, status, created_at, confirmed_at, cancelled_at,
 cancel_reason, expires_at, has_refund_protection, refund_protection_fee)
SELECT id + 1000000, event_id, buyer_id, status, created_at, confirmed_at,
       cancelled_at, cancel_reason, expires_at, has_refund_protection, refund_protection_fee
FROM reservation ORDER BY id LIMIT 10000;
SELECT 'WRITE' AS marker, 0 AS run, TIMESTAMPDIFF(MICROSECOND, @write_start, SYSDATE(6))/1000 AS ms;
ROLLBACK;
START TRANSACTION;
SET @write_start = SYSDATE(6);
INSERT INTO perf_write
(id, event_id, buyer_id, status, created_at, confirmed_at, cancelled_at,
 cancel_reason, expires_at, has_refund_protection, refund_protection_fee)
SELECT id + 1000000, event_id, buyer_id, status, created_at, confirmed_at,
       cancelled_at, cancel_reason, expires_at, has_refund_protection, refund_protection_fee
FROM reservation ORDER BY id LIMIT 10000;
SELECT 'WRITE' AS marker, 1 AS run, TIMESTAMPDIFF(MICROSECOND, @write_start, SYSDATE(6))/1000 AS ms;
ROLLBACK;
START TRANSACTION;
SET @write_start = SYSDATE(6);
INSERT INTO perf_write
(id, event_id, buyer_id, status, created_at, confirmed_at, cancelled_at,
 cancel_reason, expires_at, has_refund_protection, refund_protection_fee)
SELECT id + 1000000, event_id, buyer_id, status, created_at, confirmed_at,
       cancelled_at, cancel_reason, expires_at, has_refund_protection, refund_protection_fee
FROM reservation ORDER BY id LIMIT 10000;
SELECT 'WRITE' AS marker, 2 AS run, TIMESTAMPDIFF(MICROSECOND, @write_start, SYSDATE(6))/1000 AS ms;
ROLLBACK;
START TRANSACTION;
SET @write_start = SYSDATE(6);
INSERT INTO perf_write
(id, event_id, buyer_id, status, created_at, confirmed_at, cancelled_at,
 cancel_reason, expires_at, has_refund_protection, refund_protection_fee)
SELECT id + 1000000, event_id, buyer_id, status, created_at, confirmed_at,
       cancelled_at, cancel_reason, expires_at, has_refund_protection, refund_protection_fee
FROM reservation ORDER BY id LIMIT 10000;
SELECT 'WRITE' AS marker, 3 AS run, TIMESTAMPDIFF(MICROSECOND, @write_start, SYSDATE(6))/1000 AS ms;
ROLLBACK;
START TRANSACTION;
SET @write_start = SYSDATE(6);
INSERT INTO perf_write
(id, event_id, buyer_id, status, created_at, confirmed_at, cancelled_at,
 cancel_reason, expires_at, has_refund_protection, refund_protection_fee)
SELECT id + 1000000, event_id, buyer_id, status, created_at, confirmed_at,
       cancelled_at, cancel_reason, expires_at, has_refund_protection, refund_protection_fee
FROM reservation ORDER BY id LIMIT 10000;
SELECT 'WRITE' AS marker, 4 AS run, TIMESTAMPDIFF(MICROSECOND, @write_start, SYSDATE(6))/1000 AS ms;
ROLLBACK;
START TRANSACTION;
SET @write_start = SYSDATE(6);
INSERT INTO perf_write
(id, event_id, buyer_id, status, created_at, confirmed_at, cancelled_at,
 cancel_reason, expires_at, has_refund_protection, refund_protection_fee)
SELECT id + 1000000, event_id, buyer_id, status, created_at, confirmed_at,
       cancelled_at, cancel_reason, expires_at, has_refund_protection, refund_protection_fee
FROM reservation ORDER BY id LIMIT 10000;
SELECT 'WRITE' AS marker, 5 AS run, TIMESTAMPDIFF(MICROSECOND, @write_start, SYSDATE(6))/1000 AS ms;
ROLLBACK;
DROP TEMPORARY TABLE perf_write;
