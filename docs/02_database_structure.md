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

## Model vremena

Sistemski trenuci pohranjuju se kao TIMESTAMP, a veze s bazom koriste UTC.
Samo lokalni početak događaja ostaje DATETIME i tumači se preko lokacije i `city.time_zone`.
Rokovi za povrat i prijavu na ulazu računaju se prema proteklim UTC satima;
mjesečni prihod koristi poslovni kalendar Zagreba. Samo se `buyer.updated_at` automatski osvježava pri izmjeni retka.

## Životni ciklus rezervacije

`create_reservation` prima identifikatore kupca i događaja, JSON niz stavki, oznaku zaštite povrata i izlazni identifikator rezervacije. Zaključava kategorije, provjerava raspoloživost i atomski stvara rezervaciju na čekanju, stavke i opcionalna zauzeća sjedala. Rezervacije na čekanju zauzimaju kapacitet 15 minuta.

`confirm_reservation` potvrđuje rezervaciju koja zadovoljava uvjete i izdaje karte. `cancel_reservation` oslobađa rezervaciju na čekanju, a `cancel_ticket` obrađuje pojedinačne potvrđene karte i povrate. `expire_reservations`, koju poziva zakazani događaj baze, oslobađa istekle rezervacije na čekanju. Prijava na ulazu provjerava kod karte i identitet događaja.

Potvrda simulira uspješno plaćanje; integracija s platnim sustavom nije implementirana. Demonstracija neuspjelog plaćanja otkazuje rezervaciju na čekanju. Odbijena rezervacija zaseban je slučaj u kojem već samo stvaranje rezervacije ne uspijeva.

## Integritet i konkurentnost

Primarni i strani ključevi određuju identitet i pripadnost zapisa. Kompozitni strani ključevi osiguravaju da stavka i kategorija pripadaju događaju rezervacije, da sjedalo pripada kategoriji stavke te da zauzeće sjedala na karti pripada stavci te karte. Za te provjere potrebni su namjerno redundantni stupci i odgovarajući jedinstveni ključevi.

CHECK ograničenja provode lokalna pravila, primjerice nenegativne cijene i `0 <= reserved <= capacity`. Triggeri provode dodatna pravila između tablica i pravila prijelaza statusa. Procedure koordiniraju transakcije nad više tablica i na iznimku izvode ROLLBACK. Aplikacijske ovlasti usmjeravaju pozivatelje na te procedure umjesto izravnih upisa.

`SELECT ... FOR UPDATE` serijalizira konkurentne operacije nad istim recima kapaciteta. Sesija koja čeka čita raspoloživost nakon završetka prve transakcije. Skripta za konkurentnost pokazuje kako provjera bez zaključavanja može prodati više karata od kapaciteta čak i kada pohranjeni brojač izgleda ispravno. Sam CHECK štiti brojač, ali ne jamči usklađenost svih povezanih podataka.

`active_seat_id` je pohranjeni generirani stupac: aktivno zauzeće sadrži identifikator sjedala, a oslobođeno sadrži NULL. Jedinstveni indeks sprječava dva aktivna zauzeća istog sjedala uz očuvanje povijesti. `v_reserved_check` uspoređuje pohranjene brojače kapaciteta s podacima rezervacija.

## Kompromisi i ograničenja

- `reserved` ubrzava provjeru raspoloživosti, ali ponavlja agregirane podatke; nužni su transakcijski upisi i provjere usklađenosti.
- Povijesni zapisi cijena i naknada čuvaju uvjete kupnje nakon promjene cijene kategorije.
- Transakcije i zaključavanja štite kapacitet, ali serijaliziraju kupnje u popularnim kategorijama. Budućoj aplikaciji treba definirano ponavljanje operacija nakon prolaznih grešaka baze.
- Indeksi ubrzavaju čitanje uz trošak prostora i održavanja pri pisanju; izmjerena selektivnost važnija je od dodavanja indeksa na svaki stupac.
- Transakcijska povijest se čuva. To olakšava reviziju, ali zahtijeva buduću politiku zadržavanja podataka i zaštite privatnosti.
- Zaštita povrata iznosi 10 % cijene karata. Uz zaštitu se vraća cijela cijena karte; bez zaštite vraća se 80 % najmanje sedam dana unaprijed, 50 % najmanje 48 sati unaprijed, inače 0 %. Naknada usluge i naknada zaštite ne vraćaju se.
- Rezervacije i otkazivanja prestaju početkom događaja; prijava na ulazu ima ograničen vremenski prozor. Istek rezervacija ovisi o raspoređivaču baze.
- Projekt obuhvaća bazu podataka. Vanjska plaćanja, Keycloak integracija, dostava karata i produkcijske operativne politike zahtijevaju dodatni aplikacijski rad.

Pogledi prikazuju kapacitet, statistiku karata, posjećenost i mjesečni prihod. Prihod uključuje cijene karata i naknade umanjene za povrate; naknada zaštite mora se zbrojiti jednom po rezervaciji kako je JOIN ne bi višestruko uračunao.
