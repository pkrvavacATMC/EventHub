#!/bin/bash
# =====================================================================
# EventHub - tests/06_concurrency.sh : zadnja karta, dva kupca istovremeno
#
# Pokretanje (nakon init + seed):
#   bash tests/06_concurrency.sh
#
# Svaki dio stvara NOVI event s kapacitetom 10, od cega je 9 vec prodano
# (ostaje tocno 1 karta). Zatim dvije (ili vise) NEOVISNE sesije baze
# istovremeno pokusavaju kupiti tu zadnju kartu.
#
#   A  BEZ ZAKLJUCAVANJA (prije popravka): obicni SELECT -> pauza -> upis
#      -> obje sesije vide 1 slobodnu kartu i obje je kupe (oversell).
#   B  SELECT ... FOR UPDATE (rjesenje): druga sesija ceka na lock,
#      zatim vidi 0 slobodnih i odbija.
#   C  CHECK ograničenje kao zadnja linija obrane: bez FOR UPDATE, ali s
#      relativnim UPDATE-om; drugi upis odbije chk_category_reserved.
#   D  STVARNE PROCEDURE: 10 sesija istovremeno zove create_reservation +
#      confirm_reservation za zadnju kartu -> uspije tocno jedna.
#
# Spajanje: varijabla DB_CMD; $OPTS su opcije klijenta koje skripta dodaje.
# Zadano: Docker kontejner eventhub-db (kao tests/01_invalid_data.sql).
# Lokalno npr.:  DB_CMD='mariadb -uroot -pLOZINKA $OPTS eventhub' bash tests/06_concurrency.sh
# =====================================================================
set -uo pipefail
DB_CMD=${DB_CMD:-'docker exec -i eventhub-db sh -c "mariadb -uroot -p\"\$MARIADB_ROOT_PASSWORD\" $OPTS eventhub"'}
db()  { local OPTS="$1"; eval "$DB_CMD"; }   # SQL sa stdin
q()   { echo "$1" | db "-N -B"; }            # jedna vrijednost
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0; SUMMARY=""

# ---------------------------------------------------------------------
# Priprema: novi event, kategorija 10 mjesta, 9 prodano (4+4+1, potvrdeno)
# ---------------------------------------------------------------------
setup_event() {   # $1 = oznaka dijela; ispisuje "EVENT CAT BUYER"
  db "-N -B" <<SQL
INSERT IGNORE INTO city (name) VALUES ('Demo grad');
SET @city = (SELECT id FROM city WHERE name = 'Demo grad');
INSERT IGNORE INTO organizer (name, email) VALUES ('Demo organizator', 'demo-org@eventhub.test');
SET @org = (SELECT id FROM organizer WHERE email = 'demo-org@eventhub.test');
INSERT IGNORE INTO buyer (name, surname, email, city_id) VALUES ('Demo', 'Kupac', 'demo-buyer@eventhub.test', @city);
SET @buyer = (SELECT id FROM buyer WHERE email = 'demo-buyer@eventhub.test');
SET @loc = (SELECT MIN(id) FROM location WHERE name = 'Demo dvorana');
INSERT INTO location (name, city_id, capacity) SELECT 'Demo dvorana', @city, 100 FROM DUAL WHERE @loc IS NULL;
SET @loc = (SELECT MIN(id) FROM location WHERE name = 'Demo dvorana');
INSERT INTO event (name, event_date, capacity, location_id, organizer_id, event_type_id)
VALUES (CONCAT('Konkurentnost $1 ', DATE_FORMAT(NOW(6), '%Y-%m-%d %H:%i:%s.%f')), NOW() + INTERVAL 30 DAY, 10, @loc, @org, (SELECT id FROM event_type WHERE code = 'other'));
SET @ev = LAST_INSERT_ID();
INSERT INTO ticket_category (event_id, name, price, service_fee, capacity, seating_type)
VALUES (@ev, 'Parter', 20.00, 2.00, 10, 'standing');
SET @cat = LAST_INSERT_ID();
CALL create_reservation(@buyer, @ev, CONCAT('[{"category_id":', @cat, ',"quantity":4}]'), 0, @r); CALL confirm_reservation(@r);
CALL create_reservation(@buyer, @ev, CONCAT('[{"category_id":', @cat, ',"quantity":4}]'), 0, @r); CALL confirm_reservation(@r);
CALL create_reservation(@buyer, @ev, CONCAT('[{"category_id":', @cat, ',"quantity":1}]'), 0, @r); CALL confirm_reservation(@r);
SELECT @ev, @cat, @buyer;
SQL
}

# stvarno prodano = karte iz rezervacija koje nisu otkazane (pending + confirmed)
state() {   # $1 = event, $2 = cat -> "kapacitet reserved stvarno uspjesnih_kupnji_zadnje_karte"
  q "SELECT c.capacity, c.reserved,
            (SELECT COALESCE(SUM(ri.quantity),0) FROM reservation r JOIN reservation_item ri ON ri.reservation_id = r.id
              WHERE r.event_id = $1 AND r.status <> 'cancelled'),
            (SELECT COUNT(*) FROM reservation r JOIN reservation_item ri ON ri.reservation_id = r.id
              WHERE r.event_id = $1 AND r.status <> 'cancelled' AND ri.quantity = 1) - 1
       FROM ticket_category c WHERE c.id = $2"
}

