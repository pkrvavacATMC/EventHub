-- EventHub TASK 7: konacni izbor su izvorni uski indeksi.
-- Nakon 02_baseline.sql pokrenuti ovu skriptu pa nepromijenjeni 04_after.sql.
USE eventhub_perf;
-- Q3: datum prvi i jedini stupac za selektivni raspon potvrda.
-- InnoDB sekundarni indeks implicitno sadrzi PK id za JOIN na stavke.
CREATE INDEX IF NOT EXISTS idx_res_confirmed_at ON reservation (confirmed_at);
-- Q2/Q5: uski datum vec omogucuje range nad rijetkim povratima.
-- Pokrivajuci kandidat stedi ~0.15 ms za Q5 i ~8 ms za Q2; nije dovoljan
-- razlog za dodatni prostor. Izvorni rezultati sacuvani su u original.tsv
-- i rejected_buyer_refund.tsv; metodologija mjerenja nije promijenjena.
CREATE INDEX IF NOT EXISTS idx_ticket_cancelled_at ON ticket (cancelled_at);
-- Q4: ~22 rezervacije kupca vec se nalaze preko fk_res_buyer.
-- Slozeni indeks stedi ~13 mikrosekundi; INSERT medijan prethodne kombinacije
-- raste s ~82 na ~94 ms uz dodatni prostor reservation i ticket indeksa.
-- fk_res_buyer vec postoji u shemi i osiguran je u 02_baseline.sql.
DROP INDEX IF EXISTS idx_res_buyer_created ON reservation;
DROP INDEX IF EXISTS idx_ticket_refund_cover ON ticket;
DROP INDEX IF EXISTS idx_res_confirmed_cover ON reservation;
-- PK/UNIQUE/FK i ostali postojeci operativni indeksi ostaju.
ANALYZE TABLE reservation, ticket;
