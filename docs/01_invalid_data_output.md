# Rezultati testova neispravnih podataka

Skripta: [01_invalid_data.sql](../tests/01_invalid_data.sql).

## Sažetak

**81 PASS · 0 FAIL**. Završna provjera bilježi **0 neusklađenih brojača**.

Testovi obuhvaćaju ograničenja baze, poslovna pravila, procedure i vremenske granice. Detaljan opis provjera nalazi se u [dokumentaciji testova neispravnih podataka](03_testovi_neispravnih_podataka.md).

## Korišteni testni podaci

| Parametar | Vrijednost |
| --- | --- |
| `@buyer` | 1 |
| `@ev_future` | 6 |
| `@cat_parter_ny` | 9 |
| `@cat_vip_ny` | 10 |
| `@cat_split` | 12 |
| `@ev_past` | 2 |
| `@cat_indie` | 8 |
| `@cat_kaz` | 11 |
| `@confirmed_res` | 107 |
| `@valid_ticket` | 199 |
| `@cancelled_res` | 1 |
| `@cancelled_ticket` | 13 |
| `@past_ticket` | 47 |
| `@sold_seat` | 163 |
| `@free_seat` | 161 |

## Rezultati po kategorijama

### CHECK ograničenja

| id | opis | ocekivano | dobiveno | rezultat |
| --- | --- | --- | --- | --- |
| 1 | Lokacija s kapacitetom 0 | 4025: chk_location_capacity | 4025: CONSTRAINT `chk_location_capacity` failed for `eventhub`.`location` | PASS |
| 2 | Grad s praznim nazivom | 4025: chk_city_name | 4025: CONSTRAINT `chk_city_name` failed for `eventhub`.`city` | PASS |
| 3 | Kupac s neispravnim emailom | 4025: chk_buyer_email | 4025: CONSTRAINT `chk_buyer_email` failed for `eventhub`.`buyer` | PASS |
| 4 | Email s razmakom | 4025: chk_buyer_email | 4025: CONSTRAINT `chk_buyer_email` failed for `eventhub`.`buyer` | PASS |
| 5 | Kupac s praznim prezimenom | 4025: chk_buyer_name | 4025: CONSTRAINT `chk_buyer_name` failed for `eventhub`.`buyer` | PASS |
| 6 | Organizator s emailom bez domene | 4025: chk_organizer_email | 4025: CONSTRAINT `chk_organizer_email` failed for `eventhub`.`organizer` | PASS |
| 7 | Negativna cijena kategorije | 4025: chk_category_price | 4025: CONSTRAINT `chk_category_price` failed for `eventhub`.`ticket_category` | PASS |
| 8 | Negativna naknada kategorije | 4025: chk_category_fee | 4025: CONSTRAINT `chk_category_fee` failed for `eventhub`.`ticket_category` | PASS |
| 9 | Kategorija s kapacitetom 0 | 4025: chk_category_capacity | 4025: CONSTRAINT `chk_category_capacity` failed for `eventhub`.`ticket_category` | PASS |
| 10 | Zauzece vece od kapaciteta | 4025: chk_category_reserved | 4025: CONSTRAINT `chk_category_reserved` failed for `eventhub`.`ticket_category` | PASS |
| 11 | Negativno zauzece | 4025: chk_category_reserved | 4025: CONSTRAINT `chk_category_reserved` failed for `eventhub`.`ticket_category` | PASS |
| 12 | Stavka s kolicinom 0 | 4025: chk_item_quantity | 4025: CONSTRAINT `chk_item_quantity` failed for `eventhub`.`reservation_item` | PASS |
| 13 | Stavka s negativnom kolicinom | 4025: chk_item_quantity | 4025: CONSTRAINT `chk_item_quantity` failed for `eventhub`.`reservation_item` | PASS |
| 14 | Stavka s negativnom cijenom | 4025: chk_item_price | 4025: CONSTRAINT `chk_item_price` failed for `eventhub`.`reservation_item` | PASS |
| 15 | Potvrdena rezervacija bez datuma potvrde | 4025: chk_res_status_dates | 4025: CONSTRAINT `chk_res_status_dates` failed for `eventhub`.`reservation` | PASS |
| 16 | Otkazana rezervacija bez razloga | 4025: chk_res_cancel_reason | 4025: CONSTRAINT `chk_res_cancel_reason` failed for `eventhub`.`reservation` | PASS |
| 17 | Potvrdena rezervacija ne moze "isteci" | 1644: Rezervacija ima vazece karte | 1644: Rezervacija ima vazece karte; prvo otkazite karte | PASS |
| 18 | Rok rezervacije prije kreiranja | 4025: chk_res_expires | 4025: CONSTRAINT `chk_res_expires` failed for `eventhub`.`reservation` | PASS |
| 19 | Povrat bez otkazivanja karte | 4025: chk_ticket_refund_pair | 4025: CONSTRAINT `chk_ticket_refund_pair` failed for `eventhub`.`ticket` | PASS |
| 20 | Karta iskoristena i otkazana | 4025: chk_ticket_used_cancel | 4025: CONSTRAINT `chk_ticket_used_cancel` failed for `eventhub`.`ticket` | PASS |

