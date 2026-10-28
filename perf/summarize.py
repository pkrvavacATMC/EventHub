#!/usr/bin/env python3
"""Samo jedan potpun niz A-D x 3 iz series.tsv; nikad ne ucitava arhivu."""
import argparse
import hashlib
import json
import re
import statistics as st
from pathlib import Path

ROOT = Path(__file__).resolve().parent
LABELS = {'A': 'Bez analiziranih indeksa', 'B': 'Konacni uski',
          'C': 'Kupac + pokrivajuci povrati', 'D': 'Siri indeks potvrda + C'}
QUERIES = ['Q1', 'Q2', 'Q3', 'Q4', 'Q5']

def table(headers, rows):
    def row(values):
        return '| ' + ' | '.join(str(x).replace('|', '\\|') for x in values) + ' |'
    return '\n'.join([row(headers), row(['---'] * len(headers))] + [row(r) for r in rows])

def f(value):
    return f'{value:.1f}' if abs(value) >= 1 else f'{value:.3f}'

def stats(values):
    return f'{f(st.median(values))} [{f(min(values))}-{f(max(values))}]'

def parse_block(lines):
    data = {'runs': {q: [] for q in QUERIES}, 'plans': {}, 'actual': {},
            'space': {}, 'write': [], 'indexes': {}, 'warmups': []}
    for i, line in enumerate(lines):
        if line.startswith('ENV\t'):
            data['env'] = line.split('\t')[1:]
        elif line.startswith('RUN '):
            _, q, run = line.split()
            raw = lines[i+2].replace('\\n', '\n').replace('\\t', '\t').replace('\\"', '"').replace('\\\\', '\\')
            plan = json.loads(raw)
            if run != '0':
                data['runs'][q].append(plan['query_block']['r_total_time_ms'])
            else:
                data['warmups'].append(q)
            if run == '1':
                nodes = []
                def walk(obj):
                    if isinstance(obj, dict):
                        if 'table_name' in obj:
                            nodes.append([obj.get(k, '-') for k in
                                          ('table_name', 'access_type', 'key', 'r_loops', 'r_rows')])
                        for value in obj.values():
                            walk(value)
                    elif isinstance(obj, list):
                        for value in obj:
                            walk(value)
                walk(plan)
                data['actual'][q] = nodes
        elif line.startswith('PLAN '):
            q = line.split()[1]
            headers = lines[i+1].split('\t')
            rows, j = [], i+2
            while j < len(lines) and lines[j] != 'marker':
                rows.append(dict(zip(headers, lines[j].split('\t'))))
                j += 1
            data['plans'][q] = rows
        elif line.startswith('SPACE\t'):
            _, name, size, index = line.split('\t')
            data['space'][name] = [int(size), int(index)]
        elif line.startswith('WRITE\t'):
            _, run, ms = line.split('\t')
            if run != '0':
                data['write'].append(float(ms))
        elif line.startswith('INDEX_STATE\t'):
            _, name, index, columns = line.split('\t')
            data['indexes'][(name, index)] = columns
    assert all(len(v) == 5 for v in data['runs'].values()), 'Nepotpun blok upita'
    assert len(data['write']) == 5 and len(data['plans']) == 5
    assert data['warmups'] == QUERIES
    assert data['env'][1:] == ['OFF', '100175', '189133', '41']
    return data

