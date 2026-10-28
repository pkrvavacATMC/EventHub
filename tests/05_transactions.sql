-- =====================================================================
-- tests/05_transactions.sql - JEDAN samostalni test transakcija (EventHub)
--
-- Pokretanje (kao root, jer eventhub_app ne smije pisati u tablice):
--   mariadb -uroot -p<lozinka> -h127.0.0.1 -P<port> -t eventhub < tests/05_transactions.sql
--
-- Svaki test upisuje PASS/FAIL, a na kraju se ispisuje sazetak.
-- Svako pokretanje stvara novi demo event (brisanje je u bazi zabranjeno),
-- pa se test moze pokretati vise puta. Ne treba --force.
-- =====================================================================

-- ---------- SETUP ----------
INSERT IGNORE INTO city (name) VALUES ('Demo grad');
SET @city = (SELECT id FROM city WHERE name = 'Demo grad');
INSERT IGNORE INTO organizer (name, email) VALUES ('Demo organizator', 'demo-org@eventhub.test');
SET @org = (SELECT id FROM organizer WHERE email = 'demo-org@eventhub.test');
INSERT IGNORE INTO buyer (name, surname, email, city_id)
VALUES ('Demo', 'Kupac', 'demo-buyer@eventhub.test', @city);
SET @buyer = (SELECT id FROM buyer WHERE email = 'demo-buyer@eventhub.test');
SET @loc = (SELECT MIN(id) FROM location WHERE name = 'Demo dvorana');
INSERT INTO location (name, city_id, capacity)
SELECT 'Demo dvorana', @city, 100 FROM DUAL WHERE @loc IS NULL;
SET @loc = (SELECT MIN(id) FROM location WHERE name = 'Demo dvorana');
INSERT INTO event (name, event_date, capacity, location_id, organizer_id)
VALUES (CONCAT('TX test ', DATE_FORMAT(NOW(6), '%Y-%m-%d %H:%i:%s.%f')),
        NOW() + INTERVAL 30 DAY, 10, @loc, @org);
SET @event = LAST_INSERT_ID();
INSERT INTO ticket_category (event_id, name, price, service_fee, capacity, seating_type)
VALUES (@event, 'Parter', 20.00, 2.00, 10, 'standing');
SET @cat = LAST_INSERT_ID();

CREATE OR REPLACE TEMPORARY TABLE test_result (
  n INT AUTO_INCREMENT PRIMARY KEY, test VARCHAR(80), ocekivano VARCHAR(80),
  dobiveno VARCHAR(80), rezultat VARCHAR(4));

DELIMITER //

-- pomocne: stanje demo kategorije
CREATE OR REPLACE FUNCTION t_reserved(p_cat INT) RETURNS INT
  READS SQL DATA RETURN (SELECT reserved FROM ticket_category WHERE id = p_cat)//
CREATE OR REPLACE FUNCTION t_tickets(p_event INT) RETURNS INT
  READS SQL DATA RETURN (SELECT COUNT(*) FROM ticket t JOIN reservation_item ri ON ri.id = t.reservation_item_id
                          WHERE ri.event_id = p_event AND t.cancelled_at IS NULL)//
CREATE OR REPLACE FUNCTION t_reservations(p_event INT) RETURNS INT
  READS SQL DATA RETURN (SELECT COUNT(*) FROM reservation WHERE event_id = p_event)//
CREATE OR REPLACE FUNCTION t_consistent(p_cat INT) RETURNS VARCHAR(20)
  READS SQL DATA RETURN IF(EXISTS (SELECT 1 FROM v_reserved_check WHERE category_id = p_cat),
                           'NEKONZISTENTNO', 'OK')//

-- kupnja 3 karte "rucno" (zaobilazi procedure); p_pay_ok = ishod placanja
CREATE OR REPLACE PROCEDURE t_manual_purchase(p_event INT, p_cat INT, p_buyer INT, p_pay_ok BOOLEAN)
BEGIN
  DECLARE v_res INT;
  DECLARE v_item INT;
  UPDATE ticket_category SET reserved = reserved + 3 WHERE id = p_cat;
  INSERT INTO reservation (event_id, buyer_id, expires_at)
  VALUES (p_event, p_buyer, NOW() + INTERVAL 15 MINUTE);
  SET v_res = LAST_INSERT_ID();
  INSERT INTO reservation_item (reservation_id, event_id, category_id, quantity,
                                price_per_ticket, service_fee_per_ticket)
  SELECT v_res, p_event, id, 3, price, service_fee FROM ticket_category WHERE id = p_cat;
  SET v_item = LAST_INSERT_ID();
  UPDATE reservation SET status = 'confirmed', confirmed_at = NOW() WHERE id = v_res;
  IF NOT p_pay_ok THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Placanje odbijeno (simulacija)';
  END IF;
  INSERT INTO ticket (reservation_item_id, ticket_code)
  SELECT v_item, HEX(RANDOM_BYTES(16)) FROM seq_1_to_3;
