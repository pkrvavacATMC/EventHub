-- =====================================================================
-- EventHub - 03: procedure i MariaDB event
--
-- Strategija konkurentnosti (task 6):
--  * Sve procedure koje mijenjaju stanje rade u READ COMMITTED: svako obicno
--    citanje vidi zadnje commitano stanje, pa provjera nakon cekanja na lock
--    ne gleda zastarjeli snapshot (kao sto bi se dogodilo u REPEATABLE READ).
--  * Pristup se serijalizira eksplicitnim FOR UPDATE na redu koji se provjerava;
--    provjera (npr. kapacitet) se radi nad vrijednostima procitanim u istom
--    zakljucavajucem upitu.
--  * Redoslijed zakljucavanja je isti svugdje (nema ciklusa -> nema deadlocka):
--        reservation -> ticket -> ticket_category (uzlazno po id) -> event
--  * Zadnja linija obrane su ogranicenja u bazi:
--        CHECK chk_category_reserved (reserved BETWEEN 0 AND capacity)
--        UNIQUE uq_active_seat       (jedno sjedalo = jedan aktivan hold)
--  * Procedure se pozivaju izvan otvorene transakcije (same rade START/COMMIT).
-- =====================================================================
USE eventhub;

DELIMITER //

-- ---------------------------------------------------------------------
-- generate_seats: redovi A, B, C... x p_per_row.
-- Kapacitet kategorije mora biti tocno p_rows * p_per_row (kapacitet = broj sjedala).
-- ---------------------------------------------------------------------
CREATE PROCEDURE generate_seats(IN p_category_id INT, IN p_rows INT, IN p_per_row INT)
BEGIN
  DECLARE v_type VARCHAR(10) DEFAULT NULL;
  DECLARE v_cap INT;
  DECLARE v_reserved INT;
  DECLARE v_existing INT;
  DECLARE r INT DEFAULT 1;
  DECLARE s INT;
  DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN ROLLBACK; RESIGNAL; END;

  IF p_rows IS NULL OR p_per_row IS NULL OR p_rows < 1 OR p_rows > 26 OR p_per_row < 1 THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Neispravan broj redova (1-26) ili sjedala po redu';
  END IF;

  SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
  START TRANSACTION;
  SELECT seating_type, capacity, reserved INTO v_type, v_cap, v_reserved
    FROM ticket_category WHERE id = p_category_id FOR UPDATE;
  IF v_type IS NULL THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Kategorija ne postoji';
  END IF;
  IF v_type <> 'seated' THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Sjedala se mogu generirati samo za sjedecu kategoriju';
  END IF;
  SELECT COUNT(*) INTO v_existing FROM seat WHERE category_id = p_category_id;
  IF v_existing > 0 OR v_reserved > 0 THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Kategorija vec ima sjedala ili rezervacije';
  END IF;
  IF p_rows * p_per_row <> v_cap THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Broj sjedala (redovi x sjedala) mora biti jednak kapacitetu kategorije';
  END IF;

  WHILE r <= p_rows DO
    SET s = 1;
    WHILE s <= p_per_row DO
      INSERT INTO seat (category_id, row_label, seat_number) VALUES (p_category_id, CHAR(64 + r), s);
      SET s = s + 1;
    END WHILE;
    SET r = r + 1;
  END WHILE;
  COMMIT;
END//

-- ---------------------------------------------------------------------
-- create_reservation
-- p_items: JSON niz stavki, npr.
--   '[{"category_id":1,"quantity":2},{"category_id":2,"seats":[5,6]}]'
-- Stajace kategorije: "quantity". Sjedece: "seats" (quantity = broj sjedala).
-- Cijena i naknada UVIJEK se uzimaju iz kategorije (kupac ih ne moze zadati).
-- ---------------------------------------------------------------------
CREATE PROCEDURE create_reservation(IN p_buyer_id INT, IN p_event_id INT, IN p_items LONGTEXT,
                                    IN p_refund_protection BOOLEAN, OUT p_reservation_id INT)
