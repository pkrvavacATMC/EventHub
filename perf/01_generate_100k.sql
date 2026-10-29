-- =====================================================================
-- EventHub - perf/01_generate_100k.sql : veliki skup podataka za task 7
--
-- Generira 100.000 rezervacija (~190.000 karata) na 50 evenata kroz 2025.-2026.
--
-- Radi SAMO nad zasebnom bazom eventhub_perf (kopija seed baze), tako da
-- baza "eventhub" uvijek ostaje sa 175 realnih rezervacija za task 4.
--
-- Pokretanje (nakon seeda):
--   1. bash perf/00_create_perf_db.sh        (napravi eventhub_perf kao kopiju eventhub)
--   2. docker exec -i eventhub-db sh -c 'mariadb -uroot -p"$MARIADB_ROOT_PASSWORD"' < perf/01_generate_100k.sql
--
-- Ponovno pokretanje: skripta odbija raditi ako PERF podaci vec postoje.
-- Za svjezu kopiju samo ponovno pokreni korak 1.
--
-- Zasto masovni INSERT ... SELECT, a ne pozivi procedura:
--  * 100.000 x (create + confirm) poziva trajalo bi puno dulje.
--  * Masovni unos i dalje prolazi kroz SVE triggere, CHECK-ove i strane kljuceve
--    (npr. karte se mogu izdati samo potvrdenoj rezervaciji, max 4 karte...).
--  * Brojac "reserved" se na kraju postavlja iz stvarnih karata i provjerava
--    kroz v_reserved_check.
--
-- Raspodjela (deterministicka, preko CRC32 - svako pokretanje daje iste podatke):
--  * 70 % potvrdeno, 5 % potvrdeno pa jedna karta vracena,
--    10 % otkazao kupac, 15 % isteklo
--  * 1-4 karte po rezervaciji, 25 % sa zastitom od povrata
--  * prosli eventi: ~85 % vazecih karata ima check-in
-- =====================================================================
USE eventhub_perf;
SET time_zone = '+00:00';

-- Zastita: ne pokreci dvaput (i nista ne mijenjaj prije ove provjere)
DELIMITER //
BEGIN NOT ATOMIC
  IF EXISTS (SELECT 1 FROM city WHERE name = 'PERF Grad') THEN
    SIGNAL SQLSTATE '45000'
      SET MESSAGE_TEXT = 'PERF podaci vec postoje. Za svjezu kopiju pokreni perf/00_create_perf_db.sh';
  END IF;
END//
DELIMITER ;

-- U kopiji za performanse scheduler za istek ne treba raditi (ostaje iskljucen)
ALTER EVENT ev_expire_reservations DISABLE;
SET @t_start = SYSDATE(6);          -- SYSDATE = stvarno vrijeme (NOW() mijenjamo sa SET timestamp)

-- ---------------------------------------------------------------------
-- 1. Maticni podaci (stanje 1.1.2025.)
-- ---------------------------------------------------------------------
SET timestamp = UNIX_TIMESTAMP('2025-01-01 08:00:00');

INSERT INTO city (name) VALUES ('PERF Grad');
SET @city = LAST_INSERT_ID();
INSERT INTO location (name, city_id, capacity) VALUES ('PERF Dvorana', @city, 10000);
SET @loc = LAST_INSERT_ID();

INSERT INTO organizer (name, email)
SELECT CONCAT('PERF Organizator ', seq), CONCAT('perf.org', seq, '@example.com') FROM seq_1_to_5;
SET @org0 = LAST_INSERT_ID() - 1;          -- organizator n = @org0 + n

INSERT INTO buyer (name, surname, email, address, city_id)
SELECT 'Kupac', CONCAT('Perf', seq), CONCAT('perf.kupac', seq, '@example.com'), NULL, @city
  FROM seq_1_to_5000;
SET @buyer0 = LAST_INSERT_ID() - 1;        -- kupac n = @buyer0 + n

-- 50 evenata, svakih 13 dana od 1.3.2025. (zadnji u prosincu 2026.)
INSERT INTO event (name, event_date, capacity, location_id, organizer_id, event_type_id)
SELECT CONCAT('PERF Event ', LPAD(seq, 2, '0')),
       TIMESTAMP('2025-03-01 20:00:00') + INTERVAL (seq - 1) * 13 DAY,
       6000, @loc, @org0 + 1 + (seq % 5), (SELECT id FROM event_type WHERE code = 'other')
  FROM seq_1_to_50;
SET @ev0 = LAST_INSERT_ID() - 1;           -- event n = @ev0 + n

