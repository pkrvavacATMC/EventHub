# Task 8 — Administracija i zaštita podataka

Cilj je napraviti logički backup baze `eventhub`, vratiti ga u novu praznu
bazu `eventhub_restore`, provjeriti podatke i demonstrirati read-only ovlasti.
Naredbe se pokreću iz korijena projekta u Bashu/WSL-u, uz pokrenut servis `db`.
Lozinke se preuzimaju iz okruženja kontejnera, bez upisivanja u dokument.

## 1. Logički backup

```bash
mkdir -p backup
docker compose exec -T db sh -c 'MYSQL_PWD="$MARIADB_ROOT_PASSWORD" mariadb-dump -uroot --single-transaction --routines --triggers --events eventhub' > backup/eventhub_backup.sql
```

Naredba mora završiti bez greške. Postojeću datoteku istog imena prepisuje;
za sljedeće kopije koristi zasebna imena s datumom i vremenom.

| Opcija | Svrha |
|---|---|
| `--single-transaction` | Konzistentna snimka InnoDB podataka dok aplikacija može nastaviti čitati i pisati. Tijekom backupa ne mijenja se struktura tablica (`ALTER`, `DROP`, `TRUNCATE` i slično). |
| `--routines` | Sprema procedure i funkcije. |
| `--triggers` | Sprema triggere; uključeni su i zadano, ali opcija izričito dokumentira namjeru. |
| `--events` | Sprema definirane evente, uključujući automatski istek rezervacija. |
| `eventhub` | Izvorna baza; bez `--databases`, kako se pri restoreu može zadati drugo ime baze. |

Backup sadrži SQL za strukturu i podatke, uključujući viewove. Korisnici i
njihove ovlasti nisu dio ovog backupa jedne aplikacijske baze; njihovo stvaranje
definirano je u [`init/05_users.sh`](../init/05_users.sh).

Preusmjeravanje `>` izvršava lokalni shell, pa je datoteka na računalu u
`backup/eventhub_backup.sql`, a ne u kontejneru ili Docker volumenu.
Brisanje volumena zato ne briše ovu datoteku, ali kvar računala može ugroziti
obje kopije: za stvarnu zaštitu treba čuvati dodatnu kopiju izvan računala.

Backup sadrži podatke kupaca i **ne ide u Git**. `.gitignore` isključuje
`backup/*.sql` i `backup/*.sql.gz`. Za provjeru:

```bash
git check-ignore backup/eventhub_backup.sql
```

## 2. Restore u novu praznu bazu

Originalna baza se ne briše. Prva naredba namjerno nema `IF NOT EXISTS`:
ako `eventhub_restore` već postoji, treba stati i odabrati novo ime ili
zasebno odlučiti što s prethodnom kopijom. Ne nastavljati uvoz nakon te greške.

Tri naredbe izvršavaju se pojedinačno, uz provjeru uspjeha svake:

```bash
docker compose exec -T db sh -c 'MYSQL_PWD="$MARIADB_ROOT_PASSWORD" mariadb -uroot -e "CREATE DATABASE eventhub_restore CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"'
```

```bash
set -o pipefail
sed '/EVENT `ev_expire_reservations` ON SCHEDULE/s/ ENABLE DO / DISABLE DO /' backup/eventhub_backup.sql | docker compose exec -T db sh -c 'MYSQL_PWD="$MARIADB_ROOT_PASSWORD" mariadb -uroot eventhub_restore'
```

```bash
docker compose exec -T db sh -c 'MYSQL_PWD="$MARIADB_ROOT_PASSWORD" mariadb -uroot -e "ALTER EVENT eventhub_restore.ev_expire_reservations DISABLE;"'
```

Druga naredba prilagođava samo status eventa u ulaznom toku: u postojećem dumpu
`ENABLE DO` zamjenjuje s `DISABLE DO` na retku definicije
`ev_expire_reservations`. Backup datoteka ostaje nepromijenjena. Time je event
isključen već pri stvaranju, bez razdoblja u kojem bi mogao mijenjati kopiju.
Izraz je prilagođen formatu ovog MariaDB dumpa; kod drugog formata treba
pregledati definiciju eventa prije uvoza. `pipefail` omogućuje prijavu greške
i ako zakaže čitanje datoteke kroz `sed`.

Treća naredba izričito potvrđuje isključivanje eventa u kopiji. Scheduler je
globalna postavka servera i ne gasi se: originalni event može nastaviti raditi.
Ako uvoz zakaže, ciljna baza može ostati djelomično popunjena i nije uspješan
restore.

Za provjeru statusa:

```bash
docker compose exec -T db sh -c 'MYSQL_PWD="$MARIADB_ROOT_PASSWORD" mariadb -uroot -t -e "SELECT EVENT_SCHEMA, EVENT_NAME, STATUS FROM information_schema.EVENTS WHERE EVENT_SCHEMA IN (\"eventhub\", \"eventhub_restore\");"'
```

## 3. Provjera vraćenih podataka

Postojeća provjera nalazi se u lokalnoj datoteci `backup/verify_restore.sql`:

