-- ODBACENI kandidati: arhiva prethodne konfiguracije, nije konacni izbor.
-- Za reprodukciju: 02_baseline -> 07_rejected_indexes -> 04_after.
-- EventHub TASK 7: samo indeksi; nakon 02_baseline.sql, prije 04_after.sql.
USE eventhub_perf;
-- Q3: confirmed_at prvi zbog selektivnog raspona. Zadrzavamo postojeci uski
-- indeks; siri pokrivajuci kandidat nije ubrzao mjesecni trend (06_rejected_cover).
CREATE INDEX IF NOT EXISTS idx_res_confirmed_at ON reservation (confirmed_at);
-- Q4: jednakost buyer_id, zatim created_at/id za stabilan ORDER BY i LIMIT 10.
-- Obrnuto citanje B-tree zadovoljava oba DESC, bez filesort.
-- Ne dodajemo event_id/status: dohvat samo 10 redaka ne opravdava siri indeks.
CREATE INDEX IF NOT EXISTS idx_res_buyer_created
  ON reservation (buyer_id, created_at, id);
-- Q5: cancelled_at daje selektivni raspon, refund_amount pokriva SUM.
-- Q2: reservation_item_id pokriva JOIN povrata bez dohvata cijele karte.
CREATE INDEX IF NOT EXISTS idx_ticket_refund_cover
  ON ticket (cancelled_at, reservation_item_id, refund_amount);
-- Ukloni odbaceni kandidat i redundantni uski lijevi prefiks za povrate.
DROP INDEX IF EXISTS idx_res_confirmed_cover ON reservation;
DROP INDEX IF EXISTS idx_ticket_cancelled_at ON ticket;
-- FK/UNIQUE i operativni idx_res_status_expires/idx_event_date ostaju.
ANALYZE TABLE reservation, ticket;
