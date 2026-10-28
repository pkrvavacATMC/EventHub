-- =====================================================================
-- EventHub - 02: funkcije i triggeri
-- Triggeri provode SAMO pravila koja FK/UNIQUE/CHECK ne mogu izraziti
-- (pravila preko vise redova, prijelazi statusa, nepromjenjivost).
-- Admin triggeri zakljucavaju roditeljski red (FOR UPDATE) da istovremene
-- izmjene ne mogu zajedno preci kapacitet.
-- =====================================================================
USE eventhub;

DELIMITER //

-- Jedino mjesto gdje su definirani rokovi povrata bez zastite
CREATE FUNCTION refund_percent(p_hours_before INT) RETURNS DECIMAL(5,2)
DETERMINISTIC NO SQL
BEGIN
  IF p_hours_before >= 168 THEN RETURN 80.00;
  ELSEIF p_hours_before >= 48 THEN RETURN 50.00;
  ELSE RETURN 0.00;
  END IF;
END//

-- ---------------------------------------------------------------------
-- LOCATION / EVENT: event.capacity <= location.capacity,
--                   zbroj kategorija <= event.capacity
-- ---------------------------------------------------------------------
CREATE TRIGGER trg_location_bu BEFORE UPDATE ON location
FOR EACH ROW
BEGIN
  DECLARE v_max INT;
  IF NEW.capacity < OLD.capacity THEN
    -- red lokacije je vec zakljucan ovim UPDATE-om; trg_event_bi/bu ga zakljucavaju prije provjere
    SELECT COALESCE(MAX(capacity), 0) INTO v_max FROM event WHERE location_id = NEW.id;
    IF NEW.capacity < v_max THEN
      SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Na lokaciji postoji event veceg kapaciteta';
    END IF;
  END IF;
END//

CREATE TRIGGER trg_event_bi BEFORE INSERT ON event
FOR EACH ROW
BEGIN
  DECLARE v_loc_cap INT;
  SELECT capacity INTO v_loc_cap FROM location WHERE id = NEW.location_id FOR UPDATE;
  IF NEW.capacity > v_loc_cap THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Kapacitet eventa prelazi kapacitet lokacije';
  END IF;
  IF NEW.event_date <= NOW() THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Event mora biti u buducnosti';
  END IF;
END//

CREATE TRIGGER trg_event_bu BEFORE UPDATE ON event
FOR EACH ROW
BEGIN
  DECLARE v_loc_cap INT;
  DECLARE v_cat_sum INT;
  -- Datum: event koji je poceo/prosao se ne pomice, a novi datum mora biti u buducnosti
  IF NEW.event_date <> OLD.event_date THEN
    IF OLD.event_date <= NOW() THEN
      SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Datum eventa koji je poceo ili prosao ne moze se mijenjati';
    END IF;
    IF NEW.event_date <= NOW() THEN
      SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Novi datum eventa mora biti u buducnosti';
    END IF;
  END IF;
  IF NEW.capacity <> OLD.capacity OR NEW.location_id <> OLD.location_id THEN
    SELECT capacity INTO v_loc_cap FROM location WHERE id = NEW.location_id FOR UPDATE;
    IF NEW.capacity > v_loc_cap THEN
      SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Kapacitet eventa prelazi kapacitet lokacije';
    END IF;
    -- red eventa je zakljucan ovim UPDATE-om; trg_category_* ga zakljucavaju prije provjere
    SELECT COALESCE(SUM(capacity), 0) INTO v_cat_sum FROM ticket_category WHERE event_id = NEW.id;
    IF NEW.capacity < v_cat_sum THEN
      SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Kapacitet eventa je manji od zbroja kapaciteta kategorija';
    END IF;
  END IF;
END//

-- ---------------------------------------------------------------------
-- TICKET_CATEGORY
-- ---------------------------------------------------------------------
CREATE TRIGGER trg_category_bi BEFORE INSERT ON ticket_category
FOR EACH ROW
BEGIN
  DECLARE v_event_cap INT;
  DECLARE v_sum INT;
  IF NEW.reserved <> 0 THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Nova kategorija mora imati reserved = 0';
  END IF;
  SELECT capacity INTO v_event_cap FROM event WHERE id = NEW.event_id FOR UPDATE;
  SELECT COALESCE(SUM(capacity), 0) INTO v_sum FROM ticket_category WHERE event_id = NEW.event_id;
  IF v_sum + NEW.capacity > v_event_cap THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Zbroj kapaciteta kategorija prelazi kapacitet eventa';
  END IF;
