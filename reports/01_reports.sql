-- Pokrenuti nakon init + seed, iskljucivo nad eventhub (ne eventhub_perf).
USE eventhub;

-- Q1. Koji eventi imaju najvise potvrdenih karata?
-- Potvrdene karte: nevraćene karte potvrdenih rezervacija; ukljuceni eventi s nulom.
SELECT event_id, event_name, confirmed_tickets
FROM v_ticket_stats
ORDER BY confirmed_tickets DESC, event_id;

-- Q2. Koji kupci imaju najvise rezervacija?
-- Broje se svi statusi rezervacija; kupci bez rezervacija imaju 0.
SELECT b.id AS buyer_id, b.name, b.surname, COUNT(r.id) AS reservations
FROM buyer b LEFT JOIN reservation r ON r.buyer_id = b.id
GROUP BY b.id, b.name, b.surname
ORDER BY reservations DESC, buyer_id;

-- Q3. Koji eventi imaju manje od 10 % slobodnih karata?
-- Slobodno / prodajni kapacitet kategorija; strogo manje od 10 %, bez zaokruzivanja u filtru.
SELECT event_id, event_name, sellable_capacity, reserved, remaining, remaining_pct
FROM v_event_capacity
WHERE sellable_capacity > 0 AND remaining * 100 < sellable_capacity * 10
ORDER BY remaining_pct, event_id;

-- Q4. Koliki je ukupan prihod po eventu?
-- Prihod = cijene karata + naknade + zastita - povrati. LEFT JOIN zadrzava evente bez prodaje.
SELECT e.id AS event_id, e.name AS event_name,
       COALESCE(SUM(m.net_revenue), 0) AS net_revenue
FROM event e LEFT JOIN v_revenue_monthly m ON m.event_id = e.id
GROUP BY e.id, e.name
ORDER BY net_revenue DESC, event_id;

-- Q5. Koji eventi nemaju nijednu rezervaciju?
-- Bez rezervacija bilo kojeg statusa; view koristi LEFT JOIN event -> reservation.
SELECT event_id, event_name, total_reservations
FROM v_reservations_by_event
WHERE total_reservations = 0
ORDER BY event_id;

-- Q6. Kolika je stopa otkazivanja po eventu?
-- Po kartama: otkazao kupac / (sve rezervirane - istekle) * 100. Bez nazivnika rezultat je NULL.
SELECT event_id, event_name, tickets_reserved_ever, cancelled_tickets,
       expired_tickets, cancellation_rate_pct
FROM v_ticket_stats
ORDER BY cancellation_rate_pct DESC, event_id;

-- Q7. Koji organizatori imaju najveci prihod?
-- Ista definicija prihoda kao Q4. LEFT JOIN zadrzava organizatore bez prodaje.
SELECT o.id AS organizer_id, o.name AS organizer_name,
       COALESCE(SUM(m.net_revenue), 0) AS net_revenue
FROM organizer o LEFT JOIN v_revenue_monthly m ON m.organizer_id = o.id
GROUP BY o.id, o.name
ORDER BY net_revenue DESC, organizer_id;

-- Q8. Kakav je mjesecni trend prihoda?
-- Prodaja i zastita po confirmed_at, povrati po cancelled_at; samo mjeseci s transakcijama.
SELECT month, SUM(ticket_gross) AS ticket_gross,
       SUM(protection_fees) AS protection_fees, SUM(refunds) AS refunds,
       SUM(net_revenue) AS net_revenue
FROM v_revenue_monthly
GROUP BY month
ORDER BY month;
