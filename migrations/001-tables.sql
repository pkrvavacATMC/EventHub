--liquibase formatted sql

-- =====================================================================
-- EventHub - 01: tablice (MariaDB 10.6+, testirano na 10.11)
-- Redoslijed migracija odreduje db.changelog-master.xml.
--
-- Pretpostavke (za dokumentaciju):
--  * Jedna rezervacija = jedan event, 1 do 4 karte ukupno.
--  * Cijena je definirana po kategoriji karte (event nema cijenu).
--  * Besplatne karte = kategorija s cijenom 0 (kupac ne odreduje cijenu).
--  * Pending rezervacija istjece nakon 15 minuta.
--  * Pending se otkazuje samo cijela, confirmed po karti.
--  * Razlog otkazivanja: 'buyer' (kupac je otkazao) ili 'expired' (istekao rok
--    placanja). Istekle rezervacije se NE broje u stopu otkazivanja.
--  * Datum eventa moze se mijenjati samo dok event nije poceo, i samo u buducnost.
--  * Kod karte je nasumican (RANDOM_BYTES), ne moze se pogoditi iz susjednih karata.
--  * Check-in provjerava da karta pripada eventu na cijem se ulazu skenira.
--  * Service fee i refund protection fee se ne vracaju.
--  * Refund protection = 10 % zbroja cijena karata, vraca 100 % cijene karte.
--  * Bez zastite: >= 7 dana prije eventa 80 %, >= 48 h 50 %, inace 0 %.
--  * Nema rezervacija ni otkazivanja nakon pocetka eventa.
--  * Check-in je moguc od 24 h prije do 24 h nakon pocetka eventa.
--  * Kod sjedece kategorije kapacitet = broj sjedala (generate_seats).
--  * Nista se ne brise (DELETE je zabranjen na transakcijskim tablicama).
--
-- Namjerna redundancija koju jamce kompozitni FK-ovi:
--  * reservation_item.event_id  -> stavka i kategorija moraju biti za event rezervacije
--  * reservation_seat.category_id -> sjedalo mora biti iz kategorije stavke
--  * ticket (reservation_seat_id, reservation_item_id) -> hold mora biti iz stavke karte
-- =====================================================================


-- Pocetna struktura. Postojece tablice prethodno provjerava 000-adoption-guard.sql.

--changeset eventhub:001-table-city dbms:mariadb
--preconditions onFail:MARK_RAN onError:HALT
--precondition-sql-check expectedResult:0 SELECT COUNT(*) FROM information_schema.TABLES WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME='city';
CREATE TABLE city (
  id   INT AUTO_INCREMENT PRIMARY KEY,
  name VARCHAR(100) NOT NULL,
  CONSTRAINT uq_city_name UNIQUE (name),
  CONSTRAINT chk_city_name CHECK (TRIM(name) <> '')
) ENGINE=InnoDB;

--changeset eventhub:001-table-organizer dbms:mariadb
--preconditions onFail:MARK_RAN onError:HALT
--precondition-sql-check expectedResult:0 SELECT COUNT(*) FROM information_schema.TABLES WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME='organizer';
CREATE TABLE organizer (
  id    INT AUTO_INCREMENT PRIMARY KEY,
  name  VARCHAR(150) NOT NULL,
  email VARCHAR(190) NOT NULL,
  CONSTRAINT uq_organizer_email UNIQUE (email),
  CONSTRAINT chk_organizer_name  CHECK (TRIM(name) <> ''),
  CONSTRAINT chk_organizer_email CHECK (email LIKE '%_@_%._%' AND email NOT LIKE '% %')
) ENGINE=InnoDB;

--changeset eventhub:001-table-location dbms:mariadb
--preconditions onFail:MARK_RAN onError:HALT
--precondition-sql-check expectedResult:0 SELECT COUNT(*) FROM information_schema.TABLES WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME='location';
CREATE TABLE location (
  id       INT AUTO_INCREMENT PRIMARY KEY,
  name     VARCHAR(150) NOT NULL,
  city_id  INT NOT NULL,
  capacity INT NOT NULL,
  CONSTRAINT chk_location_name     CHECK (TRIM(name) <> ''),
  CONSTRAINT chk_location_capacity CHECK (capacity > 0),
  CONSTRAINT fk_location_city FOREIGN KEY (city_id) REFERENCES city (id) ON DELETE RESTRICT
) ENGINE=InnoDB;