END//

CREATE TRIGGER trg_category_bu BEFORE UPDATE ON ticket_category
FOR EACH ROW
BEGIN
  DECLARE v_event_cap INT;
  DECLARE v_sum INT;
  DECLARE v_seats INT;
  IF NEW.event_id <> OLD.event_id THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Kategorija ne moze promijeniti event';
  END IF;
  IF NEW.seating_type <> OLD.seating_type THEN
    SELECT COUNT(*) INTO v_seats FROM seat WHERE category_id = NEW.id;
    IF v_seats > 0 OR OLD.reserved > 0 THEN
      SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Tip sjedenja se ne moze mijenjati nakon dodavanja sjedala ili rezervacija';
    END IF;
  END IF;
  IF NEW.capacity <> OLD.capacity THEN
    SELECT capacity INTO v_event_cap FROM event WHERE id = NEW.event_id FOR UPDATE;
    SELECT COALESCE(SUM(capacity), 0) INTO v_sum FROM ticket_category
     WHERE event_id = NEW.event_id AND id <> NEW.id;
    IF v_sum + NEW.capacity > v_event_cap THEN
      SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Zbroj kapaciteta kategorija prelazi kapacitet eventa';
    END IF;
    -- sjedeca kategorija sa sjedalima: kapacitet mora ostati jednak broju sjedala
    IF NEW.seating_type = 'seated' THEN
      SELECT COUNT(*) INTO v_seats FROM seat WHERE category_id = NEW.id;
      IF v_seats > 0 AND NEW.capacity <> v_seats THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Kapacitet sjedece kategorije mora biti jednak broju sjedala';
      END IF;
    END IF;
  END IF;
END//

-- ---------------------------------------------------------------------
-- SEAT: samo u sjedecoj kategoriji, broj sjedala <= capacity, nepromjenjivo
-- ---------------------------------------------------------------------
CREATE TRIGGER trg_seat_bi BEFORE INSERT ON seat
FOR EACH ROW
BEGIN
  DECLARE v_type VARCHAR(10);
  DECLARE v_cap INT;
  DECLARE v_cnt INT;
  SELECT seating_type, capacity INTO v_type, v_cap
    FROM ticket_category WHERE id = NEW.category_id FOR UPDATE;
  IF v_type <> 'seated' THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Sjedala se mogu dodati samo u sjedecu kategoriju';
  END IF;
  SELECT COUNT(*) INTO v_cnt FROM seat WHERE category_id = NEW.category_id;
  IF v_cnt + 1 > v_cap THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Broj sjedala prelazi kapacitet kategorije';
  END IF;
END//

CREATE TRIGGER trg_seat_bu BEFORE UPDATE ON seat
FOR EACH ROW
BEGIN
  IF NEW.category_id <> OLD.category_id THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Sjedalo ne moze promijeniti kategoriju';
  END IF;
END//

-- ---------------------------------------------------------------------
-- RESERVATION: uvijek nastaje kao pending; prijelazi statusa; nepromjenjivi podaci
-- ---------------------------------------------------------------------
CREATE TRIGGER trg_reservation_bi BEFORE INSERT ON reservation
FOR EACH ROW
BEGIN
  IF NEW.status <> 'pending' OR NEW.confirmed_at IS NOT NULL OR NEW.cancelled_at IS NOT NULL
     OR NEW.cancel_reason IS NOT NULL THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Nova rezervacija mora biti pending';
  END IF;
END//

