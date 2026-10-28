-- Pokrenuti nakon init + seed, iskljucivo nad eventhub (ne eventhub_perf).
USE eventhub;

-- Privremene tablice su rezultati istih osam upita iz 01_reports.sql.
-- Nema izmjena trajnih podataka; sve provjere koriste isti snapshot.
START TRANSACTION WITH CONSISTENT SNAPSHOT;
DROP TEMPORARY TABLE IF EXISTS report_q1;
CREATE TEMPORARY TABLE report_q1 AS
SELECT event_id, event_name, confirmed_tickets
FROM v_ticket_stats
ORDER BY confirmed_tickets DESC, event_id;
DROP TEMPORARY TABLE IF EXISTS report_q2;
CREATE TEMPORARY TABLE report_q2 AS
SELECT b.id AS buyer_id, b.name, b.surname, COUNT(r.id) AS reservations
FROM buyer b LEFT JOIN reservation r ON r.buyer_id = b.id
GROUP BY b.id, b.name, b.surname
ORDER BY reservations DESC, buyer_id;
DROP TEMPORARY TABLE IF EXISTS report_q3;
CREATE TEMPORARY TABLE report_q3 AS
SELECT event_id, event_name, sellable_capacity, reserved, remaining, remaining_pct
FROM v_event_capacity
WHERE sellable_capacity > 0 AND remaining * 100 < sellable_capacity * 10
ORDER BY remaining_pct, event_id;
DROP TEMPORARY TABLE IF EXISTS report_q4;
CREATE TEMPORARY TABLE report_q4 AS
SELECT e.id AS event_id, e.name AS event_name,
       COALESCE(SUM(m.net_revenue), 0) AS net_revenue
FROM event e LEFT JOIN v_revenue_monthly m ON m.event_id = e.id
GROUP BY e.id, e.name
ORDER BY net_revenue DESC, event_id;
DROP TEMPORARY TABLE IF EXISTS report_q5;
CREATE TEMPORARY TABLE report_q5 AS
SELECT event_id, event_name, total_reservations
FROM v_reservations_by_event
WHERE total_reservations = 0
ORDER BY event_id;
DROP TEMPORARY TABLE IF EXISTS report_q6;
CREATE TEMPORARY TABLE report_q6 AS
SELECT event_id, event_name, tickets_reserved_ever, cancelled_tickets,
       expired_tickets, cancellation_rate_pct
FROM v_ticket_stats
ORDER BY cancellation_rate_pct DESC, event_id;
DROP TEMPORARY TABLE IF EXISTS report_q7;
CREATE TEMPORARY TABLE report_q7 AS
SELECT o.id AS organizer_id, o.name AS organizer_name,
       COALESCE(SUM(m.net_revenue), 0) AS net_revenue
FROM organizer o LEFT JOIN v_revenue_monthly m ON m.organizer_id = o.id
GROUP BY o.id, o.name
ORDER BY net_revenue DESC, organizer_id;
DROP TEMPORARY TABLE IF EXISTS report_q8;
CREATE TEMPORARY TABLE report_q8 AS
SELECT month, SUM(ticket_gross) AS ticket_gross,
       SUM(protection_fees) AS protection_fees, SUM(refunds) AS refunds,
       SUM(net_revenue) AS net_revenue
FROM v_revenue_monthly
GROUP BY month
ORDER BY month;

-- Neovisni izracun prihoda iz osnovnih tablica, bez viewova.
SET @base_revenue =
 (SELECT COALESCE(SUM(ri.quantity * (ri.price_per_ticket + ri.service_fee_per_ticket)),0)
  FROM reservation r JOIN reservation_item ri ON ri.reservation_id=r.id WHERE r.confirmed_at IS NOT NULL)
 + (SELECT COALESCE(SUM(refund_protection_fee),0) FROM reservation WHERE confirmed_at IS NOT NULL)
 - (SELECT COALESCE(SUM(refund_amount),0) FROM ticket WHERE cancelled_at IS NOT NULL);