def read_series():
    path = ROOT / 'results' / 'series.tsv'
    raw = path.read_bytes()
    manifest = json.loads((ROOT / 'results' / 'series_manifest.json').read_text())
    assert manifest['exit_code'] == 0 and manifest['rounds'] == 3
    assert hashlib.sha256(raw).hexdigest() == manifest['result_sha256']
    lines = raw.decode().splitlines()
    begin = next(x.split('\t') for x in lines if x.startswith('SERIES_BEGIN\t'))
    end = next(x.split('\t') for x in lines if x.startswith('SERIES_END\t'))
    connection = begin[1]
    assert end[1] == connection, 'Razlicite MariaDB sesije'
    blocks, start, current, sequence = [], None, None, []
    for i, line in enumerate(lines):
        if line.startswith('SERIES_CONFIG\t') or line.startswith('SERIES_RESTORE\t'):
            if current is not None:
                data = parse_block(lines[start:i])
                data.update(round=current[0], config=current[1])
                blocks.append(data)
            if line.startswith('SERIES_RESTORE\t'):
                assert line.split('\t')[1] == connection
                current = None
                break
            _, round_no, config, session, _ = line.split('\t')
            assert session == connection
            current = (int(round_no), config)
            sequence.append(current)
            start = i+1
    assert sequence == [(r, c) for r in range(1, 4) for c in LABELS], sequence
    # Provjeri tocne konfiguracije, ne samo oznake u logu.
    for block in blocks:
        indexes = block['indexes']
        c = block['config']
        expected = {'idx_res_confirmed_at': c in 'BC',
                    'idx_ticket_cancelled_at': c == 'B',
                    'idx_res_buyer_created': c in 'CD',
                    'idx_ticket_refund_cover': c in 'CD',
                    'idx_res_confirmed_cover': c == 'D'}
        for name, exists in expected.items():
            assert any(key[1] == name for key in indexes) == exists, (c, name)
    final = [x.split('\t') for x in lines if x.startswith('FINAL_INDEX\t')]
    names = {x[2] for x in final}
    assert {'idx_res_confirmed_at', 'idx_ticket_cancelled_at'} <= names
    assert not {'idx_res_buyer_created', 'idx_ticket_refund_cover', 'idx_res_confirmed_cover'} & names
    counts = next(x.split('\t')[1:] for x in lines if x.startswith('FINAL_COUNTS\t'))
    assert counts == ['100175', '189133', '0']
    ticket = next(x.split('\t')[1:] for x in lines if x.startswith('TICKET_DISTRIBUTION\t'))
    aggregate = {}
    for c in LABELS:
        members = [b for b in blocks if b['config'] == c]
        aggregate[c] = {
            'runs': {q: sum((b['runs'][q] for b in members), []) for q in QUERIES},
            'write': sum((b['write'] for b in members), []),
            'blocks': members,
        }
        assert all(len(v) == 15 for v in aggregate[c]['runs'].values())
    return {'data': aggregate, 'blocks': blocks, 'connection': connection,
            'version': begin[2], 'started': begin[3], 'buffer_pool': begin[4],
            'finished': end[2], 'ticket': list(map(int, ticket)), 'manifest': manifest}

NOTES = [
    ('Kupci s najvise rezervacija (Task 4 Q2)', 'Cest rang izvjestaj i kontrola citanja cijelog skupa. FK indeks pokriva COUNT, ali sve rezervacije i dalje treba brojiti, uz agregaciju i filesort. Dodatni indeks povijesti ne uklanja taj posao.'),
    ('Mjesecni trend prihoda (Task 4 Q8)', 'Najskuplji izvjestaj: UNION ALL prodaje, zastite i povrata te vise agregacija. B omogucuje range rijetkih povrata; C pokriva njihov SUM/JOIN. D pokriva i datum/event/naknadu zastite. Sve konfiguracije i dalje obradjuju velik dio rezervacija; temporary/filesort ne nestaju.'),
    ('Bruto prodaja u jednom danu', 'Tipican dnevni financijski pregled. Poluotvoreni raspon datuma ostaje sargable. Ovo je bruto cijena karata i service fee, bez zastite i povrata. COUNT(DISTINCT r.id) sprjecava visestruko brojanje rezervacije s vise stavki. Datumski indeks izdvaja mali skup umjesto obilaska svih stavki.'),
    ('Povijest jednog kupca', 'Cest ekran zadnjih 10 rezervacija. @buyer=41 ima 22 rezervacije. A/B koriste fk_res_buyer uz filesort malog skupa. C/D koriste indeks buyer_id,created_at,id, uklanjaju filesort i prekidaju nakon 10 redaka. Isplativost se procjenjuje prema apsolutnoj ustedi, prostoru i INSERT-u u ovom nizu.'),
    ('Povrati u mjesecu', 'Tipican selektivan financijski pregled. A cita cijelu tablicu ticket. B range cita mjesec povrata i dohvaca refund_amount iz tablice; C/D pokrivaju SUM indeksom. Uzi indeks vec uklanja full scan; dodatna pokrivenost ima dodatni trosak.')]

