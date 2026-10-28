-- =====================================================================
-- EventHub - seed/01_seed.sql : realni testni podaci (task 3 i 4)
--
-- Pokretanje (na SVJEZOJ bazi, odmah nakon Liquibase migracija):
--   docker exec -i eventhub-db sh -c 'mariadb -uroot -p"$MARIADB_ROOT_PASSWORD" eventhub' < seed/01_seed.sql
--
-- Kako radi:
--  * Sve rezervacije idu kroz prave procedure (create/confirm/cancel/expire/check-in),
--    pa vrijede sva pravila baze (kapacitet, 1-4 karte, sjedala, povrati...).
--  * Vrijeme se simulira sa SET timestamp: NOW() u ovoj sesiji "putuje" kroz 2026.,
--    pa podaci imaju realne datume kroz vise mjeseci (mjesecni trend prihoda).
--  * Scheduler za istek se privremeno iskljucuje, da ne bi (po stvarnom vremenu)
--    otkazao rezervaciju izmedu kreiranja i potvrde u seedu.
--  * Skripta je deterministicka: uvijek daje iste podatke (generirana iz gen_seed.py).
--
-- Sto pokriva (za izvjestaje iz taska 4):
--  * 8 evenata: 4 prosla (s check-inom), 4 buduca
--  * "Jesenski indie koncert": 19/20 prodano  -> manje od 10 % slobodno
--  * "Kazalisna premijera": nema nijedne rezervacije -> LEFT JOIN slucaj
--  * potvrdene kupnje, otkazane pending rezervacije, istekle rezervacije,
--    povrati (sa i bez zastite), sjedeca i stajaca mjesta, besplatna kategorija
-- =====================================================================
USE eventhub;

DELIMITER //
CREATE PROCEDURE seed_assert_empty()
BEGIN
  IF (SELECT COUNT(*) FROM event) > 0 OR (SELECT COUNT(*) FROM buyer) > 0 THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Seed se pokrece samo na praznoj bazi; postojeci podaci se ne brisu';
  END IF;
END//

-- Check-in svih vazecih karata jedne rezervacije (kroz pravu proceduru)
CREATE PROCEDURE seed_check_in_reservation(IN p_reservation_id INT)
BEGIN
  DECLARE done INT DEFAULT 0;
  DECLARE v_code CHAR(32);
  DECLARE v_event INT;
  DECLARE cur CURSOR FOR
    SELECT t.ticket_code FROM ticket t JOIN reservation_item ri ON ri.id = t.reservation_item_id
     WHERE ri.reservation_id = p_reservation_id AND t.cancelled_at IS NULL;
  DECLARE CONTINUE HANDLER FOR NOT FOUND SET done = 1;
  SELECT event_id INTO v_event FROM reservation WHERE id = p_reservation_id;
  OPEN cur;
  l: LOOP
    FETCH cur INTO v_code;
    IF done = 1 THEN LEAVE l; END IF;
    CALL check_in_ticket(v_event, v_code);
  END LOOP;
  CLOSE cur;
END//
DELIMITER ;

CALL seed_assert_empty();
ALTER EVENT ev_expire_reservations DISABLE;

-- ---------------------------------------------------------------------
-- Matični podaci (stanje na pocetku godine)
-- ---------------------------------------------------------------------
SET timestamp = UNIX_TIMESTAMP('2026-01-05 09:00:00');

INSERT INTO city (name) VALUES ('Zagreb'), ('Split'), ('Rijeka'), ('Osijek'), ('Zadar');
INSERT INTO location (name, city_id, capacity) VALUES
  ('Velika dvorana Sjever', 1, 5000),
  ('Klub Kotlovnica', 1, 300),
  ('Gradska arena Split', 2, 3000),
  ('Ljetna pozornica Rijeka', 3, 800),
  ('Gradsko kazaliste Osijek', 4, 400);
INSERT INTO organizer (name, email) VALUES
  ('Adria Live d.o.o.', 'info@adrialive.example'),
  ('Zvuk Grada j.d.o.o.', 'kontakt@zvukgrada.example'),
  ('Kultura Plus', 'ured@kulturaplus.example');
INSERT INTO buyer (name, surname, email, address, city_id) VALUES
  ('Ana', 'Horvat', 'ana.horvat1@example.com', 'Ulica 1', 1),
  ('Ivan', 'Knezevic', 'ivan.knezevic2@example.com', 'Ulica 2', 2),
  ('Marija', 'Bozic', 'marija.bozic3@example.com', 'Ulica 3', 3),
  ('Luka', 'Kovacevic', 'luka.kovacevic4@example.com', 'Ulica 4', 4),
  ('Petra', 'Vukovic', 'petra.vukovic5@example.com', 'Ulica 5', 5),
  ('Marko', 'Blazevic', 'marko.blazevic6@example.com', 'Ulica 6', 1),
  ('Ivana', 'Babic', 'ivana.babic7@example.com', 'Ulica 7', 2),
  ('Josip', 'Markovic', 'josip.markovic8@example.com', 'Ulica 8', 3),
  ('Lucija', 'Grgic', 'lucija.grgic9@example.com', 'Ulica 9', 4),
  ('Tomislav', 'Maric', 'tomislav.maric10@example.com', 'Ulica 10', 5),
  ('Maja', 'Petrovic', 'maja.petrovic11@example.com', 'Ulica 11', 1),
  ('Filip', 'Pavic', 'filip.pavic12@example.com', 'Ulica 12', 2),
  ('Katarina', 'Juric', 'katarina.juric13@example.com', 'Ulica 13', 3),
  ('Matej', 'Matic', 'matej.matic14@example.com', 'Ulica 14', 4),
  ('Ema', 'Radic', 'ema.radic15@example.com', 'Ulica 15', 5),
  ('Domagoj', 'Novak', 'domagoj.novak16@example.com', 'Ulica 16', 1),
  ('Sara', 'Tomic', 'sara.tomic17@example.com', 'Ulica 17', 2),
  ('Karlo', 'Peric', 'karlo.peric18@example.com', 'Ulica 18', 3),
  ('Lana', 'Kovacic', 'lana.kovacic19@example.com', 'Ulica 19', 4),
  ('Nikola', 'Pavlovic', 'nikola.pavlovic20@example.com', 'Ulica 20', 5),
  ('Ana', 'Horvat', 'ana.horvat21@example.com', 'Ulica 21', 1),
  ('Ivan', 'Knezevic', 'ivan.knezevic22@example.com', 'Ulica 22', 2),
  ('Marija', 'Bozic', 'marija.bozic23@example.com', 'Ulica 23', 3),
  ('Luka', 'Kovacevic', 'luka.kovacevic24@example.com', 'Ulica 24', 4),
  ('Petra', 'Vukovic', 'petra.vukovic25@example.com', 'Ulica 25', 5),
  ('Marko', 'Blazevic', 'marko.blazevic26@example.com', 'Ulica 26', 1),
  ('Ivana', 'Babic', 'ivana.babic27@example.com', 'Ulica 27', 2),
  ('Josip', 'Markovic', 'josip.markovic28@example.com', 'Ulica 28', 3),
  ('Lucija', 'Grgic', 'lucija.grgic29@example.com', 'Ulica 29', 4),
  ('Tomislav', 'Maric', 'tomislav.maric30@example.com', 'Ulica 30', 5),
  ('Maja', 'Petrovic', 'maja.petrovic31@example.com', 'Ulica 31', 1),
  ('Filip', 'Pavic', 'filip.pavic32@example.com', 'Ulica 32', 2),
  ('Katarina', 'Juric', 'katarina.juric33@example.com', 'Ulica 33', 3),
  ('Matej', 'Matic', 'matej.matic34@example.com', 'Ulica 34', 4),
  ('Ema', 'Radic', 'ema.radic35@example.com', 'Ulica 35', 5),
  ('Domagoj', 'Novak', 'domagoj.novak36@example.com', 'Ulica 36', 1),
  ('Sara', 'Tomic', 'sara.tomic37@example.com', 'Ulica 37', 2),
  ('Karlo', 'Peric', 'karlo.peric38@example.com', 'Ulica 38', 3),
  ('Lana', 'Kovacic', 'lana.kovacic39@example.com', 'Ulica 39', 4),
  ('Nikola', 'Pavlovic', 'nikola.pavlovic40@example.com', 'Ulica 40', 5);

INSERT INTO event (name, event_date, capacity, location_id, organizer_id) VALUES
  ('Zimska jazz vecer', '2026-02-20 20:00:00', 120, 2, 2),
  ('Proljetni rock festival', '2026-04-18 19:00:00', 2000, 1, 1),
  ('Klasika pod zvijezdama', '2026-07-10 21:00:00', 400, 4, 3),
  ('Stand-up vecer', '2026-09-12 20:00:00', 150, 5, 2),
  ('Jesenski indie koncert', '2026-11-21 20:00:00', 50, 2, 2),
  ('Novogodisnji koncert', '2026-12-31 22:00:00', 3000, 1, 1),
  ('Kazalisna premijera', '2027-01-15 19:30:00', 200, 5, 3),
  ('Ljetni festival Split', '2027-06-20 18:00:00', 3000, 3, 1);

INSERT INTO ticket_category (event_id, name, price, service_fee, capacity, seating_type) VALUES
  (1, 'Parter', 25.00, 2.00, 100, 'standing'),
  (1, 'Lounge', 45.00, 3.00, 20, 'seated'),
  (2, 'Parter', 40.00, 3.00, 1500, 'standing'),
  (2, 'VIP', 90.00, 5.00, 40, 'seated'),
  (3, 'Sjedala', 35.00, 2.00, 60, 'seated'),
  (3, 'Stajanje', 20.00, 1.00, 100, 'standing'),
  (4, 'Parter', 18.00, 1.00, 40, 'seated'),
  (5, 'Parter', 22.00, 2.00, 20, 'standing'),
  (6, 'Parter', 50.00, 4.00, 2000, 'standing'),
  (6, 'VIP', 120.00, 6.00, 40, 'seated'),
  (7, 'Sjedala', 28.00, 2.00, 40, 'seated'),
  (8, 'Dnevna ulaznica', 35.00, 3.00, 2500, 'standing'),
  (8, 'Djeca do 12 godina', 0.00, 0.00, 50, 'standing');

CALL generate_seats(2, 2, 10);   -- Zimska jazz vecer / Lounge
CALL generate_seats(4, 4, 10);   -- Proljetni rock festival / VIP
CALL generate_seats(5, 6, 10);   -- Klasika pod zvijezdama / Sjedala
CALL generate_seats(7, 4, 10);   -- Stand-up vecer / Parter
CALL generate_seats(10, 4, 10);   -- Novogodisnji koncert / VIP
CALL generate_seats(11, 4, 10);   -- Kazalisna premijera / Sjedala

-- ---------------------------------------------------------------------
-- Rezervacije kronoloskim redom
-- ---------------------------------------------------------------------

-- 2026-01-11 05:08:00 | Zimska jazz vecer | kupac 18 | refund | zastita
SET timestamp = UNIX_TIMESTAMP('2026-01-11 05:08:00');
CALL create_reservation(18, 1, '[{"category_id":1,"quantity":1}]', 1, @r);
SET timestamp = UNIX_TIMESTAMP('2026-01-11 05:19:00');
CALL confirm_reservation(@r);
SET timestamp = UNIX_TIMESTAMP('2026-02-02 00:56:00');
SELECT MIN(t.id) INTO @t FROM ticket t JOIN reservation_item ri ON ri.id = t.reservation_item_id WHERE ri.reservation_id = @r AND ri.category_id = 1;
CALL cancel_ticket(@t, @refund);
SET timestamp = UNIX_TIMESTAMP('2026-02-20 19:16:00');
CALL seed_check_in_reservation(@r);

-- 2026-01-14 13:09:00 | Zimska jazz vecer | kupac 14 | confirmed
SET timestamp = UNIX_TIMESTAMP('2026-01-14 13:09:00');
CALL create_reservation(14, 1, '[{"category_id":2,"seats":[7]}]', 0, @r);
SET timestamp = UNIX_TIMESTAMP('2026-01-14 13:21:00');
CALL confirm_reservation(@r);
SET timestamp = UNIX_TIMESTAMP('2026-02-20 19:13:00');
CALL seed_check_in_reservation(@r);

-- 2026-01-14 23:05:00 | Zimska jazz vecer | kupac 6 | cancel_pending | zastita
SET timestamp = UNIX_TIMESTAMP('2026-01-14 23:05:00');
CALL create_reservation(6, 1, '[{"category_id":2,"seats":[9]},{"category_id":1,"quantity":1}]', 1, @r);
SET timestamp = UNIX_TIMESTAMP('2026-01-14 23:09:00');
CALL cancel_reservation(@r);

