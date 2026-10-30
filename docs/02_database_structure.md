# Struktura baze i projektne odluke

[ER dijagram](../eventhub-diagram.png) · [Postavljanje](../README.md) · [Prezentacija](09_presentation.md)

## Entiteti i veze

| Tablica | Namjena i veze |
| --- | --- |
| city | Zajednički šifrarnik gradova s IANA vremenskom zonom; jedan grad ima više lokacija i kupaca. |
| organizer | Jedan organizator upravlja većim brojem događaja. |
| location | Mjesto održavanja pripada jednom gradu i može ugostiti više događaja. |
| event | Događaj s određenim početkom pripada lokaciji, organizatoru i tipu događaja; ima više kategorija i rezervacija. |
| event_type | Devet početnih tipova događaja, primjerice koncert, kazalište i festival. |
| buyer | Poslovni podaci kupca s opcionalnim jedinstvenim external_id (UUID malim slovima, Keycloak sub); kupac može napraviti više rezervacija. |
| ticket_category | Cijena, naknada, kapacitet, vrsta mjesta i brojač zauzeća za kategoriju jednog događaja. |
| seat | Numerirano sjedalo u jednoj kategoriji; kombinacija kategorije, reda i broja je jedinstvena. |
| reservation | Rezervacija jednog kupca za jedan događaj, sa statusom, vremenskim oznakama i zaštitom povrata. |
| reservation_item | Količina i povijesni zapis cijene i naknade za kategoriju unutar rezervacije. |
| reservation_seat | Povijesni zapis privremenog zauzeća sjedala za stavku; oslobađanje omogućuje novo zauzeće. |
| ticket | Pojedinačna izdana karta s opcionalnim zauzećem sjedala, nasumičnim kodom te podacima o prijavi na ulazu i povratu. |

Događaji i kupci povezani su vezom više-prema-više preko rezervacija. Jedna rezervacija može imati više stavki, ali ukupno samo 1–4 karte. Karte za stajaća mjesta nemaju zauzeće sjedala. Sjedalo može imati više povijesnih zauzeća, ali samo jedno aktivno. Iz jednog zapisa zauzeća može se izdati najviše jedna karta.

## Poslovna pravila

- Jedna rezervacija pripada jednom događaju i ukupno ima **1–4 karte**, kroz jednu ili više kategorija.
- Cijena i service fee određeni su kategorijom; besplatna karta dolazi iz kategorije s cijenom **0**.
- `pending` rezervacija zauzima mjesta **15 minuta**. Event `ev_expire_reservations` radi svake minute i otkazuje istekle kao `expired`; oslobađanje slijedi u ciklusu schedulera, a potvrda nakon isteka već je odbijena.
- `pending` se otkazuje samo cijela; `confirmed` se otkazuje po karti. Istekle rezervacije ne ulaze u stopu otkazivanja kupaca.
- Refund protection iznosi **10 % zbroja cijena karata** i vraća **100 % cijene karte**. Bez zaštite: najmanje 7 dana prije početka **80 %**, najmanje 48 h **50 %**, inače **0 %**. Service fee i fee zaštite ne vraćaju se.
- Nakon početka događaja nema rezervacija ni otkazivanja. Check-in je dopušten od **24 h prije do 24 h nakon** početka, samo za događaj na čijem se ulazu karta skenira.
- Kod karte je nepredvidljiv **`HEX(RANDOM_BYTES(16))`**. Check-in normalizira mala slova i rubne razmake.
- Za sjedeću kategoriju kapacitet mora odgovarati broju sjedala stvorenih kroz `generate_seats`.
- Transakcijska povijest se zadržava: DELETE je zabranjen triggerima na transakcijskim tablicama.
- Datum i lokacija događaja provjeravaju se pri promjeni; već započeti događaj ne može se premjestiti niti mu se može pomaknuti početak.

## Model vremena

Svi sistemski trenuci poslovnih tablica su **TIMESTAMP**, a konekcije rade u **UTC-u**.
Jedini poslovni DATETIME je **`event.event_date`**: lokalni početak na mjestu održavanja, u IANA zoni `city.time_zone`, preko `event → location → city`.
`local_to_utc` pretvara taj početak u UTC; refund i check-in prozori uspoređuju stvarne UTC trenutke.
Procedure koje obrađuju te trenutke privremeno koriste UTC i vraćaju prethodnu zonu sessiona, uključujući put greške.
Samo `buyer.updated_at` ima `ON UPDATE CURRENT_TIMESTAMP`; `reservation.created_at` ga nema.
Mjesečni prihod koristi poslovni kalendar **Europe/Zagreb**, ne zonu SQL klijenta.

Compose postavlja `--default-time-zone=+00:00`, a JDBC URL sadrži `connectionTimeZone=UTC&forceConnectionTimeZoneToSession=true&preserveInstants=true`.
IANA tablice moraju biti učitane; provjera `CONVERT_TZ('2026-07-01 12:00:00','Europe/Zagreb','+00:00')` mora vratiti `2026-07-01 10:00:00`.
Ne uključuj `MARIADB_INITDB_SKIP_TZINFO`; učitavanje tzinfo pripada inicijalizaciji MariaDB-a, ne Liquibase migracijama.

## Integritet i konkurentnost