BEGIN
  DECLARE v_event_date DATETIME DEFAULT NULL;
  DECLARE v_n INT;
  DECLARE v_total INT;
  DECLARE v_seats INT;
  DECLARE v_distinct INT;
  DECLARE v_taken INT;
  DECLARE v_bad INT;
  DECLARE i INT DEFAULT 1;
  DECLARE v_last INT DEFAULT 0;
  DECLARE v_next INT;
  DECLARE v_cat_event INT;
  DECLARE v_type VARCHAR(10);
  DECLARE v_price DECIMAL(10,2);
  DECLARE v_fee DECIMAL(10,2);
  DECLARE v_cap INT;
  DECLARE v_reserved INT;
  DECLARE v_q INT;
  DECLARE v_seat_cnt INT;
  DECLARE v_protect BOOLEAN;
  DECLARE v_protect_fee DECIMAL(10,2) DEFAULT 0;
  DECLARE v_cat INT;
  DECLARE v_qty INT;
  DECLARE v_item INT;
  DECLARE v_errno INT;
  DECLARE v_msg VARCHAR(512);

  -- Svaka greska: ROLLBACK + ciscenje. Krsenja zadnje linije obrane (UNIQUE/CHECK)
  -- pretvaraju se u razumljive poruke.
  DECLARE EXIT HANDLER FOR SQLEXCEPTION
  BEGIN
    GET DIAGNOSTICS CONDITION 1 v_errno = MYSQL_ERRNO, v_msg = MESSAGE_TEXT;
    ROLLBACK;
    DROP TEMPORARY TABLE IF EXISTS tmp_items;
    DROP TEMPORARY TABLE IF EXISTS tmp_seats;
    SET p_reservation_id = NULL;
    IF v_errno = 1062 AND v_msg LIKE '%uq_active_seat%' THEN
      SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Neko od sjedala je vec zauzeto';
    ELSEIF v_errno = 4025 AND v_msg LIKE '%chk_category_reserved%' THEN
      SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Nema dovoljno slobodnih mjesta';
    ELSE
      RESIGNAL;
    END IF;
  END;

  SET p_reservation_id = NULL;
  SET v_protect = COALESCE(p_refund_protection, FALSE);

  -- ---------- 1. Ulaz (bez zakljucavanja, samo privremene tablice) ----------
  IF p_items IS NULL OR JSON_VALID(p_items) = 0 OR JSON_TYPE(p_items) <> 'ARRAY' THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Stavke moraju biti JSON niz';
  END IF;

  DROP TEMPORARY TABLE IF EXISTS tmp_items;
  DROP TEMPORARY TABLE IF EXISTS tmp_seats;
  CREATE TEMPORARY TABLE tmp_items (
    idx INT PRIMARY KEY, category_id INT, quantity INT,
    seating_type VARCHAR(10), price DECIMAL(10,2), fee DECIMAL(10,2)) ENGINE=MEMORY;
  CREATE TEMPORARY TABLE tmp_seats (idx INT, seat_id INT) ENGINE=MEMORY;

  INSERT INTO tmp_items (idx, category_id, quantity)
  SELECT jt.idx, jt.category_id, jt.quantity
    FROM JSON_TABLE(p_items, '$[*]' COLUMNS (
           idx FOR ORDINALITY,
           category_id INT PATH '$.category_id',
           quantity    INT PATH '$.quantity')) AS jt;

  INSERT INTO tmp_seats (idx, seat_id)
  SELECT jt.idx, jt.seat_id
    FROM JSON_TABLE(p_items, '$[*]' COLUMNS (
           idx FOR ORDINALITY,
           NESTED PATH '$.seats[*]' COLUMNS (seat_id INT PATH '$'))) AS jt
   WHERE jt.seat_id IS NOT NULL;

  SELECT COUNT(*) INTO v_n FROM tmp_items;
  IF v_n = 0 THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Rezervacija mora imati barem jednu stavku';
  END IF;
  SELECT COUNT(*) INTO v_bad FROM tmp_items WHERE category_id IS NULL;
  IF v_bad > 0 THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Svaka stavka mora imati category_id';
  END IF;

  -- Kolicine prije zakljucavanja: stavka sa sjedalima ima quantity = broj sjedala
  UPDATE tmp_items t
     SET t.quantity = (SELECT COUNT(*) FROM tmp_seats s WHERE s.idx = t.idx)
   WHERE t.idx IN (SELECT idx FROM tmp_seats);

  SELECT COUNT(*) INTO v_bad FROM tmp_items WHERE quantity IS NULL OR quantity < 1;
  IF v_bad > 0 THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Svaka stavka mora imati quantity >= 1 ili odabrana sjedala';
  END IF;
  SELECT SUM(quantity) INTO v_total FROM tmp_items;
  IF v_total < 1 OR v_total > 4 THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Rezervacija mora imati izmedu 1 i 4 karte';
  END IF;
  SELECT COUNT(*), COUNT(DISTINCT seat_id) INTO v_seats, v_distinct FROM tmp_seats;
  IF v_seats <> v_distinct THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Isto sjedalo je navedeno vise puta';
  END IF;

  -- ---------- 2. Transakcija ----------
  SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
  START TRANSACTION;

  -- 2a. Kategorije: zakljucaj uzlazno po id i provjeri kapacitet nad ZAKLJUCANIM redom
  lock_loop: LOOP
    SET v_next = NULL;
    SELECT MIN(category_id) INTO v_next FROM tmp_items WHERE category_id > v_last;
    IF v_next IS NULL THEN LEAVE lock_loop; END IF;

    SET v_cat_event = NULL;
    SELECT event_id, seating_type, price, service_fee, capacity, reserved
      INTO v_cat_event, v_type, v_price, v_fee, v_cap, v_reserved
      FROM ticket_category WHERE id = v_next FOR UPDATE;
    IF v_cat_event IS NULL OR v_cat_event <> p_event_id THEN
      SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Kategorija ne postoji ili ne pripada eventu';
    END IF;

    SELECT SUM(quantity) INTO v_q FROM tmp_items WHERE category_id = v_next;
    IF v_reserved + v_q > v_cap THEN
      SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Nema dovoljno slobodnih mjesta';
    END IF;

    IF v_type = 'seated' THEN
      SELECT COUNT(*) INTO v_seat_cnt FROM seat WHERE category_id = v_next;
      IF v_seat_cnt <> v_cap THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Sjedala za kategoriju nisu generirana';
      END IF;
    END IF;

    UPDATE tmp_items SET seating_type = v_type, price = v_price, fee = v_fee WHERE category_id = v_next;
    SET v_last = v_next;
  END LOOP;

  -- 2b. Event (zakljucava se NAKON kategorija - isti redoslijed kao admin triggeri)
  SELECT event_date INTO v_event_date FROM event WHERE id = p_event_id LOCK IN SHARE MODE;
  IF v_event_date IS NULL THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Event ne postoji';
  END IF;
  IF v_event_date <= NOW() THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Event je vec poceo ili prosao';
  END IF;

  -- 2c. Pravila sjedecih/stajacih stavki
  SELECT COUNT(*) INTO v_bad FROM tmp_items t
   WHERE t.seating_type = 'seated' AND t.idx NOT IN (SELECT idx FROM tmp_seats);
  IF v_bad > 0 THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Sjedeca stavka mora imati odabrana sjedala';
  END IF;
  SELECT COUNT(*) INTO v_bad FROM tmp_items t
   WHERE t.seating_type = 'standing' AND t.idx IN (SELECT idx FROM tmp_seats);
  IF v_bad > 0 THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Stajaca stavka ne smije imati sjedala';
  END IF;

  -- 2d. Sjedala postoje i pripadaju kategoriji stavke (sjedala su nepromjenjiva)
  SELECT COUNT(*) INTO v_bad
    FROM tmp_seats s
    JOIN tmp_items t ON t.idx = s.idx
    LEFT JOIN seat se ON se.id = s.seat_id AND se.category_id = t.category_id
   WHERE se.id IS NULL;
  IF v_bad > 0 THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Sjedalo ne postoji ili ne pripada kategoriji stavke';
  END IF;

  -- 2e. Sjedala slobodna. Kategorija je zakljucana (svi holdovi te kategorije
  --     nastaju i otpustaju se samo pod tim lockom), a READ COMMITTED vidi zadnje stanje.
  SELECT COUNT(*) INTO v_taken
    FROM tmp_seats s JOIN reservation_seat rs ON rs.active_seat_id = s.seat_id;
  IF v_taken > 0 THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Neko od sjedala je vec zauzeto';
  END IF;

  -- 2f. Zastita se racuna jednom, prije unosa (nakon toga je nepromjenjiva)
  IF v_protect THEN
    SELECT ROUND(0.10 * SUM(quantity * price), 2) INTO v_protect_fee FROM tmp_items;
  END IF;

  -- ---------- 3. Upis ----------
  INSERT INTO reservation (event_id, buyer_id, expires_at, has_refund_protection, refund_protection_fee)
  VALUES (p_event_id, p_buyer_id, NOW() + INTERVAL 15 MINUTE, v_protect, v_protect_fee);
  SET p_reservation_id = LAST_INSERT_ID();

  WHILE i <= v_n DO
    SELECT category_id, quantity, price, fee INTO v_cat, v_qty, v_price, v_fee
      FROM tmp_items WHERE idx = i;
    INSERT INTO reservation_item (reservation_id, event_id, category_id, quantity,
                                  price_per_ticket, service_fee_per_ticket)
    VALUES (p_reservation_id, p_event_id, v_cat, v_qty, v_price, v_fee);
    SET v_item = LAST_INSERT_ID();
    INSERT INTO reservation_seat (reservation_item_id, category_id, seat_id)
    SELECT v_item, v_cat, seat_id FROM tmp_seats WHERE idx = i;
    SET i = i + 1;
  END WHILE;

  UPDATE ticket_category c
    JOIN (SELECT category_id, SUM(quantity) AS q FROM tmp_items GROUP BY category_id) x
      ON x.category_id = c.id
     SET c.reserved = c.reserved + x.q;

  COMMIT;
  DROP TEMPORARY TABLE IF EXISTS tmp_items;
  DROP TEMPORARY TABLE IF EXISTS tmp_seats;