show_state() {   # $1 naslov, $2 event, $3 cat
  echo "--- stanje nakon: $1 ---"
  echo "SELECT c.capacity AS kapacitet, c.reserved AS brojac_reserved,
               (SELECT COALESCE(SUM(ri.quantity),0) FROM reservation r JOIN reservation_item ri ON ri.reservation_id = r.id
                 WHERE r.event_id = $2 AND r.status <> 'cancelled') AS stvarno_prodano,
               (SELECT COUNT(*) FROM ticket t JOIN reservation_item ri ON ri.id = t.reservation_item_id
                 WHERE ri.event_id = $2 AND t.cancelled_at IS NULL) AS izdanih_karata,
               IF(EXISTS(SELECT 1 FROM v_reserved_check WHERE category_id = $3), 'NEKONZISTENTNO', 'OK') AS v_reserved_check
          FROM ticket_category c WHERE c.id = $3;" | db "-t"
}

check() {   # $1 opis, $2 uvjet (bash izraz), $3 detalj
  if eval "$2"; then R=PASS; PASS=$((PASS+1)); else R=FAIL; FAIL=$((FAIL+1)); fi
  SUMMARY+=$(printf "%-4s | %-58s | %s" "$R" "$1" "$3")$'\n'
}

# ---------------------------------------------------------------------
# Jedna "rucna" kupnja zadnje karte (1 karta). $1 = sesija, $2 = nacin citanja
#   plain    : SELECT bez locka, upis apsolutne vrijednosti (reserved = procitano + 1)
#   forupdate: SELECT ... FOR UPDATE, relativni upis (reserved = reserved + 1)
#   relative : SELECT bez locka, relativni upis -> stiti samo CHECK
# ---------------------------------------------------------------------
manual_buy() {
  local S=$1 MODE=$2 EV=$3 CAT=$4 BUYER=$5 LOCK="" UPD
  [ "$MODE" = forupdate ] && LOCK="FOR UPDATE"
  if [ "$MODE" = plain ]; then UPD="reserved = @seen_reserved + 1"; else UPD="reserved = reserved + 1"; fi
  db "-t" <<SQL
SET SESSION TRANSACTION ISOLATION LEVEL READ COMMITTED;
SELECT '$S' AS sesija, 'START, citam slobodna mjesta' AS korak, TIME(NOW(6)) AS vrijeme;
DELIMITER //
BEGIN NOT ATOMIC
  DECLARE EXIT HANDLER FOR SQLEXCEPTION
  BEGIN
    DECLARE v_msg VARCHAR(300);
    GET DIAGNOSTICS CONDITION 1 v_msg = MESSAGE_TEXT;
    ROLLBACK;
    SELECT '$S' AS sesija, CONCAT('ODBIJENO (greska baze): ', v_msg) AS korak, TIME(NOW(6)) AS vrijeme;
  END;
  START TRANSACTION;
  SELECT reserved, capacity - reserved INTO @seen_reserved, @seen_free
    FROM ticket_category WHERE id = $CAT $LOCK;
  SELECT '$S' AS sesija, CONCAT('vidim slobodnih: ', @seen_free) AS korak, TIME(NOW(6)) AS vrijeme;
  DO SLEEP(2);                         -- "kupac upisuje podatke" - prozor za utrku
  IF @seen_free >= 1 THEN
    UPDATE ticket_category SET $UPD WHERE id = $CAT;
    INSERT INTO reservation (event_id, buyer_id, expires_at) VALUES ($EV, $BUYER, NOW() + INTERVAL 15 MINUTE);
    INSERT INTO reservation_item (reservation_id, event_id, category_id, quantity, price_per_ticket, service_fee_per_ticket)
    SELECT LAST_INSERT_ID(), $EV, id, 1, price, service_fee FROM ticket_category WHERE id = $CAT;
    COMMIT;
    SELECT '$S' AS sesija, 'KUPIO zadnju kartu (COMMIT)' AS korak, TIME(NOW(6)) AS vrijeme;
  ELSE
    ROLLBACK;
    SELECT '$S' AS sesija, 'ODBIJENO: nema slobodnih mjesta' AS korak, TIME(NOW(6)) AS vrijeme;
  END IF;
END//
DELIMITER ;
SQL
}

race_two() {   # $1 nacin, $2 ev, $3 cat, $4 buyer : sesija B krece 0.3 s nakon A
  manual_buy A "$1" "$2" "$3" "$4" > "$TMP/A.txt" 2>&1 &
  sleep 0.3
  manual_buy B "$1" "$2" "$3" "$4" > "$TMP/B.txt" 2>&1 &
  wait
  cat "$TMP/A.txt" "$TMP/B.txt" | grep -E '^\| (A|B) ' | sort -t'|' -k4
}