-- 2026-01-16 01:25:00 | Zimska jazz vecer | kupac 25 | confirmed
SET timestamp = UNIX_TIMESTAMP('2026-01-16 01:25:00');
CALL create_reservation(25, 1, '[{"category_id":2,"seats":[1]}]', 0, @r);
SET timestamp = UNIX_TIMESTAMP('2026-01-16 01:33:00');
CALL confirm_reservation(@r);
SET timestamp = UNIX_TIMESTAMP('2026-02-20 19:17:00');
CALL seed_check_in_reservation(@r);

-- 2026-01-17 10:04:00 | Zimska jazz vecer | kupac 11 | expired
SET timestamp = UNIX_TIMESTAMP('2026-01-17 10:04:00');
CALL create_reservation(11, 1, '[{"category_id":1,"quantity":3},{"category_id":2,"seats":[3]}]', 0, @r);
SET timestamp = UNIX_TIMESTAMP('2026-01-17 10:20:00');
CALL expire_reservations();

-- 2026-01-19 15:39:00 | Zimska jazz vecer | kupac 35 | confirmed | zastita
SET timestamp = UNIX_TIMESTAMP('2026-01-19 15:39:00');
CALL create_reservation(35, 1, '[{"category_id":2,"seats":[12,13]}]', 1, @r);
SET timestamp = UNIX_TIMESTAMP('2026-01-19 15:48:00');
CALL confirm_reservation(@r);
SET timestamp = UNIX_TIMESTAMP('2026-02-20 19:41:00');
CALL seed_check_in_reservation(@r);

-- 2026-01-21 07:13:00 | Zimska jazz vecer | kupac 7 | confirmed
SET timestamp = UNIX_TIMESTAMP('2026-01-21 07:13:00');
CALL create_reservation(7, 1, '[{"category_id":1,"quantity":1},{"category_id":2,"seats":[18]}]', 0, @r);
SET timestamp = UNIX_TIMESTAMP('2026-01-21 07:16:00');
CALL confirm_reservation(@r);
SET timestamp = UNIX_TIMESTAMP('2026-02-20 19:14:00');
CALL seed_check_in_reservation(@r);

-- 2026-01-21 21:13:00 | Zimska jazz vecer | kupac 11 | confirmed
SET timestamp = UNIX_TIMESTAMP('2026-01-21 21:13:00');
CALL create_reservation(11, 1, '[{"category_id":2,"seats":[19,20]}]', 0, @r);
SET timestamp = UNIX_TIMESTAMP('2026-01-21 21:17:00');
CALL confirm_reservation(@r);
SET timestamp = UNIX_TIMESTAMP('2026-02-20 19:45:00');
CALL seed_check_in_reservation(@r);

-- 2026-01-26 12:25:00 | Zimska jazz vecer | kupac 18 | refund | zastita
SET timestamp = UNIX_TIMESTAMP('2026-01-26 12:25:00');
CALL create_reservation(18, 1, '[{"category_id":1,"quantity":1}]', 1, @r);
SET timestamp = UNIX_TIMESTAMP('2026-01-26 12:34:00');
CALL confirm_reservation(@r);
SET timestamp = UNIX_TIMESTAMP('2026-01-30 13:00:00');
SELECT MIN(t.id) INTO @t FROM ticket t JOIN reservation_item ri ON ri.id = t.reservation_item_id WHERE ri.reservation_id = @r AND ri.category_id = 1;
CALL cancel_ticket(@t, @refund);
SET timestamp = UNIX_TIMESTAMP('2026-02-20 19:36:00');
CALL seed_check_in_reservation(@r);

-- 2026-01-27 17:03:00 | Zimska jazz vecer | kupac 11 | refund
SET timestamp = UNIX_TIMESTAMP('2026-01-27 17:03:00');
CALL create_reservation(11, 1, '[{"category_id":1,"quantity":2}]', 0, @r);
SET timestamp = UNIX_TIMESTAMP('2026-01-27 17:13:00');
CALL confirm_reservation(@r);
SET timestamp = UNIX_TIMESTAMP('2026-02-10 19:46:00');
SELECT MIN(t.id) INTO @t FROM ticket t JOIN reservation_item ri ON ri.id = t.reservation_item_id WHERE ri.reservation_id = @r AND ri.category_id = 1;
CALL cancel_ticket(@t, @refund);
SET timestamp = UNIX_TIMESTAMP('2026-02-20 19:50:00');
CALL seed_check_in_reservation(@r);

-- 2026-01-28 16:17:00 | Zimska jazz vecer | kupac 25 | confirmed
SET timestamp = UNIX_TIMESTAMP('2026-01-28 16:17:00');
CALL create_reservation(25, 1, '[{"category_id":2,"seats":[16,17]}]', 0, @r);
SET timestamp = UNIX_TIMESTAMP('2026-01-28 16:24:00');
CALL confirm_reservation(@r);
SET timestamp = UNIX_TIMESTAMP('2026-02-20 19:54:00');
CALL seed_check_in_reservation(@r);

-- 2026-01-29 11:23:00 | Zimska jazz vecer | kupac 18 | cancel_pending | zastita
SET timestamp = UNIX_TIMESTAMP('2026-01-29 11:23:00');
CALL create_reservation(18, 1, '[{"category_id":2,"seats":[15]}]', 1, @r);
SET timestamp = UNIX_TIMESTAMP('2026-01-29 11:25:00');
CALL cancel_reservation(@r);

-- 2026-02-03 17:38:00 | Zimska jazz vecer | kupac 32 | expired
SET timestamp = UNIX_TIMESTAMP('2026-02-03 17:38:00');
CALL create_reservation(32, 1, '[{"category_id":1,"quantity":1}]', 0, @r);
SET timestamp = UNIX_TIMESTAMP('2026-02-03 17:54:00');
CALL expire_reservations();

-- 2026-02-05 20:33:00 | Zimska jazz vecer | kupac 1 | confirmed
SET timestamp = UNIX_TIMESTAMP('2026-02-05 20:33:00');
CALL create_reservation(1, 1, '[{"category_id":2,"seats":[11,14]},{"category_id":1,"quantity":1}]', 0, @r);
SET timestamp = UNIX_TIMESTAMP('2026-02-05 20:45:00');
CALL confirm_reservation(@r);
SET timestamp = UNIX_TIMESTAMP('2026-02-20 19:38:00');
CALL seed_check_in_reservation(@r);

-- 2026-02-06 06:02:00 | Zimska jazz vecer | kupac 35 | confirmed
SET timestamp = UNIX_TIMESTAMP('2026-02-06 06:02:00');
CALL create_reservation(35, 1, '[{"category_id":2,"seats":[10,15]}]', 0, @r);
SET timestamp = UNIX_TIMESTAMP('2026-02-06 06:05:00');
CALL confirm_reservation(@r);
SET timestamp = UNIX_TIMESTAMP('2026-02-20 19:29:00');
CALL seed_check_in_reservation(@r);

-- 2026-02-07 07:51:00 | Zimska jazz vecer | kupac 26 | confirmed | zastita
SET timestamp = UNIX_TIMESTAMP('2026-02-07 07:51:00');
CALL create_reservation(26, 1, '[{"category_id":1,"quantity":2}]', 1, @r);
SET timestamp = UNIX_TIMESTAMP('2026-02-07 08:03:00');
CALL confirm_reservation(@r);
SET timestamp = UNIX_TIMESTAMP('2026-02-20 19:45:00');
CALL seed_check_in_reservation(@r);

-- 2026-02-08 07:23:00 | Zimska jazz vecer | kupac 17 | cancel_pending | zastita
SET timestamp = UNIX_TIMESTAMP('2026-02-08 07:23:00');
CALL create_reservation(17, 1, '[{"category_id":1,"quantity":4}]', 1, @r);
SET timestamp = UNIX_TIMESTAMP('2026-02-08 07:32:00');
CALL cancel_reservation(@r);

-- 2026-02-09 00:37:00 | Zimska jazz vecer | kupac 24 | cancel_pending | zastita
SET timestamp = UNIX_TIMESTAMP('2026-02-09 00:37:00');
CALL create_reservation(24, 1, '[{"category_id":1,"quantity":2}]', 1, @r);
SET timestamp = UNIX_TIMESTAMP('2026-02-09 00:47:00');
CALL cancel_reservation(@r);

-- 2026-02-09 20:00:00 | Proljetni rock festival | kupac 38 | confirmed | zastita
SET timestamp = UNIX_TIMESTAMP('2026-02-09 20:00:00');
CALL create_reservation(38, 2, '[{"category_id":4,"seats":[26,27]}]', 1, @r);
SET timestamp = UNIX_TIMESTAMP('2026-02-09 20:07:00');
CALL confirm_reservation(@r);
SET timestamp = UNIX_TIMESTAMP('2026-04-18 18:48:00');
CALL seed_check_in_reservation(@r);

-- 2026-02-10 01:39:00 | Zimska jazz vecer | kupac 36 | expired
SET timestamp = UNIX_TIMESTAMP('2026-02-10 01:39:00');
CALL create_reservation(36, 1, '[{"category_id":1,"quantity":1}]', 0, @r);
SET timestamp = UNIX_TIMESTAMP('2026-02-10 01:55:00');
CALL expire_reservations();

-- 2026-02-10 04:58:00 | Zimska jazz vecer | kupac 30 | confirmed
SET timestamp = UNIX_TIMESTAMP('2026-02-10 04:58:00');
CALL create_reservation(30, 1, '[{"category_id":1,"quantity":1}]', 0, @r);
SET timestamp = UNIX_TIMESTAMP('2026-02-10 05:00:00');
CALL confirm_reservation(@r);
SET timestamp = UNIX_TIMESTAMP('2026-02-20 19:32:00');
CALL seed_check_in_reservation(@r);

-- 2026-02-11 02:25:00 | Zimska jazz vecer | kupac 15 | confirmed
SET timestamp = UNIX_TIMESTAMP('2026-02-11 02:25:00');
CALL create_reservation(15, 1, '[{"category_id":1,"quantity":4}]', 0, @r);
SET timestamp = UNIX_TIMESTAMP('2026-02-11 02:27:00');
CALL confirm_reservation(@r);
SET timestamp = UNIX_TIMESTAMP('2026-02-20 19:20:00');
CALL seed_check_in_reservation(@r);

-- 2026-02-11 20:24:00 | Zimska jazz vecer | kupac 35 | refund
SET timestamp = UNIX_TIMESTAMP('2026-02-11 20:24:00');
CALL create_reservation(35, 1, '[{"category_id":2,"seats":[5]}]', 0, @r);
SET timestamp = UNIX_TIMESTAMP('2026-02-11 20:33:00');
CALL confirm_reservation(@r);
SET timestamp = UNIX_TIMESTAMP('2026-02-14 07:55:00');
SELECT t.id INTO @t FROM ticket t JOIN reservation_seat rs ON rs.id = t.reservation_seat_id WHERE rs.seat_id = 5 AND rs.reservation_item_id IN (SELECT id FROM reservation_item WHERE reservation_id = @r);
CALL cancel_ticket(@t, @refund);
SET timestamp = UNIX_TIMESTAMP('2026-02-20 19:15:00');
CALL seed_check_in_reservation(@r);

-- 2026-02-12 16:52:00 | Proljetni rock festival | kupac 35 | confirmed | zastita
SET timestamp = UNIX_TIMESTAMP('2026-02-12 16:52:00');
CALL create_reservation(35, 2, '[{"category_id":4,"seats":[42,43]},{"category_id":3,"quantity":2}]', 1, @r);
SET timestamp = UNIX_TIMESTAMP('2026-02-12 17:02:00');
CALL confirm_reservation(@r);
SET timestamp = UNIX_TIMESTAMP('2026-04-18 18:29:00');
CALL seed_check_in_reservation(@r);

-- 2026-02-13 01:40:00 | Zimska jazz vecer | kupac 5 | refund
SET timestamp = UNIX_TIMESTAMP('2026-02-13 01:40:00');
CALL create_reservation(5, 1, '[{"category_id":2,"seats":[9]},{"category_id":1,"quantity":1}]', 0, @r);
SET timestamp = UNIX_TIMESTAMP('2026-02-13 01:43:00');
CALL confirm_reservation(@r);
SET timestamp = UNIX_TIMESTAMP('2026-02-19 16:07:00');
SELECT t.id INTO @t FROM ticket t JOIN reservation_seat rs ON rs.id = t.reservation_seat_id WHERE rs.seat_id = 9 AND rs.reservation_item_id IN (SELECT id FROM reservation_item WHERE reservation_id = @r);
CALL cancel_ticket(@t, @refund);

-- 2026-02-13 08:12:00 | Proljetni rock festival | kupac 4 | refund
SET timestamp = UNIX_TIMESTAMP('2026-02-13 08:12:00');
CALL create_reservation(4, 2, '[{"category_id":4,"seats":[41,44]}]', 0, @r);
SET timestamp = UNIX_TIMESTAMP('2026-02-13 08:22:00');
CALL confirm_reservation(@r);
SET timestamp = UNIX_TIMESTAMP('2026-03-12 21:29:00');
SELECT t.id INTO @t FROM ticket t JOIN reservation_seat rs ON rs.id = t.reservation_seat_id WHERE rs.seat_id = 41 AND rs.reservation_item_id IN (SELECT id FROM reservation_item WHERE reservation_id = @r);
CALL cancel_ticket(@t, @refund);
SET timestamp = UNIX_TIMESTAMP('2026-04-18 18:25:00');
CALL seed_check_in_reservation(@r);