### Obavezni podaci (NOT NULL)

| id | opis | ocekivano | dobiveno | rezultat |
| --- | --- | --- | --- | --- |
| 21 | Event bez naziva | 1048: name | 1048: Column 'name' cannot be null | PASS |
| 22 | Kupac bez emaila | 1048: email | 1048: Column 'email' cannot be null | PASS |

### Jedinstvenost (UNIQUE)

| id | opis | ocekivano | dobiveno | rezultat |
| --- | --- | --- | --- | --- |
| 23 | Dupli grad | 1062: uq_city_name | 1062: Duplicate entry 'Zagreb' for key 'uq_city_name' | PASS |
| 24 | Dupli email kupca | 1062: uq_buyer_email | 1062: Duplicate entry 'ana.horvat1@example.com' for key 'uq_buyer_email' | PASS |
| 25 | Dupli email organizatora | 1062: uq_organizer_email | 1062: Duplicate entry 'info@adrialive.example' for key 'uq_organizer_email' | PASS |
| 26 | Dva puta ista kategorija u eventu | 1062: uq_category_event_name | 1062: Duplicate entry '6-VIP' for key 'uq_category_event_name' | PASS |

### Referencijalni integritet (FK)

| id | opis | ocekivano | dobiveno | rezultat |
| --- | --- | --- | --- | --- |
| 27 | Kupac iz nepostojeceg grada | 1452: fk_buyer_city | 1452: Cannot add or update a child row: a foreign key constraint fails (`eventhub`.`buyer`, CONSTRAINT `fk_buyer_city` FOREIGN KEY (`city_id`) REFERENCES `city` (`id`)) | PASS |
| 28 | Event nepostojeceg organizatora | 1452: fk_event_organizer | 1452: Cannot add or update a child row: a foreign key constraint fails (`eventhub`.`event`, CONSTRAINT `fk_event_organizer` FOREIGN KEY (`organizer_id`) REFERENCES `organizer` (`id`)) | PASS |
| 29 | Stavka s kategorijom drugog eventa | 1452: fk_item_category | 1452: Cannot add or update a child row: a foreign key constraint fails (`eventhub`.`reservation_item`, CONSTRAINT `fk_item_category` FOREIGN KEY (`category_id`, `event_id`) REFERENCES `ticket_category` (`id`, `event_id`)) | PASS |
| 30 | Stavka ne odgovara eventu rezervacije | 1452: fk_item_reservation | 1452: Cannot add or update a child row: a foreign key constraint fails (`eventhub`.`reservation_item`, CONSTRAINT `fk_item_reservation` FOREIGN KEY (`reservation_id`, `event_id`) REFERENCES `reservation` (`id`, `event_id`)) | PASS |
| 31 | Brisanje organizatora koji ima evente | 1451: fk_event_organizer | 1451: Cannot delete or update a parent row: a foreign key constraint fails (`eventhub`.`event`, CONSTRAINT `fk_event_organizer` FOREIGN KEY (`organizer_id`) REFERENCES `organizer` (`id`)) | PASS |
| 32 | Brisanje grada koji ima kupce | 1451: fk_ | 1451: Cannot delete or update a parent row: a foreign key constraint fails (`eventhub`.`buyer`, CONSTRAINT `fk_buyer_city` FOREIGN KEY (`city_id`) REFERENCES `city` (`id`)) | PASS |
| 33 | Rezervacija za nepostojeceg kupca | 1452: fk_res_buyer | 1452: Cannot add or update a child row: a foreign key constraint fails (`eventhub`.`reservation`, CONSTRAINT `fk_res_buyer` FOREIGN KEY (`buyer_id`) REFERENCES `buyer` (`id`)) | PASS |

### Poslovna pravila

