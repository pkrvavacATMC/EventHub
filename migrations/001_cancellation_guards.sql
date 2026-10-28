-- Nadogradnja postojece eventhub baze bez brisanja podataka.
-- Ne izvrsavati init/01_schema.sql nad postojecom bazom (sadrzi DROP DATABASE).
USE eventhub;
DELIMITER //
CREATE OR REPLACE TRIGGER trg_reservation_bu BEFORE UPDATE ON reservation
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
DELIMITER ;
CREATE OR REPLACE VIEW v_ticket_stats AS
SELECT e.id AS event_id, e.organizer_id, e.name AS event_name,
       COALESCE(i.reserved_ever, 0)        AS tickets_reserved_ever,
       COALESCE(i.pending_tickets, 0)      AS pending_tickets,
       COALESCE(t.confirmed_tickets, 0)    AS confirmed_tickets,
       COALESCE(t.cancelled_tickets, 0) + COALESCE(i.cancelled_unconfirmed, 0) AS cancelled_tickets,
       COALESCE(i.expired_tickets, 0)      AS expired_tickets,
       ROUND(100 * (COALESCE(t.cancelled_tickets, 0) + COALESCE(i.cancelled_unconfirmed, 0))
             / NULLIF(COALESCE(i.reserved_ever, 0) - COALESCE(i.expired_tickets, 0), 0), 1)
         AS cancellation_rate_pct
  FROM event e
  LEFT JOIN (SELECT r.event_id,
                    SUM(ri.quantity) AS reserved_ever,
                    SUM(CASE WHEN r.status = 'pending' THEN ri.quantity ELSE 0 END) AS pending_tickets,
                    -- kupac otkazao pending rezervaciju (prije placanja)
                    SUM(CASE WHEN r.cancel_reason = 'buyer' AND r.confirmed_at IS NULL
                             THEN ri.quantity ELSE 0 END) AS cancelled_unconfirmed,
                    -- istekao rok placanja (nije otkazivanje)
                    SUM(CASE WHEN r.cancel_reason = 'expired'
                             THEN ri.quantity ELSE 0 END) AS expired_tickets
               FROM reservation r JOIN reservation_item ri ON ri.reservation_id = r.id
              GROUP BY r.event_id) i ON i.event_id = e.id
  LEFT JOIN (SELECT r.event_id,
                    SUM(r.status = 'confirmed' AND tk.cancelled_at IS NULL) AS confirmed_tickets,
                    SUM(tk.cancelled_at IS NOT NULL) AS cancelled_tickets
               FROM ticket tk
               JOIN reservation_item ri ON ri.id = tk.reservation_item_id
               JOIN reservation r       ON r.id  = ri.reservation_id
              GROUP BY r.event_id) t ON t.event_id = e.id;
