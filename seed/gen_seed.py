"""Generira seed/01_seed.sql (deterministicki, random.Random(42)).
Svaka rezervacija ide kroz prave procedure; vrijeme se simulira sa SET timestamp.
Python simulira zauzetost sjedala/kapaciteta da bi svi pozivi bili valjani."""
import random, datetime as dt, sys

R = random.Random(42)
NOW_REAL = dt.datetime(2026, 10, 27, 18, 0)   # zadnji trenutak "povijesti" u seedu

def ts(d): return d.strftime('%Y-%m-%d %H:%M:%S')

cities = ['Zagreb', 'Split', 'Rijeka', 'Osijek', 'Zadar']
locations = [  # name, city_id, capacity
    ('Velika dvorana Sjever', 1, 5000),
    ('Klub Kotlovnica', 1, 300),
    ('Gradska arena Split', 2, 3000),
    ('Ljetna pozornica Rijeka', 3, 800),
    ('Gradsko kazaliste Osijek', 4, 400),
]
organizers = [('Adria Live d.o.o.', 'info@adrialive.example'),
              ('Zvuk Grada j.d.o.o.', 'kontakt@zvukgrada.example'),
              ('Kultura Plus', 'ured@kulturaplus.example')]
first = ['Ana','Ivan','Marija','Luka','Petra','Marko','Ivana','Josip','Lucija','Tomislav',
         'Maja','Filip','Katarina','Matej','Ema','Domagoj','Sara','Karlo','Lana','Nikola']
last = ['Horvat','Kovacevic','Babic','Maric','Juric','Novak','Kovacic','Knezevic','Vukovic','Markovic',
        'Petrovic','Matic','Tomic','Pavlovic','Bozic','Blazevic','Grgic','Pavic','Radic','Peric']
buyers = []
for i in range(40):
    f, l = first[i % 20], last[(i * 7) % 20]
    buyers.append((f, l, f'{f.lower()}.{l.lower()}{i+1}@example.com', (i % 5) + 1))

# events: name, date, capacity, location_id, organizer_id, categories
# category: name, price, fee, capacity, type, (rows, per_row) za seated
events = [
 ('Zimska jazz vecer', dt.datetime(2026,2,20,20,0), 120, 2, 2,
   [('Parter',25,2,100,'standing',None), ('Lounge',45,3,20,'seated',(2,10))]),
 ('Proljetni rock festival', dt.datetime(2026,4,18,19,0), 2000, 1, 1,
   [('Parter',40,3,1500,'standing',None), ('VIP',90,5,40,'seated',(4,10))]),
 ('Klasika pod zvijezdama', dt.datetime(2026,7,10,21,0), 400, 4, 3,
   [('Sjedala',35,2,60,'seated',(6,10)), ('Stajanje',20,1,100,'standing',None)]),
 ('Stand-up vecer', dt.datetime(2026,9,12,20,0), 150, 5, 2,
   [('Parter',18,1,40,'seated',(4,10))]),
 ('Jesenski indie koncert', dt.datetime(2026,11,21,20,0), 50, 2, 2,
   [('Parter',22,2,20,'standing',None)]),
 ('Novogodisnji koncert', dt.datetime(2026,12,31,22,0), 3000, 1, 1,
   [('Parter',50,4,2000,'standing',None), ('VIP',120,6,40,'seated',(4,10))]),
 ('Kazalisna premijera', dt.datetime(2027,1,15,19,30), 200, 5, 3,
   [('Sjedala',28,2,40,'seated',(4,10))]),
 ('Ljetni festival Split', dt.datetime(2027,6,20,18,0), 3000, 3, 1,
   [('Dnevna ulaznica',35,3,2500,'standing',None), ('Djeca do 12 godina',0,0,50,'standing',None)]),
]

# --- ID-jevi kategorija i sjedala (svjeza baza: AUTO_INCREMENT od 1) ---
cats = []          # dict po kategoriji
cat_id = 0
for ei, ev in enumerate(events, start=1):
    for c in ev[5]:
        cat_id += 1
        cats.append(dict(id=cat_id, event=ei, name=c[0], price=c[1], fee=c[2], cap=c[3],
                         type=c[4], grid=c[5], reserved=0, seats=[], free=set()))
seat_id = 0
for c in cats:
    if c['type'] == 'seated':
        rows, per = c['grid']
        for r in range(rows):
            for s in range(per):
                seat_id += 1
                c['seats'].append((seat_id, chr(65 + r), s + 1))
                c['free'].add(seat_id)
