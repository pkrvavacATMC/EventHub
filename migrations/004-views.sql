--liquibase formatted sql

--changeset eventhub:004-v_category_capacity dbms:mariadb splitStatements:false rollbackSplitStatements:false
CREATE OR REPLACE VIEW v_category_capacity AS
SELECT c.id AS category_id, c.event_id, c.name AS category_name, c.seating_type,
       c.price, c.service_fee, c.capacity, c.reserved,
       c.capacity - c.reserved AS remaining
  FROM ticket_category c;
--rollback DROP VIEW v_category_capacity;

--changeset eventhub:004-v_event_capacity dbms:mariadb splitStatements:false rollbackSplitStatements:false
CREATE OR REPLACE VIEW v_event_capacity AS
SELECT e.id AS event_id, e.organizer_id, e.name AS event_name, e.event_date,
       e.capacity AS event_capacity,
       COALESCE(SUM(c.capacity),0)              AS sellable_capacity,
       COALESCE(SUM(c.reserved),0)              AS reserved,
       COALESCE(SUM(c.capacity - c.reserved),0) AS remaining,
       ROUND(100 * SUM(c.capacity - c.reserved) / NULLIF(SUM(c.capacity),0), 1) AS remaining_pct,
       city.time_zone AS event_time_zone
  FROM event e
  JOIN location l ON l.id = e.location_id
  JOIN city ON city.id = l.city_id
  LEFT JOIN ticket_category c ON c.event_id = e.id
 GROUP BY e.id, e.organizer_id, e.name, e.event_date, e.capacity, city.time_zone;
--rollback DROP VIEW v_event_capacity;

--changeset eventhub:004-v_reservations_by_event dbms:mariadb splitStatements:false rollbackSplitStatements:false
CREATE OR REPLACE VIEW v_reservations_by_event AS
SELECT e.id AS event_id, e.organizer_id, e.name AS event_name,
       COUNT(r.id) AS total_reservations,
       COALESCE(SUM(r.status = 'pending'),0)   AS pending,
       COALESCE(SUM(r.status = 'confirmed'),0) AS confirmed,
       COALESCE(SUM(r.cancel_reason = 'buyer'),0)   AS cancelled_by_buyer,
       COALESCE(SUM(r.cancel_reason = 'expired'),0) AS expired
  FROM event e
  LEFT JOIN reservation r ON r.event_id = e.id
 GROUP BY e.id, e.organizer_id, e.name;
--rollback DROP VIEW v_reservations_by_event;

--changeset eventhub:004-v_ticket_stats dbms:mariadb splitStatements:false rollbackSplitStatements:false
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
--rollback DROP VIEW v_ticket_stats;

--changeset eventhub:004-v_attendance dbms:mariadb splitStatements:false rollbackSplitStatements:false
CREATE OR REPLACE VIEW v_attendance AS
SELECT e.id AS event_id, e.organizer_id, e.name AS event_name, e.event_date,
       COALESCE(a.valid_tickets, 0)  AS valid_tickets,
       COALESCE(a.checked_in, 0)     AS checked_in,
       COALESCE(a.valid_tickets, 0) - COALESCE(a.checked_in, 0) AS not_checked_in,
       ROUND(100 * a.checked_in / NULLIF(a.valid_tickets, 0), 1) AS attendance_pct,
       city.time_zone AS event_time_zone
  FROM event e
  JOIN location l ON l.id = e.location_id
  JOIN city ON city.id = l.city_id
  LEFT JOIN (SELECT r.event_id,
                    SUM(t.cancelled_at IS NULL)      AS valid_tickets,
                    SUM(t.checked_in_at IS NOT NULL) AS checked_in
               FROM ticket t
               JOIN reservation_item ri ON ri.id = t.reservation_item_id
               JOIN reservation r       ON r.id  = ri.reservation_id
              GROUP BY r.event_id) a ON a.event_id = e.id;
--rollback DROP VIEW v_attendance;