--changeset eventhub:001-table-buyer dbms:mariadb
--preconditions onFail:MARK_RAN onError:HALT
--precondition-sql-check expectedResult:0 SELECT COUNT(*) FROM information_schema.TABLES WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME='buyer';
CREATE TABLE buyer (
  id      INT AUTO_INCREMENT PRIMARY KEY,
  name    VARCHAR(100) NOT NULL,
  surname VARCHAR(100) NOT NULL,
  email   VARCHAR(190) NOT NULL,
  address VARCHAR(200) NULL,
  city_id INT NOT NULL,
  CONSTRAINT uq_buyer_email UNIQUE (email),
  CONSTRAINT chk_buyer_name    CHECK (TRIM(name) <> '' AND TRIM(surname) <> ''),
  CONSTRAINT chk_buyer_email   CHECK (email LIKE '%_@_%._%' AND email NOT LIKE '% %'),
  CONSTRAINT fk_buyer_city FOREIGN KEY (city_id) REFERENCES city (id) ON DELETE RESTRICT
) ENGINE=InnoDB;

--changeset eventhub:001-table-event dbms:mariadb
--preconditions onFail:MARK_RAN onError:HALT
--precondition-sql-check expectedResult:0 SELECT COUNT(*) FROM information_schema.TABLES WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME='event';
CREATE TABLE event (
  id           INT AUTO_INCREMENT PRIMARY KEY,
  name         VARCHAR(200) NOT NULL,
  event_date   DATETIME NOT NULL,
  capacity     INT NOT NULL,
  location_id  INT NOT NULL,
  organizer_id INT NOT NULL,
  CONSTRAINT chk_event_name     CHECK (TRIM(name) <> ''),
  CONSTRAINT chk_event_capacity CHECK (capacity > 0),
  CONSTRAINT fk_event_location  FOREIGN KEY (location_id)  REFERENCES location (id)  ON DELETE RESTRICT,
  CONSTRAINT fk_event_organizer FOREIGN KEY (organizer_id) REFERENCES organizer (id) ON DELETE RESTRICT,
  INDEX idx_event_date (event_date)
) ENGINE=InnoDB;

--changeset eventhub:001-table-ticket_category dbms:mariadb
--preconditions onFail:MARK_RAN onError:HALT
--precondition-sql-check expectedResult:0 SELECT COUNT(*) FROM information_schema.TABLES WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME='ticket_category';
CREATE TABLE ticket_category (
  id           INT AUTO_INCREMENT PRIMARY KEY,
  event_id     INT NOT NULL,
  name         VARCHAR(100) NOT NULL,
  price        DECIMAL(10,2) NOT NULL,
  service_fee  DECIMAL(10,2) NOT NULL DEFAULT 0,
  capacity     INT NOT NULL,
  seating_type ENUM('seated','standing') NOT NULL,
  reserved     INT NOT NULL DEFAULT 0,
  CONSTRAINT uq_category_event_name UNIQUE (event_id, name),
  CONSTRAINT uq_category_id_event   UNIQUE (id, event_id),          -- cilj kompozitnog FK-a
  CONSTRAINT chk_category_name     CHECK (TRIM(name) <> ''),
  CONSTRAINT chk_category_price    CHECK (price >= 0),
  CONSTRAINT chk_category_fee      CHECK (service_fee >= 0),
  CONSTRAINT chk_category_capacity CHECK (capacity > 0),
  CONSTRAINT chk_category_reserved CHECK (reserved BETWEEN 0 AND capacity),
  CONSTRAINT fk_category_event FOREIGN KEY (event_id) REFERENCES event (id) ON DELETE RESTRICT
) ENGINE=InnoDB;