cat_by_event = {}
for c in cats: cat_by_event.setdefault(c['event'], []).append(c)

out = []
w = out.append

def take_items(ev_idx, total):
    """Odaberi stavke za rezervaciju; vrati [(cat, qty, [seat_ids])] ili None."""
    clist = cat_by_event[ev_idx]
    items, left = [], total
    order = clist[:]
    R.shuffle(order)
    for c in order:
        if left == 0: break
        avail = c['cap'] - c['reserved']
        if avail <= 0: continue
        q = min(left, avail) if c is order[-1] else min(left, avail, R.randint(1, left))
        if c['type'] == 'seated':
            free = sorted(c['free'])
            if len(free) < q: q = len(free)
            if q == 0: continue
            start = R.randrange(0, len(free) - q + 1)
            seats = free[start:start + q]
        else:
            seats = []
        items.append((c, q, seats))
        left -= q
    if left > 0 and not items: return None
    return items

def json_items(items):
    parts = []
    for c, q, seats in items:
        if c['type'] == 'seated':
            parts.append('{"category_id":%d,"seats":[%s]}' % (c['id'], ','.join(map(str, seats))))
        else:
            parts.append('{"category_id":%d,"quantity":%d}' % (c['id'], q))
    return '[' + ','.join(parts) + ']'

def hold(items):
    for c, q, seats in items:
        c['reserved'] += q
        for s in seats: c['free'].discard(s)

def release(items):
    for c, q, seats in items:
        c['reserved'] -= q
        for s in seats: c['free'].add(s)

# --- plan rezervacija ---
plan = []   # (booked_at, event_idx, buyer, total, outcome, protection)
def rand_time(a, b):
    sec = int((b - a).total_seconds())
    t = a + dt.timedelta(seconds=R.randrange(sec))
    return t.replace(second=0)

counts = {1: 26, 2: 46, 3: 26, 4: 16, 6: 32, 8: 22}
for ev_idx, n in counts.items():
    ev_date = events[ev_idx - 1][1]
    if ev_date < NOW_REAL:
        a = max(dt.datetime(2026, 1, 10), ev_date - dt.timedelta(days=70)); b = ev_date - dt.timedelta(days=1)
        weights = [('confirmed', 62), ('refund', 13), ('cancel_pending', 10), ('expired', 15)]
    else:
        a = dt.datetime(2026, 8, 1); b = NOW_REAL - dt.timedelta(days=1)
        weights = [('confirmed', 66), ('refund', 9), ('cancel_pending', 10), ('expired', 15)]
    for _ in range(n):
        outcome = R.choices([x for x, _ in weights], [y for _, y in weights])[0]
        plan.append((rand_time(a, b), ev_idx, R.randint(1, 40), R.choice([1, 1, 2, 2, 2, 3, 4]),
                     outcome, R.random() < 0.25))
# Event 5: skoro rasprodan (19/20) + jedna istekla i jedna otkazana
e5 = [(dt.datetime(2026,9,3,10,15), 5, 3, 2, 'expired', False),
      (dt.datetime(2026,9,5,18,40), 5, 7, 4, 'confirmed', False),
      (dt.datetime(2026,9,9,12,5), 5, 11, 4, 'confirmed', True),
      (dt.datetime(2026,9,14,21,30), 5, 15, 1, 'cancel_pending', False),
      (dt.datetime(2026,9,20,9,50), 5, 19, 4, 'confirmed', False),
      (dt.datetime(2026,10,2,16,20), 5, 23, 4, 'confirmed', False),
      (dt.datetime(2026,10,11,11,0), 5, 27, 3, 'confirmed', False)]
plan += e5
plan.sort(key=lambda p: p[0])