--changeset eventhub:004-v_revenue_monthly dbms:mariadb splitStatements:false rollbackSplitStatements:false
CREATE OR REPLACE VIEW v_revenue_monthly AS
SELECT x.event_id, e.organizer_id, e.name AS event_name, x.month,
       SUM(x.ticket_gross)   AS ticket_gross,
       SUM(x.protection_fee) AS protection_fees,
       SUM(x.refunds)        AS refunds,
       SUM(x.ticket_gross) + SUM(x.protection_fee) - SUM(x.refunds) AS net_revenue
  FROM (
        SELECT r.event_id, DATE_FORMAT(CONVERT_TZ('1970-01-01 00:00:00' + INTERVAL UNIX_TIMESTAMP(r.confirmed_at) SECOND, '+00:00', 'Europe/Zagreb'), '%Y-%m') AS month,
               SUM(ri.quantity * (ri.price_per_ticket + ri.service_fee_per_ticket)) AS ticket_gross,
               0 AS protection_fee, 0 AS refunds
          FROM reservation r JOIN reservation_item ri ON ri.reservation_id = r.id
         WHERE r.confirmed_at IS NOT NULL
         GROUP BY r.event_id, DATE_FORMAT(CONVERT_TZ('1970-01-01 00:00:00' + INTERVAL UNIX_TIMESTAMP(r.confirmed_at) SECOND, '+00:00', 'Europe/Zagreb'), '%Y-%m')
        UNION ALL
        SELECT r.event_id, DATE_FORMAT(CONVERT_TZ('1970-01-01 00:00:00' + INTERVAL UNIX_TIMESTAMP(r.confirmed_at) SECOND, '+00:00', 'Europe/Zagreb'), '%Y-%m'),
               0, SUM(r.refund_protection_fee), 0
          FROM reservation r
         WHERE r.confirmed_at IS NOT NULL
         GROUP BY r.event_id, DATE_FORMAT(CONVERT_TZ('1970-01-01 00:00:00' + INTERVAL UNIX_TIMESTAMP(r.confirmed_at) SECOND, '+00:00', 'Europe/Zagreb'), '%Y-%m')
        UNION ALL
        SELECT r.event_id, DATE_FORMAT(CONVERT_TZ('1970-01-01 00:00:00' + INTERVAL UNIX_TIMESTAMP(tk.cancelled_at) SECOND, '+00:00', 'Europe/Zagreb'), '%Y-%m'),
               0, 0, SUM(tk.refund_amount)
          FROM ticket tk
          JOIN reservation_item ri ON ri.id = tk.reservation_item_id
          JOIN reservation r       ON r.id  = ri.reservation_id
         WHERE tk.cancelled_at IS NOT NULL
         GROUP BY r.event_id, DATE_FORMAT(CONVERT_TZ('1970-01-01 00:00:00' + INTERVAL UNIX_TIMESTAMP(tk.cancelled_at) SECOND, '+00:00', 'Europe/Zagreb'), '%Y-%m')
       ) x
  JOIN event e ON e.id = x.event_id
 GROUP BY x.event_id, e.organizer_id, e.name, x.month;
--rollback DROP VIEW v_revenue_monthly;

--changeset eventhub:004-v_reserved_check dbms:mariadb splitStatements:false rollbackSplitStatements:false
CREATE OR REPLACE VIEW v_reserved_check AS
SELECT c.id AS category_id, c.reserved,
       COALESCE(p.q, 0) + COALESCE(t.q, 0) AS computed
  FROM ticket_category c
  LEFT JOIN (SELECT ri.category_id, SUM(ri.quantity) AS q
               FROM reservation_item ri JOIN reservation r ON r.id = ri.reservation_id
              WHERE r.status = 'pending'
              GROUP BY ri.category_id) p ON p.category_id = c.id
  LEFT JOIN (SELECT ri.category_id, COUNT(*) AS q
               FROM ticket tk JOIN reservation_item ri ON ri.id = tk.reservation_item_id
              WHERE tk.cancelled_at IS NULL
              GROUP BY ri.category_id) t ON t.category_id = c.id
 WHERE c.reserved <> COALESCE(p.q, 0) + COALESCE(t.q, 0);
--rollback DROP VIEW v_reserved_check;