echo "=================================================================="
echo " A) BEZ ZAKLJUCAVANJA - reprodukcija problema"
echo "=================================================================="
read EV CAT BUYER < <(setup_event A)
echo "Event $EV: kapacitet 10, prodano 9, ostaje 1 karta. Sesije A i B krecu istovremeno."
race_two plain "$EV" "$CAT" "$BUYER"
show_state "A" "$EV" "$CAT"
read CAPA RES REAL WIN < <(state "$EV" "$CAT")
check "A: problem reproduciran (prodano > kapacitet)" '[ "$REAL" -gt "$CAPA" ]' "kapacitet=$CAPA, brojac=$RES, stvarno=$REAL, kupili zadnju=$WIN"
# Popravak stete (brisanje je zabranjeno): visak (zadnja rezervacija) se otkazuje.
# Brojac ga nikad nije ubrojio (izgubljeni upis), pa se reserved ne mijenja.
q "UPDATE reservation SET status = 'cancelled', cancelled_at = NOW(), cancel_reason = 'buyer'
    WHERE id = (SELECT MAX(id) FROM (SELECT id FROM reservation WHERE event_id = $EV AND status = 'pending') x)" >/dev/null
show_state "A - rucni popravak (visak otkazan)" "$EV" "$CAT"

echo
echo "=================================================================="
echo " B) RJESENJE: SELECT ... FOR UPDATE (pesimisticko zakljucavanje)"
echo "=================================================================="
read EV CAT BUYER < <(setup_event B)
echo "Event $EV: kapacitet 10, prodano 9, ostaje 1 karta. Sesije A i B krecu istovremeno."
race_two forupdate "$EV" "$CAT" "$BUYER"
show_state "B" "$EV" "$CAT"
read CAPA RES REAL WIN < <(state "$EV" "$CAT")
check "B: FOR UPDATE - zadnju kartu kupila tocno 1 sesija" '[ "$WIN" -eq 1 ] && [ "$REAL" -le "$CAPA" ] && [ "$RES" -eq "$REAL" ]' "kapacitet=$CAPA, brojac=$RES, stvarno=$REAL, kupili zadnju=$WIN"

echo
echo "=================================================================="
echo " C) ZADNJA LINIJA OBRANE: CHECK chk_category_reserved (bez locka)"
echo "=================================================================="
read EV CAT BUYER < <(setup_event C)
echo "Event $EV: obje sesije vide 1 slobodno mjesto, ali upis reserved+1 druge sesije krsi CHECK."
race_two relative "$EV" "$CAT" "$BUYER"
show_state "C" "$EV" "$CAT"
read CAPA RES REAL WIN < <(state "$EV" "$CAT")
check "C: CHECK odbio drugi upis, nema prekoracenja" '[ "$WIN" -eq 1 ] && [ "$REAL" -le "$CAPA" ] && [ "$RES" -eq "$REAL" ]' "kapacitet=$CAPA, brojac=$RES, stvarno=$REAL, kupili zadnju=$WIN"

echo
echo "=================================================================="
echo " D) STVARNE PROCEDURE: 10 sesija istovremeno, create + confirm"
echo "=================================================================="
read EV CAT BUYER < <(setup_event D)
echo "Event $EV: 10 neovisnih sesija istovremeno trazi zadnju kartu."
for i in $(seq 1 10); do
  ( db "-N -B" <<SQL
DELIMITER //
BEGIN NOT ATOMIC
  DECLARE v_msg VARCHAR(300);
  DECLARE EXIT HANDLER FOR SQLEXCEPTION
  BEGIN
    GET DIAGNOSTICS CONDITION 1 v_msg = MESSAGE_TEXT;
    SELECT CONCAT('sesija $i: ODBIJENO - ', v_msg);
  END;
  CALL create_reservation($BUYER, $EV, '[{"category_id":$CAT,"quantity":1}]', 0, @r);
  CALL confirm_reservation(@r);
  SELECT CONCAT('sesija $i: KUPILA zadnju kartu (rezervacija ', @r, ', confirmed)');
END//
DELIMITER ;
SQL
  ) > "$TMP/D$i.txt" 2>&1 &
done
wait
cat "$TMP"/D*.txt | sort -V
show_state "D" "$EV" "$CAT"
read CAPA RES REAL WIN < <(state "$EV" "$CAT")
CONF=$(q "SELECT COUNT(*) FROM reservation r JOIN reservation_item ri ON ri.reservation_id = r.id
           WHERE r.event_id = $EV AND r.status = 'confirmed' AND ri.quantity = 1")
check "D: procedure - potvrdena tocno 1 od 10 kupnji zadnje karte" '[ "$WIN" -eq 1 ] && [ "$CONF" -eq 2 ] && [ "$REAL" -le "$CAPA" ] && [ "$RES" -eq "$REAL" ]' "kapacitet=$CAPA, brojac=$RES, stvarno=$REAL, kupili zadnju=$WIN"

echo
echo "=================================================================="
echo " SAZETAK"
echo "=================================================================="
printf "%s" "$SUMMARY"
echo "UKUPNO: $PASS PASS, $FAIL FAIL"

# Neuspjeh mora biti vidljiv automatiziranom runneru.
[ "$FAIL" -eq 0 ]
