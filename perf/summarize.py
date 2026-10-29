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
    assert all(value >= 0 for value in data['write']), 'Nevaljano trajanje INSERT-a; ponovi cijelu seriju'
    assert all(value >= 0 for values in data['runs'].values() for value in values), 'Nevaljano trajanje upita'
    assert data['warmups'] == QUERIES
    assert data['env'][1]=='OFF' and int(data['env'][2])>=100000 and int(data['env'][3])>0
    return data

def read_series():
    path = ROOT / 'results' / 'series.tsv'
    raw = path.read_bytes()
    manifest = json.loads((ROOT / 'results' / 'series_manifest.json').read_text())
    assert manifest['exit_code'] == 0 and manifest['rounds'] == 3
    assert hashlib.sha256(raw).hexdigest() == manifest['result_sha256']
    for name,digest in manifest['schema_sha256'].items():
        assert hashlib.sha256((ROOT.parent/name).read_bytes()).hexdigest()==digest, 'Promijenjena shema: '+name
    for name,digest in manifest['source_sha256'].items():
        assert hashlib.sha256((ROOT/name).read_bytes()).hexdigest()==digest, 'Promijenjen upit: '+name
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
    assert counts == [str(manifest['database']['reservations']),str(manifest['database']['tickets']),'0']
    assert all(b['env'][2:4]==counts[:2] for b in blocks)
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
    ('Bruto prodaja u jednom UTC danu', 'Selektivni dnevni pregled u UTC-u. Poluotvoreni raspon datuma ostaje sargable. Ovo je bruto cijena karata i service fee, bez zastite i povrata. COUNT(DISTINCT r.id) sprjecava visestruko brojanje rezervacije s vise stavki. Datumski indeks izdvaja mali skup umjesto obilaska svih stavki.'),
    ('Povijest jednog kupca', 'Ekran zadnjih 10 rezervacija jednog kupca u generiranom skupu. A/B koriste fk_res_buyer uz filesort malog skupa. C/D koriste indeks buyer_id,created_at,id, uklanjaju filesort i prekidaju nakon 10 redaka. Isplativost se procjenjuje prema apsolutnoj ustedi, prostoru i INSERT-u u ovom nizu.'),
    ('Povrati u UTC mjesecu', 'Selektivni pregled UTC mjeseca. A cita cijelu tablicu ticket. B range cita mjesec povrata i dohvaca refund_amount iz tablice; C/D pokrivaju SUM indeksom. Uzi indeks vec uklanja full scan; dodatna pokrivenost ima dodatni trosak.')]

def render_summary(series):
    data = series['data']
    print('## Izmjerena vremena\n')
    print('Samo series.tsv: jedna MariaDB sesija, tri uzastopna A-D kruga. Svaka celija: medijan [min-max] u ms svih 15 mjerenja (5 po krugu); vremena >= 1 ms imaju jednu decimalu, manja tri; tri zagrijavanja po konfiguraciji/upitu su iskljucena. Arhiva nije ukljucena.\n')
    print(table(['Upit']+[f'{c}: {LABELS[c]}' for c in LABELS],
                [[q]+[stats(data[c]['runs'][q]) for c in LABELS] for q in QUERIES]))
    print('\n### Medijani pojedinih krugova\n')
    print(table(['Krug','Konfiguracija']+QUERIES+['INSERT ms'],
                [[b['round'], b['config']]+[f(st.median(b['runs'][q])) for q in QUERIES]+[f(st.median(b['write'])) if all(x >= 0 for x in b['write']) else 'Nevaljano mjerenje'] for b in series['blocks']]))
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
    print('\nINSERT 10.000 redaka u privremenu InnoDB kopiju reservation. Pocetni podaci su isti, svako mjerenje se ponisti; zagrijavanje, priprema kopije i ROLLBACK nisu u vremenu. Medijan/min-max svih 15 uzoraka po konfiguraciji. Negativno trajanje odbacuje cijelu seriju prije generiranja dokumentacije; svi prikazani uzorci prosli su provjeru.\n')
    base = st.median(data['A']['write'])
    print(table(['Konfiguracija','Medijan [min-max] ms','Promjena prema A'],
                [[c, stats(data[c]['write']), f'{(st.median(data[c]["write"])/base-1)*100:+.2f} %'] if all(x >= 0 for x in data[c]['write']) else [c, 'Iskljuceno: nevaljano mjerenje', 'Nije dostupno'] for c in LABELS]))
    for c in LABELS:
        if all(x >= 0 for x in data[c]['write']):
            print(f'\n{c}, svih 15 INSERT vremena (ms): '+', '.join(f(x) for x in data[c]['write'])+'.')
        else:
            print(f'\n{c}: INSERT mjerenje treba ponoviti. Izvorni zapis ostaje u series.tsv radi provjerljivosti; trajanja i usporedbe ovog niza nisu prikazani.')
    total, refunded, not_refunded = series['ticket']
    delta = [data['B']['blocks'][i]['space']['ticket'][1]-data['A']['blocks'][i]['space']['ticket'][1] for i in range(3)]
    print(f'\nTicket: {total} karata, {refunded} s povratom ({100*refunded/total:.4f} %), {not_refunded} s NULL cancelled_at. Uski idx_ticket_cancelled_at povecava INDEX_LENGTH prema A za {min(delta)}-{max(delta)} bajtova (oko {st.median(delta)/1e6:.1f} MB). Indeks sadrzi i NULL vrijednosti svih neotkazanih karata.\n')