```bash
docker compose exec -T db sh -c 'MYSQL_PWD="$MARIADB_ROOT_PASSWORD" mariadb -uroot -t' < backup/verify_restore.sql
```

Provjeru radi administrator jer `eventhub_report` ima ovlasti samo za
`eventhub`, a ne i za `eventhub_restore`. Za ponavljanje nakon novog backupa
treba osigurati da između backupa i usporedbe nema promjena izvornih podataka.
Inače razlika može nastati zbog novih izmjena originala, a ne zbog lošeg restorea.

Sljedeće tablice stvarni su ispis provjere izvršene 28. 10. 2026.
`isto = 1` znači da su uspoređene vrijednosti jednake.

Provjeren je i status eventa:

```text
+------------------+------------------------+----------+
| EVENT_SCHEMA     | EVENT_NAME             | STATUS   |
+------------------+------------------------+----------+
| eventhub         | ev_expire_reservations | ENABLED  |
| eventhub_restore | ev_expire_reservations | DISABLED |
+------------------+------------------------+----------+
```

### Broj redaka u svim tablicama

```text
+------------------+----------+----------+------+
| tablica          | original | restore_ | isto |
+------------------+----------+----------+------+
| city             |        5 |        5 |    1 |
| organizer        |        3 |        3 |    1 |
| location         |        5 |        5 |    1 |
| buyer            |       40 |       40 |    1 |
| event            |        8 |        8 |    1 |
| ticket_category  |       13 |       13 |    1 |
| seat             |      240 |      240 |    1 |
| reservation      |      175 |      175 |    1 |
| reservation_item |      229 |      229 |    1 |
| reservation_seat |      170 |      170 |    1 |
| ticket           |      290 |      290 |    1 |
+------------------+----------+----------+------+
```

### Poslovne brojke

```text
+-----------------------+----------+----------+------+
| provjera              | original | restore_ | isto |
+-----------------------+----------+----------+------+
| neto prihod           | 14436.60 | 14436.60 |    1 |
| potvrdene rezervacije |   123.00 |   123.00 |    1 |
| vazece karte          |   267.00 |   267.00 |    1 |
| neuskladjeni brojaci  |     0.00 |     0.00 |    1 |
+-----------------------+----------+----------+------+
```

Vraćeno je svih 175 rezervacija i 290 karata. Od toga je 123 rezervacija
potvrđeno, a 267 karata nema `cancelled_at`. Neto prihod je 14.436,60 €.
`v_reserved_check` u obje baze nema odstupanja, pa su provjereni brojači usklađeni.
Ove brojke odnose se na postojeći seed, a nisu očekivanje svakog budućeg backupa.

### Objekti baze

```text
+----------------------+----------+----------+------+
| objekt               | original | restore_ | isto |
+----------------------+----------+----------+------+
| procedure i funkcije |        9 |        9 |    1 |
| triggeri             |       19 |       19 |    1 |
| viewovi              |        7 |        7 |    1 |
| eventi               |        1 |        1 |    1 |
+----------------------+----------+----------+------+
```

Upit koji traži viewove kopije s referencama na izvornu bazu
(`VIEW_DEFINITION LIKE '%`eventhub`.%'`) vratio je **0 redaka**.

### Dopunska provjera sadržaja

```text
+------------------------------+------------+
| Table                        | Checksum   |
+------------------------------+------------+
| eventhub.reservation         | 4262995935 |
| eventhub_restore.reservation | 4262995935 |
| eventhub.ticket              | 1229139992 |
| eventhub_restore.ticket      | 1229139992 |
+------------------------------+------------+
```

Checksumovi rezervacija i karata jednaki su u parovima. To je dopunska provjera
sadržaja uz broj redaka i poslovne brojke, a ne apsolutan dokaz identičnosti.
Sve prikazane usporedbe su prošle. Backup koji nije testiran restoreom nema
potvrđenu mogućnost oporavka.

`backup/verify_restore.sql` također je ignoriran pravilom `backup/*.sql`.
Ako se provjera predaje kroz Git, treba je zasebno sačuvati u praćenom direktoriju;
stvarni ispis je ovdje dokumentiran.

## 4. Read-only korisnik

Korisnik se stvara prilikom inicijalizacije praznog volumena u
[`init/05_users.sh`](../init/05_users.sh). Skripta preuzima lozinku iz
`EVENTHUB_REPORT_PASSWORD`, izvršava `CREATE USER IF NOT EXISTS` i dodjeljuje:

```sql
GRANT SELECT, SHOW VIEW ON eventhub.* TO 'eventhub_report'@'%';
```

`SELECT` dopušta čitanje tablica i viewova, a `SHOW VIEW` pregled definicija
viewova. Nisu dodijeljene ovlasti za izmjenu podataka, DDL ni izvršavanje procedura.

Test se pokreće kao taj korisnik, a ne kao root:

```bash
docker compose exec -T db sh -c 'MYSQL_PWD="$EVENTHUB_REPORT_PASSWORD" mariadb --force -t -ueventhub_report eventhub' < tests/08_readonly_user.sql
```