CREATE TRIGGER trg_reservation_bu BEFORE UPDATE ON reservation
FOR EACH ROW
BEGIN
  IF NEW.event_id <> OLD.event_id OR NEW.buyer_id <> OLD.buyer_id
     OR NEW.created_at <> OLD.created_at OR NEW.expires_at <> OLD.expires_at THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Event, kupac i vremena rezervacije su nepromjenjivi';
  END IF;
  -- zastita se racuna jednom, pri kreiranju, i vise se ne mijenja
  IF NEW.has_refund_protection <> OLD.has_refund_protection
     OR NEW.refund_protection_fee <> OLD.refund_protection_fee THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Refund protection je nepromjenjiv nakon kreiranja rezervacije';
  END IF;
  IF OLD.status = 'cancelled' THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Otkazana rezervacija je konacna';
  END IF;
  IF OLD.status = 'confirmed' AND NEW.status = 'pending' THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Nedozvoljen prijelaz statusa confirmed -> pending';
  END IF;
  -- Procedure prvo otkazuju karte / oslobadjaju holdove, tek zatim rezervaciju.
  IF NEW.status = 'cancelled' AND OLD.status = 'confirmed' AND EXISTS (
    SELECT 1 FROM ticket t JOIN reservation_item ri ON ri.id = t.reservation_item_id
     WHERE ri.reservation_id = OLD.id AND t.cancelled_at IS NULL
  ) THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Rezervacija ima vazece karte; prvo otkazite karte';
  END IF;
  IF NEW.status = 'cancelled' AND OLD.status = 'pending' AND EXISTS (
    SELECT 1 FROM reservation_seat rs JOIN reservation_item ri ON ri.id = rs.reservation_item_id
     WHERE ri.reservation_id = OLD.id AND rs.released_at IS NULL
  ) THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Rezervacija ima aktivne holdove sjedala; prvo oslobodite sjedala';
  END IF;
  IF OLD.confirmed_at IS NOT NULL AND NOT (NEW.confirmed_at <=> OLD.confirmed_at) THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'confirmed_at se ne smije mijenjati';
  END IF;
END//

-- ---------------------------------------------------------------------
-- RESERVATION_ITEM: samo pending, max 4 karte, nepromjenjivo
-- (isti event provodi kompozitni FK fk_item_reservation + fk_item_category)
-- ---------------------------------------------------------------------
CREATE TRIGGER trg_item_bi BEFORE INSERT ON reservation_item
FOR EACH ROW
BEGIN
  DECLARE v_status VARCHAR(10);
  DECLARE v_total INT;
  SELECT status INTO v_status FROM reservation WHERE id = NEW.reservation_id;
  IF v_status <> 'pending' THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Stavke se mogu dodati samo pending rezervaciji';
  END IF;
  SELECT COALESCE(SUM(quantity), 0) INTO v_total FROM reservation_item WHERE reservation_id = NEW.reservation_id;
  IF v_total + NEW.quantity > 4 THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Rezervacija moze imati najvise 4 karte';
  END IF;
END//

CREATE TRIGGER trg_item_bu BEFORE UPDATE ON reservation_item
FOR EACH ROW
BEGIN
  SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Stavke rezervacije su nepromjenjive';
END//

-- ---------------------------------------------------------------------
-- RESERVATION_SEAT: samo sjedeca kategorija, aktivan, broj <= quantity
-- (sjedalo iz kategorije stavke provode fk_rs_seat + fk_rs_item)
-- ---------------------------------------------------------------------
CREATE TRIGGER trg_rs_bi BEFORE INSERT ON reservation_seat
FOR EACH ROW
BEGIN
  DECLARE v_type VARCHAR(10);
  DECLARE v_qty INT;
  DECLARE v_cnt INT;
  SELECT seating_type INTO v_type FROM ticket_category WHERE id = NEW.category_id;
  IF v_type <> 'seated' THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Stajaca kategorija nema sjedala';
  END IF;
  IF NEW.released_at IS NOT NULL THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Novo zauzece sjedala mora biti aktivno';
  END IF;
  SELECT quantity INTO v_qty FROM reservation_item WHERE id = NEW.reservation_item_id;
  SELECT COUNT(*) INTO v_cnt FROM reservation_seat WHERE reservation_item_id = NEW.reservation_item_id;
  IF v_cnt + 1 > v_qty THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Broj sjedala prelazi kolicinu stavke';
  END IF;
END//

CREATE TRIGGER trg_rs_bu BEFORE UPDATE ON reservation_seat
FOR EACH ROW
BEGIN
  IF NEW.reservation_item_id <> OLD.reservation_item_id OR NEW.seat_id <> OLD.seat_id
     OR NEW.category_id <> OLD.category_id THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Zauzece sjedala je nepromjenjivo';
  END IF;
  IF OLD.released_at IS NOT NULL THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Oslobodeno sjedalo se ne moze ponovno aktivirati';
  END IF;
END//