stats = dict(reservations=0, confirmed=0, refund=0, cancel_pending=0, expired=0, checkins=0)
for (t, ev_idx, buyer, total, outcome, prot) in plan:
    ev_name, ev_date = events[ev_idx - 1][0], events[ev_idx - 1][1]
    items = take_items(ev_idx, total)
    if not items: continue
    stats['reservations'] += 1
    hold(items)
    w(f"-- {ts(t)} | {ev_name} | kupac {buyer} | {outcome}{' | zastita' if prot else ''}")
    w(f"SET timestamp = UNIX_TIMESTAMP('{ts(t)}');")
    w(f"CALL create_reservation({buyer}, {ev_idx}, '{json_items(items)}', {1 if prot else 0}, @r);")
    if outcome == 'cancel_pending':
        w(f"SET timestamp = UNIX_TIMESTAMP('{ts(t + dt.timedelta(minutes=R.randint(2,10)))}');")
        w("CALL cancel_reservation(@r);")
        release(items); stats['cancel_pending'] += 1
    elif outcome == 'expired':
        w(f"SET timestamp = UNIX_TIMESTAMP('{ts(t + dt.timedelta(minutes=16))}');")
        w("CALL expire_reservations();")
        release(items); stats['expired'] += 1
    else:
        ct = t + dt.timedelta(minutes=R.randint(2, 12))
        w(f"SET timestamp = UNIX_TIMESTAMP('{ts(ct)}');")
        w("CALL confirm_reservation(@r);")
        stats['confirmed'] += 1
        cancelled_one = None
        if outcome == 'refund':
            end = min(ev_date - dt.timedelta(hours=2), NOW_REAL)
            start = ct + dt.timedelta(days=1)
            if start < end:
                rt = rand_time(start, end)
                c, q, seats = items[0]
                w(f"SET timestamp = UNIX_TIMESTAMP('{ts(rt)}');")
                if seats:
                    w(f"SELECT t.id INTO @t FROM ticket t JOIN reservation_seat rs ON rs.id = t.reservation_seat_id "
                      f"WHERE rs.seat_id = {seats[0]} AND rs.reservation_item_id IN "
                      f"(SELECT id FROM reservation_item WHERE reservation_id = @r);")
                    c['free'].add(seats[0])
                else:
                    w(f"SELECT MIN(t.id) INTO @t FROM ticket t JOIN reservation_item ri ON ri.id = t.reservation_item_id "
                      f"WHERE ri.reservation_id = @r AND ri.category_id = {c['id']};")
                c['reserved'] -= 1
                w("CALL cancel_ticket(@t, @refund);")
                stats['refund'] += 1
        if ev_date < NOW_REAL and R.random() < 0.85:
            w(f"SET timestamp = UNIX_TIMESTAMP('{ts(ev_date - dt.timedelta(minutes=R.randint(5,50)))}');")
            w("CALL seed_check_in_reservation(@r);")
            stats['checkins'] += 1
    w("")

# ------------------------------------------------------------------ zapis
H = []
h = H.append
h("""-- =====================================================================
-- EventHub - seed/01_seed.sql : realni testni podaci (task 3 i 4)
--
-- Pokretanje (na SVJEZOJ bazi, odmah nakon Liquibase migracija):
--   docker exec -i eventhub-db sh -c 'mariadb -uroot -p"$MARIADB_ROOT_PASSWORD" eventhub' < seed/01_seed.sql
--
-- Kako radi:
--  * Sve rezervacije idu kroz prave procedure (create/confirm/cancel/expire/check-in),
--    pa vrijede sva pravila baze (kapacitet, 1-4 karte, sjedala, povrati...).
--  * Vrijeme se simulira sa SET timestamp: NOW() u ovoj sesiji "putuje" kroz 2026.,
--    pa podaci imaju realne datume kroz vise mjeseci (mjesecni trend prihoda).
--  * Scheduler za istek se privremeno iskljucuje, da ne bi (po stvarnom vremenu)
--    otkazao rezervaciju izmedu kreiranja i potvrde u seedu.
--  * Skripta je deterministicka: uvijek daje iste podatke (generirana iz gen_seed.py).
--
-- Sto pokriva (za izvjestaje iz taska 4):
--  * 8 evenata: 4 prosla (s check-inom), 4 buduca
--  * "Jesenski indie koncert": 19/20 prodano  -> manje od 10 % slobodno
--  * "Kazalisna premijera": nema nijedne rezervacije -> LEFT JOIN slucaj
--  * potvrdene kupnje, otkazane pending rezervacije, istekle rezervacije,
--    povrati (sa i bez zastite), sjedeca i stajaca mjesta, besplatna kategorija
-- =====================================================================
USE eventhub;

DELIMITER //
CREATE PROCEDURE seed_assert_empty()
BEGIN
  IF (SELECT COUNT(*) FROM event) > 0 OR (SELECT COUNT(*) FROM buyer) > 0 THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Seed se pokrece samo na praznoj bazi; postojeci podaci se ne brisu';
  END IF;
END//

-- Check-in svih vazecih karata jedne rezervacije (kroz pravu proceduru)
CREATE PROCEDURE seed_check_in_reservation(IN p_reservation_id INT)
BEGIN
  DECLARE done INT DEFAULT 0;
  DECLARE v_code CHAR(32);
  DECLARE v_event INT;
  DECLARE cur CURSOR FOR
    SELECT t.ticket_code FROM ticket t JOIN reservation_item ri ON ri.id = t.reservation_item_id
     WHERE ri.reservation_id = p_reservation_id AND t.cancelled_at IS NULL;
  DECLARE CONTINUE HANDLER FOR NOT FOUND SET done = 1;
  SELECT event_id INTO v_event FROM reservation WHERE id = p_reservation_id;
  OPEN cur;
  l: LOOP
    FETCH cur INTO v_code;
    IF done = 1 THEN LEAVE l; END IF;
    CALL check_in_ticket(v_event, v_code);
  END LOOP;
  CLOSE cur;
END//
DELIMITER ;

CALL seed_assert_empty();
ALTER EVENT ev_expire_reservations DISABLE;

-- ---------------------------------------------------------------------
-- Matični podaci (stanje na pocetku godine)
-- ---------------------------------------------------------------------
SET timestamp = UNIX_TIMESTAMP('2026-01-05 09:00:00');
""")
h("INSERT INTO city (name) VALUES " + ", ".join(f"('{c}')" for c in cities) + ";")
h("INSERT INTO location (name, city_id, capacity) VALUES\n  " +
  ",\n  ".join(f"('{n}', {ci}, {cap})" for n, ci, cap in locations) + ";")