-- Dvije stajace kategorije po eventu
INSERT INTO ticket_category (event_id, name, price, service_fee, capacity, seating_type)
SELECT @ev0 + seq, 'Parter', 20 + (seq % 5) * 10, 2, 5000, 'standing' FROM seq_1_to_50;
INSERT INTO ticket_category (event_id, name, price, service_fee, capacity, seating_type)
SELECT @ev0 + seq, 'Balkon', 15 + (seq % 3) * 5, 1, 1000, 'standing' FROM seq_1_to_50;

-- ---------------------------------------------------------------------
-- 2. Plan rezervacija (privremena tablica)
-- ---------------------------------------------------------------------
DROP TEMPORARY TABLE IF EXISTS tmp_perf;
CREATE TEMPORARY TABLE tmp_perf (
  seq INT PRIMARY KEY, event_id INT, event_date DATETIME, category_id INT, buyer_id INT,
  qty INT, price DECIMAL(10,2), fee DECIMAL(10,2), protect TINYINT, protect_fee DECIMAL(10,2),
  created_at DATETIME, outcome VARCHAR(10), res_id INT
) ENGINE=InnoDB;

INSERT INTO tmp_perf (seq, event_id, buyer_id, qty, protect, outcome, category_id)
SELECT s.seq,
       @ev0 + 1 + CRC32(CONCAT('e', s.seq)) % 50,
       @buyer0 + 1 + CRC32(CONCAT('b', s.seq)) % 5000,
       1 + CRC32(CONCAT('q', s.seq)) % 4,
       CRC32(CONCAT('p', s.seq)) % 4 = 0,
       CASE WHEN CRC32(CONCAT('o', s.seq)) % 100 < 70 THEN 'confirmed'
            WHEN CRC32(CONCAT('o', s.seq)) % 100 < 75 THEN 'refund'
            WHEN CRC32(CONCAT('o', s.seq)) % 100 < 85 THEN 'buyer'
            ELSE 'expired' END,
       CRC32(CONCAT('c', s.seq)) % 5          -- 0-3 Parter, 4 Balkon (privremeno)
  FROM seq_1_to_100000 s;

UPDATE tmp_perf t
  JOIN event e ON e.id = t.event_id
  JOIN location l ON l.id = e.location_id
  JOIN city ct ON ct.id = l.city_id
  JOIN ticket_category c ON c.event_id = t.event_id
                        AND c.name = IF(t.category_id = 4, 'Balkon', 'Parter')
   SET t.event_date  = local_to_utc(e.event_date, ct.time_zone),
       t.category_id = c.id,
       t.price       = c.price,
       t.fee         = c.service_fee,
       -- kupnja 3-90 dana prije eventa, ali nikad nakon 27.10.2026.
       t.created_at  = LEAST(local_to_utc(e.event_date, ct.time_zone) - INTERVAL (3 + CRC32(CONCAT('d', t.seq)) % 88) DAY
                                          - INTERVAL (CRC32(CONCAT('m', t.seq)) % 600) MINUTE,
                             TIMESTAMP('2026-10-27 12:00:00') - INTERVAL (CRC32(CONCAT('m', t.seq)) % 600) MINUTE);

-- povrat ima smisla samo uz vise karata (ostaje barem jedna vazeca)
UPDATE tmp_perf SET outcome = 'confirmed' WHERE outcome = 'refund' AND qty = 1;
UPDATE tmp_perf SET protect_fee = IF(protect, ROUND(0.10 * qty * price, 2), 0);

-- ---------------------------------------------------------------------
-- 3. Rezervacije i stavke (sve nastaju kao pending - trigger to provjerava)
-- ---------------------------------------------------------------------
INSERT INTO reservation (event_id, buyer_id, created_at, expires_at, has_refund_protection, refund_protection_fee)
SELECT event_id, buyer_id, created_at, created_at + INTERVAL 15 MINUTE, protect, protect_fee
  FROM tmp_perf ORDER BY seq;
SET @res0 = LAST_INSERT_ID() - 1;
UPDATE tmp_perf SET res_id = @res0 + seq;

-- provjera da su ID-jevi uzastopni (InnoDB autoinc u jednom INSERT ... SELECT)
SELECT IF(COUNT(*) = 100000, 'OK', 'GRESKA: ID-jevi nisu uzastopni') AS provjera_id
  FROM tmp_perf t JOIN reservation r ON r.id = t.res_id
 WHERE r.buyer_id = t.buyer_id AND r.event_id = t.event_id AND r.created_at = t.created_at;

INSERT INTO reservation_item (reservation_id, event_id, category_id, quantity, price_per_ticket, service_fee_per_ticket)
SELECT res_id, event_id, category_id, qty, price, fee FROM tmp_perf ORDER BY seq;