def render_summary(series):
    data = series['data']
    print('## Izmjerena vremena\n')
    print('Samo series.tsv: jedna MariaDB sesija, tri uzastopna A-D kruga. Svaka celija: medijan [min-max] u ms svih 15 mjerenja (5 po krugu); vremena >= 1 ms imaju jednu decimalu, manja tri; tri zagrijavanja po konfiguraciji/upitu su iskljucena. Arhiva nije ukljucena.\n')
    print(table(['Upit']+[f'{c}: {LABELS[c]}' for c in LABELS],
                [[q]+[stats(data[c]['runs'][q]) for c in LABELS] for q in QUERIES]))
    print('\n### Medijani pojedinih krugova\n')
    print(table(['Krug','Konfiguracija']+QUERIES+['INSERT ms'],
                [[b['round'], b['config']]+[f(st.median(b['runs'][q])) for q in QUERIES]+[f(st.median(b['write']))] for b in series['blocks']]))
    print('\n## SQL, EXPLAIN i stvarni redci\n')
    print('Potpuni EXPLAIN i JSON planovi sva tri kruga ostaju u series.tsv. Ovdje su planovi prvog kruga svih konfiguracija; rows je procjena, r_rows prosjek stvarnih redaka po petlji, r_loops broj petlji.\n')
    sqls = re.findall(r'EXPLAIN (SELECT .*?);', (ROOT/'02_baseline.sql').read_text(), re.S)
    assert len(sqls) == 5
    for q, sql, (title, note) in zip(QUERIES, sqls, NOTES):
        print(f'### {q} - {title}\n\n{note}\n\n```sql\n{sql};\n```\n')
        for c in LABELS:
            b = data[c]['blocks'][0]
            print(f'**{c}: {LABELS[c]} - EXPLAIN, krug 1**\n')
            keys = ['id','select_type','table','type','key','rows','Extra']
            print(table(['id','select_type','tablica','type','key','rows','Extra'],
                        [[row[k] for k in keys] for row in b['plans'][q]]))
            print('\nANALYZE, krug 1, mjerenje 1:\n')
            print(table(['tablica','access_type','key','r_loops','r_rows'], b['actual'][q]))
            print('\n15 vremena (ms), redom krugovi 1-3: '+', '.join(f(x) for x in data[c]['runs'][q])+'.\n')
    print('## Prostor i INSERT\n')
    print('Bajtovi iz information_schema.TABLES nakon ANALYZE. Prikaz svih krugova izbjegava skrivanje promjena alokacije; ovo su procjene alociranih stranica, ne tocne logicke velicine indeksa.\n')
    print(table(['Krug','Konfiguracija','Tablica','DATA_LENGTH','INDEX_LENGTH','INDEX prema A'],
                [[b['round'], b['config'], name, *b['space'][name],
                  b['space'][name][1]-data['A']['blocks'][b['round']-1]['space'][name][1]]
                 for b in series['blocks'] for name in ['reservation','ticket']]))
    print('\nINSERT 10.000 redaka u privremenu InnoDB kopiju reservation. Pocetni podaci su isti, svako mjerenje se ponisti; zagrijavanje, priprema kopije i ROLLBACK nisu u vremenu. Medijan/min-max svih 15 uzoraka po konfiguraciji.\n')
    base = st.median(data['A']['write'])
    print(table(['Konfiguracija','Medijan [min-max] ms','Promjena prema A'],
                [[c, stats(data[c]['write']), f'{(st.median(data[c]["write"])/base-1)*100:+.2f} %'] for c in LABELS]))
    for c in LABELS:
        print(f'\n{c}, svih 15 INSERT vremena (ms): '+', '.join(f(x) for x in data[c]['write'])+'.')
    total, refunded, not_refunded = series['ticket']
    delta = [data['B']['blocks'][i]['space']['ticket'][1]-data['A']['blocks'][i]['space']['ticket'][1] for i in range(3)]
    print(f'\nTicket: {total} karata, {refunded} s povratom ({100*refunded/total:.4f} %), {not_refunded} s NULL cancelled_at. Uski idx_ticket_cancelled_at povecava INDEX_LENGTH prema A za {min(delta)}-{max(delta)} bajtova (oko {st.median(delta)/1e6:.1f} MB). Indeks sadrzi i NULL vrijednosti svih neotkazanih karata.\n')