h("INSERT INTO organizer (name, email) VALUES\n  " +
  ",\n  ".join(f"('{n}', '{e}')" for n, e in organizers) + ";")
h("INSERT INTO buyer (name, surname, email, address, city_id) VALUES\n  " +
  ",\n  ".join(f"('{f}', '{l}', '{e}', 'Ulica {i+1}', {ci})" for i, (f, l, e, ci) in enumerate(buyers)) + ";")
h("")
h("INSERT INTO event (name, event_date, capacity, location_id, organizer_id) VALUES\n  " +
  ",\n  ".join(f"('{e[0]}', '{ts(e[1])}', {e[2]}, {e[3]}, {e[4]})" for e in events) + ";")
h("")
h("INSERT INTO ticket_category (event_id, name, price, service_fee, capacity, seating_type) VALUES\n  " +
  ",\n  ".join(f"({c['event']}, '{c['name']}', {c['price']:.2f}, {c['fee']:.2f}, {c['cap']}, '{c['type']}')" for c in cats) + ";")
h("")
for c in cats:
    if c['type'] == 'seated':
        h(f"CALL generate_seats({c['id']}, {c['grid'][0]}, {c['grid'][1]});   -- {events[c['event']-1][0]} / {c['name']}")
h("""
-- ---------------------------------------------------------------------
-- Rezervacije kronoloskim redom
-- ---------------------------------------------------------------------
""")
F = []
F.append("""-- ---------------------------------------------------------------------
-- Kraj: vrati stvarno vrijeme, ukljuci scheduler, pocisti pomocne procedure
-- ---------------------------------------------------------------------
SET timestamp = DEFAULT;
ALTER EVENT ev_expire_reservations ENABLE;
DROP PROCEDURE seed_check_in_reservation;
DROP PROCEDURE seed_assert_empty;

-- Kontrola: brojaci moraju biti uskladeni (ocekivano: 0)
SELECT COUNT(*) AS neuskladjeni_brojaci FROM v_reserved_check;

-- Sazetak
SELECT
  (SELECT COUNT(*) FROM event)                                    AS eventi,
  (SELECT COUNT(*) FROM buyer)                                    AS kupci,
  (SELECT COUNT(*) FROM reservation)                              AS rezervacije,
  (SELECT COUNT(*) FROM reservation WHERE status = 'confirmed')   AS potvrdene,
  (SELECT COUNT(*) FROM reservation WHERE cancel_reason = 'buyer')   AS otkazane_kupac,
  (SELECT COUNT(*) FROM reservation WHERE cancel_reason = 'expired') AS istekle,
  (SELECT COUNT(*) FROM ticket)                                   AS karte,
  (SELECT COUNT(*) FROM ticket WHERE cancelled_at IS NOT NULL)    AS povrati,
  (SELECT COUNT(*) FROM ticket WHERE checked_in_at IS NOT NULL)   AS check_in;
""")
open(sys.argv[1], 'w').write("\n".join(H) + "\n" + "\n".join(out) + "\n" + "\n".join(F))
print(stats, file=sys.stderr)