-- 2026-02-13 11:16:00 | Proljetni rock festival | kupac 38 | confirmed
SET timestamp = UNIX_TIMESTAMP('2026-02-13 11:16:00');
CALL create_reservation(38, 2, '[{"category_id":3,"quantity":1},{"category_id":4,"seats":[55,56]}]', 0, @r);
SET timestamp = UNIX_TIMESTAMP('2026-02-13 11:26:00');
CALL confirm_reservation(@r);
SET timestamp = UNIX_TIMESTAMP('2026-04-18 18:43:00');
CALL seed_check_in_reservation(@r);

-- 2026-02-13 20:25:00 | Zimska jazz vecer | kupac 21 | expired
SET timestamp = UNIX_TIMESTAMP('2026-02-13 20:25:00');
CALL create_reservation(21, 1, '[{"category_id":2,"seats":[4]}]', 0, @r);
SET timestamp = UNIX_TIMESTAMP('2026-02-13 20:41:00');
CALL expire_reservations();

-- 2026-02-14 16:25:00 | Proljetni rock festival | kupac 4 | confirmed | zastita
SET timestamp = UNIX_TIMESTAMP('2026-02-14 16:25:00');
CALL create_reservation(4, 2, '[{"category_id":3,"quantity":1}]', 1, @r);
SET timestamp = UNIX_TIMESTAMP('2026-02-14 16:35:00');
CALL confirm_reservation(@r);
SET timestamp = UNIX_TIMESTAMP('2026-04-18 18:55:00');
CALL seed_check_in_reservation(@r);

-- 2026-02-15 02:39:00 | Proljetni rock festival | kupac 29 | expired
SET timestamp = UNIX_TIMESTAMP('2026-02-15 02:39:00');
CALL create_reservation(29, 2, '[{"category_id":3,"quantity":3},{"category_id":4,"seats":[59]}]', 0, @r);
SET timestamp = UNIX_TIMESTAMP('2026-02-15 02:55:00');
CALL expire_reservations();

-- 2026-02-15 10:31:00 | Proljetni rock festival | kupac 6 | expired
SET timestamp = UNIX_TIMESTAMP('2026-02-15 10:31:00');
CALL create_reservation(6, 2, '[{"category_id":4,"seats":[58,59]},{"category_id":3,"quantity":1}]', 0, @r);
SET timestamp = UNIX_TIMESTAMP('2026-02-15 10:47:00');
CALL expire_reservations();

-- 2026-02-16 16:06:00 | Zimska jazz vecer | kupac 4 | cancel_pending
SET timestamp = UNIX_TIMESTAMP('2026-02-16 16:06:00');
CALL create_reservation(4, 1, '[{"category_id":1,"quantity":1}]', 0, @r);
SET timestamp = UNIX_TIMESTAMP('2026-02-16 16:16:00');
CALL cancel_reservation(@r);

-- 2026-02-17 11:58:00 | Proljetni rock festival | kupac 5 | expired | zastita
SET timestamp = UNIX_TIMESTAMP('2026-02-17 11:58:00');
CALL create_reservation(5, 2, '[{"category_id":3,"quantity":2}]', 1, @r);
SET timestamp = UNIX_TIMESTAMP('2026-02-17 12:14:00');
CALL expire_reservations();

-- 2026-02-18 07:03:00 | Zimska jazz vecer | kupac 1 | confirmed
SET timestamp = UNIX_TIMESTAMP('2026-02-18 07:03:00');
CALL create_reservation(1, 1, '[{"category_id":1,"quantity":2},{"category_id":2,"seats":[8,9]}]', 0, @r);
SET timestamp = UNIX_TIMESTAMP('2026-02-18 07:08:00');
CALL confirm_reservation(@r);
SET timestamp = UNIX_TIMESTAMP('2026-02-20 19:41:00');
CALL seed_check_in_reservation(@r);

-- 2026-02-18 09:36:00 | Proljetni rock festival | kupac 16 | confirmed | zastita
SET timestamp = UNIX_TIMESTAMP('2026-02-18 09:36:00');
CALL create_reservation(16, 2, '[{"category_id":3,"quantity":1}]', 1, @r);
SET timestamp = UNIX_TIMESTAMP('2026-02-18 09:43:00');
CALL confirm_reservation(@r);
SET timestamp = UNIX_TIMESTAMP('2026-04-18 18:10:00');
CALL seed_check_in_reservation(@r);

-- 2026-02-22 15:08:00 | Proljetni rock festival | kupac 24 | confirmed | zastita
SET timestamp = UNIX_TIMESTAMP('2026-02-22 15:08:00');
CALL create_reservation(24, 2, '[{"category_id":3,"quantity":4}]', 1, @r);
SET timestamp = UNIX_TIMESTAMP('2026-02-22 15:20:00');
CALL confirm_reservation(@r);
SET timestamp = UNIX_TIMESTAMP('2026-04-18 18:14:00');
CALL seed_check_in_reservation(@r);

-- 2026-02-23 19:46:00 | Proljetni rock festival | kupac 17 | expired
SET timestamp = UNIX_TIMESTAMP('2026-02-23 19:46:00');
CALL create_reservation(17, 2, '[{"category_id":4,"seats":[23,24]}]', 0, @r);
SET timestamp = UNIX_TIMESTAMP('2026-02-23 20:02:00');
CALL expire_reservations();

-- 2026-02-25 20:00:00 | Proljetni rock festival | kupac 5 | confirmed | zastita
SET timestamp = UNIX_TIMESTAMP('2026-02-25 20:00:00');
CALL create_reservation(5, 2, '[{"category_id":4,"seats":[29,30]}]', 1, @r);
SET timestamp = UNIX_TIMESTAMP('2026-02-25 20:09:00');
CALL confirm_reservation(@r);
SET timestamp = UNIX_TIMESTAMP('2026-04-18 18:26:00');
CALL seed_check_in_reservation(@r);

-- 2026-02-26 06:41:00 | Proljetni rock festival | kupac 7 | cancel_pending
SET timestamp = UNIX_TIMESTAMP('2026-02-26 06:41:00');
CALL create_reservation(7, 2, '[{"category_id":4,"seats":[38]}]', 0, @r);
SET timestamp = UNIX_TIMESTAMP('2026-02-26 06:45:00');
CALL cancel_reservation(@r);

-- 2026-02-28 08:31:00 | Proljetni rock festival | kupac 35 | confirmed
SET timestamp = UNIX_TIMESTAMP('2026-02-28 08:31:00');
CALL create_reservation(35, 2, '[{"category_id":4,"seats":[53,54,57,58]}]', 0, @r);
SET timestamp = UNIX_TIMESTAMP('2026-02-28 08:37:00');
CALL confirm_reservation(@r);
SET timestamp = UNIX_TIMESTAMP('2026-04-18 18:11:00');
CALL seed_check_in_reservation(@r);

-- 2026-02-28 14:12:00 | Proljetni rock festival | kupac 35 | refund
SET timestamp = UNIX_TIMESTAMP('2026-02-28 14:12:00');
CALL create_reservation(35, 2, '[{"category_id":3,"quantity":1}]', 0, @r);
SET timestamp = UNIX_TIMESTAMP('2026-02-28 14:19:00');
CALL confirm_reservation(@r);
SET timestamp = UNIX_TIMESTAMP('2026-04-11 23:21:00');
SELECT MIN(t.id) INTO @t FROM ticket t JOIN reservation_item ri ON ri.id = t.reservation_item_id WHERE ri.reservation_id = @r AND ri.category_id = 3;
CALL cancel_ticket(@t, @refund);
SET timestamp = UNIX_TIMESTAMP('2026-04-18 18:21:00');
CALL seed_check_in_reservation(@r);

-- 2026-03-02 17:48:00 | Proljetni rock festival | kupac 11 | confirmed
SET timestamp = UNIX_TIMESTAMP('2026-03-02 17:48:00');
CALL create_reservation(11, 2, '[{"category_id":3,"quantity":2}]', 0, @r);
SET timestamp = UNIX_TIMESTAMP('2026-03-02 18:00:00');
CALL confirm_reservation(@r);
SET timestamp = UNIX_TIMESTAMP('2026-04-18 18:24:00');
CALL seed_check_in_reservation(@r);

-- 2026-03-05 08:44:00 | Proljetni rock festival | kupac 33 | refund | zastita
SET timestamp = UNIX_TIMESTAMP('2026-03-05 08:44:00');
CALL create_reservation(33, 2, '[{"category_id":4,"seats":[32]},{"category_id":3,"quantity":3}]', 1, @r);
SET timestamp = UNIX_TIMESTAMP('2026-03-05 08:56:00');
CALL confirm_reservation(@r);
SET timestamp = UNIX_TIMESTAMP('2026-04-08 14:18:00');
SELECT t.id INTO @t FROM ticket t JOIN reservation_seat rs ON rs.id = t.reservation_seat_id WHERE rs.seat_id = 32 AND rs.reservation_item_id IN (SELECT id FROM reservation_item WHERE reservation_id = @r);
CALL cancel_ticket(@t, @refund);

-- 2026-03-05 12:58:00 | Proljetni rock festival | kupac 30 | expired
SET timestamp = UNIX_TIMESTAMP('2026-03-05 12:58:00');
CALL create_reservation(30, 2, '[{"category_id":4,"seats":[38]},{"category_id":3,"quantity":1}]', 0, @r);
SET timestamp = UNIX_TIMESTAMP('2026-03-05 13:14:00');
CALL expire_reservations();

-- 2026-03-05 13:55:00 | Proljetni rock festival | kupac 26 | confirmed
SET timestamp = UNIX_TIMESTAMP('2026-03-05 13:55:00');
CALL create_reservation(26, 2, '[{"category_id":4,"seats":[39]}]', 0, @r);
SET timestamp = UNIX_TIMESTAMP('2026-03-05 13:59:00');
CALL confirm_reservation(@r);
SET timestamp = UNIX_TIMESTAMP('2026-04-18 18:54:00');
CALL seed_check_in_reservation(@r);

-- 2026-03-10 01:21:00 | Proljetni rock festival | kupac 26 | confirmed
SET timestamp = UNIX_TIMESTAMP('2026-03-10 01:21:00');
CALL create_reservation(26, 2, '[{"category_id":4,"seats":[22,23]},{"category_id":3,"quantity":1}]', 0, @r);
SET timestamp = UNIX_TIMESTAMP('2026-03-10 01:27:00');
CALL confirm_reservation(@r);
SET timestamp = UNIX_TIMESTAMP('2026-04-18 18:28:00');
CALL seed_check_in_reservation(@r);

-- 2026-03-10 11:44:00 | Proljetni rock festival | kupac 5 | confirmed
SET timestamp = UNIX_TIMESTAMP('2026-03-10 11:44:00');
CALL create_reservation(5, 2, '[{"category_id":4,"seats":[47]}]', 0, @r);
SET timestamp = UNIX_TIMESTAMP('2026-03-10 11:52:00');
CALL confirm_reservation(@r);
SET timestamp = UNIX_TIMESTAMP('2026-04-18 18:44:00');
CALL seed_check_in_reservation(@r);

-- 2026-03-10 12:11:00 | Proljetni rock festival | kupac 17 | confirmed
SET timestamp = UNIX_TIMESTAMP('2026-03-10 12:11:00');
CALL create_reservation(17, 2, '[{"category_id":4,"seats":[25]}]', 0, @r);
SET timestamp = UNIX_TIMESTAMP('2026-03-10 12:22:00');
CALL confirm_reservation(@r);

-- 2026-03-11 20:57:00 | Proljetni rock festival | kupac 5 | confirmed | zastita
SET timestamp = UNIX_TIMESTAMP('2026-03-11 20:57:00');
CALL create_reservation(5, 2, '[{"category_id":4,"seats":[51,52]}]', 1, @r);
SET timestamp = UNIX_TIMESTAMP('2026-03-11 21:01:00');
CALL confirm_reservation(@r);
SET timestamp = UNIX_TIMESTAMP('2026-04-18 18:15:00');
CALL seed_check_in_reservation(@r);

-- 2026-03-13 01:58:00 | Proljetni rock festival | kupac 14 | confirmed
SET timestamp = UNIX_TIMESTAMP('2026-03-13 01:58:00');
CALL create_reservation(14, 2, '[{"category_id":3,"quantity":2},{"category_id":4,"seats":[36]}]', 0, @r);
SET timestamp = UNIX_TIMESTAMP('2026-03-13 02:10:00');
CALL confirm_reservation(@r);
SET timestamp = UNIX_TIMESTAMP('2026-04-18 18:26:00');
CALL seed_check_in_reservation(@r);

