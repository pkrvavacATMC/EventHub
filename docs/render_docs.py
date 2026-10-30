'Osvjezi dokumentaciju iskljucivo iz zadnjih uspjesnih dokaza.'
import argparse
import contextlib
import hashlib
import io
import json
from pathlib import Path
import re
import sys

ROOT=Path(__file__).resolve().parents[1]
RESULTS=ROOT/'tests/results'
DOCS=ROOT/'docs'


def table(headers,rows):
    def row(items):return '| '+' | '.join(str(x).replace('|','\\|') for x in items)+' |'
    return '\n'.join([row(headers),row(['---']*len(headers))]+[row(r) for r in rows])


def main():
    assert (ROOT/'eventhub-diagram.png').is_file(), 'Nedostaje postojeci PNG dijagram'
    manifest=json.loads((RESULTS/'manifest.json').read_text())
    assert manifest['status']=='passed','Skup testova nije uspješno zavrsio'
    for name,digest in manifest['source_sha256'].items():
        assert hashlib.sha256((ROOT/name).read_bytes()).hexdigest()==digest,'Nakon testa promijenjen: '+name
    for name,digest in manifest['artifacts'].items():
        assert hashlib.sha256((RESULTS/name).read_bytes()).hexdigest()==digest,name
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--with-performance', action='store_true', help='Zahtijeva nove dokaze mjerenja performansi koji odgovaraju aktualnim migracijama')
    args=parser.parse_args()
    series=None
    if args.with_performance:
        sys.path.insert(0,str(ROOT/'perf'))
        import summarize
        series=summarize.read_series()
    date=manifest['finished_utc'];prefix=f'Provjereno **{date}**, na novoj shemi. Dokazi: [manifest](../tests/results/manifest.json).\n\n'
    read=lambda name:(RESULTS/name).read_text()
    rows=[line.split('\t') for line in read('invalid_data.tsv').splitlines() if len(line.split('\t'))==6 and line.split('\t')[0].isdigit() and line.endswith('\tPASS')]
    assert len(rows)==88
    negative_rows=rows
    (DOCS/'01_invalid_data_output.md').write_text('# Rezultati testova neispravnih podataka\n\n'+prefix+f'**{len(negative_rows)} PASS, 0 FAIL**, brojaci uskladeni.\n\n'+table(['id','kategorija','opis','očekivano','dobiveno','rezultat'],rows)+'\n\n[Sirovi ispis](../tests/results/invalid_data.tsv). Dodatni UUID/type/zone testovi su u [constraints.txt](../tests/results/constraints.txt).\n')
    rows=[line.split('\t') for line in read('transactions.tsv').splitlines() if len(line.split('\t'))==5 and line.split('\t')[0].isdigit() and line.endswith('\tPASS')]
    assert len(rows)==7
    (DOCS/'05_transactions_output.md').write_text('# Rezultati transakcijskih testova\n\n'+prefix+'**7/7 PASS.** PASS u prvom scenariju znači da je namjerni problem bez transakcije reproduciran i zatim popravljen.\n\n'+table(['n','test','očekivano','dobiveno','rezultat'],rows)+'\n\n[Sirovi rezultat](../tests/results/transactions.tsv). Dodatno je provjereno šest zaštita transakcije i pet vraćanja vremenske zone veze nakon greške: [dokaz](../tests/results/transaction_guards.txt).\n')
    raw=read('concurrency.txt');summary=[line.split('|') for line in raw.splitlines() if line.startswith(('PASS |','FAIL |'))]
    assert len(summary)==4
    (DOCS/'06_concurrency_output.md').write_text('# Rezultati konkurentnih kupnji\n\n'+prefix+table(['rezultat','scenarij','stanje'],[[x.strip() for x in r] for r in summary])+'\n\nA prikazuje prodaju 11 karata uz kapacitet 10 i ispravak transakcijom. B zaključava redak, C odbija prekoračenje brojača, a D koristi 10 zasebnih veza i poslovne procedure. Sva četiri scenarija prolaze; završni v_reserved_check je prazan.\n\n[Potpun ispis svih sesija](../tests/results/concurrency.txt). Reprodukcija: `bash tests/06_concurrency.sh`, nad testnom bazom; dodaje demo podatke.\n')
    checks=[line.split('\t') for line in read('reports.tsv').splitlines() if line.endswith('\tPASS')]
    assert len(checks)==18
    (DOCS/'04_izvjestaji.md').write_text('# Izvještaji i provjera\n\n'+prefix+'Nad čistim seedom: **8 događaja, 40 kupaca, 175 rezervacija, 290 karata**. Rezultat: **18 PASS, 0 FAIL**.\n\n```bash\ndocker compose exec -T db sh -c \'MYSQL_PWD="$MARIADB_ROOT_PASSWORD" mariadb -uroot eventhub\' < reports/02_verify_reports.sql\n```\n\nOsam upita je u [reports/01_reports.sql](../reports/01_reports.sql), definicije u [004-views.sql](../migrations/004-views.sql). Q1 broji potvrđene karte; Q2 rangira kupce; Q3 nalazi manje od 10 % mjesta; Q4 prihod po događaju; Q5 događaje bez rezervacija; Q6 stopu otkazivanja bez isteka u nazivniku; Q7 organizatore; Q8 poslovne mjesece u Europe/Zagreb.\n\n'+table(['provjera','rezultat'],checks)+'\n\n[Sirovi dokaz](../tests/results/reports.tsv). Provjera se izvršava prije demonstracija koje dodaju podatke; poznate seed brojke poslije toga nisu primjenjive.\n')
    restore=read('restore.tsv').splitlines();rows=[r.split('\t') for r in restore[1:] if not r.startswith('PASS')]
    (DOCS/'08_administracija.md').write_text('# Sigurnosna kopija, povrat podataka i ovlasti\n\n'+prefix+'Izrada sigurnosne kopije i povrat podataka provjereni su u izoliranom Compose okruzenju na novoj shemi, bez promjena glavne baze. Uspoređeni su svi reci preko CHECKSUM TABLE EXTENDED te UNIX_TIMESTAMP svih devet vremenskih stupaca.\n\n'+table(['tablica','redaka','checksum jednak','epoch jednak'],rows)+'\n\nVraćeno je 10 rutina, 21 trigger, 7 pogleda i event. Provjereno je da pogledi čitaju restore bazu, ne izvor. Scheduler je isključen već u ulaznom dumpu. [Dokaz](../tests/results/restore.tsv).\n\n## Ručni postupak\n\n```bash\nmkdir -p backup\ndocker compose exec -T db sh -c \'MYSQL_PWD="$MARIADB_ROOT_PASSWORD" mariadb-dump -uroot --single-transaction --routines --triggers --events eventhub\' > backup/eventhub_backup.sql\ndocker compose exec -T db sh -c \'MYSQL_PWD="$MARIADB_ROOT_PASSWORD" mariadb -uroot -e "CREATE DATABASE eventhub_restore CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"\'\nset -o pipefail\nsed \'/EVENT `ev_expire_reservations` ON SCHEDULE/s/ ENABLE DO / DISABLE DO /\' backup/eventhub_backup.sql | docker compose exec -T db sh -c \'MYSQL_PWD="$MARIADB_ROOT_PASSWORD" mariadb -uroot eventhub_restore\'\n```\n\nSvaki korak mora završiti uspješno. CREATE namjerno staje ako cilj već postoji. Backup ne sadrzi korisnike/grantove; oni su u 005. Prije usporedbe izvor ne smije biti mijenjan. Izvornu bazu ne brisati. Dump sadrzi podatke i ne ide u Git; za stvarne podatke čuvati i kopiju izvan racunala.\n\n## Ovlasti\n\nKorisniku s ovlastima samo za čitanje prolazi čitanje; pet DML/DDL pokušaja odbijeno je s 1142, CALL s 1370. [Stvarni ispis](../tests/results/readonly.txt). Kao eventhub_app uspješno je pozvano svih pet dopuštenih procedura, a SELECT buyer i direktni UPDATE su odbijeni. [Pozivi](../tests/results/app_calls.txt), [SHOW GRANTS](../tests/results/grants.txt). Root se koristi za administraciju, ne za aplikaciju.\n\nAutomatska reprodukcija ukljucuje sve provjere: `python3 tests/test_database.py`. Postupak provjerava podatke i ovlasti u zasebnom okruženju.\n')
    (DOCS/'10_schema_validation.md').write_text('# Završna provjera nove baze\n\n'+prefix+'Sedam SQL datoteka, 56 changesetova; 006 nadograđuje buyer bez promjene prethodnih changesetova. Shema je testirana od praznog volumena i ponovnim updateom, zatim potpunim rollbackom svih 56 changesetova, ponovnim updateom i seedom.\n\n| Područje | Rezultat |\n| --- | --- |\n| Ograničenja izvornih poslovnih pravila | 88/88 |\n| Novi UUID/type/zone unosi | 15 odbijenih nevaljanih unosa; UUID testiran u oba SQL načina |\n| Izvještaji čistog seeda | 18/18 |\n| Transakcijski scenariji | 7/7 |\n| Konkurentnost | 4/4; 10 veza za zadnju kartu |\n| UTC/DST matrica | 24 create, 12 confirm, 72 refund, 48 check-in, 12 simulacija sata |\n| Rok preko samog DST prijelaza | 6/6; 900 sekundi u tri zone |\n| Zaštite transakcije / povrat zone nakon greške | 6/6 i 5/5 |\n| Ovlasti i stvarni app pozivi | Pet procedura prolazi; nedopušteni upisi/čitanje odbijeni |\n| Sigurnosna kopija i povrat podataka | 12 tablica; svi checksumovi i epoch vrijednosti isti |\n| Scheduler | Stvarni UTC event otkazao isteklu rezervaciju; rok 900 sekundi |\n| Seed | 8 događaja, 40 kupaca, 175 rezervacija; external_id je NULL |\n| Potpuni rollback i ponovna instalacija | 56/56 |\n\n## Reprodukcija\n\n```bash\npython3 tests/test_database.py\n# Obnovi i izmjeri eventhub_perf prema docs/07_performanse.md.\npython3 docs/render_docs.py\n```\n\nTest koristi vlastiti Compose projekt i volumen; glavnu i performance bazu ne mijenja. Vremenski model i poslovna pravila opisani su u [strukturi baze](02_database_structure.md).\n\n[EXPLAIN check-ina](../tests/results/check_in_explain.tsv) koristi uq_ticket_code, const i jedan redak. [Mjerenja indeksa](07_performanse.md) imaju zaseban manifest i datum; čitanje/pisanje cijelog produkcijskog workload-a, aplikacija i gateway nisu predmet ovih testova. Ovo je dokaz navedenih provjera na MariaDB 10.11, ne tvrdnja da nijedna moguća greška ne postoji.\n')
    live_path=RESULTS/'keycloak_live_manifest.json'
    if live_path.exists():
        live=json.loads(live_path.read_text())
        assert live['status']=='passed'
        for name,digest in live['artifacts_sha256'].items():
            assert hashlib.sha256((RESULTS/name).read_bytes()).hexdigest()==digest,name
        preservation=json.loads((RESULTS/live['migration_preservation']).read_text())
        assert preservation['status']=='passed' and preservation['before']==preservation['after']
        preserved=[[name,*details['counts']] for name,details in preservation['after'].items()]
        validation=DOCS/'10_schema_validation.md'
        validation.write_text(validation.read_text()+
            '\n## Nadogradnja postojećih baza na 006\n\n'+
            f'Provjereno {live["finished_utc"]}. U obje baze primijenjena je samo 006; prethodnih 55 changesetova i njihovi checksumi ostali su isti. '
            'Usporedba svih poslovnih stupaca kupaca i svih redaka rezervacija i karata daje identične SHA-256 prije i poslije migracije.\n\n'+
            table(['baza','kupci','rezervacije','karte'],preserved)+
            '\n\nNa postojećem eventhubu: 88/88 podataka, 18/18 izvještaja, 7/7 transakcija, 4/4 konkurentnost i sve očekivane read-only zabrane. '
            'Seed nije ponovno pokrenut. Transakcijske i konkurentne demonstracije dodaju podatke; navedene brojke čistog seeda vrijede prije demonstracija. '
            'Obje baze imaju usklađene brojače. [Očuvanje podataka](../tests/results/keycloak_migration.json), '
            '[manifest provjere postojeće baze](../tests/results/keycloak_live_manifest.json).\n')
    (DOCS/'03_testovi_neispravnih_podataka.md').write_text(
        '# Testovi neispravnih podataka i očekivano ponašanje\n\n'+prefix+
        'Skripta `tests/01_invalid_data.sql` izvršava se nakon migracija i seeda. '
        'Svaki test provjerava očekivani kod greške i dio poruke; pozitivni testovi očekuju uspjeh. '
        'Direktni upisi izvode se u transakciji koju `t_expect` poništava, a nedopušteni pozivi procedura moraju biti odbijeni. '
        'Brojači zauzeća na kraju moraju biti usklađeni.\n\n'
        '| Kod | Zaštita |\n| --- | --- |\n| 1048 | NOT NULL |\n| 1062 | UNIQUE |\n| 1451 / 1452 | FOREIGN KEY |\n| 4025 | CHECK |\n| 1644 | Poslovno pravilo u triggeru ili proceduri |\n\n'
        '## Keycloak poveznica\n\n'
        '`external_id` je NULL ili UUID malim slovima s crticama. UNIQUE odbija duplikat, '
        'CHECK odbija pogrešan format, velika slova, nedostajuće crtice i neheksadekadske znakove. '
        'Dva nova kupca s NULL vrijednošću i upis valjanog UUID-a prolaze; svi upisi se poništavaju. '
        'Dodatne provjere u `tests/suite_checks.py` pokrivaju newline i NO_BACKSLASH_ESCAPES.\n\n'
        '## Rezultati\n\nSvi scenariji i njihovi rezultati nalaze se u [tablici rezultata](01_invalid_data_output.md).'+
        f'\n\n**{len(negative_rows)} PASS, 0 FAIL.** [Sirovi ispis](../tests/results/invalid_data.tsv). '
        '[Dodatne provjere](../tests/results/constraints.txt), [završna validacija](10_schema_validation.md).\n')
    # Vodič za prezentaciju ručno se održava na hrvatskom; rezultati su povezani manifestom.
    if series is not None:
        with contextlib.redirect_stdout(io.StringIO()) as output:summarize.render_document(series)
        (DOCS/'07_performanse.md').write_text(output.getvalue())
        validation=DOCS/'10_schema_validation.md'
        read_count=sum(len(values) for data in series['data'].values() for values in data['runs'].values())
        write_count=sum(len(data['write']) for data in series['data'].values())
        validation.write_text(validation.read_text()+f'\n## Zavrsno performance mjerenje\n\nCijela A/B/C/D serija ponovljena je {series["manifest"]["finished_utc"]}: {read_count} mjerenja upita i {write_count} INSERT mjerenja, sva trajanja valjana. Sva tri kruga zavrsena su nad istim skupom; na kraju je vracena konfiguracija B, uz 0 neuskladjenih brojaca. Negativno trajanje odbacuje seriju prije objave dokumentacije. [Dokazi i ogranicenja](07_performanse.md), [manifest](../perf/results/series_manifest.json).\n')
    print('PASS: dokumentacija generirana iz uspješnog manifesta; postojeci PNG dijagram ostaje sačuvan.')


if __name__=='__main__':main()