DROP TEMPORARY TABLE IF EXISTS report_checks;
CREATE TEMPORARY TABLE report_checks (opis VARCHAR(180), rezultat VARCHAR(4));
INSERT INTO report_checks VALUES
 ('Seed: 8 evenata, 40 kupaca, 175 rezervacija, 290 karata',
 IF((SELECT COUNT(*) FROM event)=8 AND (SELECT COUNT(*) FROM buyer)=40
 AND (SELECT COUNT(*) FROM reservation)=175 AND (SELECT COUNT(*) FROM ticket)=290,'PASS','FAIL')),
 ('Q1: potvrdene karte = 267 i neovisni broj vazecih karata',
 IF((SELECT SUM(confirmed_tickets) FROM report_q1)=267 AND
 (SELECT SUM(confirmed_tickets) FROM report_q1)=(SELECT COUNT(*) FROM ticket t
 JOIN reservation_item ri ON ri.id=t.reservation_item_id JOIN reservation r ON r.id=ri.reservation_id
 WHERE r.status='confirmed' AND t.cancelled_at IS NULL),'PASS','FAIL')),
 ('Q1/Q4/Q6: svi eventi su ukljuceni',
 IF((SELECT COUNT(*) FROM report_q1)=(SELECT COUNT(*) FROM event) AND
 (SELECT COUNT(*) FROM report_q4)=(SELECT COUNT(*) FROM event) AND
 (SELECT COUNT(*) FROM report_q6)=(SELECT COUNT(*) FROM event),'PASS','FAIL')),
 ('Q2: svi kupci, ukupno 175 rezervacija',
 IF((SELECT COUNT(*) FROM report_q2)=40 AND (SELECT SUM(reservations) FROM report_q2)=175,'PASS','FAIL')),
 ('Q3: samo Jesenski indie koncert, 19/20 prodano, 5 % slobodno',
 IF((SELECT COUNT(*) FROM report_q3)=1 AND (SELECT COUNT(*) FROM report_q3
 WHERE event_name='Jesenski indie koncert' AND reserved=19 AND sellable_capacity=20 AND remaining_pct=5)=1,'PASS','FAIL')),
 ('Q5: samo Kazalisna premijera bez rezervacija',
 IF((SELECT COUNT(*) FROM report_q5)=1 AND (SELECT COUNT(*) FROM report_q5 WHERE event_name='Kazalisna premijera')=1,'PASS','FAIL')),
 ('Q4: Kazalisna premijera postoji i prihod je 0',
 IF((SELECT COUNT(*) FROM report_q4 WHERE event_name='Kazalisna premijera' AND net_revenue=0)=1,'PASS','FAIL')),
 ('Q4/Q7/Q8: prihod jednak neovisnom izracunu iz tablica',
 IF((SELECT SUM(net_revenue) FROM report_q4)=@base_revenue AND
 (SELECT SUM(net_revenue) FROM report_q7)=@base_revenue AND
 (SELECT SUM(net_revenue) FROM report_q8)=@base_revenue,'PASS','FAIL')),
 ('Q7: svaki organizator ukljucen, cak i bez prihoda',
 IF((SELECT COUNT(*) FROM report_q7)=(SELECT COUNT(*) FROM organizer),'PASS','FAIL')),
 ('Q6: Kazalisna premijera ima NULL stopu (nema rezerviranih karata)',
 IF((SELECT COUNT(*) FROM report_q6 WHERE event_name='Kazalisna premijera' AND cancellation_rate_pct IS NULL)=1,'PASS','FAIL'));

-- Neovisno brojanje otkazivanja i nazivnika za svaki event iz osnovnih tablica.
INSERT INTO report_checks
SELECT 'Q6: stopa svakog eventa odgovara neovisnom izracunu',
 IF(COUNT(*)=0,'PASS','FAIL')
FROM report_q6 q
WHERE NOT (q.cancellation_rate_pct <=> ROUND(100 * (
 (SELECT COUNT(*) FROM ticket t JOIN reservation_item ri ON ri.id=t.reservation_item_id
 WHERE ri.event_id=q.event_id AND t.cancelled_at IS NOT NULL)
 + (SELECT COALESCE(SUM(ri.quantity),0) FROM reservation_item ri JOIN reservation r ON r.id=ri.reservation_id
 WHERE r.event_id=q.event_id AND r.cancel_reason='buyer' AND r.confirmed_at IS NULL))
 / NULLIF((SELECT COALESCE(SUM(ri.quantity),0) FROM reservation_item ri JOIN reservation r ON r.id=ri.reservation_id
 WHERE r.event_id=q.event_id AND (r.cancel_reason IS NULL OR r.cancel_reason<>'expired')),0),1));