-- 2026-03-13 16:14:00 | Proljetni rock festival | kupac 5 | confirmed
SET timestamp = UNIX_TIMESTAMP('2026-03-13 16:14:00');
CALL create_reservation(5, 2, '[{"category_id":3,"quantity":1}]', 0, @r);
SET timestamp = UNIX_TIMESTAMP('2026-03-13 16:17:00');
CALL confirm_reservation(@r);
SET timestamp = UNIX_TIMESTAMP('2026-04-18 18:33:00');
CALL seed_check_in_reservation(@r);

-- 2026-03-15 00:48:00 | Proljetni rock festival | kupac 20 | confirmed | zastita
SET timestamp = UNIX_TIMESTAMP('2026-03-15 00:48:00');
CALL create_reservation(20, 2, '[{"category_id":3,"quantity":1}]', 1, @r);
SET timestamp = UNIX_TIMESTAMP('2026-03-15 00:54:00');
CALL confirm_reservation(@r);
SET timestamp = UNIX_TIMESTAMP('2026-04-18 18:36:00');
CALL seed_check_in_reservation(@r);

-- 2026-03-18 17:29:00 | Proljetni rock festival | kupac 4 | confirmed
SET timestamp = UNIX_TIMESTAMP('2026-03-18 17:29:00');
CALL create_reservation(4, 2, '[{"category_id":4,"seats":[49]}]', 0, @r);
SET timestamp = UNIX_TIMESTAMP('2026-03-18 17:32:00');
CALL confirm_reservation(@r);
SET timestamp = UNIX_TIMESTAMP('2026-04-18 18:19:00');
CALL seed_check_in_reservation(@r);

-- 2026-03-18 23:51:00 | Proljetni rock festival | kupac 8 | expired | zastita
SET timestamp = UNIX_TIMESTAMP('2026-03-18 23:51:00');
CALL create_reservation(8, 2, '[{"category_id":3,"quantity":2}]', 1, @r);
SET timestamp = UNIX_TIMESTAMP('2026-03-19 00:07:00');
CALL expire_reservations();

-- 2026-03-19 16:56:00 | Proljetni rock festival | kupac 30 | confirmed
SET timestamp = UNIX_TIMESTAMP('2026-03-19 16:56:00');
CALL create_reservation(30, 2, '[{"category_id":3,"quantity":1},{"category_id":4,"seats":[45,46,48]}]', 0, @r);
SET timestamp = UNIX_TIMESTAMP('2026-03-19 17:02:00');
CALL confirm_reservation(@r);
SET timestamp = UNIX_TIMESTAMP('2026-04-18 18:12:00');
CALL seed_check_in_reservation(@r);

-- 2026-03-20 18:03:00 | Proljetni rock festival | kupac 12 | confirmed
SET timestamp = UNIX_TIMESTAMP('2026-03-20 18:03:00');
CALL create_reservation(12, 2, '[{"category_id":4,"seats":[59,60]}]', 0, @r);
SET timestamp = UNIX_TIMESTAMP('2026-03-20 18:09:00');
CALL confirm_reservation(@r);
SET timestamp = UNIX_TIMESTAMP('2026-04-18 18:41:00');
CALL seed_check_in_reservation(@r);

-- 2026-03-22 00:04:00 | Proljetni rock festival | kupac 11 | confirmed | zastita
SET timestamp = UNIX_TIMESTAMP('2026-03-22 00:04:00');
CALL create_reservation(11, 2, '[{"category_id":3,"quantity":1},{"category_id":4,"seats":[40]}]', 1, @r);
SET timestamp = UNIX_TIMESTAMP('2026-03-22 00:09:00');
CALL confirm_reservation(@r);
SET timestamp = UNIX_TIMESTAMP('2026-04-18 18:12:00');
CALL seed_check_in_reservation(@r);

-- 2026-03-27 05:21:00 | Proljetni rock festival | kupac 17 | confirmed | zastita
SET timestamp = UNIX_TIMESTAMP('2026-03-27 05:21:00');
CALL create_reservation(17, 2, '[{"category_id":4,"seats":[41]},{"category_id":3,"quantity":3}]', 1, @r);
SET timestamp = UNIX_TIMESTAMP('2026-03-27 05:33:00');
CALL confirm_reservation(@r);
SET timestamp = UNIX_TIMESTAMP('2026-04-18 18:27:00');
CALL seed_check_in_reservation(@r);

-- 2026-03-30 01:02:00 | Proljetni rock festival | kupac 29 | confirmed | zastita
SET timestamp = UNIX_TIMESTAMP('2026-03-30 01:02:00');
CALL create_reservation(29, 2, '[{"category_id":4,"seats":[28]}]', 1, @r);
SET timestamp = UNIX_TIMESTAMP('2026-03-30 01:05:00');
CALL confirm_reservation(@r);

-- 2026-03-31 03:31:00 | Proljetni rock festival | kupac 1 | cancel_pending
SET timestamp = UNIX_TIMESTAMP('2026-03-31 03:31:00');
CALL create_reservation(1, 2, '[{"category_id":3,"quantity":3}]', 0, @r);
SET timestamp = UNIX_TIMESTAMP('2026-03-31 03:39:00');
CALL cancel_reservation(@r);

-- 2026-03-31 06:48:00 | Proljetni rock festival | kupac 1 | expired
SET timestamp = UNIX_TIMESTAMP('2026-03-31 06:48:00');
CALL create_reservation(1, 2, '[{"category_id":4,"seats":[31]},{"category_id":3,"quantity":1}]', 0, @r);
SET timestamp = UNIX_TIMESTAMP('2026-03-31 07:04:00');
CALL expire_reservations();

-- 2026-03-31 08:36:00 | Proljetni rock festival | kupac 11 | expired
SET timestamp = UNIX_TIMESTAMP('2026-03-31 08:36:00');
CALL create_reservation(11, 2, '[{"category_id":3,"quantity":1}]', 0, @r);
SET timestamp = UNIX_TIMESTAMP('2026-03-31 08:52:00');
CALL expire_reservations();

-- 2026-03-31 12:17:00 | Proljetni rock festival | kupac 9 | confirmed
SET timestamp = UNIX_TIMESTAMP('2026-03-31 12:17:00');
CALL create_reservation(9, 2, '[{"category_id":4,"seats":[37]}]', 0, @r);
SET timestamp = UNIX_TIMESTAMP('2026-03-31 12:23:00');
CALL confirm_reservation(@r);
SET timestamp = UNIX_TIMESTAMP('2026-04-18 18:34:00');
CALL seed_check_in_reservation(@r);

-- 2026-03-31 22:13:00 | Proljetni rock festival | kupac 18 | refund
SET timestamp = UNIX_TIMESTAMP('2026-03-31 22:13:00');
CALL create_reservation(18, 2, '[{"category_id":4,"seats":[21,24,31,32]}]', 0, @r);
SET timestamp = UNIX_TIMESTAMP('2026-03-31 22:17:00');
CALL confirm_reservation(@r);
SET timestamp = UNIX_TIMESTAMP('2026-04-07 09:42:00');
SELECT t.id INTO @t FROM ticket t JOIN reservation_seat rs ON rs.id = t.reservation_seat_id WHERE rs.seat_id = 21 AND rs.reservation_item_id IN (SELECT id FROM reservation_item WHERE reservation_id = @r);
CALL cancel_ticket(@t, @refund);

-- 2026-04-01 12:47:00 | Proljetni rock festival | kupac 20 | confirmed
SET timestamp = UNIX_TIMESTAMP('2026-04-01 12:47:00');
CALL create_reservation(20, 2, '[{"category_id":3,"quantity":2}]', 0, @r);
SET timestamp = UNIX_TIMESTAMP('2026-04-01 12:50:00');
CALL confirm_reservation(@r);
SET timestamp = UNIX_TIMESTAMP('2026-04-18 18:55:00');
CALL seed_check_in_reservation(@r);

-- 2026-04-02 12:06:00 | Proljetni rock festival | kupac 10 | expired
SET timestamp = UNIX_TIMESTAMP('2026-04-02 12:06:00');
CALL create_reservation(10, 2, '[{"category_id":3,"quantity":1},{"category_id":4,"seats":[35]}]', 0, @r);
SET timestamp = UNIX_TIMESTAMP('2026-04-02 12:22:00');
CALL expire_reservations();

-- 2026-04-02 18:02:00 | Proljetni rock festival | kupac 32 | expired | zastita
SET timestamp = UNIX_TIMESTAMP('2026-04-02 18:02:00');
CALL create_reservation(32, 2, '[{"category_id":3,"quantity":1}]', 1, @r);
SET timestamp = UNIX_TIMESTAMP('2026-04-02 18:18:00');
CALL expire_reservations();

-- 2026-04-04 17:40:00 | Proljetni rock festival | kupac 31 | expired
SET timestamp = UNIX_TIMESTAMP('2026-04-04 17:40:00');
CALL create_reservation(31, 2, '[{"category_id":3,"quantity":1}]', 0, @r);
SET timestamp = UNIX_TIMESTAMP('2026-04-04 17:56:00');
CALL expire_reservations();

-- 2026-04-08 22:15:00 | Proljetni rock festival | kupac 6 | confirmed
SET timestamp = UNIX_TIMESTAMP('2026-04-08 22:15:00');
CALL create_reservation(6, 2, '[{"category_id":4,"seats":[35]},{"category_id":3,"quantity":1}]', 0, @r);
SET timestamp = UNIX_TIMESTAMP('2026-04-08 22:17:00');
CALL confirm_reservation(@r);
SET timestamp = UNIX_TIMESTAMP('2026-04-18 18:20:00');
CALL seed_check_in_reservation(@r);

-- 2026-04-09 12:03:00 | Proljetni rock festival | kupac 20 | expired
SET timestamp = UNIX_TIMESTAMP('2026-04-09 12:03:00');
CALL create_reservation(20, 2, '[{"category_id":3,"quantity":2},{"category_id":4,"seats":[21,33]}]', 0, @r);
SET timestamp = UNIX_TIMESTAMP('2026-04-09 12:19:00');
CALL expire_reservations();

-- 2026-04-11 12:42:00 | Proljetni rock festival | kupac 7 | refund
SET timestamp = UNIX_TIMESTAMP('2026-04-11 12:42:00');
CALL create_reservation(7, 2, '[{"category_id":3,"quantity":1}]', 0, @r);
SET timestamp = UNIX_TIMESTAMP('2026-04-11 12:54:00');
CALL confirm_reservation(@r);
SET timestamp = UNIX_TIMESTAMP('2026-04-17 11:49:00');
SELECT MIN(t.id) INTO @t FROM ticket t JOIN reservation_item ri ON ri.id = t.reservation_item_id WHERE ri.reservation_id = @r AND ri.category_id = 3;
CALL cancel_ticket(@t, @refund);
SET timestamp = UNIX_TIMESTAMP('2026-04-18 18:53:00');
CALL seed_check_in_reservation(@r);

-- 2026-04-13 04:48:00 | Proljetni rock festival | kupac 7 | confirmed
SET timestamp = UNIX_TIMESTAMP('2026-04-13 04:48:00');
CALL create_reservation(7, 2, '[{"category_id":4,"seats":[38]}]', 0, @r);
SET timestamp = UNIX_TIMESTAMP('2026-04-13 04:51:00');
CALL confirm_reservation(@r);
SET timestamp = UNIX_TIMESTAMP('2026-04-18 18:21:00');
CALL seed_check_in_reservation(@r);

-- 2026-05-01 21:56:00 | Klasika pod zvijezdama | kupac 20 | confirmed | zastita
SET timestamp = UNIX_TIMESTAMP('2026-05-01 21:56:00');
CALL create_reservation(20, 3, '[{"category_id":6,"quantity":2}]', 1, @r);
SET timestamp = UNIX_TIMESTAMP('2026-05-01 22:05:00');
CALL confirm_reservation(@r);
SET timestamp = UNIX_TIMESTAMP('2026-07-10 20:11:00');
CALL seed_check_in_reservation(@r);

-- 2026-05-02 00:56:00 | Klasika pod zvijezdama | kupac 34 | refund
SET timestamp = UNIX_TIMESTAMP('2026-05-02 00:56:00');
CALL create_reservation(34, 3, '[{"category_id":5,"seats":[117,118]},{"category_id":6,"quantity":2}]', 0, @r);
SET timestamp = UNIX_TIMESTAMP('2026-05-02 01:04:00');
CALL confirm_reservation(@r);
SET timestamp = UNIX_TIMESTAMP('2026-07-05 15:08:00');
SELECT t.id INTO @t FROM ticket t JOIN reservation_seat rs ON rs.id = t.reservation_seat_id WHERE rs.seat_id = 117 AND rs.reservation_item_id IN (SELECT id FROM reservation_item WHERE reservation_id = @r);
CALL cancel_ticket(@t, @refund);
SET timestamp = UNIX_TIMESTAMP('2026-07-10 20:24:00');
CALL seed_check_in_reservation(@r);

