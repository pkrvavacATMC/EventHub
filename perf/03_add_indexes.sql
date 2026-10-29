-- Konacna umjerena konfiguracija: uski indeksi za selektivne datumske upite.
-- Dobitke, prostor i ogranicenja usporedbe daje aktualni docs/07_performanse.md.
USE eventhub_perf;
CREATE INDEX IF NOT EXISTS idx_res_confirmed_at ON reservation (confirmed_at);
CREATE INDEX IF NOT EXISTS idx_ticket_cancelled_at ON ticket (cancelled_at);
-- FK indeks dovoljan je za mali broj rezervacija jednog kupca u testnom skupu.
DROP INDEX IF EXISTS idx_res_buyer_created ON reservation;
DROP INDEX IF EXISTS idx_ticket_refund_cover ON ticket;
DROP INDEX IF EXISTS idx_res_confirmed_cover ON reservation;
ANALYZE TABLE reservation, ticket;