| id | opis | ocekivano | dobiveno | rezultat |
| --- | --- | --- | --- | --- |
| 34 | Event veci od lokacije | 1644: Kapacitet eventa prelazi kapacitet lokacije | 1644: Kapacitet eventa prelazi kapacitet lokacije | PASS |
| 35 | Novi event u proslosti | 1644: Event mora biti u buducnosti | 1644: Event mora biti u buducnosti | PASS |
| 36 | Pomicanje eventa u proslost | 1644: Novi datum eventa mora biti u buducnosti | 1644: Novi datum eventa mora biti u buducnosti | PASS |
| 37 | Promjena datuma odrzanog eventa | 1644: Datum eventa koji je poceo ili prosao | 1644: Datum eventa koji je poceo ili prosao ne moze se mijenjati | PASS |
| 38 | Smanjenje eventa ispod zbroja kategorija | 1644: manji od zbroja kapaciteta kategorija | 1644: Kapacitet eventa je manji od zbroja kapaciteta kategorija | PASS |
| 39 | Kategorije preko kapaciteta eventa | 1644: Zbroj kapaciteta kategorija prelazi kapacitet eventa | 1644: Zbroj kapaciteta kategorija prelazi kapacitet eventa | PASS |
| 40 | Sjedalo preko kapaciteta kategorije | 1644: Broj sjedala prelazi kapacitet kategorije | 1644: Broj sjedala prelazi kapacitet kategorije | PASS |
| 41 | Kapacitet sjedece kategorije razlicit od broja sjedala | 1644: mora biti jednak broju sjedala | 1644: Kapacitet sjedece kategorije mora biti jednak broju sjedala | PASS |
| 42 | Nova rezervacija vec potvrdena | 1644: Nova rezervacija mora biti pending | 1644: Nova rezervacija mora biti pending | PASS |
| 43 | Potvrdena natrag u pending | 1644: confirmed -> pending | 1644: Nedozvoljen prijelaz statusa confirmed -> pending | PASS |
| 44 | Izmjena otkazane rezervacije | 1644: Otkazana rezervacija je konacna | 1644: Otkazana rezervacija je konacna | PASS |
| 45 | Naknadna promjena zastite od povrata | 1644: Refund protection je nepromjenjiv | 1644: Refund protection je nepromjenjiv nakon kreiranja rezervacije | PASS |
| 46 | Izmjena stavke rezervacije | 1644: Stavke rezervacije su nepromjenjive | 1644: Stavke rezervacije su nepromjenjive | PASS |
| 47 | Stavka na potvrdenoj rezervaciji | 1644: samo pending rezervaciji | 1644: Stavke se mogu dodati samo pending rezervaciji | PASS |
| 48 | Povrat veci od cijene karte | 1644: Povrat ne smije biti veci od cijene | 1644: Povrat ne smije biti veci od cijene karte | PASS |
| 49 | Brisanje rezervacije | 1644: Brisanje rezervacija nije dozvoljeno | 1644: Brisanje rezervacija nije dozvoljeno | PASS |
| 50 | Brisanje karte | 1644: Brisanje karata nije dozvoljeno | 1644: Brisanje karata nije dozvoljeno | PASS |
| 80 | Direktno otkazivanje potvrdene rezervacije s vazecim kartama | 1644: Rezervacija ima vazece karte | 1644: Rezervacija ima vazece karte; prvo otkazite karte | PASS |
| 81 | Direktno otkazivanje pending rezervacije s aktivnim holdom | 1644: Rezervacija ima aktivne holdove sjedala | 1644: Rezervacija ima aktivne holdove sjedala; prvo oslobodite sjedala | PASS |

### Provjere procedura