-- 2026-05-05 17:57:00 | Klasika pod zvijezdama | kupac 23 | confirmed
SET timestamp = UNIX_TIMESTAMP('2026-05-05 17:57:00');
CALL create_reservation(23, 3, '[{"category_id":5,"seats":[63]}]', 0, @r);
SET timestamp = UNIX_TIMESTAMP('2026-05-05 18:04:00');
CALL confirm_reservation(@r);
SET timestamp = UNIX_TIMESTAMP('2026-07-10 20:27:00');
CALL seed_check_in_reservation(@r);

-- 2026-05-08 14:45:00 | Klasika pod zvijezdama | kupac 18 | confirmed
SET timestamp = UNIX_TIMESTAMP('2026-05-08 14:45:00');
CALL create_reservation(18, 3, '[{"category_id":6,"quantity":2}]', 0, @r);
SET timestamp = UNIX_TIMESTAMP('2026-05-08 14:48:00');
CALL confirm_reservation(@r);

-- 2026-05-16 06:05:00 | Klasika pod zvijezdama | kupac 28 | confirmed | zastita
SET timestamp = UNIX_TIMESTAMP('2026-05-16 06:05:00');
CALL create_reservation(28, 3, '[{"category_id":5,"seats":[65]}]', 1, @r);
SET timestamp = UNIX_TIMESTAMP('2026-05-16 06:13:00');
CALL confirm_reservation(@r);
SET timestamp = UNIX_TIMESTAMP('2026-07-10 20:48:00');
CALL seed_check_in_reservation(@r);

-- 2026-05-16 08:19:00 | Klasika pod zvijezdama | kupac 35 | expired
SET timestamp = UNIX_TIMESTAMP('2026-05-16 08:19:00');
CALL create_reservation(35, 3, '[{"category_id":5,"seats":[105]}]', 0, @r);
SET timestamp = UNIX_TIMESTAMP('2026-05-16 08:35:00');
CALL expire_reservations();

-- 2026-05-16 21:08:00 | Klasika pod zvijezdama | kupac 16 | refund | zastita
SET timestamp = UNIX_TIMESTAMP('2026-05-16 21:08:00');
CALL create_reservation(16, 3, '[{"category_id":6,"quantity":1},{"category_id":5,"seats":[66,67,68]}]', 1, @r);
SET timestamp = UNIX_TIMESTAMP('2026-05-16 21:15:00');
CALL confirm_reservation(@r);
SET timestamp = UNIX_TIMESTAMP('2026-06-10 12:48:00');
SELECT MIN(t.id) INTO @t FROM ticket t JOIN reservation_item ri ON ri.id = t.reservation_item_id WHERE ri.reservation_id = @r AND ri.category_id = 6;
CALL cancel_ticket(@t, @refund);

-- 2026-05-19 01:33:00 | Klasika pod zvijezdama | kupac 27 | cancel_pending | zastita
SET timestamp = UNIX_TIMESTAMP('2026-05-19 01:33:00');
CALL create_reservation(27, 3, '[{"category_id":6,"quantity":1}]', 1, @r);
SET timestamp = UNIX_TIMESTAMP('2026-05-19 01:43:00');
CALL cancel_reservation(@r);

-- 2026-05-19 05:05:00 | Klasika pod zvijezdama | kupac 38 | expired | zastita
SET timestamp = UNIX_TIMESTAMP('2026-05-19 05:05:00');
CALL create_reservation(38, 3, '[{"category_id":6,"quantity":1},{"category_id":5,"seats":[119]}]', 1, @r);
SET timestamp = UNIX_TIMESTAMP('2026-05-19 05:21:00');
CALL expire_reservations();

-- 2026-05-23 12:26:00 | Klasika pod zvijezdama | kupac 2 | expired | zastita
SET timestamp = UNIX_TIMESTAMP('2026-05-23 12:26:00');
CALL create_reservation(2, 3, '[{"category_id":6,"quantity":2},{"category_id":5,"seats":[115]}]', 1, @r);
SET timestamp = UNIX_TIMESTAMP('2026-05-23 12:42:00');
CALL expire_reservations();

-- 2026-05-27 07:24:00 | Klasika pod zvijezdama | kupac 11 | confirmed
SET timestamp = UNIX_TIMESTAMP('2026-05-27 07:24:00');
CALL create_reservation(11, 3, '[{"category_id":6,"quantity":3}]', 0, @r);
SET timestamp = UNIX_TIMESTAMP('2026-05-27 07:26:00');
CALL confirm_reservation(@r);
SET timestamp = UNIX_TIMESTAMP('2026-07-10 20:46:00');
CALL seed_check_in_reservation(@r);

-- 2026-05-28 17:42:00 | Klasika pod zvijezdama | kupac 3 | refund
SET timestamp = UNIX_TIMESTAMP('2026-05-28 17:42:00');
CALL create_reservation(3, 3, '[{"category_id":6,"quantity":1}]', 0, @r);
SET timestamp = UNIX_TIMESTAMP('2026-05-28 17:46:00');
CALL confirm_reservation(@r);
SET timestamp = UNIX_TIMESTAMP('2026-06-04 01:50:00');
SELECT MIN(t.id) INTO @t FROM ticket t JOIN reservation_item ri ON ri.id = t.reservation_item_id WHERE ri.reservation_id = @r AND ri.category_id = 6;
CALL cancel_ticket(@t, @refund);
SET timestamp = UNIX_TIMESTAMP('2026-07-10 20:54:00');
CALL seed_check_in_reservation(@r);

-- 2026-05-31 00:48:00 | Klasika pod zvijezdama | kupac 33 | confirmed
SET timestamp = UNIX_TIMESTAMP('2026-05-31 00:48:00');
CALL create_reservation(33, 3, '[{"category_id":6,"quantity":1},{"category_id":5,"seats":[88]}]', 0, @r);
SET timestamp = UNIX_TIMESTAMP('2026-05-31 00:53:00');
CALL confirm_reservation(@r);
SET timestamp = UNIX_TIMESTAMP('2026-07-10 20:54:00');
CALL seed_check_in_reservation(@r);

-- 2026-06-02 22:25:00 | Klasika pod zvijezdama | kupac 40 | expired
SET timestamp = UNIX_TIMESTAMP('2026-06-02 22:25:00');
CALL create_reservation(40, 3, '[{"category_id":6,"quantity":2}]', 0, @r);
SET timestamp = UNIX_TIMESTAMP('2026-06-02 22:41:00');
CALL expire_reservations();

-- 2026-06-04 10:30:00 | Klasika pod zvijezdama | kupac 21 | confirmed
SET timestamp = UNIX_TIMESTAMP('2026-06-04 10:30:00');
CALL create_reservation(21, 3, '[{"category_id":6,"quantity":1},{"category_id":5,"seats":[114]}]', 0, @r);
SET timestamp = UNIX_TIMESTAMP('2026-06-04 10:38:00');
CALL confirm_reservation(@r);
SET timestamp = UNIX_TIMESTAMP('2026-07-10 20:51:00');
CALL seed_check_in_reservation(@r);

-- 2026-06-05 05:07:00 | Klasika pod zvijezdama | kupac 36 | refund
SET timestamp = UNIX_TIMESTAMP('2026-06-05 05:07:00');
CALL create_reservation(36, 3, '[{"category_id":5,"seats":[90,91,92,93]}]', 0, @r);
SET timestamp = UNIX_TIMESTAMP('2026-06-05 05:17:00');
CALL confirm_reservation(@r);
SET timestamp = UNIX_TIMESTAMP('2026-07-05 00:57:00');
SELECT t.id INTO @t FROM ticket t JOIN reservation_seat rs ON rs.id = t.reservation_seat_id WHERE rs.seat_id = 90 AND rs.reservation_item_id IN (SELECT id FROM reservation_item WHERE reservation_id = @r);
CALL cancel_ticket(@t, @refund);
SET timestamp = UNIX_TIMESTAMP('2026-07-10 20:23:00');
CALL seed_check_in_reservation(@r);

-- 2026-06-07 16:28:00 | Klasika pod zvijezdama | kupac 12 | confirmed
SET timestamp = UNIX_TIMESTAMP('2026-06-07 16:28:00');
CALL create_reservation(12, 3, '[{"category_id":6,"quantity":1},{"category_id":5,"seats":[117]}]', 0, @r);
SET timestamp = UNIX_TIMESTAMP('2026-06-07 16:40:00');
CALL confirm_reservation(@r);
SET timestamp = UNIX_TIMESTAMP('2026-07-10 20:26:00');
CALL seed_check_in_reservation(@r);

-- 2026-06-08 00:23:00 | Klasika pod zvijezdama | kupac 3 | refund
SET timestamp = UNIX_TIMESTAMP('2026-06-08 00:23:00');
CALL create_reservation(3, 3, '[{"category_id":6,"quantity":1},{"category_id":5,"seats":[100,101,102]}]', 0, @r);
SET timestamp = UNIX_TIMESTAMP('2026-06-08 00:31:00');
CALL confirm_reservation(@r);
SET timestamp = UNIX_TIMESTAMP('2026-06-29 17:09:00');
SELECT MIN(t.id) INTO @t FROM ticket t JOIN reservation_item ri ON ri.id = t.reservation_item_id WHERE ri.reservation_id = @r AND ri.category_id = 6;
CALL cancel_ticket(@t, @refund);
SET timestamp = UNIX_TIMESTAMP('2026-07-10 20:24:00');
CALL seed_check_in_reservation(@r);

-- 2026-06-08 06:34:00 | Klasika pod zvijezdama | kupac 37 | confirmed
SET timestamp = UNIX_TIMESTAMP('2026-06-08 06:34:00');
CALL create_reservation(37, 3, '[{"category_id":5,"seats":[71]}]', 0, @r);
SET timestamp = UNIX_TIMESTAMP('2026-06-08 06:41:00');
CALL confirm_reservation(@r);
SET timestamp = UNIX_TIMESTAMP('2026-07-10 20:51:00');
CALL seed_check_in_reservation(@r);

-- 2026-06-10 20:21:00 | Klasika pod zvijezdama | kupac 16 | expired | zastita
SET timestamp = UNIX_TIMESTAMP('2026-06-10 20:21:00');
CALL create_reservation(16, 3, '[{"category_id":6,"quantity":2}]', 1, @r);
SET timestamp = UNIX_TIMESTAMP('2026-06-10 20:37:00');
CALL expire_reservations();

-- 2026-06-15 13:35:00 | Klasika pod zvijezdama | kupac 23 | confirmed
SET timestamp = UNIX_TIMESTAMP('2026-06-15 13:35:00');
CALL create_reservation(23, 3, '[{"category_id":5,"seats":[112,113]}]', 0, @r);
SET timestamp = UNIX_TIMESTAMP('2026-06-15 13:45:00');
CALL confirm_reservation(@r);
SET timestamp = UNIX_TIMESTAMP('2026-07-10 20:23:00');
CALL seed_check_in_reservation(@r);

-- 2026-06-22 22:28:00 | Klasika pod zvijezdama | kupac 22 | confirmed | zastita
SET timestamp = UNIX_TIMESTAMP('2026-06-22 22:28:00');
CALL create_reservation(22, 3, '[{"category_id":5,"seats":[74]}]', 1, @r);
SET timestamp = UNIX_TIMESTAMP('2026-06-22 22:40:00');
CALL confirm_reservation(@r);
SET timestamp = UNIX_TIMESTAMP('2026-07-10 20:20:00');
CALL seed_check_in_reservation(@r);

-- 2026-06-25 08:00:00 | Klasika pod zvijezdama | kupac 1 | refund | zastita
SET timestamp = UNIX_TIMESTAMP('2026-06-25 08:00:00');
CALL create_reservation(1, 3, '[{"category_id":6,"quantity":1}]', 1, @r);
SET timestamp = UNIX_TIMESTAMP('2026-06-25 08:09:00');
CALL confirm_reservation(@r);
SET timestamp = UNIX_TIMESTAMP('2026-07-01 21:15:00');
SELECT MIN(t.id) INTO @t FROM ticket t JOIN reservation_item ri ON ri.id = t.reservation_item_id WHERE ri.reservation_id = @r AND ri.category_id = 6;
CALL cancel_ticket(@t, @refund);
SET timestamp = UNIX_TIMESTAMP('2026-07-10 20:26:00');
CALL seed_check_in_reservation(@r);

-- 2026-06-29 18:37:00 | Klasika pod zvijezdama | kupac 21 | cancel_pending
SET timestamp = UNIX_TIMESTAMP('2026-06-29 18:37:00');
CALL create_reservation(21, 3, '[{"category_id":5,"seats":[73,75]}]', 0, @r);
SET timestamp = UNIX_TIMESTAMP('2026-06-29 18:44:00');
CALL cancel_reservation(@r);

