--liquibase formatted sql

-- Lozinke nisu dio changeloga. Korisnike prethodno stvara 005-users.sql.

--changeset eventhub:005-grants dbms:mariadb
GRANT EXECUTE ON PROCEDURE eventhub.create_reservation  TO 'eventhub_app'@'%';
GRANT EXECUTE ON PROCEDURE eventhub.confirm_reservation TO 'eventhub_app'@'%';
GRANT EXECUTE ON PROCEDURE eventhub.cancel_reservation  TO 'eventhub_app'@'%';
GRANT EXECUTE ON PROCEDURE eventhub.cancel_ticket       TO 'eventhub_app'@'%';
GRANT EXECUTE ON PROCEDURE eventhub.check_in_ticket     TO 'eventhub_app'@'%';
GRANT SELECT ON eventhub.v_category_capacity     TO 'eventhub_app'@'%';
GRANT SELECT ON eventhub.v_event_capacity        TO 'eventhub_app'@'%';
GRANT SELECT ON eventhub.v_reservations_by_event TO 'eventhub_app'@'%';
GRANT SELECT ON eventhub.v_ticket_stats          TO 'eventhub_app'@'%';
GRANT SELECT ON eventhub.v_attendance            TO 'eventhub_app'@'%';
GRANT SELECT ON eventhub.v_revenue_monthly       TO 'eventhub_app'@'%';
GRANT SELECT, SHOW VIEW ON eventhub.* TO 'eventhub_report'@'%';

-- Pri ponistavanju ukloni ovlasti testnih korisnika.
--rollback REVOKE EXECUTE ON PROCEDURE eventhub.create_reservation  FROM 'eventhub_app'@'%';
--rollback REVOKE EXECUTE ON PROCEDURE eventhub.confirm_reservation FROM 'eventhub_app'@'%';
--rollback REVOKE EXECUTE ON PROCEDURE eventhub.cancel_reservation  FROM 'eventhub_app'@'%';
--rollback REVOKE EXECUTE ON PROCEDURE eventhub.cancel_ticket       FROM 'eventhub_app'@'%';
--rollback REVOKE EXECUTE ON PROCEDURE eventhub.check_in_ticket     FROM 'eventhub_app'@'%';
--rollback REVOKE SELECT ON eventhub.v_category_capacity     FROM 'eventhub_app'@'%';
--rollback REVOKE SELECT ON eventhub.v_event_capacity        FROM 'eventhub_app'@'%';
--rollback REVOKE SELECT ON eventhub.v_reservations_by_event FROM 'eventhub_app'@'%';
--rollback REVOKE SELECT ON eventhub.v_ticket_stats          FROM 'eventhub_app'@'%';
--rollback REVOKE SELECT ON eventhub.v_attendance            FROM 'eventhub_app'@'%';
--rollback REVOKE SELECT ON eventhub.v_revenue_monthly       FROM 'eventhub_app'@'%';
--rollback REVOKE SELECT, SHOW VIEW ON eventhub.* FROM 'eventhub_report'@'%';
