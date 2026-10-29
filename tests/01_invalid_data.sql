-- =====================================================================
-- EventHub - tests/01_invalid_data.sql : testovi neispravnih podataka (task 3)
--
-- Pokretanje (nakon Liquibase migracija i seeda):
--   docker exec -i eventhub-db sh -c 'mariadb -uroot -p"$MARIADB_ROOT_PASSWORD" eventhub' < tests/01_invalid_data.sql
--
-- Negativni testovi provjeravaju odbijanje, a pozitivni testovi prihvacanje.
-- Svaki negativni test provjerava da je baza odbila operaciju
-- s ocekivanom greskom (kod + dio poruke). Rezultat: PASS / FAIL.
--
-- Testovi NE mijenjaju podatke:
--  * direktni INSERT/UPDATE/DELETE izvrsavaju se u transakciji koja se uvijek
--    ponisti (ROLLBACK), cak i kad bi operacija neocekivano prosla;
--  * pozivi procedura (CALL) moraju pasti; ako neki prode, test je FAIL.
--
-- Kodovi gresaka:
--   1048  NOT NULL               1062  UNIQUE (duplikat)
--   1451  FK - brisanje roditelja koji ima djecu (ON DELETE RESTRICT)
--   1452  FK - nepostojeci roditelj
--   4025  CHECK ogranicenje      1644  poslovno pravilo (SIGNAL u triggeru/proceduri)
-- =====================================================================
USE eventhub;

-- Fiksno vrijeme vrijedi samo u ovoj sesiji: testovi ne ovise o datumu pokretanja.
SET @test_previous_time_zone = @@session.time_zone;
SET time_zone = '+01:00';
SET timestamp = UNIX_TIMESTAMP('2026-10-28 12:00:00');

-- ---------------------------------------------------------------------
-- Pomocni alat za testiranje
-- ---------------------------------------------------------------------
DROP TEMPORARY TABLE IF EXISTS test_result;
CREATE TEMPORARY TABLE test_result (
  id         INT AUTO_INCREMENT PRIMARY KEY,
  kategorija VARCHAR(30),
  opis       VARCHAR(120),
  ocekivano  VARCHAR(160),
  dobiveno   VARCHAR(400),
  rezultat   CHAR(4)
);

DROP PROCEDURE IF EXISTS t_expect;
DELIMITER //
-- p_setup: opcionalna priprema u ISTOJ transakciji (npr. pending rezervacija).
--          Koristi se samo uz direktne izmjene - CALL se ne moze izvrsiti unutar
--          transakcije (procedure same upravljaju transakcijom).
CREATE PROCEDURE t_expect(IN p_kat VARCHAR(30), IN p_opis VARCHAR(120),
                          IN p_setup TEXT, IN p_sql TEXT,
                          IN p_errno INT, IN p_text VARCHAR(160))
BEGIN
  DECLARE v_errno INT DEFAULT 0;
  DECLARE v_msg VARCHAR(400) DEFAULT 'Operacija je prosla';
  DECLARE v_tx BOOLEAN DEFAULT (p_sql NOT LIKE 'CALL%');

  IF v_tx THEN START TRANSACTION; END IF;
  BEGIN
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
      GET DIAGNOSTICS CONDITION 1 v_errno = MYSQL_ERRNO, v_msg = MESSAGE_TEXT;
    IF p_setup IS NOT NULL THEN
      SET @t_sql = p_setup; PREPARE st FROM @t_sql; EXECUTE st; DEALLOCATE PREPARE st;
    END IF;
    SET @t_sql = p_sql; PREPARE st FROM @t_sql; EXECUTE st; DEALLOCATE PREPARE st;
  END;
  IF v_tx THEN ROLLBACK; END IF;

  INSERT INTO test_result (kategorija, opis, ocekivano, dobiveno, rezultat)
  VALUES (p_kat, p_opis, CONCAT(p_errno, ': ', p_text), CONCAT(v_errno, ': ', v_msg),
          IF(v_errno = p_errno AND v_msg LIKE CONCAT('%', p_text, '%'), 'PASS', 'FAIL'));
END//
DELIMITER ;