-- 2026-07-05 23:40:00 | Klasika pod zvijezdama | kupac 13 | refund
SET timestamp = UNIX_TIMESTAMP('2026-07-05 23:40:00');
CALL create_reservation(13, 3, '[{"category_id":5,"seats":[84,85]}]', 0, @r);
SET timestamp = UNIX_TIMESTAMP('2026-07-05 23:47:00');
CALL confirm_reservation(@r);
SET timestamp = UNIX_TIMESTAMP('2026-07-07 22:00:00');
SELECT t.id INTO @t FROM ticket t JOIN reservation_seat rs ON rs.id = t.reservation_seat_id WHERE rs.seat_id = 84 AND rs.reservation_item_id IN (SELECT id FROM reservation_item WHERE reservation_id = @r);
CALL cancel_ticket(@t, @refund);
SET timestamp = UNIX_TIMESTAMP('2026-07-10 20:25:00');
CALL seed_check_in_reservation(@r);

-- 2026-07-08 13:36:00 | Klasika pod zvijezdama | kupac 19 | confirmed | zastita
SET timestamp = UNIX_TIMESTAMP('2026-07-08 13:36:00');
CALL create_reservation(19, 3, '[{"category_id":6,"quantity":1},{"category_id":5,"seats":[72]}]', 1, @r);
SET timestamp = UNIX_TIMESTAMP('2026-07-08 13:39:00');
CALL confirm_reservation(@r);
SET timestamp = UNIX_TIMESTAMP('2026-07-10 20:32:00');
CALL seed_check_in_reservation(@r);

-- 2026-07-15 04:21:00 | Stand-up vecer | kupac 28 | confirmed | zastita
SET timestamp = UNIX_TIMESTAMP('2026-07-15 04:21:00');
CALL create_reservation(28, 4, '[{"category_id":7,"seats":[129]}]', 1, @r);
SET timestamp = UNIX_TIMESTAMP('2026-07-15 04:31:00');
CALL confirm_reservation(@r);
SET timestamp = UNIX_TIMESTAMP('2026-09-12 19:20:00');
CALL seed_check_in_reservation(@r);

-- 2026-07-16 14:47:00 | Stand-up vecer | kupac 30 | expired
SET timestamp = UNIX_TIMESTAMP('2026-07-16 14:47:00');
CALL create_reservation(30, 4, '[{"category_id":7,"seats":[157]}]', 0, @r);
SET timestamp = UNIX_TIMESTAMP('2026-07-16 15:03:00');
CALL expire_reservations();

-- 2026-07-20 06:51:00 | Stand-up vecer | kupac 31 | confirmed
SET timestamp = UNIX_TIMESTAMP('2026-07-20 06:51:00');
CALL create_reservation(31, 4, '[{"category_id":7,"seats":[143,144]}]', 0, @r);
SET timestamp = UNIX_TIMESTAMP('2026-07-20 07:03:00');
CALL confirm_reservation(@r);
SET timestamp = UNIX_TIMESTAMP('2026-09-12 19:33:00');
CALL seed_check_in_reservation(@r);

-- 2026-07-21 07:24:00 | Stand-up vecer | kupac 6 | cancel_pending
SET timestamp = UNIX_TIMESTAMP('2026-07-21 07:24:00');
CALL create_reservation(6, 4, '[{"category_id":7,"seats":[151,152]}]', 0, @r);
SET timestamp = UNIX_TIMESTAMP('2026-07-21 07:26:00');
CALL cancel_reservation(@r);

-- 2026-07-28 01:28:00 | Stand-up vecer | kupac 18 | confirmed | zastita
SET timestamp = UNIX_TIMESTAMP('2026-07-28 01:28:00');
CALL create_reservation(18, 4, '[{"category_id":7,"seats":[140,141]}]', 1, @r);
SET timestamp = UNIX_TIMESTAMP('2026-07-28 01:39:00');
CALL confirm_reservation(@r);
SET timestamp = UNIX_TIMESTAMP('2026-09-12 19:49:00');
CALL seed_check_in_reservation(@r);

-- 2026-07-28 14:31:00 | Stand-up vecer | kupac 31 | confirmed
SET timestamp = UNIX_TIMESTAMP('2026-07-28 14:31:00');
CALL create_reservation(31, 4, '[{"category_id":7,"seats":[158,159]}]', 0, @r);
SET timestamp = UNIX_TIMESTAMP('2026-07-28 14:36:00');
CALL confirm_reservation(@r);
SET timestamp = UNIX_TIMESTAMP('2026-09-12 19:25:00');
CALL seed_check_in_reservation(@r);

-- 2026-07-31 05:08:00 | Stand-up vecer | kupac 22 | confirmed
SET timestamp = UNIX_TIMESTAMP('2026-07-31 05:08:00');
CALL create_reservation(22, 4, '[{"category_id":7,"seats":[136,137]}]', 0, @r);
SET timestamp = UNIX_TIMESTAMP('2026-07-31 05:11:00');
CALL confirm_reservation(@r);
SET timestamp = UNIX_TIMESTAMP('2026-09-12 19:20:00');
CALL seed_check_in_reservation(@r);

-- 2026-08-02 08:58:00 | Ljetni festival Split | kupac 35 | confirmed
SET timestamp = UNIX_TIMESTAMP('2026-08-02 08:58:00');
CALL create_reservation(35, 8, '[{"category_id":12,"quantity":1}]', 0, @r);
SET timestamp = UNIX_TIMESTAMP('2026-08-02 09:04:00');
CALL confirm_reservation(@r);

-- 2026-08-03 19:37:00 | Novogodisnji koncert | kupac 25 | confirmed
SET timestamp = UNIX_TIMESTAMP('2026-08-03 19:37:00');
CALL create_reservation(25, 6, '[{"category_id":10,"seats":[196,197]}]', 0, @r);
SET timestamp = UNIX_TIMESTAMP('2026-08-03 19:48:00');
CALL confirm_reservation(@r);

-- 2026-08-03 23:19:00 | Stand-up vecer | kupac 15 | confirmed | zastita
SET timestamp = UNIX_TIMESTAMP('2026-08-03 23:19:00');
CALL create_reservation(15, 4, '[{"category_id":7,"seats":[147,148,149,150]}]', 1, @r);
SET timestamp = UNIX_TIMESTAMP('2026-08-03 23:31:00');
CALL confirm_reservation(@r);
SET timestamp = UNIX_TIMESTAMP('2026-09-12 19:54:00');
CALL seed_check_in_reservation(@r);

-- 2026-08-04 00:18:00 | Novogodisnji koncert | kupac 16 | confirmed
SET timestamp = UNIX_TIMESTAMP('2026-08-04 00:18:00');
CALL create_reservation(16, 6, '[{"category_id":9,"quantity":1}]', 0, @r);
SET timestamp = UNIX_TIMESTAMP('2026-08-04 00:22:00');
CALL confirm_reservation(@r);

-- 2026-08-06 09:02:00 | Stand-up vecer | kupac 6 | refund
SET timestamp = UNIX_TIMESTAMP('2026-08-06 09:02:00');
CALL create_reservation(6, 4, '[{"category_id":7,"seats":[130,131,132,133]}]', 0, @r);
SET timestamp = UNIX_TIMESTAMP('2026-08-06 09:08:00');
CALL confirm_reservation(@r);
SET timestamp = UNIX_TIMESTAMP('2026-08-23 21:03:00');
SELECT t.id INTO @t FROM ticket t JOIN reservation_seat rs ON rs.id = t.reservation_seat_id WHERE rs.seat_id = 130 AND rs.reservation_item_id IN (SELECT id FROM reservation_item WHERE reservation_id = @r);
CALL cancel_ticket(@t, @refund);
SET timestamp = UNIX_TIMESTAMP('2026-09-12 19:44:00');
CALL seed_check_in_reservation(@r);

-- 2026-08-07 01:05:00 | Novogodisnji koncert | kupac 14 | confirmed
SET timestamp = UNIX_TIMESTAMP('2026-08-07 01:05:00');
CALL create_reservation(14, 6, '[{"category_id":10,"seats":[165,166,167,168]}]', 0, @r);
SET timestamp = UNIX_TIMESTAMP('2026-08-07 01:09:00');
CALL confirm_reservation(@r);

-- 2026-08-07 05:39:00 | Novogodisnji koncert | kupac 27 | refund
SET timestamp = UNIX_TIMESTAMP('2026-08-07 05:39:00');
CALL create_reservation(27, 6, '[{"category_id":10,"seats":[200]},{"category_id":9,"quantity":1}]', 0, @r);
SET timestamp = UNIX_TIMESTAMP('2026-08-07 05:44:00');
CALL confirm_reservation(@r);
SET timestamp = UNIX_TIMESTAMP('2026-09-13 18:19:00');
SELECT t.id INTO @t FROM ticket t JOIN reservation_seat rs ON rs.id = t.reservation_seat_id WHERE rs.seat_id = 200 AND rs.reservation_item_id IN (SELECT id FROM reservation_item WHERE reservation_id = @r);
CALL cancel_ticket(@t, @refund);

-- 2026-08-07 16:40:00 | Novogodisnji koncert | kupac 33 | refund
SET timestamp = UNIX_TIMESTAMP('2026-08-07 16:40:00');
CALL create_reservation(33, 6, '[{"category_id":9,"quantity":2},{"category_id":10,"seats":[186]}]', 0, @r);
SET timestamp = UNIX_TIMESTAMP('2026-08-07 16:44:00');
CALL confirm_reservation(@r);
SET timestamp = UNIX_TIMESTAMP('2026-09-13 15:01:00');
SELECT MIN(t.id) INTO @t FROM ticket t JOIN reservation_item ri ON ri.id = t.reservation_item_id WHERE ri.reservation_id = @r AND ri.category_id = 9;
CALL cancel_ticket(@t, @refund);

-- 2026-08-08 04:37:00 | Ljetni festival Split | kupac 37 | confirmed
SET timestamp = UNIX_TIMESTAMP('2026-08-08 04:37:00');
CALL create_reservation(37, 8, '[{"category_id":12,"quantity":3}]', 0, @r);
SET timestamp = UNIX_TIMESTAMP('2026-08-08 04:44:00');
CALL confirm_reservation(@r);

-- 2026-08-10 18:14:00 | Ljetni festival Split | kupac 13 | confirmed | zastita
SET timestamp = UNIX_TIMESTAMP('2026-08-10 18:14:00');
CALL create_reservation(13, 8, '[{"category_id":13,"quantity":1},{"category_id":12,"quantity":1}]', 1, @r);
SET timestamp = UNIX_TIMESTAMP('2026-08-10 18:18:00');
CALL confirm_reservation(@r);

-- 2026-08-12 15:15:00 | Stand-up vecer | kupac 16 | confirmed
SET timestamp = UNIX_TIMESTAMP('2026-08-12 15:15:00');
CALL create_reservation(16, 4, '[{"category_id":7,"seats":[126]}]', 0, @r);
SET timestamp = UNIX_TIMESTAMP('2026-08-12 15:26:00');
CALL confirm_reservation(@r);
SET timestamp = UNIX_TIMESTAMP('2026-09-12 19:50:00');
CALL seed_check_in_reservation(@r);

-- 2026-08-14 01:43:00 | Stand-up vecer | kupac 37 | confirmed
SET timestamp = UNIX_TIMESTAMP('2026-08-14 01:43:00');
CALL create_reservation(37, 4, '[{"category_id":7,"seats":[134]}]', 0, @r);
SET timestamp = UNIX_TIMESTAMP('2026-08-14 01:52:00');
CALL confirm_reservation(@r);
SET timestamp = UNIX_TIMESTAMP('2026-09-12 19:24:00');
CALL seed_check_in_reservation(@r);

-- 2026-08-15 15:27:00 | Novogodisnji koncert | kupac 15 | confirmed
SET timestamp = UNIX_TIMESTAMP('2026-08-15 15:27:00');
CALL create_reservation(15, 6, '[{"category_id":9,"quantity":2}]', 0, @r);
SET timestamp = UNIX_TIMESTAMP('2026-08-15 15:33:00');
CALL confirm_reservation(@r);

-- 2026-08-16 21:36:00 | Novogodisnji koncert | kupac 20 | cancel_pending
SET timestamp = UNIX_TIMESTAMP('2026-08-16 21:36:00');
CALL create_reservation(20, 6, '[{"category_id":10,"seats":[188]}]', 0, @r);
SET timestamp = UNIX_TIMESTAMP('2026-08-16 21:44:00');
CALL cancel_reservation(@r);

-- 2026-08-22 03:53:00 | Novogodisnji koncert | kupac 30 | confirmed
SET timestamp = UNIX_TIMESTAMP('2026-08-22 03:53:00');
CALL create_reservation(30, 6, '[{"category_id":10,"seats":[199,200]},{"category_id":9,"quantity":1}]', 0, @r);
SET timestamp = UNIX_TIMESTAMP('2026-08-22 04:03:00');
CALL confirm_reservation(@r);

