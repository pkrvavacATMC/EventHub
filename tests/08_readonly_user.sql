-- Pokrece se KAO eventhub_report (vidi naredbu u docs/08_administracija.md).
-- Citanje mora proci; svaka izmjena mora pasti s ERROR 1142 ili 1370.
SELECT CURRENT_USER();
SHOW GRANTS;

-- Citanje: prolazi
SELECT COUNT(*) AS rezervacije FROM reservation;
SELECT month, net_revenue FROM v_revenue_monthly ORDER BY month LIMIT 3;

-- Izmjene: moraju pasti (WHERE 1=0 = nista se ne bi promijenilo ni da prode)
INSERT INTO city (name) VALUES ('Test');                       -- ERROR 1142
UPDATE reservation SET status = 'cancelled' WHERE 1 = 0;       -- ERROR 1142
DELETE FROM ticket WHERE 1 = 0;                                -- ERROR 1142
CREATE TABLE test_tablica (id INT);                            -- ERROR 1142
DROP TABLE nepostojeca_tablica;                                -- ERROR 1142
CALL confirm_reservation(999999);                              -- ERROR 1370