-- ---------------------------------------------------------------------
-- Testni podaci iz seeda (po nazivu, ne po ID-ju)
-- ---------------------------------------------------------------------
SET @buyer         = (SELECT MIN(id) FROM buyer);
SET @ev_future     = (SELECT id FROM event WHERE name = 'Novogodisnji koncert');
SET @cat_parter_ny = (SELECT id FROM ticket_category WHERE event_id = @ev_future AND name = 'Parter');
SET @cat_vip_ny    = (SELECT id FROM ticket_category WHERE event_id = @ev_future AND name = 'VIP');
SET @ev_other      = (SELECT id FROM event WHERE name = 'Ljetni festival Split');
SET @cat_split     = (SELECT id FROM ticket_category WHERE event_id = @ev_other AND name = 'Dnevna ulaznica');
SET @ev_past       = (SELECT id FROM event WHERE name = 'Proljetni rock festival');
SET @cat_past      = (SELECT id FROM ticket_category WHERE event_id = @ev_past AND name = 'Parter');
SET @ev_soon       = (SELECT id FROM event WHERE name = 'Jesenski indie koncert');
SET @cat_indie     = (SELECT id FROM ticket_category WHERE event_id = @ev_soon);
SET @cat_kaz       = (SELECT c.id FROM ticket_category c JOIN event e ON e.id = c.event_id
                       WHERE e.name = 'Kazalisna premijera');
-- potvrdena rezervacija buduceg eventa i njena vazeca karta
SET @confirmed_res = (SELECT MIN(r.id) FROM reservation r JOIN reservation_item ri ON ri.reservation_id = r.id
                        JOIN ticket t ON t.reservation_item_id = ri.id
                       WHERE r.event_id = @ev_future AND r.status = 'confirmed' AND t.cancelled_at IS NULL);
SET @valid_ticket  = (SELECT MIN(t.id) FROM ticket t JOIN reservation_item ri ON ri.id = t.reservation_item_id
                       WHERE ri.reservation_id = @confirmed_res AND t.cancelled_at IS NULL);
SET @valid_code    = (SELECT ticket_code FROM ticket WHERE id = @valid_ticket);
SET @cancelled_res = (SELECT MIN(id) FROM reservation WHERE status = 'cancelled');
-- vracena karta cija je rezervacija i dalje potvrdena
SET @cancelled_ticket = (SELECT MIN(t.id) FROM ticket t JOIN reservation_item ri ON ri.id = t.reservation_item_id
                           JOIN reservation r ON r.id = ri.reservation_id
                          WHERE t.cancelled_at IS NOT NULL AND r.status = 'confirmed');
-- vazeca, neiskoristena karta proslog eventa
SET @past_ticket   = (SELECT MIN(t.id) FROM ticket t JOIN reservation_item ri ON ri.id = t.reservation_item_id
                        JOIN reservation r ON r.id = ri.reservation_id JOIN event e ON e.id = r.event_id
                       WHERE e.event_date < NOW() AND r.status = 'confirmed'
                         AND t.cancelled_at IS NULL AND t.checked_in_at IS NULL);
-- zauzeto i slobodno sjedalo u VIP-u novogodisnjeg koncerta
SET @sold_seat     = (SELECT MIN(active_seat_id) FROM reservation_seat WHERE category_id = @cat_vip_ny);
SET @free_seat     = (SELECT MIN(s.id) FROM seat s WHERE s.category_id = @cat_vip_ny
                         AND s.id NOT IN (SELECT active_seat_id FROM reservation_seat WHERE active_seat_id IS NOT NULL));
-- priprema: nova pending rezervacija (samo unutar transakcije testa)
SET @setup_pending = 'INSERT INTO reservation (event_id, buyer_id, expires_at) VALUES (@ev_future, @buyer, NOW() + INTERVAL 15 MINUTE)';

SELECT @buyer, @ev_future, @cat_parter_ny, @cat_vip_ny, @cat_split, @ev_past, @cat_indie, @cat_kaz,
       @confirmed_res, @valid_ticket, @cancelled_res, @cancelled_ticket, @past_ticket, @sold_seat, @free_seat;

-- =====================================================================
-- 1. CHECK ogranicenja (neispravne vrijednosti)
-- =====================================================================
CALL t_expect('CHECK', 'Lokacija s kapacitetom 0', NULL,
  'INSERT INTO location (name, city_id, capacity) VALUES (''Test'', 1, 0)', 4025, 'chk_location_capacity');
CALL t_expect('CHECK', 'Grad s praznim nazivom', NULL,
  'INSERT INTO city (name) VALUES (''   '')', 4025, 'chk_city_name');
CALL t_expect('CHECK', 'Kupac s neispravnim emailom', NULL,
  'INSERT INTO buyer (name, surname, email, city_id) VALUES (''Test'', ''Test'', ''nije-email'', 1)', 4025, 'chk_buyer_email');