END//

-- ---------------------------------------------------------------------
-- confirm_reservation: provjera isteka, status, izdavanje karata
-- ---------------------------------------------------------------------
CREATE PROCEDURE confirm_reservation(IN p_reservation_id INT)
BEGIN
  DECLARE v_status VARCHAR(10) DEFAULT NULL;
  DECLARE v_expires DATETIME;
  DECLARE v_event INT;
  DECLARE v_event_date DATETIME;
  DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN ROLLBACK; RESIGNAL; END;

  SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
  START TRANSACTION;
  SELECT status, expires_at, event_id INTO v_status, v_expires, v_event
    FROM reservation WHERE id = p_reservation_id FOR UPDATE;
  IF v_status IS NULL THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Rezervacija ne postoji';
  END IF;
  IF v_status <> 'pending' THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Samo pending rezervacija se moze potvrditi';
  END IF;
  IF v_expires <= NOW() THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Rezervacija je istekla';
  END IF;
  SELECT event_date INTO v_event_date FROM event WHERE id = v_event;
  IF v_event_date <= NOW() THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Event je vec poceo ili prosao';
  END IF;

  UPDATE reservation SET status = 'confirmed', confirmed_at = NOW() WHERE id = p_reservation_id;

  -- Kod karte: 16 nasumicnih bajtova (128 bita) kao HEX - nepredvidljiv,
  -- za razliku od UUID() koji je u MariaDB-u vremenski (verzija 1).

  -- Stajace: quantity karata bez sjedala
  INSERT INTO ticket (reservation_item_id, reservation_seat_id, ticket_code)
  SELECT ri.id, NULL, HEX(RANDOM_BYTES(16))
    FROM reservation_item ri
    JOIN ticket_category c ON c.id = ri.category_id AND c.seating_type = 'standing'
    JOIN (SELECT 1 AS n UNION ALL SELECT 2 UNION ALL SELECT 3 UNION ALL SELECT 4) nums
      ON nums.n <= ri.quantity
   WHERE ri.reservation_id = p_reservation_id;

  -- Sjedece: jedna karta po aktivnom holdu
  INSERT INTO ticket (reservation_item_id, reservation_seat_id, ticket_code)
  SELECT rs.reservation_item_id, rs.id, HEX(RANDOM_BYTES(16))
    FROM reservation_seat rs
    JOIN reservation_item ri ON ri.id = rs.reservation_item_id
   WHERE ri.reservation_id = p_reservation_id AND rs.released_at IS NULL;

  COMMIT;