-- 2026-08-23 11:07:00 | Stand-up vecer | kupac 31 | refund
SET timestamp = UNIX_TIMESTAMP('2026-08-23 11:07:00');
CALL create_reservation(31, 4, '[{"category_id":7,"seats":[138,139,142,145]}]', 0, @r);
SET timestamp = UNIX_TIMESTAMP('2026-08-23 11:09:00');
CALL confirm_reservation(@r);
SET timestamp = UNIX_TIMESTAMP('2026-08-29 19:36:00');
SELECT t.id INTO @t FROM ticket t JOIN reservation_seat rs ON rs.id = t.reservation_seat_id WHERE rs.seat_id = 138 AND rs.reservation_item_id IN (SELECT id FROM reservation_item WHERE reservation_id = @r);
CALL cancel_ticket(@t, @refund);
SET timestamp = UNIX_TIMESTAMP('2026-09-12 19:17:00');
CALL seed_check_in_reservation(@r);

-- 2026-08-24 02:55:00 | Stand-up vecer | kupac 30 | expired
SET timestamp = UNIX_TIMESTAMP('2026-08-24 02:55:00');
CALL create_reservation(30, 4, '[{"category_id":7,"seats":[122]}]', 0, @r);
SET timestamp = UNIX_TIMESTAMP('2026-08-24 03:11:00');
CALL expire_reservations();

-- 2026-08-24 03:51:00 | Novogodisnji koncert | kupac 9 | confirmed
SET timestamp = UNIX_TIMESTAMP('2026-08-24 03:51:00');
CALL create_reservation(9, 6, '[{"category_id":10,"seats":[174]},{"category_id":9,"quantity":1}]', 0, @r);
SET timestamp = UNIX_TIMESTAMP('2026-08-24 03:56:00');
CALL confirm_reservation(@r);

-- 2026-08-24 14:56:00 | Ljetni festival Split | kupac 20 | confirmed
SET timestamp = UNIX_TIMESTAMP('2026-08-24 14:56:00');
CALL create_reservation(20, 8, '[{"category_id":13,"quantity":2},{"category_id":12,"quantity":1}]', 0, @r);
SET timestamp = UNIX_TIMESTAMP('2026-08-24 15:02:00');
CALL confirm_reservation(@r);

-- 2026-08-25 12:19:00 | Ljetni festival Split | kupac 31 | expired
SET timestamp = UNIX_TIMESTAMP('2026-08-25 12:19:00');
CALL create_reservation(31, 8, '[{"category_id":12,"quantity":1}]', 0, @r);
SET timestamp = UNIX_TIMESTAMP('2026-08-25 12:35:00');
CALL expire_reservations();

-- 2026-08-28 02:23:00 | Stand-up vecer | kupac 39 | refund
SET timestamp = UNIX_TIMESTAMP('2026-08-28 02:23:00');
CALL create_reservation(39, 4, '[{"category_id":7,"seats":[121,122]}]', 0, @r);
SET timestamp = UNIX_TIMESTAMP('2026-08-28 02:32:00');
CALL confirm_reservation(@r);
SET timestamp = UNIX_TIMESTAMP('2026-09-08 13:24:00');
SELECT t.id INTO @t FROM ticket t JOIN reservation_seat rs ON rs.id = t.reservation_seat_id WHERE rs.seat_id = 121 AND rs.reservation_item_id IN (SELECT id FROM reservation_item WHERE reservation_id = @r);
CALL cancel_ticket(@t, @refund);
SET timestamp = UNIX_TIMESTAMP('2026-09-12 19:31:00');
CALL seed_check_in_reservation(@r);

-- 2026-09-01 07:01:00 | Novogodisnji koncert | kupac 16 | confirmed
SET timestamp = UNIX_TIMESTAMP('2026-09-01 07:01:00');
CALL create_reservation(16, 6, '[{"category_id":10,"seats":[163,164,169]},{"category_id":9,"quantity":1}]', 0, @r);
SET timestamp = UNIX_TIMESTAMP('2026-09-01 07:09:00');
CALL confirm_reservation(@r);

-- 2026-09-02 07:35:00 | Stand-up vecer | kupac 33 | expired
SET timestamp = UNIX_TIMESTAMP('2026-09-02 07:35:00');
CALL create_reservation(33, 4, '[{"category_id":7,"seats":[123,124]}]', 0, @r);
SET timestamp = UNIX_TIMESTAMP('2026-09-02 07:51:00');
CALL expire_reservations();

-- 2026-09-03 10:15:00 | Jesenski indie koncert | kupac 3 | expired
SET timestamp = UNIX_TIMESTAMP('2026-09-03 10:15:00');
CALL create_reservation(3, 5, '[{"category_id":8,"quantity":2}]', 0, @r);
SET timestamp = UNIX_TIMESTAMP('2026-09-03 10:31:00');
CALL expire_reservations();

-- 2026-09-04 03:46:00 | Ljetni festival Split | kupac 30 | confirmed
SET timestamp = UNIX_TIMESTAMP('2026-09-04 03:46:00');
CALL create_reservation(30, 8, '[{"category_id":12,"quantity":1},{"category_id":13,"quantity":1}]', 0, @r);
SET timestamp = UNIX_TIMESTAMP('2026-09-04 03:55:00');
CALL confirm_reservation(@r);

-- 2026-09-04 17:51:00 | Stand-up vecer | kupac 18 | confirmed
SET timestamp = UNIX_TIMESTAMP('2026-09-04 17:51:00');
CALL create_reservation(18, 4, '[{"category_id":7,"seats":[155,156,157,160]}]', 0, @r);
SET timestamp = UNIX_TIMESTAMP('2026-09-04 17:54:00');
CALL confirm_reservation(@r);

-- 2026-09-05 18:40:00 | Jesenski indie koncert | kupac 7 | confirmed
SET timestamp = UNIX_TIMESTAMP('2026-09-05 18:40:00');
CALL create_reservation(7, 5, '[{"category_id":8,"quantity":4}]', 0, @r);
SET timestamp = UNIX_TIMESTAMP('2026-09-05 18:51:00');
CALL confirm_reservation(@r);

-- 2026-09-06 19:06:00 | Ljetni festival Split | kupac 22 | confirmed
SET timestamp = UNIX_TIMESTAMP('2026-09-06 19:06:00');
CALL create_reservation(22, 8, '[{"category_id":12,"quantity":1}]', 0, @r);
SET timestamp = UNIX_TIMESTAMP('2026-09-06 19:18:00');
CALL confirm_reservation(@r);

-- 2026-09-09 12:05:00 | Jesenski indie koncert | kupac 11 | confirmed | zastita
SET timestamp = UNIX_TIMESTAMP('2026-09-09 12:05:00');
CALL create_reservation(11, 5, '[{"category_id":8,"quantity":4}]', 1, @r);
SET timestamp = UNIX_TIMESTAMP('2026-09-09 12:13:00');
CALL confirm_reservation(@r);

-- 2026-09-13 12:19:00 | Ljetni festival Split | kupac 2 | refund
SET timestamp = UNIX_TIMESTAMP('2026-09-13 12:19:00');
CALL create_reservation(2, 8, '[{"category_id":12,"quantity":1}]', 0, @r);
SET timestamp = UNIX_TIMESTAMP('2026-09-13 12:27:00');
CALL confirm_reservation(@r);
SET timestamp = UNIX_TIMESTAMP('2026-09-15 12:44:00');
SELECT MIN(t.id) INTO @t FROM ticket t JOIN reservation_item ri ON ri.id = t.reservation_item_id WHERE ri.reservation_id = @r AND ri.category_id = 12;
CALL cancel_ticket(@t, @refund);

-- 2026-09-13 18:26:00 | Novogodisnji koncert | kupac 16 | confirmed
SET timestamp = UNIX_TIMESTAMP('2026-09-13 18:26:00');
CALL create_reservation(16, 6, '[{"category_id":9,"quantity":2},{"category_id":10,"seats":[195,198]}]', 0, @r);
SET timestamp = UNIX_TIMESTAMP('2026-09-13 18:37:00');
CALL confirm_reservation(@r);

-- 2026-09-14 03:31:00 | Novogodisnji koncert | kupac 21 | confirmed
SET timestamp = UNIX_TIMESTAMP('2026-09-14 03:31:00');
CALL create_reservation(21, 6, '[{"category_id":9,"quantity":2}]', 0, @r);
SET timestamp = UNIX_TIMESTAMP('2026-09-14 03:34:00');
CALL confirm_reservation(@r);

-- 2026-09-14 19:50:00 | Novogodisnji koncert | kupac 12 | confirmed
SET timestamp = UNIX_TIMESTAMP('2026-09-14 19:50:00');
CALL create_reservation(12, 6, '[{"category_id":9,"quantity":1}]', 0, @r);
SET timestamp = UNIX_TIMESTAMP('2026-09-14 19:55:00');
CALL confirm_reservation(@r);

-- 2026-09-14 21:30:00 | Jesenski indie koncert | kupac 15 | cancel_pending
SET timestamp = UNIX_TIMESTAMP('2026-09-14 21:30:00');
CALL create_reservation(15, 5, '[{"category_id":8,"quantity":1}]', 0, @r);
SET timestamp = UNIX_TIMESTAMP('2026-09-14 21:38:00');
CALL cancel_reservation(@r);

-- 2026-09-15 13:46:00 | Ljetni festival Split | kupac 31 | confirmed
SET timestamp = UNIX_TIMESTAMP('2026-09-15 13:46:00');
CALL create_reservation(31, 8, '[{"category_id":12,"quantity":1},{"category_id":13,"quantity":1}]', 0, @r);
SET timestamp = UNIX_TIMESTAMP('2026-09-15 13:54:00');
CALL confirm_reservation(@r);

-- 2026-09-16 07:26:00 | Novogodisnji koncert | kupac 1 | confirmed
SET timestamp = UNIX_TIMESTAMP('2026-09-16 07:26:00');
CALL create_reservation(1, 6, '[{"category_id":9,"quantity":2}]', 0, @r);
SET timestamp = UNIX_TIMESTAMP('2026-09-16 07:31:00');
CALL confirm_reservation(@r);

-- 2026-09-16 22:37:00 | Novogodisnji koncert | kupac 30 | confirmed
SET timestamp = UNIX_TIMESTAMP('2026-09-16 22:37:00');
CALL create_reservation(30, 6, '[{"category_id":9,"quantity":1},{"category_id":10,"seats":[170]}]', 0, @r);
SET timestamp = UNIX_TIMESTAMP('2026-09-16 22:47:00');
CALL confirm_reservation(@r);

-- 2026-09-17 08:04:00 | Ljetni festival Split | kupac 14 | confirmed
SET timestamp = UNIX_TIMESTAMP('2026-09-17 08:04:00');
CALL create_reservation(14, 8, '[{"category_id":13,"quantity":1},{"category_id":12,"quantity":1}]', 0, @r);
SET timestamp = UNIX_TIMESTAMP('2026-09-17 08:11:00');
CALL confirm_reservation(@r);

-- 2026-09-20 03:49:00 | Ljetni festival Split | kupac 13 | confirmed | zastita
SET timestamp = UNIX_TIMESTAMP('2026-09-20 03:49:00');
CALL create_reservation(13, 8, '[{"category_id":12,"quantity":1}]', 1, @r);
SET timestamp = UNIX_TIMESTAMP('2026-09-20 03:54:00');
CALL confirm_reservation(@r);

-- 2026-09-20 09:50:00 | Jesenski indie koncert | kupac 19 | confirmed
SET timestamp = UNIX_TIMESTAMP('2026-09-20 09:50:00');
CALL create_reservation(19, 5, '[{"category_id":8,"quantity":4}]', 0, @r);
SET timestamp = UNIX_TIMESTAMP('2026-09-20 09:53:00');
CALL confirm_reservation(@r);

-- 2026-09-20 15:45:00 | Novogodisnji koncert | kupac 18 | confirmed
SET timestamp = UNIX_TIMESTAMP('2026-09-20 15:45:00');
CALL create_reservation(18, 6, '[{"category_id":10,"seats":[176,177]}]', 0, @r);
SET timestamp = UNIX_TIMESTAMP('2026-09-20 15:49:00');
CALL confirm_reservation(@r);

-- 2026-09-21 13:08:00 | Ljetni festival Split | kupac 23 | confirmed
SET timestamp = UNIX_TIMESTAMP('2026-09-21 13:08:00');
CALL create_reservation(23, 8, '[{"category_id":13,"quantity":1},{"category_id":12,"quantity":1}]', 0, @r);
SET timestamp = UNIX_TIMESTAMP('2026-09-21 13:12:00');
CALL confirm_reservation(@r);

-- 2026-09-23 17:25:00 | Ljetni festival Split | kupac 19 | expired
SET timestamp = UNIX_TIMESTAMP('2026-09-23 17:25:00');
CALL create_reservation(19, 8, '[{"category_id":12,"quantity":2},{"category_id":13,"quantity":1}]', 0, @r);
SET timestamp = UNIX_TIMESTAMP('2026-09-23 17:41:00');
CALL expire_reservations();