Namjerno redundantni `event_id` i `category_id` omogućuju kompozitne FK-ove: stavka i kategorija moraju pripadati događaju rezervacije, sjedalo kategoriji stavke, a hold stavci izdane karte.
`reservation_seat.active_seat_id` je **STORED generirani stupac**: aktivni hold izlaže `seat_id`, oslobođeni NULL; UNIQUE dopušta najviše jedan aktivan hold po sjedalu, uz očuvanu povijest.
`ticket_category.reserved` je denormalizirani brojač. CHECK štiti `0 <= reserved <= capacity`, a transakcije zaključavaju kategorije pomoću `SELECT ... FOR UPDATE` uzlazno po ID-u.
Sam CHECK brojača ne sprječava svaki izgubljeni upis; usklađenost sa stvarnim rezervacijama provjerava `v_reserved_check`, koji mora biti **prazan**.

Vlastite transakcije koriste `generate_seats`, `create_reservation`, `confirm_reservation`, `release_reservation` i `cancel_ticket`: traže poziv izvan aktivne vanjske transakcije, rade u **READ COMMITTED** i na grešku izvode ROLLBACK.
Provjera vanjske transakcije nalazi se izvan ROLLBACK handlera pa odbijanje ne poništava pozivateljevu transakciju; `cancel_reservation` delegira `release_reservation`.
`check_in_ticket` ima jedan UPDATE i ne otvara vlastitu transakciju; `expire_reservations` prolazi istekle rezervacije i nastavlja nakon pojedinačne greške.
Detaljno obrazloženje: [struktura i odluke](02_database_structure.md).

## Procedure, pogledi i ovlasti

Poslovne poruke grešaka su na hrvatskom, tipično **SQLSTATE `45000` / errno `1644`**.
Povrede CHECK, UNIQUE, FK i ovlasti imaju zasebne MariaDB kodove; pregled je u [opisu negativnih testova](03_testovi_neispravnih_podataka.md).
Funkcije su `refund_percent(hours)` i `local_to_utc(local_datetime, time_zone)`.

| Procedura | Uloga |
| --- | --- |
| `create_reservation(buyer_id, event_id, items, refund_protection, OUT reservation_id)` | Atomski stvara pending rezervaciju, stavke i holdove; `items` je JSON niz u SQL parametru `LONGTEXT` |
| `confirm_reservation(reservation_id)` | Simulira uspješno plaćanje, potvrđuje i izdaje karte |
| `cancel_reservation(reservation_id)` | Otkazuje cijelu pending rezervaciju |
| `cancel_ticket(ticket_id, OUT refund_amount)` | Otkazuje potvrđenu kartu i računa povrat |
| `check_in_ticket(event_id, ticket_code)` | Provjerava događaj, vremenski prozor i iskorištenost karte |
| `generate_seats(category_id, rows, per_row)` | Administratorski stvara sjedala sjedeće kategorije |
| `release_reservation(reservation_id, reason)` | Interno oslobađa pending rezervaciju za razlog `buyer` ili `expired` |
| `expire_reservations()` | Interna obrada koju poziva scheduler |

Primjer JSON formata: jedna stajaća i dvije sjedeće karte, ukupno tri.
Prije poziva odaberi ID-jeve iz svoje baze: kupac i budući događaj moraju postojati, obje kategorije pripadati istom događaju, a sjedala biti slobodna i pripadati sjedećoj kategoriji.
Brojevi u primjeru ilustriraju format; raspoloživost konkretnih ID-jeva ovisi o stanju baze.

```sql
CALL create_reservation(
  1, 6,
  '[{"category_id":9,"quantity":1},{"category_id":10,"seats":[201,202]}]',
  TRUE, @reservation_id
);
SELECT @reservation_id;
```

Za stajaću stavku šalje se `quantity`; za sjedeću `seats` s ID-jevima sjedala, a količina se izvodi iz duljine niza.
OUT vrijednost i sljedeće pozive koristi u istoj vezi. Plaćanje nije integrirano: tek poziv `confirm_reservation` predstavlja uspješnu potvrdu.

Sedam pogleda: `v_category_capacity`, `v_event_capacity`, `v_reservations_by_event`, `v_ticket_stats`, `v_attendance`, `v_revenue_monthly`, `v_reserved_check`.

| Korisnik | Ovlasti |
| --- | --- |
| `eventhub_app` | EXECUTE na `create_reservation`, `confirm_reservation`, `cancel_reservation`, `cancel_ticket`, `check_in_ticket`; SELECT na `v_category_capacity`, `v_event_capacity`, `v_reservations_by_event`, `v_ticket_stats`, `v_attendance`, `v_revenue_monthly`; nema direktnog SELECT/UPDATE nad tablicama ni pristup `v_reserved_check` |
| `eventhub_report` | SELECT i SHOW VIEW na cijeloj bazi `eventhub`; bez poslovnih upisa i EXECUTE ovlasti |
| `root` | Administracija, migracije, seed i provjere koje zahtijevaju šire ovlasti |

Buduća aplikacija provjerava identitet preko Keycloaka i povezuje ga s `buyer.external_id`; postojeći grantovi ostaju nepromijenjeni.
Definicije: [procedure](../migrations/003-procedures-event.sql), [pogledi](../migrations/004-views.sql), [grantovi](../migrations/005-grants.sql).


## Vanjski identitet kupca

`buyer.external_id` je opcionalan jedinstven UUID malim slovima s crticama, predviđen za Keycloak `sub`. Više kupaca može imati NULL. Baza ne čuva login podatke; Keycloak servis i autentikacija nisu implementirani.