| id | opis | ocekivano | dobiveno | rezultat |
| --- | --- | --- | --- | --- |
| 51 | Rezervacija s 5 karata | 1644: izmedu 1 i 4 karte | 1644: Rezervacija mora imati izmedu 1 i 4 karte | PASS |
| 52 | Negativna kolicina karata | 1644: quantity >= 1 | 1644: Svaka stavka mora imati quantity >= 1 ili odabrana sjedala | PASS |
| 53 | Prazna rezervacija | 1644: barem jednu stavku | 1644: Rezervacija mora imati barem jednu stavku | PASS |
| 54 | Neispravan JSON | 1644: Stavke moraju biti JSON niz | 1644: Stavke moraju biti JSON niz | PASS |
| 55 | Kategorija drugog eventa | 1644: ne pripada eventu | 1644: Kategorija ne postoji ili ne pripada eventu | PASS |
| 56 | Vise karata nego slobodnih mjesta | 1644: Nema dovoljno slobodnih mjesta | 1644: Nema dovoljno slobodnih mjesta | PASS |
| 57 | Vec zauzeto sjedalo | 1644: vec zauzeto | 1644: Neko od sjedala je vec zauzeto | PASS |
| 58 | Isto sjedalo dvaput | 1644: navedeno vise puta | 1644: Isto sjedalo je navedeno vise puta | PASS |
| 59 | Sjedalo iz druge kategorije | 1644: ne pripada kategoriji stavke | 1644: Sjedalo ne postoji ili ne pripada kategoriji stavke | PASS |
| 60 | Sjedeca kategorija bez odabranih sjedala | 1644: mora imati odabrana sjedala | 1644: Sjedeca stavka mora imati odabrana sjedala | PASS |
| 61 | Rezervacija za odrzani event | 1644: Event je vec poceo ili prosao | 1644: Event je vec poceo ili prosao | PASS |
| 62 | Potvrda vec potvrdene rezervacije | 1644: Samo pending rezervacija se moze potvrditi | 1644: Samo pending rezervacija se moze potvrditi | PASS |
| 63 | Potvrda nepostojece rezervacije | 1644: Rezervacija ne postoji | 1644: Rezervacija ne postoji | PASS |
| 64 | Otkazivanje cijele potvrdene rezervacije | 1644: samo pending rezervacija | 1644: Cijela se moze otkazati samo pending rezervacija; potvrdene se otkazuju po karti | PASS |
| 65 | Ponovno otkazivanje vracene karte | 1644: Karta je vec otkazana | 1644: Karta je vec otkazana | PASS |
| 66 | Otkazivanje karte nakon eventa | 1644: Nema otkazivanja nakon pocetka eventa | 1644: Nema otkazivanja nakon pocetka eventa | PASS |
| 67 | Check-in na ulazu drugog eventa | 1644: Karta nije za ovaj event | 1644: Karta nije za ovaj event | PASS |
| 68 | Check-in izvan termina | 1644: Check-in nije moguc u ovom terminu | 1644: Check-in nije moguc u ovom terminu | PASS |
| 69 | Check-in nepostojece karte | 1644: Karta ne postoji | 1644: Karta ne postoji | PASS |
| 70 | Sjedala u stajacoj kategoriji | 1644: samo za sjedecu kategoriju | 1644: Sjedala se mogu generirati samo za sjedecu kategoriju | PASS |
| 71 | Ponovno generiranje sjedala | 1644: vec ima sjedala ili rezervacije | 1644: Kategorija vec ima sjedala ili rezervacije | PASS |
| 72 | Istek potvrdene rezervacije | 1644: samo pending rezervacija | 1644: Cijela se moze otkazati samo pending rezervacija; potvrdene se otkazuju po karti | PASS |
| 73 | Nepoznat razlog otkazivanja | 1644: Razlog otkazivanja mora biti | 1644: Razlog otkazivanja mora biti buyer ili expired | PASS |

### Vremenske granice

| id | opis | ocekivano | dobiveno | rezultat |
| --- | --- | --- | --- | --- |
| 74 | Novi event sekundu u proslosti | 1644: Event mora biti u buducnosti | 1644: Event mora biti u buducnosti | PASS |
| 75 | Novi event tocno sada | 1644: Event mora biti u buducnosti | 1644: Event mora biti u buducnosti | PASS |
| 76 | Novi event sekundu u buducnosti | 0: | 0: Operacija je prosla | PASS |
| 77 | Pomicanje eventa tocno na sada | 1644: Novi datum eventa mora biti u buducnosti | 1644: Novi datum eventa mora biti u buducnosti | PASS |
| 78 | Pomicanje eventa u buducnost | 0: | 0: Operacija je prosla | PASS |
| 79 | Rezervacija tocno na pocetku eventa | 1644: Event je vec poceo ili prosao | 1644: Event je vec poceo ili prosao | PASS |

## Pregled rezultata

| kategorija | pass | fail |
| --- | --- | --- |
| CHECK | 20 | 0 |
| FK | 7 | 0 |
| NOT NULL | 2 | 0 |
| PRAVILO | 19 | 0 |
| PROCEDURA | 23 | 0 |
| UNIQUE | 4 | 0 |
| VRIJEME | 6 | 0 |
| UKUPNO | 81 | 0 |

## Završna provjera konzistentnosti

| neuskladjeni_brojaci |
| --- |
| 0 |