END//

-- ---------------------------------------------------------------------
-- release_reservation (INTERNA - aplikacija je ne smije pozivati):
-- otkazuje pending rezervaciju i oslobada mjesta, uz razlog otkazivanja.
--   'buyer'   - kupac je otkazao (poziva cancel_reservation)
--   'expired' - istekao rok placanja (poziva expire_reservations);
--               rok se ponovno provjerava pod lockom
-- ---------------------------------------------------------------------
CREATE PROCEDURE release_reservation(IN p_reservation_id INT, IN p_reason VARCHAR(10))
BEGIN
  DECLARE v_status VARCHAR(10) DEFAULT NULL;
  DECLARE v_expires DATETIME;
  DECLARE v_last INT DEFAULT 0;
  DECLARE v_next INT;
  DECLARE v_dummy INT;
  DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN ROLLBACK; RESIGNAL; END;

  IF p_reason IS NULL OR p_reason NOT IN ('buyer', 'expired') THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Razlog otkazivanja mora biti buyer ili expired';
  END IF;

  SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
  START TRANSACTION;
  SELECT status, expires_at INTO v_status, v_expires
    FROM reservation WHERE id = p_reservation_id FOR UPDATE;
  IF v_status IS NULL THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Rezervacija ne postoji';
  END IF;
  IF v_status <> 'pending' THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Cijela se moze otkazati samo pending rezervacija; potvrdene se otkazuju po karti';
  END IF;
  IF p_reason = 'expired' AND v_expires > NOW() THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Rezervacija jos nije istekla';
  END IF;

  -- kategorije uzlazno po id (isti redoslijed kao create_reservation)
  lock_loop: LOOP
    SET v_next = NULL;
    SELECT MIN(category_id) INTO v_next FROM reservation_item
     WHERE reservation_id = p_reservation_id AND category_id > v_last;
    IF v_next IS NULL THEN LEAVE lock_loop; END IF;
    SELECT id INTO v_dummy FROM ticket_category WHERE id = v_next FOR UPDATE;
    SET v_last = v_next;
  END LOOP;

  UPDATE ticket_category c
    JOIN (SELECT category_id, SUM(quantity) AS q FROM reservation_item
           WHERE reservation_id = p_reservation_id GROUP BY category_id) x
      ON x.category_id = c.id
     SET c.reserved = c.reserved - x.q;

  UPDATE reservation_seat rs
    JOIN reservation_item ri ON ri.id = rs.reservation_item_id
     SET rs.released_at = NOW()
   WHERE ri.reservation_id = p_reservation_id AND rs.released_at IS NULL;

  UPDATE reservation
     SET status = 'cancelled', cancelled_at = NOW(), cancel_reason = p_reason
   WHERE id = p_reservation_id;
  COMMIT;