-- Poznate vrijednosti sprecavaju da jednako pogresni ukupni zbrojevi prodju.
INSERT INTO report_checks VALUES
 ('Q2: kupac 35 (Ema Radic) ima najvise rezervacija: 10',
 IF((SELECT COUNT(*) FROM report_q2 WHERE buyer_id=35 AND reservations=10)=1
 AND (SELECT MAX(reservations) FROM report_q2)=10,'PASS','FAIL')),
 ('Q4/Q7/Q8: poznati ukupni neto prihod 14436.60 EUR',
 IF(@base_revenue=14436.60,'PASS','FAIL')),
 ('Q7: Adria Live ima 11120.00 EUR i najveci prihod',
 IF((SELECT COUNT(*) FROM report_q7 WHERE organizer_name='Adria Live d.o.o.' AND net_revenue=11120.00)=1
 AND (SELECT MAX(net_revenue) FROM report_q7)=11120.00,'PASS','FAIL')),
 ('Q8: sijecanj 2026: 567 + 14 - 25 = 556 EUR',
 IF((SELECT COUNT(*) FROM report_q8 WHERE month='2026-01' AND ticket_gross=567
 AND protection_fees=14 AND refunds=25 AND net_revenue=556)=1,'PASS','FAIL')),
 ('Q6: Zimska jazz vecer: 15 / (50 - 7) = 34.9 %',
 IF((SELECT COUNT(*) FROM report_q6 WHERE event_name='Zimska jazz vecer'
 AND tickets_reserved_ever=50 AND cancelled_tickets=15 AND expired_tickets=7
 AND cancellation_rate_pct=ROUND(100*15/43,1))=1,'PASS','FAIL'));
-- Regresija: direktno otkazivanje mora biti odbijeno; SAVEPOINT stiti podatke
-- i ako bi trigger nedostajao. Test ne poziva procedure koje rade COMMIT.
SET @regression_res = (SELECT MIN(r.id) FROM reservation r
 JOIN reservation_item ri ON ri.reservation_id=r.id JOIN ticket t ON t.reservation_item_id=ri.id
 WHERE r.status='confirmed' AND t.cancelled_at IS NULL);
SAVEPOINT cancellation_regression;
SET @regression_errno=0;
SET @regression_message='';
DELIMITER //
BEGIN NOT ATOMIC
 DECLARE CONTINUE HANDLER FOR SQLEXCEPTION
  GET DIAGNOSTICS CONDITION 1 @regression_errno=MYSQL_ERRNO, @regression_message=MESSAGE_TEXT;
 UPDATE reservation SET status='cancelled', cancelled_at=NOW(), cancel_reason='buyer'
 WHERE id=@regression_res;
END//
DELIMITER ;
ROLLBACK TO SAVEPOINT cancellation_regression;
RELEASE SAVEPOINT cancellation_regression;
INSERT INTO report_checks VALUES
 ('Regresija Q1: direktno otkazivanje s vazecim kartama je odbijeno',
 IF(@regression_res IS NOT NULL AND @regression_errno=1644
 AND @regression_message LIKE '%Rezervacija ima vazece karte%','PASS','FAIL'));
INSERT INTO report_checks
SELECT 'Q1: svaki event odgovara kartama confirmed rezervacija',
 IF(COUNT(*)=0,'PASS','FAIL') FROM report_q1 q
 WHERE q.confirmed_tickets<>(SELECT COUNT(*) FROM ticket t
 JOIN reservation_item ri ON ri.id=t.reservation_item_id JOIN reservation r ON r.id=ri.reservation_id
 WHERE r.event_id=q.event_id AND r.status='confirmed' AND t.cancelled_at IS NULL);
SELECT * FROM report_checks;
SELECT SUM(rezultat='PASS') AS pass, SUM(rezultat='FAIL') AS fail FROM report_checks;
COMMIT;
DROP TEMPORARY TABLE report_q1;
DROP TEMPORARY TABLE report_q2;
DROP TEMPORARY TABLE report_q3;
DROP TEMPORARY TABLE report_q4;
DROP TEMPORARY TABLE report_q5;
DROP TEMPORARY TABLE report_q6;
DROP TEMPORARY TABLE report_q7;
DROP TEMPORARY TABLE report_q8;
DROP TEMPORARY TABLE report_checks;