def render_document(series):
    assert not (ROOT / 'results' / 'archive').exists(), 'Tekst treba uskladiti s novom arhivom'
    for name in ['invalid_data.tsv', 'verify_reports.tsv']:
        assert (ROOT / 'results' / 'checks' / name).is_file(), name
    data = series['data']
    m = lambda c,q: st.median(data[c]['runs'][q])
    w = lambda c: st.median(data[c]['write'])
    print('# TASK 7 - Analiza performansi\n')
    # Sazetak: tocno deset redaka, ukljucujuci naslov i prazne retke.
    print('## Sazetak\n')
    print(table(['Medijani (ms)'] + QUERIES + ['INSERT'],
                [[c] + [f'{m(c,q):.2f}' for q in QUERIES] + [f'{w(c):.2f}']
                 for c in ['A', 'B']]))
    print('\nZadrzavamo uske indekse (B); A je stanje bez analiziranih indeksa.')
    print(f'Indeks kupca odbacujemo: mala usteda Q4 prati +{(w("C")/w("B")-1)*100:.1f} % INSERT-a u reservation.')
    print('Pokrivajuci indeks povrata odbacujemo radi prostora i jednostavnosti; njegova cijena pisanja nije izmjerena.\n')
    print(f'''Konacni izbor ostaje uski `idx_res_confirmed_at(confirmed_at)` i
`idx_ticket_cancelled_at(cancelled_at)`. FK/UNIQUE i ostali postojeci operativni
indeksi ostaju. Sve usporedbe u ovom dokumentu potjecu iskljucivo iz jednog novog
niza mjerenja; stara neusporediva mjerenja su obrisana.

## Skup podataka i okruzenje

MariaDB {series['version']}, InnoDB, Docker `eventhub-db`, buffer pool
{series['buffer_pool']} bajtova. `eventhub_perf` sadrzi 100.175 rezervacija i
189.133 karte: kopirani seed i 100.000 rezervacija iz `perf/01_generate_100k.sql`.
Postojeci skup zadovoljava prag; u ovoj reviziji nije regeneriran niti obnovljen.
`v_reserved_check` na kraju vraca 0 odstupanja. Perf scheduler je iskljucen.

## Postupak i ponavljanje

Iz korijena projekta, uz vec pripremljeni eventhub_perf:

```bash
# Prije novog pokretanja sacuvaj prethodni series.tsv i series_manifest.json
# u zasebnu mapu; runner odbija prepisati postojeci series.tsv.
python3 perf/run_series.py
python3 perf/summarize.py --document > docs/07_performanse.md
```

Ako performance baza nedostaje, prvo `bash perf/00_create_perf_db.sh` pa
`perf/01_generate_100k.sql` prema uputama generatora. To nije potrebno za ponavljanje
samih mjerenja i zamjenjuje postojecu performance kopiju.

Runner koristi jedan `docker exec` i jedan `mariadb --batch` proces/vezu. U toj
istoj sesiji redom izvrsava A, B, C, D, pa cijeli niz ponavlja ukupno tri puta:

| Konfiguracija | Skripte i stanje |
| --- | --- |
| A | 02_baseline.sql: bez analiziranih indeksa |
| B | 03_add_indexes.sql + 04_after.sql: dva konacna uska indeksa |
| C | 07_rejected_indexes.sql + 04_after.sql: uski datum potvrde, indeks kupca i pokrivajuci povrati |
| D | 06_rejected_cover.sql: siri datum potvrde uz iste ostale kandidate kao C |

Nakon treceg D runner izvrsava **02 -> 03** za povrat konacnog stanja. Mjerenja
koja se zbog sadrzaja 02 izvrse tijekom povrata oznacena su SERIES_RESTORE i
iskljucena iz statistike. Upiti, indeksi konfiguracija i SQL datoteke 02/03/04/06/07
nisu mijenjani u ovoj reviziji.

Sesija CONNECTION_ID={series['connection']}; pocetak {series['started']}, kraj
{series['finished']} (vrijeme servera). `series.tsv` sadrzi oznake svakog kruga,
iste CONNECTION_ID vrijednosti, sve sirove planove i popis indeksa svake
konfiguracije. `series_manifest.json` biljezi SHA-256 izvrsenih SQL datoteka,
rezultata, UTC vrijeme pokretanja i izlazni kod. `summarize.py` provjerava hash
rezultata, istu sesiju, redoslijed 12 konfiguracija, broj uzoraka i stvarne indekse.

Za svaki upit i INSERT u svakom krugu izvrsava se jedno zagrijavanje i pet
mjerenja. Konacna vrijednost je **medijan svih 15 pojedinacnih mjerenja**, a ne
medijan triju medijana. Prikazan je min-max svih 15 uzoraka. Query cache je OFF,
SELECT koristi SQL_NO_CACHE; InnoDB buffer pool nije praznjen. To je usporedba
zagrijanog rada, ne hladnog diska. U fiksnom A-D redoslijedu mogu ostati vremenski
trendovi i utjecaj OS-a; tri kruga i rasponi ih pokazuju, ali ih potpuno ne uklanjaju.

Vremena SELECT-a su korijenski `query_block.r_total_time_ms` iz ANALYZE JSON-a:
ukljucuju instrumentaciju, ne pokretanje Dockera ni prijenos rezultata klijentu.
Podcvorovi se ne zbrajaju jer vec ulaze u roditelja. `EXPLAIN.rows` je procjena,
`r_rows` prosjecan stvarni broj po petlji; ukupni dohvati ovise i o `r_loops`.
[MariaDB: ANALYZE FORMAT=JSON](https://mariadb.com/docs/server/reference/sql-statements/administrative-sql-statements/analyze-and-explain-statements/analyze-format-json).

Baseline ne uklanja PK/UNIQUE/FK indekse. `idx_res_event_status` je ujedno potporni
indeks fk_res_event, a fk_res_buyer se osigurava prije brisanja kandidata s istim
lijevim prefiksom. idx_res_status_expires i idx_event_date nisu kandidati ovog testa.
Q1/Q2 ovdje su Task 4 Q2/Q8; Q3-Q5 su dodatni selektivni upiti. Viewovi, triggeri,
procedure, podaci i SQL upiti ostaju isti.

Stara neusporediva mjerenja su obrisana. Jedini izvor usporedbi je
**perf/results/series.tsv** s tri A-D kruga u istoj sesiji.
''')
    render_summary(series)
    print(f'''## Odluke o indeksima

**idx_res_confirmed_at(confirmed_at)** ostaje: Q3 s {f(m('A','Q3'))} ms u A pada
na {f(m('B','Q3'))} ms u B. Datum omogucuje selektivni range, a implicitni InnoDB
PK id pokriva JOIN na stavke. Siri datum nije potreban samo za taj upit.

**idx_ticket_cancelled_at(cancelled_at)** ostaje: Q5 s {f(m('A','Q5'))} ms u A pada
na {f(m('B','Q5'))} ms u B. Za rijetke povrate Q2 takodjer moze koristiti range.
Iznos i item jos se dohvacaju iz tablice; prihvacamo tu cijenu uz manji indeks.

**fk_res_buyer(buyer_id)** vec postoji i dovoljan je za oko 20 rezervacija kupca.
B zadrzava filesort malog skupa. Ostali FK/UNIQUE/operativni indeksi ostaju:
idx_res_status_expires odgovara jednakosti statusa i rasponu isteka u proceduri,
a idx_res_event_status podupire FK/event upite. Ovaj niz ne dokazuje njihovu
beskorisnost i ne sluzi njihovu brisanju.

## Odbaceni kandidati

C naspram B: Q4 medijan je {f(m('B','Q4'))} -> {f(m('C','Q4'))} ms,
razlika {(m('B','Q4')-m('C','Q4'))*1000:.1f} mikrosekundi u korist C (negativno znaci sporije).
idx_res_buyer_created(buyer_id,created_at,id) uklanja filesort i rano staje,
ali apsolutna usteda ostaje mala za 22 rezervacije kupca. Ne zadrzavamo ga.

idx_ticket_refund_cover(cancelled_at,reservation_item_id,refund_amount) u C
pokriva SUM/JOIN: Q5 je {f(m('B','Q5'))} -> {f(m('C','Q5'))} ms,
Q2 {f(m('B','Q2'))} -> {f(m('C','Q2'))} ms. To su stvarni dobitci/gubitci novog
niza, a ne povijesne brojke. Promjena medijana Q2 je {(m('C','Q2')/m('B','Q2')-1)*100:+.2f} %; ne odbacujemo
stvaran dobitak citanja kao da ga nema. Dobitak citanja usporedjuje cijele konfiguracije B/C.
Za INSERT je atribucija drukcija: test unosi samo u privremenu kopiju reservation,
a B i C na toj tablici razlikuju se samo po idx_res_buyer_created.
C prema B povecava medijan INSERT-a s {f(w('B'))} na {f(w('C'))} ms
({(w('C')/w('B')-1)*100:+.1f} %): to je izmjerena cijena dodatnog
idx_res_buyer_created u ovom testu, uz prikazani raspon i moguci sum.
Cijena pisanja idx_ticket_refund_cover NIJE izmjerena jer test ne upisuje u ticket.
Taj indeks odbacujemo zbog dodatnog prostora i jednostavnosti, a ne na temelju
ovog INSERT usporenja. Razlika INDEX_LENGTH u svakom krugu je
{data['C']['blocks'][0]['space']['reservation'][1]-data['B']['blocks'][0]['space']['reservation'][1]} bajtova na reservation i
{data['C']['blocks'][0]['space']['ticket'][1]-data['B']['blocks'][0]['space']['ticket'][1]} na ticket.
Za ovaj studentski workload biramo manje indekse i jeftiniji unos, uz prihvaceno
sporije izvjestavanje nego u C. Bez definiranog produkcijskog omjera citanja i
pisanja ne tvrdimo da je B optimalan za svaki moguci workload.

D naspram C izolira zamjenu uskog datuma potvrde s
idx_res_confirmed_cover(confirmed_at,event_id,refund_protection_fee).
Q2: {f(m('C','Q2'))} -> {f(m('D','Q2'))} ms; Q3:
{f(m('C','Q3'))} -> {f(m('D','Q3'))} ms. Pokrivenost ne uklanja agregacije
velikog skupa. Rasponi svih konfiguracija prikazani su gore; ne tvrdimo da je
svaka razlika medijana statisticki znacajna.

## Zasto ne indeksirati svaki stupac

**Pisanje.** B prema A: INSERT medijan {f(w('A'))} -> {f(w('B'))} ms,
{(w('B')/w('A')-1)*100:+.2f} %. C prema A: {f(w('A'))} -> {f(w('C'))} ms,
{(w('C')/w('A')-1)*100:+.2f} %. Usporedbe su iz istog niza i istog testa.
Svaki dodatni B-tree trazi rad pri INSERT-u i promjeni indeksiranih vrijednosti.
Razlike vremena mogu biti pod utjecajem prikazanog suma i redoslijeda.

**Prostor i NULL.** Uski idx_ticket_cancelled_at zauzima oko 2,6 MB, iako samo
oko 2 % karata ima povrat: InnoDB indeks sadrzi i NULL cancelled_at vrijednosti
za sve preostale karte. Tocan broj/pct i izmjerena INDEX razlika prikazani su gore.
Niska ucestalost povrata ne znaci da je indeks djelomican ili da sadrzi samo povrate.
Dodatni indeksi povecavaju buffer pool/I/O, backup, izgradnju i odrzavanje statistika.

**Zasto su DATA/INDEX velicine drukcije nego u obrisanim starim mjerenjima?** Tablice su prije ovog niza
obnovljene iz logickog dumpa tijekom prethodne obnove baze. Dump prenosi retke i
DDL, ne stari fizicki raspored stranica. Restore ponovno gradi klasterirane i
sekundarne indekse, mijenja popunjenost i slobodne stranice; kasniji DROP/CREATE
indeksa takodjer utjece na alokaciju. Zato jednaki logicki podaci ne jamce jednak
DATA_LENGTH/INDEX_LENGTH. To nije dokaz nestanka redaka niti se stari i novi
apsolutni brojevi prostora koriste kao usporedba kandidata. Usporedba je sada
medju A-D unutar istog kruga, a u tablici su sve tri vrijednosti.

**Q4 i preklapanje.** Uklanjanje filesort nije samo po sebi dovoljan razlog za
indeks: sortiranje 22 redaka je jeftino. Kandidat ponavlja buyer_id prefiks vec
postojeceg FK indeksa. Uski i pokrivajuci datum povrata takodjer dijele prefiks;
ne zadrzavamo oba. Pojedinacni indeksi na svakom stupcu ne zamjenjuju smislen
redoslijed slozenog indeksa, ali ni svaki slozeni indeks nije isplativ.

**Optimizator i selektivnost.** Vise mogucih pristupnih puteva ne jamci bolji plan.
Status ima malo vrijednosti, dok datum moze izdvojiti mali raspon. Q1 mora brojiti
cijeli skup bez obzira na indeks; Q2 mora agregirati mnogo rezervacija. Temporary
i filesort u takvom izvjestaju nisu sami po sebi pogreska.

**Kompozitni FK.** uq_reservation_id_event, uq_category_id_event,
uq_item_id_category, uq_seat_id_category i uq_rs_id_item vec trose prostor i rad
provjere jedinstvenosti, ali jamce konzistentnu pripadnost eventu/kategoriji/stavci.
Ostaju u A-D i kopiraju se u INSERT mikrobenchmark; ne uklanjaju se zbog
preklapanja s PK.

## Kompromisi i zakljucak

Izbor indeksa nije promijenjen: uski indeksi su dovoljni za demonstrirane
selektivne upite, a C/D ostaju odbaceni kandidati. To je odluka o apsolutnoj koristi,
prostoru i pisanju, a ne tvrdnja da su B vremena najbolja za svaki upit.
C ima bolji Q2 medijan i znatno bolji Q5 od B; D ima losiji Q2 medijan od C.
Novi niz zato ne podrzava staru tvrdnju da C nema mjerljiv dobitak u citanju:
podrzava odbacivanje indeksa kupca prema kompromisu s INSERT-om i prostorom,
a indeksa povrata zbog prostora i jednostavnosti; njegova cijena pisanja nije izmjerena.
Q1 i B-Q4 imaju iste pristupne puteve kao A; razlike vremena nisu dokaz poboljsanja.
Q2 ostaje skup i ne postaje selektivan samo dodavanjem indeksa. Q5 prihvaca dodatni
dohvat iz tablice u zamjenu za uzi indeks.

INSERT je mikrobenchmark reservation indeksa: CREATE TEMPORARY TABLE LIKE kopira
stupce, CHECK/UNIQUE i indekse, ali ne FK/triggere. Nema poslovnih procedura,
trajnog COMMIT-a, ni upisa u ticket. Priprema i rollback nisu u vremenu.
Zato cijena pisanja ticket indeksa i puna poslovna transakcija nisu izmjerene.
[MariaDB: CREATE TABLE LIKE](https://mariadb.com/docs/server/server-usage/tables/create-table).

## Zavrsno stanje i samoprovjera

Nakon niza stvarno je izvrsen 02 -> 03. FINAL_INDEX/FINAL_COUNTS u series.tsv
potvrdjuju dva uska indeksa, odsutnost tri kandidata, 100.175 rezervacija,
189.133 karte i 0 odstupanja brojacima. Mala baza eventhub nije mijenjana.
Regresije prethodne revizije 81/81 i 18/18 sacuvane su u
`perf/results/checks/invalid_data.tsv` i `verify_reports.tsv`. To su provjere
ispravnosti, a ne stara mjerenja performansi; nisu predstavljene kao nova izvrsavanja.

| Acceptance kriterij | Gdje |
| --- | --- |
| Najmanje 100.000 rezervacija | Skup podataka; ENV i FINAL_COUNTS u series.tsv; perf/01_generate_100k.sql |
| Spori izvjestaji i EXPLAIN za najmanje dva upita | SQL, EXPLAIN i stvarni redci: svih pet upita, sve cetiri konfiguracije |
| Opravdane odluke o indeksima | Odluke o indeksima i Odbaceni kandidati; konfiguracije B/C/D |
| Mjerenja prije i poslije | Izmjerena vremena: medijan/min-max 15 uzoraka; sirovi series.tsv |
| Trade-off dodatnih indeksa | Prostor i INSERT; Zasto ne indeksirati svaki stupac; Kompromisi |
| Ponovljivost | perf/run_series.py, series_manifest.json; tri A-D kruga i zavrsni povrat |
''')

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--document', action='store_true', help='Ispisi cijeli docs/07_performanse.md')
    args = parser.parse_args()
    series = read_series()
    if args.document:
        render_document(series)
    else:
        render_summary(series)

if __name__ == '__main__':
    main()