END//

-- ---------------------------------------------------------------------
-- cancel_reservation: kupac otkazuje pending rezervaciju (cijelu)
-- ---------------------------------------------------------------------
CREATE PROCEDURE cancel_reservation(IN p_reservation_id INT)
BEGIN
  CALL release_reservation(p_reservation_id, 'buyer');
END//

-- ---------------------------------------------------------------------
-- cancel_ticket: otkazivanje jedne karte potvrdene rezervacije, uz povrat
-- ---------------------------------------------------------------------
CREATE PROCEDURE cancel_ticket(IN p_ticket_id INT, OUT p_refund_amount DECIMAL(10,2))
BEGIN
  DECLARE v_res INT DEFAULT NULL;
  DECLARE v_status VARCHAR(10);
  DECLARE v_protect BOOLEAN;
  DECLARE v_event INT;
  DECLARE v_event_date DATETIME;
  DECLARE v_cancelled DATETIME;
  DECLARE v_checked DATETIME;
  DECLARE v_rs INT;
  DECLARE v_price DECIMAL(10,2);
  DECLARE v_cat INT;
  DECLARE v_dummy INT;
  DECLARE v_hours INT;
  DECLARE v_active INT;
  DECLARE EXIT HANDLER FOR SQLEXCEPTION BEGIN ROLLBACK; RESIGNAL; END;

  SET p_refund_amount = NULL;
  -- karta -> rezervacija (veza je nepromjenjiva, pa ovo smije biti izvan transakcije)
  SELECT ri.reservation_id INTO v_res
    FROM ticket t JOIN reservation_item ri ON ri.id = t.reservation_item_id
   WHERE t.id = p_ticket_id;
  IF v_res IS NULL THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Karta ne postoji';
  END IF;

  SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
  START TRANSACTION;
  -- 1. rezervacija
  SELECT status, has_refund_protection, event_id INTO v_status, v_protect, v_event
    FROM reservation WHERE id = v_res FOR UPDATE;
  IF v_status <> 'confirmed' THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Karta ne pripada potvrdenoj rezervaciji';
  END IF;

  -- 2. karta
  SELECT t.cancelled_at, t.checked_in_at, t.reservation_seat_id, ri.price_per_ticket, ri.category_id
    INTO v_cancelled, v_checked, v_rs, v_price, v_cat
    FROM ticket t JOIN reservation_item ri ON ri.id = t.reservation_item_id
   WHERE t.id = p_ticket_id FOR UPDATE;
  IF v_cancelled IS NOT NULL THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Karta je vec otkazana';
  END IF;
  IF v_checked IS NOT NULL THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Iskoristena karta se ne moze otkazati';
  END IF;

  -- 3. kategorija
  SELECT id INTO v_dummy FROM ticket_category WHERE id = v_cat FOR UPDATE;

  -- 4. event (samo citanje datuma)
  SELECT event_date INTO v_event_date FROM event WHERE id = v_event;
  IF v_event_date <= NOW() THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Nema otkazivanja nakon pocetka eventa';
  END IF;

  SET v_hours = TIMESTAMPDIFF(HOUR, NOW(), v_event_date);
  IF v_protect THEN
    SET p_refund_amount = v_price;
  ELSE
    SET p_refund_amount = ROUND(v_price * refund_percent(v_hours) / 100, 2);
  END IF;

  UPDATE ticket SET cancelled_at = NOW(), refund_amount = p_refund_amount WHERE id = p_ticket_id;
  IF v_rs IS NOT NULL THEN
    UPDATE reservation_seat SET released_at = NOW() WHERE id = v_rs;
  END IF;
  UPDATE ticket_category SET reserved = reserved - 1 WHERE id = v_cat;

  -- Ako su otkazane sve karte, rezervacija postaje cancelled
  SELECT COUNT(*) INTO v_active
    FROM ticket t JOIN reservation_item ri ON ri.id = t.reservation_item_id
   WHERE ri.reservation_id = v_res AND t.cancelled_at IS NULL;
  IF v_active = 0 THEN
    UPDATE reservation SET status = 'cancelled', cancelled_at = NOW(), cancel_reason = 'buyer'
     WHERE id = v_res;
  END IF;

  COMMIT;