-- ---------------------------------------------------------------------
-- TICKET: samo potvrdena rezervacija, sjedeca/stajaca pravila, aktivan hold
-- (hold iz iste stavke provodi kompozitni FK fk_ticket_rs)
-- ---------------------------------------------------------------------
CREATE TRIGGER trg_ticket_bi BEFORE INSERT ON ticket
FOR EACH ROW
BEGIN
  DECLARE v_type VARCHAR(10);
  DECLARE v_status VARCHAR(10);
  DECLARE v_qty INT;
  DECLARE v_cnt INT;
  DECLARE v_rs_released DATETIME;
  SELECT c.seating_type, r.status, ri.quantity INTO v_type, v_status, v_qty
    FROM reservation_item ri
    JOIN ticket_category c ON c.id = ri.category_id
    JOIN reservation r     ON r.id = ri.reservation_id
   WHERE ri.id = NEW.reservation_item_id;
  IF v_status <> 'confirmed' THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Karte se izdaju samo za potvrdenu rezervaciju';
  END IF;
  IF NEW.cancelled_at IS NOT NULL OR NEW.checked_in_at IS NOT NULL OR NEW.refund_amount IS NOT NULL THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Nova karta mora biti vazeca i neiskoristena';
  END IF;
  IF v_type = 'seated' THEN
    IF NEW.reservation_seat_id IS NULL THEN
      SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Karta sjedece kategorije mora imati sjedalo';
    END IF;
    SELECT released_at INTO v_rs_released FROM reservation_seat WHERE id = NEW.reservation_seat_id;
    IF v_rs_released IS NOT NULL THEN
      SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Zauzece sjedala je oslobodeno';
    END IF;
  ELSEIF NEW.reservation_seat_id IS NOT NULL THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Karta stajace kategorije ne smije imati sjedalo';
  END IF;
  SELECT COUNT(*) INTO v_cnt FROM ticket WHERE reservation_item_id = NEW.reservation_item_id;
  IF v_cnt + 1 > v_qty THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Broj karata prelazi kolicinu stavke';
  END IF;
END//

CREATE TRIGGER trg_ticket_bu BEFORE UPDATE ON ticket
FOR EACH ROW
BEGIN
  DECLARE v_price DECIMAL(10,2);
  DECLARE v_status VARCHAR(10);
  IF NEW.reservation_item_id <> OLD.reservation_item_id
     OR NOT (NEW.reservation_seat_id <=> OLD.reservation_seat_id)
     OR NEW.ticket_code <> OLD.ticket_code THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Stavka, sjedalo i kod karte su nepromjenjivi';
  END IF;
  IF OLD.cancelled_at IS NOT NULL THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Otkazana karta je konacna';
  END IF;
  IF OLD.checked_in_at IS NOT NULL AND NOT (NEW.checked_in_at <=> OLD.checked_in_at) THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'checked_in_at se ne smije mijenjati';
  END IF;
  SELECT ri.price_per_ticket, r.status INTO v_price, v_status
    FROM reservation_item ri JOIN reservation r ON r.id = ri.reservation_id
   WHERE ri.id = NEW.reservation_item_id;
  IF NEW.checked_in_at IS NOT NULL AND OLD.checked_in_at IS NULL AND v_status <> 'confirmed' THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Check-in je moguc samo za potvrdenu rezervaciju';
  END IF;
  IF NEW.refund_amount IS NOT NULL AND NEW.refund_amount > v_price THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Povrat ne smije biti veci od cijene karte';
  END IF;
END//

-- ---------------------------------------------------------------------
-- Zabrana brisanja (povijesna tocnost)
-- ---------------------------------------------------------------------
CREATE TRIGGER trg_reservation_bd BEFORE DELETE ON reservation FOR EACH ROW
  SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Brisanje rezervacija nije dozvoljeno'//
CREATE TRIGGER trg_item_bd BEFORE DELETE ON reservation_item FOR EACH ROW
  SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Brisanje stavki nije dozvoljeno'//
CREATE TRIGGER trg_rs_bd BEFORE DELETE ON reservation_seat FOR EACH ROW
  SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Brisanje zauzeca sjedala nije dozvoljeno'//
CREATE TRIGGER trg_ticket_bd BEFORE DELETE ON ticket FOR EACH ROW
  SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Brisanje karata nije dozvoljeno'//

DELIMITER ;