END//

-- stvarni tok aplikacije: procedure + placanje + kompenzacija
CREATE OR REPLACE PROCEDURE t_app_purchase(p_buyer INT, p_event INT, p_items LONGTEXT,
                                           p_pay_ok BOOLEAN, OUT p_res INT, OUT p_result VARCHAR(200))
BEGIN
  DECLARE v_msg VARCHAR(512);
  DECLARE EXIT HANDLER FOR SQLEXCEPTION
  BEGIN
    GET DIAGNOSTICS CONDITION 1 v_msg = MESSAGE_TEXT;
    IF p_res IS NOT NULL THEN CALL cancel_reservation(p_res); END IF;
    SET p_result = CONCAT('NEUSPJEH: ', v_msg);
  END;
  SET p_res = NULL;
  CALL create_reservation(p_buyer, p_event, p_items, FALSE, p_res);
  IF NOT p_pay_ok THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Placanje odbijeno (simulacija)';
  END IF;
  CALL confirm_reservation(p_res);
  SET p_result = 'USPJEH';
END//

-- ---------- TEST 1: bez transakcije -> nekonzistentno stanje ----------
BEGIN NOT ATOMIC
  DECLARE CONTINUE HANDLER FOR SQLEXCEPTION BEGIN END;
  SET autocommit = 1;
  CALL t_manual_purchase(@event, @cat, @buyer, FALSE);
END//
INSERT INTO test_result (test, ocekivano, dobiveno, rezultat)
SELECT '1 bez transakcije, placanje palo', 'reserved=3, karte=0, NEKONZISTENTNO',
       CONCAT('reserved=', t_reserved(@cat), ', karte=', t_tickets(@event), ', ', t_consistent(@cat)),
       IF(t_reserved(@cat) = 3 AND t_tickets(@event) = 0 AND t_consistent(@cat) = 'NEKONZISTENTNO', 'PASS', 'FAIL')//

-- rucni popravak stete iz testa 1 (u transakciji)
BEGIN NOT ATOMIC
  DECLARE v_bad INT;
  START TRANSACTION;
  SELECT id INTO v_bad FROM reservation WHERE event_id = @event AND status = 'confirmed' LIMIT 1;
  UPDATE ticket_category SET reserved = reserved - 3 WHERE id = @cat;
  UPDATE reservation SET status = 'cancelled', cancelled_at = NOW(), cancel_reason = 'buyer' WHERE id = v_bad;
  COMMIT;
END//
INSERT INTO test_result (test, ocekivano, dobiveno, rezultat)
SELECT '1b rucni popravak', 'reserved=0, OK',
       CONCAT('reserved=', t_reserved(@cat), ', ', t_consistent(@cat)),
       IF(t_reserved(@cat) = 0 AND t_consistent(@cat) = 'OK', 'PASS', 'FAIL')//

-- ---------- TEST 2: transakcija, placanje palo -> ROLLBACK ----------
SET @r0 = t_reserved(@cat), @n0 = t_reservations(@event), @k0 = t_tickets(@event)//
BEGIN NOT ATOMIC
  DECLARE EXIT HANDLER FOR SQLEXCEPTION ROLLBACK;
  START TRANSACTION;
  CALL t_manual_purchase(@event, @cat, @buyer, FALSE);
  COMMIT;
END//
INSERT INTO test_result (test, ocekivano, dobiveno, rezultat)
SELECT '2 transakcija, placanje palo -> ROLLBACK',
       CONCAT('reserved=', @r0, ', rezervacija=', @n0, ', karte=', @k0),
       CONCAT('reserved=', t_reserved(@cat), ', rezervacija=', t_reservations(@event), ', karte=', t_tickets(@event)),
       IF(t_reserved(@cat) = @r0 AND t_reservations(@event) = @n0 AND t_tickets(@event) = @k0
          AND t_consistent(@cat) = 'OK', 'PASS', 'FAIL')//