--changeset eventhub:001-table-seat dbms:mariadb
--preconditions onFail:MARK_RAN onError:HALT
--precondition-sql-check expectedResult:0 SELECT COUNT(*) FROM information_schema.TABLES WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME='seat';
CREATE TABLE seat (
  id          INT AUTO_INCREMENT PRIMARY KEY,
  category_id INT NOT NULL,
  row_label   VARCHAR(10) NOT NULL,
  seat_number INT NOT NULL,
  CONSTRAINT uq_seat             UNIQUE (category_id, row_label, seat_number),
  CONSTRAINT uq_seat_id_category UNIQUE (id, category_id),         -- cilj kompozitnog FK-a
  CONSTRAINT chk_seat_row    CHECK (TRIM(row_label) <> ''),
  CONSTRAINT chk_seat_number CHECK (seat_number > 0),
  CONSTRAINT fk_seat_category FOREIGN KEY (category_id) REFERENCES ticket_category (id) ON DELETE RESTRICT
) ENGINE=InnoDB;

--changeset eventhub:001-table-reservation dbms:mariadb
--preconditions onFail:MARK_RAN onError:HALT
--precondition-sql-check expectedResult:0 SELECT COUNT(*) FROM information_schema.TABLES WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME='reservation';
CREATE TABLE reservation (
  id                    INT AUTO_INCREMENT PRIMARY KEY,
  event_id              INT NOT NULL,
  buyer_id              INT NOT NULL,
  status                ENUM('pending','confirmed','cancelled') NOT NULL DEFAULT 'pending',
  created_at            DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  confirmed_at          DATETIME NULL,
  cancelled_at          DATETIME NULL,
  cancel_reason         ENUM('buyer','expired') NULL,   -- postavlja se samo uz status cancelled
  expires_at            DATETIME NOT NULL,
  has_refund_protection BOOLEAN NOT NULL DEFAULT FALSE,
  refund_protection_fee DECIMAL(10,2) NOT NULL DEFAULT 0,
  CONSTRAINT uq_reservation_id_event UNIQUE (id, event_id),        -- cilj kompozitnog FK-a
  CONSTRAINT chk_res_status_dates CHECK (
       (status = 'pending'   AND confirmed_at IS NULL     AND cancelled_at IS NULL)
    OR (status = 'confirmed' AND confirmed_at IS NOT NULL AND cancelled_at IS NULL)
    OR (status = 'cancelled' AND cancelled_at IS NOT NULL)),
  -- razlog postoji tocno onda kad je rezervacija otkazana
  CONSTRAINT chk_res_cancel_reason CHECK ((status = 'cancelled') = (cancel_reason IS NOT NULL)),
  -- istjece samo rezervacija koja nikad nije bila potvrdena
  CONSTRAINT chk_res_expired_unconfirmed CHECK (cancel_reason IS NULL OR cancel_reason <> 'expired'
                                                OR confirmed_at IS NULL),
  CONSTRAINT chk_res_protection     CHECK (has_refund_protection = 1 OR refund_protection_fee = 0),
  CONSTRAINT chk_res_protection_fee CHECK (refund_protection_fee >= 0),
  CONSTRAINT chk_res_expires        CHECK (expires_at > created_at),
  CONSTRAINT fk_res_event FOREIGN KEY (event_id) REFERENCES event (id) ON DELETE RESTRICT,
  CONSTRAINT fk_res_buyer FOREIGN KEY (buyer_id) REFERENCES buyer (id) ON DELETE RESTRICT,
  INDEX idx_res_event_status   (event_id, status),
  INDEX idx_res_status_expires (status, expires_at),
  INDEX idx_res_confirmed_at   (confirmed_at),
  -- Postojeci uski FK indeks dovoljan je za povijest kupca (~20 redaka).
  INDEX fk_res_buyer (buyer_id)
) ENGINE=InnoDB;

--changeset eventhub:001-table-reservation_item dbms:mariadb
--preconditions onFail:MARK_RAN onError:HALT
--precondition-sql-check expectedResult:0 SELECT COUNT(*) FROM information_schema.TABLES WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME='reservation_item';
CREATE TABLE reservation_item (
  id                     INT AUTO_INCREMENT PRIMARY KEY,
  reservation_id         INT NOT NULL,
  event_id               INT NOT NULL,
  category_id            INT NOT NULL,
  quantity               INT NOT NULL,
  price_per_ticket       DECIMAL(10,2) NOT NULL,   -- snimka cijene
  service_fee_per_ticket DECIMAL(10,2) NOT NULL,   -- snimka naknade
  CONSTRAINT uq_item_id_category UNIQUE (id, category_id),          -- cilj kompozitnog FK-a
  CONSTRAINT chk_item_quantity CHECK (quantity BETWEEN 1 AND 4),
  CONSTRAINT chk_item_price    CHECK (price_per_ticket >= 0),
  CONSTRAINT chk_item_fee      CHECK (service_fee_per_ticket >= 0),
  -- stavka pripada rezervaciji I njenom eventu
  CONSTRAINT fk_item_reservation FOREIGN KEY (reservation_id, event_id)
    REFERENCES reservation (id, event_id) ON DELETE RESTRICT,
  -- kategorija pripada ISTOM eventu
  CONSTRAINT fk_item_category FOREIGN KEY (category_id, event_id)
    REFERENCES ticket_category (id, event_id) ON DELETE RESTRICT
) ENGINE=InnoDB;