END//

-- ---------------------------------------------------------------------
-- check_in_ticket: skeniranje na ulazu odredenog eventa.
-- Karta mora pripadati tom eventu; od 24 h prije do 24 h nakon pocetka.
-- Sam check-in je jedan atomicni UPDATE.
-- ---------------------------------------------------------------------
CREATE PROCEDURE check_in_ticket(IN p_event_id INT, IN p_ticket_code CHAR(32))
BEGIN
  DECLARE v_event_id INT DEFAULT NULL;
  DECLARE v_event_date DATETIME DEFAULT NULL;
  SELECT e.id, e.event_date INTO v_event_id, v_event_date
    FROM ticket t
    JOIN reservation_item ri ON ri.id = t.reservation_item_id
    JOIN event e             ON e.id  = ri.event_id
   WHERE t.ticket_code = p_ticket_code;
  IF v_event_id IS NULL THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Karta ne postoji';
  END IF;
  IF p_event_id IS NULL OR v_event_id <> p_event_id THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Karta nije za ovaj event';
  END IF;
  IF NOW() < v_event_date - INTERVAL 24 HOUR OR NOW() > v_event_date + INTERVAL 24 HOUR THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Check-in nije moguc u ovom terminu';
  END IF;
  UPDATE ticket SET checked_in_at = NOW()
   WHERE ticket_code = p_ticket_code AND checked_in_at IS NULL AND cancelled_at IS NULL;
  IF ROW_COUNT() = 0 THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Karta je otkazana ili vec iskoristena';
  END IF;