-- ---------- TEST 3: transakcija, placanje uspjelo -> COMMIT ----------
SET @r0 = t_reserved(@cat), @k0 = t_tickets(@event)//
BEGIN NOT ATOMIC
  DECLARE EXIT HANDLER FOR SQLEXCEPTION ROLLBACK;
  START TRANSACTION;
  CALL t_manual_purchase(@event, @cat, @buyer, TRUE);
  COMMIT;
END//
INSERT INTO test_result (test, ocekivano, dobiveno, rezultat)
SELECT '3 transakcija, placanje uspjelo -> COMMIT',
       CONCAT('reserved=', @r0 + 3, ', karte=', @k0 + 3),
       CONCAT('reserved=', t_reserved(@cat), ', karte=', t_tickets(@event)),
       IF(t_reserved(@cat) = @r0 + 3 AND t_tickets(@event) = @k0 + 3
          AND t_consistent(@cat) = 'OK', 'PASS', 'FAIL')//

-- ---------- TEST 4: procedure, placanje palo -> kompenzacija ----------
SET @r0 = t_reserved(@cat), @k0 = t_tickets(@event)//
CALL t_app_purchase(@buyer, @event, CONCAT('[{"category_id":', @cat, ',"quantity":3}]'), FALSE, @res4, @out4)//
INSERT INTO test_result (test, ocekivano, dobiveno, rezultat)
SELECT '4 procedure, placanje palo',
       CONCAT('reserved=', @r0, ', karte=', @k0, ', cancelled'),
       CONCAT('reserved=', t_reserved(@cat), ', karte=', t_tickets(@event), ', ',
              (SELECT CONCAT(status, '/', cancel_reason) FROM reservation WHERE id = @res4)),
       IF(t_reserved(@cat) = @r0 AND t_tickets(@event) = @k0 AND t_consistent(@cat) = 'OK'
          AND (SELECT status FROM reservation WHERE id = @res4) = 'cancelled', 'PASS', 'FAIL')//

-- ---------- TEST 5: procedure, placanje uspjelo ----------
SET @r0 = t_reserved(@cat), @k0 = t_tickets(@event)//
CALL t_app_purchase(@buyer, @event, CONCAT('[{"category_id":', @cat, ',"quantity":3}]'), TRUE, @res5, @out5)//
INSERT INTO test_result (test, ocekivano, dobiveno, rezultat)
SELECT '5 procedure, placanje uspjelo',
       CONCAT('reserved=', @r0 + 3, ', karte=', @k0 + 3, ', confirmed'),
       CONCAT('reserved=', t_reserved(@cat), ', karte=', t_tickets(@event), ', ',
              (SELECT status FROM reservation WHERE id = @res5)),
       IF(t_reserved(@cat) = @r0 + 3 AND t_tickets(@event) = @k0 + 3 AND t_consistent(@cat) = 'OK'
          AND (SELECT status FROM reservation WHERE id = @res5) = 'confirmed', 'PASS', 'FAIL')//

-- ---------- TEST 6: procedura odbije neispravan unos (5 karata) ----------
SET @r0 = t_reserved(@cat), @n0 = t_reservations(@event)//
CALL t_app_purchase(@buyer, @event, CONCAT('[{"category_id":', @cat, ',"quantity":5}]'), TRUE, @res6, @out6)//
INSERT INTO test_result (test, ocekivano, dobiveno, rezultat)
SELECT '6 procedure, 5 karata -> nista upisano',
       CONCAT('reserved=', @r0, ', rezervacija=', @n0),
       CONCAT('reserved=', t_reserved(@cat), ', rezervacija=', t_reservations(@event)),
       IF(t_reserved(@cat) = @r0 AND t_reservations(@event) = @n0 AND @res6 IS NULL, 'PASS', 'FAIL')//

DELIMITER ;

-- ---------- REZULTATI ----------
SELECT n, test, ocekivano, dobiveno, rezultat FROM test_result ORDER BY n;

SELECT CONCAT(SUM(rezultat = 'PASS'), '/', COUNT(*), ' PASS') AS sazetak,
       IF(SUM(rezultat = 'FAIL') = 0, 'SVI TESTOVI PROSLI', 'IMA PALIH TESTOVA') AS status
  FROM test_result;

-- kako je zabiljezena odbijena kupnja (test 4)
SELECT id AS rezervacija, status, cancel_reason, created_at, cancelled_at
  FROM reservation WHERE id = @res4;

-- pomocni objekti nisu dio sheme
DROP FUNCTION t_reserved; DROP FUNCTION t_tickets; DROP FUNCTION t_reservations;
DROP FUNCTION t_consistent; DROP PROCEDURE t_manual_purchase; DROP PROCEDURE t_app_purchase;