--changeset eventhub:001-table-reservation_seat dbms:mariadb
--preconditions onFail:MARK_RAN onError:HALT
--precondition-sql-check expectedResult:0 SELECT COUNT(*) FROM information_schema.TABLES WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME='reservation_seat';
CREATE TABLE reservation_seat (
  id                  INT AUTO_INCREMENT PRIMARY KEY,
  reservation_item_id INT NOT NULL,
  category_id         INT NOT NULL,
  seat_id             INT NOT NULL,
  released_at         DATETIME NULL,
  active_seat_id      INT AS (IF(released_at IS NULL, seat_id, NULL)) STORED,
  CONSTRAINT uq_active_seat UNIQUE (active_seat_id),
  CONSTRAINT uq_rs_id_item  UNIQUE (id, reservation_item_id),      -- cilj kompozitnog FK-a
  -- sjedalo pripada kategoriji ...
  CONSTRAINT fk_rs_seat FOREIGN KEY (seat_id, category_id)
    REFERENCES seat (id, category_id) ON DELETE RESTRICT,
  -- ... a stavka je za ISTU kategoriju
  CONSTRAINT fk_rs_item FOREIGN KEY (reservation_item_id, category_id)
    REFERENCES reservation_item (id, category_id) ON DELETE RESTRICT
) ENGINE=InnoDB;

--changeset eventhub:001-table-ticket dbms:mariadb
--preconditions onFail:MARK_RAN onError:HALT
--precondition-sql-check expectedResult:0 SELECT COUNT(*) FROM information_schema.TABLES WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME='ticket';
CREATE TABLE ticket (
  id                  INT AUTO_INCREMENT PRIMARY KEY,
  reservation_item_id INT NOT NULL,
  reservation_seat_id INT NULL,                    -- NULL za stajace kategorije
  ticket_code         CHAR(32) NOT NULL,           -- HEX(RANDOM_BYTES(16)), nepredvidljiv
  checked_in_at       DATETIME NULL,
  cancelled_at        DATETIME NULL,
  refund_amount       DECIMAL(10,2) NULL,
  CONSTRAINT uq_ticket_code UNIQUE (ticket_code),
  CONSTRAINT chk_ticket_code CHECK (ticket_code REGEXP '^[0-9A-F]{32}$'),
  CONSTRAINT uq_ticket_seat UNIQUE (reservation_seat_id),          -- jedan hold = najvise jedna karta
  CONSTRAINT chk_ticket_refund_pair CHECK ((cancelled_at IS NULL) = (refund_amount IS NULL)),
  CONSTRAINT chk_ticket_refund      CHECK (refund_amount IS NULL OR refund_amount >= 0),
  CONSTRAINT chk_ticket_used_cancel CHECK (NOT (checked_in_at IS NOT NULL AND cancelled_at IS NOT NULL)),
  CONSTRAINT fk_ticket_item FOREIGN KEY (reservation_item_id)
    REFERENCES reservation_item (id) ON DELETE RESTRICT,
  -- hold mora pripadati stavci karte (NULL = stajaca, FK se ne provjerava)
  CONSTRAINT fk_ticket_rs FOREIGN KEY (reservation_seat_id, reservation_item_id)
    REFERENCES reservation_seat (id, reservation_item_id) ON DELETE RESTRICT,
  -- Task 7: uski indeks dovoljan je za selektivni raspon povrata.
  INDEX idx_ticket_cancelled_at (cancelled_at)
) ENGINE=InnoDB;

