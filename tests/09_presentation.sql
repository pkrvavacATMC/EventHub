-- Run as root against eventhub. Each run creates a new demo event.
-- Failure is the final statement: do not use --force.
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
VALUES (CONCAT('Presentation ', DATE_FORMAT(NOW(6), '%Y-%m-%d %H:%i:%s.%f')),
        NOW() + INTERVAL 30 DAY, 10, @loc, @org);
SET @event = LAST_INSERT_ID();
INSERT INTO ticket_category (event_id, name, price, service_fee, capacity, seating_type)
VALUES (@event, 'Parter', 20.00, 2.00, 10, 'standing');
SET @cat = LAST_INSERT_ID();


CALL create_reservation(@buyer, @event, CONCAT('[{"category_id":', @cat, ',"quantity":4}]'), 0, @reservation);
CALL confirm_reservation(@reservation);
SELECT id, status FROM reservation WHERE id = @reservation;
SELECT capacity, reserved FROM ticket_category WHERE id = @cat;
SELECT COUNT(*) AS issued_tickets FROM ticket t JOIN reservation_item i ON i.id=t.reservation_item_id WHERE i.reservation_id=@reservation;
CALL create_reservation(@buyer, @event, CONCAT('[{"category_id":', @cat, ',"quantity":4}]'), 0, @second);
CALL confirm_reservation(@second);
-- Eight occupied, two free. Requesting three must fail, leaving reserved=8.
SELECT @event AS demo_event, @cat AS demo_category, capacity, reserved FROM ticket_category WHERE id=@cat;
CALL create_reservation(@buyer, @event, CONCAT('[{"category_id":', @cat, ',"quantity":3}]'), 0, @rejected);