CALL t_expect('CHECK', 'Email s razmakom', NULL,
  'INSERT INTO buyer (name, surname, email, city_id) VALUES (''Test'', ''Test'', ''test @example.com'', 1)', 4025, 'chk_buyer_email');
CALL t_expect('CHECK', 'Kupac s praznim prezimenom', NULL,
  'INSERT INTO buyer (name, surname, email, city_id) VALUES (''Test'', '''', ''prazno@example.com'', 1)', 4025, 'chk_buyer_name');
CALL t_expect('CHECK', 'Organizator s emailom bez domene', NULL,
  'INSERT INTO organizer (name, email) VALUES (''Test'', ''org@'')', 4025, 'chk_organizer_email');
CALL t_expect('CHECK', 'Negativna cijena kategorije', NULL,
  'INSERT INTO ticket_category (event_id, name, price, service_fee, capacity, seating_type) VALUES (@ev_future, ''Test'', -10, 0, 1, ''standing'')',
  4025, 'chk_category_price');
CALL t_expect('CHECK', 'Negativna naknada kategorije', NULL,
  'INSERT INTO ticket_category (event_id, name, price, service_fee, capacity, seating_type) VALUES (@ev_future, ''Test'', 10, -1, 1, ''standing'')',
  4025, 'chk_category_fee');
CALL t_expect('CHECK', 'Kategorija s kapacitetom 0', NULL,
  'INSERT INTO ticket_category (event_id, name, price, service_fee, capacity, seating_type) VALUES (@ev_future, ''Test'', 10, 0, 0, ''standing'')',
  4025, 'chk_category_capacity');
CALL t_expect('CHECK', 'Zauzece vece od kapaciteta', NULL,
  'UPDATE ticket_category SET reserved = capacity + 1 WHERE id = @cat_parter_ny', 4025, 'chk_category_reserved');
CALL t_expect('CHECK', 'Negativno zauzece', NULL,
  'UPDATE ticket_category SET reserved = -1 WHERE id = @cat_parter_ny', 4025, 'chk_category_reserved');
CALL t_expect('CHECK', 'Stavka s kolicinom 0', @setup_pending,
  'INSERT INTO reservation_item (reservation_id, event_id, category_id, quantity, price_per_ticket, service_fee_per_ticket) VALUES (LAST_INSERT_ID(), @ev_future, @cat_parter_ny, 0, 50, 4)',
  4025, 'chk_item_quantity');
CALL t_expect('CHECK', 'Stavka s negativnom kolicinom', @setup_pending,
  'INSERT INTO reservation_item (reservation_id, event_id, category_id, quantity, price_per_ticket, service_fee_per_ticket) VALUES (LAST_INSERT_ID(), @ev_future, @cat_parter_ny, -2, 50, 4)',
  4025, 'chk_item_quantity');
CALL t_expect('CHECK', 'Stavka s negativnom cijenom', @setup_pending,
  'INSERT INTO reservation_item (reservation_id, event_id, category_id, quantity, price_per_ticket, service_fee_per_ticket) VALUES (LAST_INSERT_ID(), @ev_future, @cat_parter_ny, 1, -5, 4)',
  4025, 'chk_item_price');
CALL t_expect('CHECK', 'Potvrdena rezervacija bez datuma potvrde', @setup_pending,
  'UPDATE reservation SET status = ''confirmed'' WHERE id = LAST_INSERT_ID()', 4025, 'chk_res_status_dates');
CALL t_expect('CHECK', 'Otkazana rezervacija bez razloga', @setup_pending,
  'UPDATE reservation SET status = ''cancelled'', cancelled_at = NOW() WHERE id = LAST_INSERT_ID()', 4025, 'chk_res_cancel_reason');
CALL t_expect('CHECK', 'Potvrdena rezervacija ne moze "isteci"', NULL,
  'UPDATE reservation SET status = ''cancelled'', cancelled_at = NOW(), cancel_reason = ''expired'' WHERE id = @confirmed_res',
  1644, 'Rezervacija ima vazece karte');
CALL t_expect('CHECK', 'Rok rezervacije prije kreiranja', NULL,
  'INSERT INTO reservation (event_id, buyer_id, created_at, expires_at) VALUES (@ev_future, @buyer, NOW(), NOW() - INTERVAL 1 MINUTE)',
  4025, 'chk_res_expires');
CALL t_expect('CHECK', 'Povrat bez otkazivanja karte', NULL,
  'UPDATE ticket SET refund_amount = 1 WHERE id = @valid_ticket', 4025, 'chk_ticket_refund_pair');
CALL t_expect('CHECK', 'Karta iskoristena i otkazana', NULL,
  'UPDATE ticket SET checked_in_at = NOW(), cancelled_at = NOW(), refund_amount = 0 WHERE id = @valid_ticket',
  4025, 'chk_ticket_used_cancel');

-- =====================================================================
-- 2. NOT NULL (obavezni podaci)
-- =====================================================================
CALL t_expect('NOT NULL', 'Event bez naziva', NULL,
  'INSERT INTO event (name, event_date, capacity, location_id, organizer_id, event_type_id) VALUES (NULL, NOW() + INTERVAL 30 DAY, 10, 1, 1, (SELECT id FROM event_type WHERE code = ''other''))',
  1048, 'name');
CALL t_expect('NOT NULL', 'Kupac bez emaila', NULL,
  'INSERT INTO buyer (name, surname, email, city_id) VALUES (''Test'', ''Test'', NULL, 1)', 1048, 'email');

-- =====================================================================
-- 3. UNIQUE (duplikati)
-- =====================================================================
CALL t_expect('UNIQUE', 'Dupli grad', NULL,
  'INSERT INTO city (name) VALUES (''Zagreb'')', 1062, 'uq_city_name');
CALL t_expect('UNIQUE', 'Dupli email kupca', NULL,
  'INSERT INTO buyer (name, surname, email, city_id) SELECT ''Test'', ''Test'', email, 1 FROM buyer WHERE id = @buyer',
  1062, 'uq_buyer_email');
CALL t_expect('UNIQUE', 'Dupli email organizatora', NULL,
  'INSERT INTO organizer (name, email) SELECT ''Test'', email FROM organizer ORDER BY id LIMIT 1', 1062, 'uq_organizer_email');
CALL t_expect('UNIQUE', 'Dva puta ista kategorija u eventu', NULL,
  'INSERT INTO ticket_category (event_id, name, price, service_fee, capacity, seating_type) VALUES (@ev_future, ''VIP'', 10, 0, 1, ''standing'')',
  1062, 'uq_category_event_name');

-- =====================================================================
-- 4. Strani kljucevi (nepostojece i nekonzistentne reference)
-- =====================================================================
CALL t_expect('FK', 'Kupac iz nepostojeceg grada', NULL,
  'INSERT INTO buyer (name, surname, email, city_id) VALUES (''Test'', ''Test'', ''fk@example.com'', 999999)', 1452, 'fk_buyer_city');
CALL t_expect('FK', 'Event nepostojeceg organizatora', NULL,
  'INSERT INTO event (name, event_date, capacity, location_id, organizer_id, event_type_id) VALUES (''Test'', NOW() + INTERVAL 30 DAY, 10, 1, 999999, (SELECT id FROM event_type WHERE code = ''other''))',
  1452, 'fk_event_organizer');
CALL t_expect('FK', 'Stavka s kategorijom drugog eventa', @setup_pending,
  'INSERT INTO reservation_item (reservation_id, event_id, category_id, quantity, price_per_ticket, service_fee_per_ticket) VALUES (LAST_INSERT_ID(), @ev_future, @cat_split, 1, 35, 3)',
  1452, 'fk_item_category');
CALL t_expect('FK', 'Stavka ne odgovara eventu rezervacije', @setup_pending,
  'INSERT INTO reservation_item (reservation_id, event_id, category_id, quantity, price_per_ticket, service_fee_per_ticket) VALUES (LAST_INSERT_ID(), @ev_other, @cat_split, 1, 35, 3)',
  1452, 'fk_item_reservation');
CALL t_expect('FK', 'Brisanje organizatora koji ima evente', NULL,
  'DELETE FROM organizer WHERE id = (SELECT organizer_id FROM event WHERE id = @ev_future)', 1451, 'fk_event_organizer');
CALL t_expect('FK', 'Brisanje grada koji ima kupce', NULL,
  'DELETE FROM city WHERE id = (SELECT city_id FROM buyer WHERE id = @buyer)', 1451, 'fk_');
CALL t_expect('FK', 'Rezervacija za nepostojeceg kupca',  NULL,
  'CALL create_reservation(999999, @ev_future, CONCAT(''[{"category_id":'', @cat_parter_ny, '',"quantity":1}]''), 0, @x)',
  1452, 'fk_res_buyer');

-- =====================================================================
-- 5. Poslovna pravila u triggerima (direktne izmjene)
-- =====================================================================
CALL t_expect('PRAVILO', 'Event veci od lokacije', NULL,
  'INSERT INTO event (name, event_date, capacity, location_id, organizer_id, event_type_id) VALUES (''Test'', NOW() + INTERVAL 30 DAY, 9999999, 1, 1, (SELECT id FROM event_type WHERE code = ''other''))',
  1644, 'Kapacitet eventa prelazi kapacitet lokacije');
CALL t_expect('PRAVILO', 'Novi event u proslosti', NULL,
  'INSERT INTO event (name, event_date, capacity, location_id, organizer_id, event_type_id) VALUES (''Test'', NOW() - INTERVAL 1 DAY, 10, 1, 1, (SELECT id FROM event_type WHERE code = ''other''))',
  1644, 'Event mora biti u buducnosti');
CALL t_expect('PRAVILO', 'Pomicanje eventa u proslost', NULL,
  'UPDATE event SET event_date = NOW() - INTERVAL 1 DAY WHERE id = @ev_future', 1644, 'Novi datum eventa mora biti u buducnosti');
CALL t_expect('PRAVILO', 'Promjena datuma odrzanog eventa', NULL,
  'UPDATE event SET event_date = NOW() + INTERVAL 30 DAY WHERE id = @ev_past', 1644, 'Datum eventa koji je poceo ili prosao');
CALL t_expect('PRAVILO', 'Smanjenje eventa ispod zbroja kategorija', NULL,
  'UPDATE event SET capacity = 1 WHERE id = @ev_future', 1644, 'manji od zbroja kapaciteta kategorija');
CALL t_expect('PRAVILO', 'Kategorije preko kapaciteta eventa', NULL,
  'INSERT INTO ticket_category (event_id, name, price, service_fee, capacity, seating_type) VALUES (@ev_soon, ''Test'', 10, 0, 40, ''standing'')',
  1644, 'Zbroj kapaciteta kategorija prelazi kapacitet eventa');
CALL t_expect('PRAVILO', 'Sjedalo preko kapaciteta kategorije', NULL,
  'INSERT INTO seat (category_id, row_label, seat_number) VALUES (@cat_kaz, ''Z'', 1)', 1644, 'Broj sjedala prelazi kapacitet kategorije');
CALL t_expect('PRAVILO', 'Kapacitet sjedece kategorije razlicit od broja sjedala', NULL,
  'UPDATE ticket_category SET capacity = capacity + 1 WHERE id = @cat_kaz', 1644, 'mora biti jednak broju sjedala');
CALL t_expect('PRAVILO', 'Nova rezervacija vec potvrdena', NULL,
  'INSERT INTO reservation (event_id, buyer_id, status, confirmed_at, expires_at) VALUES (@ev_future, @buyer, ''confirmed'', NOW(), NOW() + INTERVAL 15 MINUTE)',
  1644, 'Nova rezervacija mora biti pending');
CALL t_expect('PRAVILO', 'Potvrdena natrag u pending', NULL,
  'UPDATE reservation SET status = ''pending'', confirmed_at = NULL WHERE id = @confirmed_res', 1644, 'confirmed -> pending');
CALL t_expect('PRAVILO', 'Izmjena otkazane rezervacije', NULL,
  'UPDATE reservation SET status = ''confirmed'', confirmed_at = NOW(), cancelled_at = NULL, cancel_reason = NULL WHERE id = @cancelled_res',
  1644, 'Otkazana rezervacija je konacna');
CALL t_expect('PRAVILO', 'Naknadna promjena zastite od povrata', NULL,
  'UPDATE reservation SET has_refund_protection = 1 - has_refund_protection WHERE id = @confirmed_res', 1644, 'Refund protection je nepromjenjiv');
CALL t_expect('PRAVILO', 'Izmjena stavke rezervacije', NULL,
  'UPDATE reservation_item SET quantity = 1 WHERE reservation_id = @confirmed_res', 1644, 'Stavke rezervacije su nepromjenjive');
CALL t_expect('PRAVILO', 'Stavka na potvrdenoj rezervaciji', NULL,
  'INSERT INTO reservation_item (reservation_id, event_id, category_id, quantity, price_per_ticket, service_fee_per_ticket) VALUES (@confirmed_res, @ev_future, @cat_parter_ny, 1, 50, 4)',
  1644, 'samo pending rezervaciji');
CALL t_expect('PRAVILO', 'Povrat veci od cijene karte', NULL,
  'UPDATE ticket SET cancelled_at = NOW(), refund_amount = 999999 WHERE id = @valid_ticket', 1644, 'Povrat ne smije biti veci od cijene');
CALL t_expect('PRAVILO', 'Brisanje rezervacije', NULL,
  'DELETE FROM reservation WHERE id = @confirmed_res', 1644, 'Brisanje rezervacija nije dozvoljeno');
CALL t_expect('PRAVILO', 'Brisanje karte', NULL,
  'DELETE FROM ticket WHERE id = @valid_ticket', 1644, 'Brisanje karata nije dozvoljeno');

-- =====================================================================
-- 6. Poslovna pravila u procedurama (ono sto aplikacija stvarno poziva)
-- =====================================================================
CALL t_expect('PROCEDURA', 'Rezervacija s 5 karata', NULL,
  'CALL create_reservation(@buyer, @ev_future, CONCAT(''[{"category_id":'', @cat_parter_ny, '',"quantity":5}]''), 0, @x)',
  1644, 'izmedu 1 i 4 karte');
CALL t_expect('PROCEDURA', 'Negativna kolicina karata', NULL,
  'CALL create_reservation(@buyer, @ev_future, CONCAT(''[{"category_id":'', @cat_parter_ny, '',"quantity":-2}]''), 0, @x)',
  1644, 'quantity >= 1');
CALL t_expect('PROCEDURA', 'Prazna rezervacija', NULL,
  'CALL create_reservation(@buyer, @ev_future, ''[]'', 0, @x)', 1644, 'barem jednu stavku');
CALL t_expect('PROCEDURA', 'Neispravan JSON', NULL,
  'CALL create_reservation(@buyer, @ev_future, ''nije json'', 0, @x)', 1644, 'Stavke moraju biti JSON niz');
CALL t_expect('PROCEDURA', 'Kategorija drugog eventa', NULL,
  'CALL create_reservation(@buyer, @ev_future, CONCAT(''[{"category_id":'', @cat_split, '',"quantity":1}]''), 0, @x)',
  1644, 'ne pripada eventu');
CALL t_expect('PROCEDURA', 'Vise karata nego slobodnih mjesta', NULL,
  'CALL create_reservation(@buyer, @ev_soon, CONCAT(''[{"category_id":'', @cat_indie, '',"quantity":2}]''), 0, @x)',
  1644, 'Nema dovoljno slobodnih mjesta');
CALL t_expect('PROCEDURA', 'Vec zauzeto sjedalo', NULL,
  'CALL create_reservation(@buyer, @ev_future, CONCAT(''[{"category_id":'', @cat_vip_ny, '',"seats":['', @sold_seat, '']}]''), 0, @x)',
  1644, 'vec zauzeto');
CALL t_expect('PROCEDURA', 'Isto sjedalo dvaput', NULL,
  'CALL create_reservation(@buyer, @ev_future, CONCAT(''[{"category_id":'', @cat_vip_ny, '',"seats":['', @free_seat, '','', @free_seat, '']}]''), 0, @x)',
  1644, 'navedeno vise puta');
CALL t_expect('PROCEDURA', 'Sjedalo iz druge kategorije', NULL,
  'CALL create_reservation(@buyer, @ev_future, CONCAT(''[{"category_id":'', @cat_vip_ny, '',"seats":['', (SELECT MIN(id) FROM seat WHERE category_id = @cat_kaz), '']}]''), 0, @x)',
  1644, 'ne pripada kategoriji stavke');
CALL t_expect('PROCEDURA', 'Sjedeca kategorija bez odabranih sjedala', NULL,
  'CALL create_reservation(@buyer, @ev_future, CONCAT(''[{"category_id":'', @cat_vip_ny, '',"quantity":1}]''), 0, @x)',
  1644, 'mora imati odabrana sjedala');
CALL t_expect('PROCEDURA', 'Rezervacija za odrzani event', NULL,
  'CALL create_reservation(@buyer, @ev_past, CONCAT(''[{"category_id":'', @cat_past, '',"quantity":1}]''), 0, @x)',
  1644, 'Event je vec poceo ili prosao');
CALL t_expect('PROCEDURA', 'Potvrda vec potvrdene rezervacije', NULL,
  'CALL confirm_reservation(@confirmed_res)', 1644, 'Samo pending rezervacija se moze potvrditi');
CALL t_expect('PROCEDURA', 'Potvrda nepostojece rezervacije', NULL,
  'CALL confirm_reservation(999999)', 1644, 'Rezervacija ne postoji');
CALL t_expect('PROCEDURA', 'Otkazivanje cijele potvrdene rezervacije', NULL,
  'CALL cancel_reservation(@confirmed_res)', 1644, 'samo pending rezervacija');
CALL t_expect('PROCEDURA', 'Ponovno otkazivanje vracene karte', NULL,
  'CALL cancel_ticket(@cancelled_ticket, @x)', 1644, 'Karta je vec otkazana');
CALL t_expect('PROCEDURA', 'Otkazivanje karte nakon eventa', NULL,
  'CALL cancel_ticket(@past_ticket, @x)', 1644, 'Nema otkazivanja nakon pocetka eventa');
CALL t_expect('PROCEDURA', 'Check-in na ulazu drugog eventa', NULL,
  'CALL check_in_ticket(@ev_other, @valid_code)', 1644, 'Karta nije za ovaj event');
CALL t_expect('PROCEDURA', 'Check-in izvan termina', NULL,
  'CALL check_in_ticket(@ev_future, @valid_code)', 1644, 'Check-in nije moguc u ovom terminu');
CALL t_expect('PROCEDURA', 'Check-in nepostojece karte', NULL,
  'CALL check_in_ticket(@ev_future, REPEAT(''F'', 32))', 1644, 'Karta ne postoji');
CALL t_expect('PROCEDURA', 'Sjedala u stajacoj kategoriji', NULL,
  'CALL generate_seats(@cat_parter_ny, 1, 1)', 1644, 'samo za sjedecu kategoriju');
CALL t_expect('PROCEDURA', 'Ponovno generiranje sjedala', NULL,
  'CALL generate_seats(@cat_kaz, 4, 10)', 1644, 'vec ima sjedala ili rezervacije');
CALL t_expect('PROCEDURA', 'Istek potvrdene rezervacije', NULL,
  'CALL release_reservation(@confirmed_res, ''expired'')', 1644, 'samo pending rezervacija');
CALL t_expect('PROCEDURA', 'Nepoznat razlog otkazivanja', NULL,
  'CALL release_reservation(@confirmed_res, ''nesto'')', 1644, 'Razlog otkazivanja mora biti');

-- =====================================================================
-- 7. Vremenske granice: proslost, sadasnjost i buducnost
-- Uspjesni INSERT/UPDATE takoder se ponistavaju pomocu t_expect.
-- =====================================================================
CALL t_expect('VRIJEME', 'Novi event sekundu u proslosti', NULL,
  'INSERT INTO event (name, event_date, capacity, location_id, organizer_id, event_type_id) VALUES (''Test vrijeme'', NOW() - INTERVAL 1 SECOND, 10, 1, 1, (SELECT id FROM event_type WHERE code = ''other''))',
  1644, 'Event mora biti u buducnosti');
CALL t_expect('VRIJEME', 'Novi event tocno sada', NULL,
  'INSERT INTO event (name, event_date, capacity, location_id, organizer_id, event_type_id) VALUES (''Test vrijeme'', NOW(), 10, 1, 1, (SELECT id FROM event_type WHERE code = ''other''))',
  1644, 'Event mora biti u buducnosti');
CALL t_expect('VRIJEME', 'Novi event sekundu u buducnosti', NULL,
  'INSERT INTO event (name, event_date, capacity, location_id, organizer_id, event_type_id) VALUES (''Test vrijeme'', NOW() + INTERVAL 1 SECOND, 10, 1, 1, (SELECT id FROM event_type WHERE code = ''other''))',
  0, '');
CALL t_expect('VRIJEME', 'Pomicanje eventa tocno na sada', NULL,
  'UPDATE event SET event_date = NOW() WHERE id = @ev_future',
  1644, 'Novi datum eventa mora biti u buducnosti');
CALL t_expect('VRIJEME', 'Pomicanje eventa u buducnost', NULL,
  'UPDATE event SET event_date = NOW() + INTERVAL 1 DAY WHERE id = @ev_future',
  0, '');

-- Postojeci test 61 odbija rezervaciju u proslosti; ovdje testiramo sam pocetak.
SET timestamp = (SELECT UNIX_TIMESTAMP(event_date) FROM event WHERE id = @ev_future);
CALL t_expect('VRIJEME', 'Rezervacija tocno na pocetku eventa', NULL,
  'CALL create_reservation(@buyer, @ev_future, CONCAT(''[{"category_id":'', @cat_parter_ny, '',"quantity":1}]''), 0, @x)',
  1644, 'Event je vec poceo ili prosao');
SET timestamp = UNIX_TIMESTAMP('2026-10-28 12:00:00');

-- Direktni UPDATE ne smije zaobici redoslijed poslovnih procedura.
CALL t_expect('PRAVILO', 'Direktno otkazivanje potvrdene rezervacije s vazecim kartama', NULL,
  'UPDATE reservation SET status = ''cancelled'', cancelled_at = NOW(), cancel_reason = ''buyer'' WHERE id = @confirmed_res',
  1644, 'Rezervacija ima vazece karte');

-- Fixture u transakciji t_expect; nema COMMIT-a i sve se ponistava.
DELIMITER //
CREATE PROCEDURE t_setup_pending_hold()
BEGIN
  INSERT INTO reservation(event_id, buyer_id, expires_at)
  VALUES (@ev_future, @buyer, NOW() + INTERVAL 15 MINUTE);
  SET @pending_hold_res = LAST_INSERT_ID();
  INSERT INTO reservation_item(reservation_id, event_id, category_id, quantity, price_per_ticket, service_fee_per_ticket)
  SELECT @pending_hold_res, @ev_future, id, 1, price, service_fee FROM ticket_category WHERE id=@cat_vip_ny;
  SET @pending_hold_item = LAST_INSERT_ID();
  INSERT INTO reservation_seat(reservation_item_id, category_id, seat_id)
  VALUES (@pending_hold_item, @cat_vip_ny, @free_seat);
END//
DELIMITER ;
CALL t_expect('PRAVILO', 'Direktno otkazivanje pending rezervacije s aktivnim holdom',
  'CALL t_setup_pending_hold()',
  'UPDATE reservation SET status = ''cancelled'', cancelled_at = NOW(), cancel_reason = ''buyer'' WHERE id = @pending_hold_res',
  1644, 'Rezervacija ima aktivne holdove sjedala');
DROP PROCEDURE t_setup_pending_hold;

-- Keycloak poveznica: sve izmjene ponistava t_expect.
CALL t_expect('KEYCLOAK', 'Duplikat external_id',
  'UPDATE buyer SET external_id = ''01234567-89ab-cdef-0123-456789abcdef'' WHERE id = 1',
  'UPDATE buyer SET external_id = ''01234567-89ab-cdef-0123-456789abcdef'' WHERE id = 2',
  1062, 'uq_buyer_external_id');
CALL t_expect('KEYCLOAK', 'Neispravan UUID', NULL,
  'UPDATE buyer SET external_id = ''nije-uuid'' WHERE id = 1',
  4025, 'chk_buyer_external_id');
CALL t_expect('KEYCLOAK', 'UUID s velikim slovima', NULL,
  'UPDATE buyer SET external_id = ''01234567-89AB-cdef-0123-456789abcdef'' WHERE id = 1',
  4025, 'chk_buyer_external_id');
CALL t_expect('KEYCLOAK', 'UUID bez crtica', NULL,
  'UPDATE buyer SET external_id = ''0123456789abcdef0123456789abcdef'' WHERE id = 1',
  4025, 'chk_buyer_external_id');
CALL t_expect('KEYCLOAK', 'UUID s pogresnim znakom', NULL,
  'UPDATE buyer SET external_id = ''g1234567-89ab-cdef-0123-456789abcdef'' WHERE id = 1',
  4025, 'chk_buyer_external_id');
CALL t_expect('KEYCLOAK', 'Dva kupca s NULL external_id', NULL,
  'INSERT INTO buyer (name, surname, email, city_id, external_id) VALUES (''Keycloak'', ''Null jedan'', ''keycloak-null-1@example.test'', 1, NULL), (''Keycloak'', ''Null dva'', ''keycloak-null-2@example.test'', 1, NULL)',
  0, '');
CALL t_expect('KEYCLOAK', 'Valjan UUID malim slovima', NULL,
  'UPDATE buyer SET external_id = ''01234567-89ab-cdef-0123-456789abcdef'' WHERE id = 1',
  0, '');

-- ---------------------------------------------------------------------
-- Rezultati
-- ---------------------------------------------------------------------
SELECT id, kategorija, opis, ocekivano, dobiveno, rezultat FROM test_result ORDER BY id;

SELECT kategorija,
       SUM(rezultat = 'PASS') AS pass,
       SUM(rezultat = 'FAIL') AS fail
  FROM test_result GROUP BY kategorija
UNION ALL
SELECT 'UKUPNO', SUM(rezultat = 'PASS'), SUM(rezultat = 'FAIL') FROM test_result;

-- Kontrola: testovi nisu promijenili brojace (ocekivano 0)
SELECT COUNT(*) AS neuskladjeni_brojaci FROM v_reserved_check;

DROP PROCEDURE t_expect;
SET timestamp = DEFAULT;
SET time_zone = @test_previous_time_zone;