END//

-- ---------------------------------------------------------------------
-- expire_reservations: otkazuje istekle pending rezervacije (razlog 'expired').
-- Greska na jednoj ne zaustavlja ostale, ali se zapisuje u job_error_log.
-- ---------------------------------------------------------------------
CREATE PROCEDURE expire_reservations()
BEGIN
  DECLARE done INT DEFAULT 0;
  DECLARE v_id INT DEFAULT NULL;
  DECLARE v_errno INT;
  DECLARE v_msg VARCHAR(512);
  DECLARE cur CURSOR FOR
    SELECT id FROM reservation WHERE status = 'pending' AND expires_at <= NOW();
  DECLARE CONTINUE HANDLER FOR NOT FOUND SET done = 1;
  DECLARE CONTINUE HANDLER FOR SQLEXCEPTION
  BEGIN
    GET DIAGNOSTICS CONDITION 1 v_errno = MYSQL_ERRNO, v_msg = MESSAGE_TEXT;
    INSERT INTO job_error_log (job_name, reservation_id, error_code, message)
    VALUES ('expire_reservations', v_id, v_errno, v_msg);
  END;

  OPEN cur;
  read_loop: LOOP
    FETCH cur INTO v_id;
    IF done = 1 THEN LEAVE read_loop; END IF;
    CALL release_reservation(v_id, 'expired');
    SET done = 0;   -- upozorenje iz pozvane procedure ne smije prekinuti petlju
  END LOOP;
  CLOSE cur;
END//

DELIMITER ;

-- Scheduler mora biti ukljucen (--event-scheduler=ON, vidi docker-compose.yml)
CREATE EVENT ev_expire_reservations
  ON SCHEDULE EVERY 1 MINUTE
  DO CALL expire_reservations();