-- ---------------------------------------------------------------------
-- 4. Ishodi (prijelazi statusa provjeravaju triggeri i CHECK-ovi)
-- ---------------------------------------------------------------------
UPDATE reservation r JOIN tmp_perf t ON t.res_id = r.id
   SET r.status = 'confirmed', r.confirmed_at = r.created_at + INTERVAL 5 MINUTE
 WHERE t.outcome IN ('confirmed', 'refund');

UPDATE reservation r JOIN tmp_perf t ON t.res_id = r.id
   SET r.status = 'cancelled', r.cancelled_at = r.created_at + INTERVAL 3 MINUTE, r.cancel_reason = 'buyer'
 WHERE t.outcome = 'buyer';

UPDATE reservation r JOIN tmp_perf t ON t.res_id = r.id
   SET r.status = 'cancelled', r.cancelled_at = r.expires_at + INTERVAL 1 MINUTE, r.cancel_reason = 'expired'
 WHERE t.outcome = 'expired';

-- Karte za potvrdene rezervacije (quantity karata po stavci)
INSERT INTO ticket (reservation_item_id, reservation_seat_id, ticket_code)
SELECT ri.id, NULL, HEX(RANDOM_BYTES(16))
  FROM reservation_item ri
  JOIN tmp_perf t ON t.res_id = ri.reservation_id AND t.outcome IN ('confirmed', 'refund')
  JOIN seq_1_to_4 n ON n.seq <= ri.quantity;

-- Povrat: prva karta, 2 dana nakon kupnje (najkasnije 27.10.2026.);
-- 100 % uz zastitu, inace po pravilu roka
UPDATE ticket tk
  JOIN (SELECT MIN(tk2.id) AS ticket_id, t.event_date, t.protect, t.price, t.created_at
          FROM tmp_perf t
          JOIN reservation_item ri ON ri.reservation_id = t.res_id
          JOIN ticket tk2 ON tk2.reservation_item_id = ri.id
         WHERE t.outcome = 'refund'
         GROUP BY t.res_id) x ON x.ticket_id = tk.id
   SET tk.cancelled_at  = LEAST(x.created_at + INTERVAL 2 DAY, TIMESTAMP('2026-10-27 18:00:00')),
       tk.refund_amount = IF(x.protect, x.price,
                             ROUND(x.price * refund_percent(TIMESTAMPDIFF(HOUR,
                               LEAST(x.created_at + INTERVAL 2 DAY, TIMESTAMP('2026-10-27 18:00:00')),
                               x.event_date)) / 100, 2));

-- Check-in za prosle evente (~85 % vazecih karata)
UPDATE ticket tk
  JOIN reservation_item ri ON ri.id = tk.reservation_item_id
  JOIN tmp_perf t ON t.res_id = ri.reservation_id
   SET tk.checked_in_at = t.event_date - INTERVAL (CRC32(CONCAT('ci', tk.id)) % 60) MINUTE
 WHERE t.event_date < TIMESTAMP('2026-10-27 12:00:00')
   AND tk.cancelled_at IS NULL
   AND CRC32(CONCAT('k', tk.id)) % 100 < 85;

-- ---------------------------------------------------------------------
-- 5. Brojac zauzeca iz stvarnih karata
-- ---------------------------------------------------------------------
UPDATE ticket_category c
  JOIN (SELECT ri.category_id, COUNT(*) AS q
          FROM ticket tk JOIN reservation_item ri ON ri.id = tk.reservation_item_id
         WHERE tk.cancelled_at IS NULL AND ri.event_id BETWEEN @ev0 + 1 AND @ev0 + 50
         GROUP BY ri.category_id) x ON x.category_id = c.id
   SET c.reserved = x.q;

DROP TEMPORARY TABLE tmp_perf;
SET timestamp = DEFAULT;
ANALYZE TABLE reservation, reservation_item, ticket, ticket_category, event;

-- ---------------------------------------------------------------------
-- 6. Kontrola i sazetak
-- ---------------------------------------------------------------------
SELECT COUNT(*) AS neuskladjeni_brojaci FROM v_reserved_check;   -- ocekivano 0

SELECT
  ROUND(TIMESTAMPDIFF(MICROSECOND, @t_start, SYSDATE(6)) / 1000000, 1) AS trajanje_s,
  (SELECT COUNT(*) FROM reservation r JOIN event e ON e.id = r.event_id
    WHERE e.name LIKE 'PERF %')                                  AS perf_rezervacije,
  (SELECT COUNT(*) FROM reservation)                              AS ukupno_rezervacija,
  (SELECT COUNT(*) FROM ticket)                                   AS ukupno_karata;