`--force` nastavlja izvršavanje nakon očekivane SQL greške, kako bi se prikazali
svi pokušaji. Uspjeh se procjenjuje prema pojedinačnim rezultatima i greškama.

### Identitet i SHOW GRANTS

Iz priloženog ispisa testa:

```text
+-------------------+
| CURRENT_USER()    |
+-------------------+
| eventhub_report@% |
+-------------------+
```

`SHOW GRANTS` vratio je sljedeće ovlasti (hash lozinke izostavljen iz dokumenta):

```sql
GRANT USAGE ON *.* TO `eventhub_report`@`%` IDENTIFIED BY PASSWORD '[IZOSTAVLJENO]';
GRANT SELECT, SHOW VIEW ON `eventhub`.* TO `eventhub_report`@`%`;
```

Prvi redak je redigirani prikaz ispisa, nije naredba za izvršavanje.
`USAGE` ne dodjeljuje dodatne ovlasti nad podacima.

### Uspješno čitanje

```text
+-------------+
| rezervacije |
+-------------+
|         175 |
+-------------+
+---------+-------------+
| month   | net_revenue |
+---------+-------------+
| 2026-01 |      556.00 |
| 2026-02 |     1846.00 |
| 2026-02 |      618.50 |
+---------+-------------+
```

To su rezultati `COUNT(*) FROM reservation` i prva tri retka iz
`v_revenue_monthly`. View sadrži retke po eventu i mjesecu, pa se veljača
pojavljuje dvaput; upit ne zbraja sve evente po mjesecu.

### Odbijene operacije

| Naredba | Rezultat iz testa |
|---|---|
| `SELECT COUNT(*) AS rezervacije FROM reservation` | Prošla: 175. |
| `SELECT month, net_revenue FROM v_revenue_monthly ORDER BY month LIMIT 3` | Prošla: prikazani redci iz viewa. |
| `INSERT INTO city (name) VALUES ('Test')` | Odbijena: `ERROR 1142 (42000)`, `INSERT command denied`, tablica `eventhub.city`. |
| `UPDATE reservation SET status = 'cancelled' WHERE 1 = 0` | Odbijena: `ERROR 1142 (42000)`, `UPDATE command denied`, tablica `eventhub.reservation`. |
| `DELETE FROM ticket WHERE 1 = 0` | Odbijena: `ERROR 1142 (42000)`, `DELETE command denied`, tablica `eventhub.ticket`. |
| `CREATE TABLE test_tablica (id INT)` | Odbijena: `ERROR 1142 (42000)`, `CREATE command denied`, tablica `eventhub.test_tablica`. |
| `DROP TABLE nepostojeca_tablica` | Odbijena: `ERROR 1142 (42000)`, `DROP command denied`, tablica `eventhub.nepostojeca_tablica`. |
| `CALL confirm_reservation(999999)` | Odbijena: `ERROR 1370 (42000)`, `execute command denied`, rutina `eventhub.confirm_reservation`. |

U greškama nad tablicama klijent je prikazan kao
`'eventhub_report'@'localhost'`, dok `CURRENT_USER()` pokazuje račun čije su
ovlasti primijenjene: `eventhub_report@%`.

Za `UPDATE` i `DELETE`, `WHERE 1 = 0` spriječio bi izmjene čak i da su ovlasti
preširoke. `INSERT` i `CREATE TABLE` ipak bi nešto stvorili kad bi bili dopušteni;
prikazani rezultati potvrđuju da su ovdje odbijeni. Očekivane greške dokazuju
ograničenje ovlasti, a nisu kvar testa.

## 5. Zašto aplikacija ne koristi root

**Najmanje ovlasti.** Aplikaciji trebaju pozivi poslovnih procedura i čitanje
odabranih izvještajnih viewova. `eventhub_app` ima upravo te ovlasti. Root može
obrisati bazu, stvarati korisnike i mijenjati postavke servera.

**Šteta kod napada.** Procurjela root lozinka ili SQL injection kroz vezu s root
ovlastima ugrožava cijeli server baze. S računom `eventhub_app` napadač je
ograničen na dodijeljene viewove i procedure. I dalje može zloupotrijebiti
dopuštene operacije, pa ograničene ovlasti smanjuju posljedice, ali ne zamjenjuju
zaštitu aplikacije.

**Zaobilaženje pravila.** Dizajn aplikacije predviđa izmjene kroz poslovne
procedure. Root može direktnim `UPDATE` naredbama zaobići dio tih provjera i
narušiti usklađenost brojača ili dodjele sjedala, iako i dalje postoje zaštite
triggerima i ograničenjima tablica. `eventhub_app` nema direktne ovlasti za
izmjenu tablica.

**Praćenje.** Odvojeni računi za aplikaciju, izvještaje i administraciju
olakšavaju razlikovanje pristupa po ulozi. Za dokaz tko je izvršio pojedinu
naredbu treba uključeno odgovarajuće audit zapisivanje; sami odvojeni računi
nisu audit log.