-- 2026-09-23 21:39:00 | Ljetni festival Split | kupac 16 | confirmed
SET timestamp = UNIX_TIMESTAMP('2026-09-23 21:39:00');
CALL create_reservation(16, 8, '[{"category_id":12,"quantity":3}]', 0, @r);
SET timestamp = UNIX_TIMESTAMP('2026-09-23 21:50:00');
CALL confirm_reservation(@r);

-- 2026-09-24 04:24:00 | Ljetni festival Split | kupac 27 | confirmed
SET timestamp = UNIX_TIMESTAMP('2026-09-24 04:24:00');
CALL create_reservation(27, 8, '[{"category_id":12,"quantity":2}]', 0, @r);
SET timestamp = UNIX_TIMESTAMP('2026-09-24 04:28:00');
CALL confirm_reservation(@r);

-- 2026-09-25 21:42:00 | Novogodisnji koncert | kupac 25 | expired
SET timestamp = UNIX_TIMESTAMP('2026-09-25 21:42:00');
CALL create_reservation(25, 6, '[{"category_id":9,"quantity":1},{"category_id":10,"seats":[188]}]', 0, @r);
SET timestamp = UNIX_TIMESTAMP('2026-09-25 21:58:00');
CALL expire_reservations();

-- 2026-09-26 17:00:00 | Novogodisnji koncert | kupac 2 | expired
SET timestamp = UNIX_TIMESTAMP('2026-09-26 17:00:00');
CALL create_reservation(2, 6, '[{"category_id":9,"quantity":3},{"category_id":10,"seats":[180]}]', 0, @r);
SET timestamp = UNIX_TIMESTAMP('2026-09-26 17:16:00');
CALL expire_reservations();

-- 2026-09-27 11:41:00 | Novogodisnji koncert | kupac 16 | confirmed
SET timestamp = UNIX_TIMESTAMP('2026-09-27 11:41:00');
CALL create_reservation(16, 6, '[{"category_id":10,"seats":[189]}]', 0, @r);
SET timestamp = UNIX_TIMESTAMP('2026-09-27 11:44:00');
CALL confirm_reservation(@r);

-- 2026-09-28 13:40:00 | Novogodisnji koncert | kupac 15 | confirmed | zastita
SET timestamp = UNIX_TIMESTAMP('2026-09-28 13:40:00');
CALL create_reservation(15, 6, '[{"category_id":9,"quantity":2}]', 1, @r);
SET timestamp = UNIX_TIMESTAMP('2026-09-28 13:49:00');
CALL confirm_reservation(@r);

-- 2026-09-28 19:49:00 | Novogodisnji koncert | kupac 39 | confirmed
SET timestamp = UNIX_TIMESTAMP('2026-09-28 19:49:00');
CALL create_reservation(39, 6, '[{"category_id":10,"seats":[183]},{"category_id":9,"quantity":2}]', 0, @r);
SET timestamp = UNIX_TIMESTAMP('2026-09-28 19:55:00');
CALL confirm_reservation(@r);

-- 2026-09-30 09:57:00 | Novogodisnji koncert | kupac 35 | confirmed
SET timestamp = UNIX_TIMESTAMP('2026-09-30 09:57:00');
CALL create_reservation(35, 6, '[{"category_id":10,"seats":[194]}]', 0, @r);
SET timestamp = UNIX_TIMESTAMP('2026-09-30 10:08:00');
CALL confirm_reservation(@r);

-- 2026-10-02 16:20:00 | Jesenski indie koncert | kupac 23 | confirmed
SET timestamp = UNIX_TIMESTAMP('2026-10-02 16:20:00');
CALL create_reservation(23, 5, '[{"category_id":8,"quantity":4}]', 0, @r);
SET timestamp = UNIX_TIMESTAMP('2026-10-02 16:30:00');
CALL confirm_reservation(@r);

-- 2026-10-03 02:56:00 | Novogodisnji koncert | kupac 5 | confirmed
SET timestamp = UNIX_TIMESTAMP('2026-10-03 02:56:00');
CALL create_reservation(5, 6, '[{"category_id":9,"quantity":4}]', 0, @r);
SET timestamp = UNIX_TIMESTAMP('2026-10-03 03:07:00');
CALL confirm_reservation(@r);

-- 2026-10-04 08:54:00 | Novogodisnji koncert | kupac 2 | confirmed
SET timestamp = UNIX_TIMESTAMP('2026-10-04 08:54:00');
CALL create_reservation(2, 6, '[{"category_id":10,"seats":[193]}]', 0, @r);
SET timestamp = UNIX_TIMESTAMP('2026-10-04 09:06:00');
CALL confirm_reservation(@r);

-- 2026-10-06 10:26:00 | Novogodisnji koncert | kupac 39 | confirmed | zastita
SET timestamp = UNIX_TIMESTAMP('2026-10-06 10:26:00');
CALL create_reservation(39, 6, '[{"category_id":10,"seats":[190,191,192]},{"category_id":9,"quantity":1}]', 1, @r);
SET timestamp = UNIX_TIMESTAMP('2026-10-06 10:36:00');
CALL confirm_reservation(@r);

-- 2026-10-10 00:42:00 | Ljetni festival Split | kupac 13 | confirmed | zastita
SET timestamp = UNIX_TIMESTAMP('2026-10-10 00:42:00');
CALL create_reservation(13, 8, '[{"category_id":13,"quantity":1},{"category_id":12,"quantity":1}]', 1, @r);
SET timestamp = UNIX_TIMESTAMP('2026-10-10 00:51:00');
CALL confirm_reservation(@r);

-- 2026-10-10 07:27:00 | Novogodisnji koncert | kupac 11 | cancel_pending
SET timestamp = UNIX_TIMESTAMP('2026-10-10 07:27:00');
CALL create_reservation(11, 6, '[{"category_id":10,"seats":[184,185,187]},{"category_id":9,"quantity":1}]', 0, @r);
SET timestamp = UNIX_TIMESTAMP('2026-10-10 07:30:00');
CALL cancel_reservation(@r);

-- 2026-10-10 08:24:00 | Ljetni festival Split | kupac 38 | confirmed
SET timestamp = UNIX_TIMESTAMP('2026-10-10 08:24:00');
CALL create_reservation(38, 8, '[{"category_id":13,"quantity":1},{"category_id":12,"quantity":3}]', 0, @r);
SET timestamp = UNIX_TIMESTAMP('2026-10-10 08:29:00');
CALL confirm_reservation(@r);

-- 2026-10-11 11:00:00 | Jesenski indie koncert | kupac 27 | confirmed
SET timestamp = UNIX_TIMESTAMP('2026-10-11 11:00:00');
CALL create_reservation(27, 5, '[{"category_id":8,"quantity":3}]', 0, @r);
SET timestamp = UNIX_TIMESTAMP('2026-10-11 11:09:00');
CALL confirm_reservation(@r);

-- 2026-10-12 17:21:00 | Novogodisnji koncert | kupac 35 | confirmed
SET timestamp = UNIX_TIMESTAMP('2026-10-12 17:21:00');
CALL create_reservation(35, 6, '[{"category_id":9,"quantity":1}]', 0, @r);
SET timestamp = UNIX_TIMESTAMP('2026-10-12 17:28:00');
CALL confirm_reservation(@r);

-- 2026-10-13 00:18:00 | Novogodisnji koncert | kupac 27 | confirmed
SET timestamp = UNIX_TIMESTAMP('2026-10-13 00:18:00');
CALL create_reservation(27, 6, '[{"category_id":9,"quantity":2}]', 0, @r);
SET timestamp = UNIX_TIMESTAMP('2026-10-13 00:26:00');
CALL confirm_reservation(@r);

-- 2026-10-13 02:07:00 | Ljetni festival Split | kupac 32 | confirmed
SET timestamp = UNIX_TIMESTAMP('2026-10-13 02:07:00');
CALL create_reservation(32, 8, '[{"category_id":12,"quantity":1}]', 0, @r);
SET timestamp = UNIX_TIMESTAMP('2026-10-13 02:19:00');
CALL confirm_reservation(@r);

-- 2026-10-14 00:01:00 | Ljetni festival Split | kupac 12 | confirmed | zastita
SET timestamp = UNIX_TIMESTAMP('2026-10-14 00:01:00');
CALL create_reservation(12, 8, '[{"category_id":13,"quantity":1}]', 1, @r);
SET timestamp = UNIX_TIMESTAMP('2026-10-14 00:04:00');
CALL confirm_reservation(@r);

-- 2026-10-15 07:29:00 | Ljetni festival Split | kupac 34 | confirmed
SET timestamp = UNIX_TIMESTAMP('2026-10-15 07:29:00');
CALL create_reservation(34, 8, '[{"category_id":12,"quantity":1},{"category_id":13,"quantity":1}]', 0, @r);
SET timestamp = UNIX_TIMESTAMP('2026-10-15 07:39:00');
CALL confirm_reservation(@r);

-- 2026-10-15 23:40:00 | Novogodisnji koncert | kupac 3 | expired
SET timestamp = UNIX_TIMESTAMP('2026-10-15 23:40:00');
CALL create_reservation(3, 6, '[{"category_id":9,"quantity":2}]', 0, @r);
SET timestamp = UNIX_TIMESTAMP('2026-10-15 23:56:00');
CALL expire_reservations();

-- 2026-10-18 18:05:00 | Ljetni festival Split | kupac 37 | confirmed | zastita
SET timestamp = UNIX_TIMESTAMP('2026-10-18 18:05:00');
CALL create_reservation(37, 8, '[{"category_id":12,"quantity":1},{"category_id":13,"quantity":1}]', 1, @r);
SET timestamp = UNIX_TIMESTAMP('2026-10-18 18:12:00');
CALL confirm_reservation(@r);

-- 2026-10-19 20:10:00 | Novogodisnji koncert | kupac 32 | cancel_pending
SET timestamp = UNIX_TIMESTAMP('2026-10-19 20:10:00');
CALL create_reservation(32, 6, '[{"category_id":10,"seats":[188]}]', 0, @r);
SET timestamp = UNIX_TIMESTAMP('2026-10-19 20:17:00');
CALL cancel_reservation(@r);

-- 2026-10-25 11:17:00 | Ljetni festival Split | kupac 39 | confirmed
SET timestamp = UNIX_TIMESTAMP('2026-10-25 11:17:00');
CALL create_reservation(39, 8, '[{"category_id":12,"quantity":3}]', 0, @r);
SET timestamp = UNIX_TIMESTAMP('2026-10-25 11:29:00');
CALL confirm_reservation(@r);

-- 2026-10-26 13:31:00 | Novogodisnji koncert | kupac 30 | confirmed | zastita
SET timestamp = UNIX_TIMESTAMP('2026-10-26 13:31:00');
CALL create_reservation(30, 6, '[{"category_id":9,"quantity":1},{"category_id":10,"seats":[181,182]}]', 1, @r);
SET timestamp = UNIX_TIMESTAMP('2026-10-26 13:34:00');
CALL confirm_reservation(@r);

-- 2026-10-26 13:40:00 | Novogodisnji koncert | kupac 27 | confirmed
SET timestamp = UNIX_TIMESTAMP('2026-10-26 13:40:00');
CALL create_reservation(27, 6, '[{"category_id":9,"quantity":2}]', 0, @r);
SET timestamp = UNIX_TIMESTAMP('2026-10-26 13:52:00');
CALL confirm_reservation(@r);

-- ---------------------------------------------------------------------
-- Kraj: vrati stvarno vrijeme, ukljuci scheduler, pocisti pomocne procedure
-- ---------------------------------------------------------------------
SET timestamp = DEFAULT;
ALTER EVENT ev_expire_reservations ENABLE;
DROP PROCEDURE seed_check_in_reservation;
DROP PROCEDURE seed_assert_empty;

-- Kontrola: brojaci moraju biti uskladeni (ocekivano: 0)
SELECT COUNT(*) AS neuskladjeni_brojaci FROM v_reserved_check;

-- Sazetak
SELECT
  (SELECT COUNT(*) FROM event)                                    AS eventi,
  (SELECT COUNT(*) FROM buyer)                                    AS kupci,
  (SELECT COUNT(*) FROM reservation)                              AS rezervacije,
  (SELECT COUNT(*) FROM reservation WHERE status = 'confirmed')   AS potvrdene,
  (SELECT COUNT(*) FROM reservation WHERE cancel_reason = 'buyer')   AS otkazane_kupac,
  (SELECT COUNT(*) FROM reservation WHERE cancel_reason = 'expired') AS istekle,
  (SELECT COUNT(*) FROM ticket)                                   AS karte,
  (SELECT COUNT(*) FROM ticket WHERE cancelled_at IS NOT NULL)    AS povrati,
  (SELECT COUNT(*) FROM ticket WHERE checked_in_at IS NOT NULL)   AS check_in;