def render_document(series):
    data=series['data']
    median=lambda c,q:st.median(data[c]['runs'][q])
    write=lambda c:st.median(data[c]['write'])
    meta=series['manifest']
    print('# Analiza performansi nove testne sheme\n')
    print(f"Mjerenje zavrseno {meta['finished_utc']}. MariaDB {series['version']}; session UTC; "
          f"{meta['database']['reservations']} rezervacija i {meta['database']['tickets']} karata. "
          f"Buffer pool: {series['buffer_pool']} bajtova.\n")
    print('Performance baza je ponovno stvorena iz aktualnog cistog seeda i prosirena za 100.000 rezervacija. '
          f"Koristi {series['manifest']['database']['system_timestamp_columns']} TIMESTAMP stupaca, lokalni event_date, IANA zone i ASCII kod karte. "
          'Stara mjerenja nisu ukljucena u ove rezultate.\n')
    print('## Postupak\n')
    print('Jedna MariaDB sesija, tri A-D kruga; jedno zagrijavanje i pet mjerenja po upitu/krugu. '
          'Medijan je iz svih 15 uzoraka, uz min-max. Query cache OFF, SQL_NO_CACHE; buffer pool nije praznjen. '
          'Fiksni redoslijed i OS sum ostaju ogranicenja. ANALYZE instrumentacija ulazi u vrijeme.\n')
    print(table(['Konfiguracija','Opis'],[[c,LABELS[c]] for c in LABELS]))
    print('\nA uklanja samo kandidate; PK/UNIQUE/FK i operativni indeksi ostaju. '
          'B koristi dva uska datumska indeksa. C dodaje povijest kupca i pokrivajuce povrate; '
          'D prosiruje i indeks potvrda. Na kraju se vraca B.\n')
    print('Q3 i Q5 koriste UTC datumske granice jer je session UTC; Q2 koristi poslovne mjesece u Europe/Zagreb. Za lokalni dan ili mjesec granice se prvo pretvore u UTC, a indeksirani stupac ostaje bez funkcije.\n')
    print('Manifest biljezi hash sheme, generatora, upita i rezultata te stvarne tipove stupaca. '
          'Parser provjerava iste podatke u svim krugovima i stvarne indekse konfiguracija.\n')
    render_summary(series)
    print('## Procjena indeksa\n')
    print(table(['Usporedba','Prije ms','Poslije ms','Tumacenje'],[
        ['A/B, Q3',f(median('A','Q3')),f(median('B','Q3')),'Uski confirmed_at izdvaja datumski raspon'],
        ['A/B, Q5',f(median('A','Q5')),f(median('B','Q5')),'Uski cancelled_at izdvaja povrate'],
        ['B/C, Q4',f(median('B','Q4')),f(median('C','Q4')),'Indeks kupca izbjegava sortiranje'],
        ['B/C, Q2',f(median('B','Q2')),f(median('C','Q2')),'Pokrivajuci povrati mijenjaju dio izvjestaja'],
        ['C/D, Q2',f(median('C','Q2')),f(median('D','Q2')),'Siri indeks potvrda'],
        ['B/C, INSERT',f(write('B')),f(write('C')),'Samo trosak reservation indeksa']]))
    print(f"\nQ4 razlika B/C je {(median('B','Q4')-median('C','Q4'))*1000:.1f} mikrosekundi. "
          f"INSERT C/B promjena je {(write('C')/write('B')-1)*100:+.1f} %. "
          'To su izmjereni smjerovi promjene, bez tvrdnje da je svaka razlika statisticki znacajna.\n')
    print('Konacni izbor za ovaj testni workload ostaje B: uski confirmed_at i cancelled_at uz postojece '
          'FK/UNIQUE/operativne indekse. C/D ostaju kandidati za opterecenje s vise citanja. '
          'Prednost u izvjestaju ne odbacujemo ako postoji: tablice iznad pokazuju stvaran dobitak i trosak. '
          'Bez omjera citanja/pisanja i ciljne latencije ne tvrdimo da je B univerzalno optimalan.\n')
    print('idx_res_status_expires(status,expires_at) odgovara jednakosti statusa i rasponu isteka; '
          'uq_ticket_code sluzi pojedinacnom check-in lookupu. Kompozitni UNIQUE indeksi sluze i FK '
          'konzistentnosti pa se ne brisu samo zbog preklapanja s PK. '
          'Indeks event_date opisuje lokalni kalendar, ne globalno UTC sortiranje vise zona.\n')
    print('## Ogranicenja mjerenja\n')
    print('INSERT koristi CREATE TEMPORARY TABLE LIKE reservation: kopira stupce, CHECK/UNIQUE i indekse, '
          'ali ne FK ni triggere. Ne mjeri poslovne procedure, trajni COMMIT ni pisanje ticket tablice. '
          'Zato ovim testom nije izmjerena cijena pisanja pokrivajuceg ticket indeksa. '
          'INDEX_LENGTH su procjene alociranih stranica, ne precizne logicke velicine; '
          'NULL vrijednosti takodjer ulaze u InnoDB indekse. Mjesecno grupiranje ima '
          'CONVERT_TZ/UNIX_TIMESTAMP obradu pa se stari DATETIME rezultati ne prenose.\n')
    print('Izvori: [MariaDB ANALYZE FORMAT=JSON](https://mariadb.com/docs/server/reference/sql-statements/administrative-sql-statements/analyze-and-explain-statements/analyze-format-json), '
          '[CREATE TABLE LIKE](https://mariadb.com/docs/server/server-usage/tables/create-table), '
          '[izbor indeksa](https://mariadb.com/docs/server/ha-and-performance/optimization-and-tuning/optimization-and-indexes/building-the-best-index-for-a-given-select).\n')
    print('## Reprodukcija\n\n```bash\nbash perf/00_create_perf_db.sh\ndocker compose exec -T db sh -c \'MYSQL_PWD="$MARIADB_ROOT_PASSWORD" mariadb -uroot\' < perf/01_generate_100k.sql\n# Arhiviraj stari series.tsv i series_manifest.json izvan perf/results.\npython3 perf/run_series.py\npython3 perf/summarize.py --document > docs/07_performanse.md\n```\n')
    print('Glavna baza treba imati cisti seed od 175 rezervacija; performance kopija se zamjenjuje. '
          'Funkcionalni dokazi nove sheme su u tests/results/manifest.json, a nezavisne seed '
          'provjere u perf/results/checks. FINAL_COUNTS potvrduje 0 neuskladjenih brojaca.\n')

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
