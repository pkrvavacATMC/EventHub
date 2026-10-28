#!/usr/bin/env python3
"""Stvarni MariaDB/Liquibase test; koristi i uklanja samo vlastiti Compose projekt."""
import os
from pathlib import Path
import re
import subprocess
import uuid

ROOT = Path(__file__).resolve().parents[1]
PROJECT = "eventhub-liquibase-test-" + uuid.uuid4().hex[:10]
ENV = dict(os.environ, MARIADB_ROOT_PASSWORD="isolated-root-only",
           EVENTHUB_APP_PASSWORD="isolated'app\\password$();",
           EVENTHUB_REPORT_PASSWORD="isolated'report\\password$();",
           EVENTHUB_TEST_DB_CONTAINER=PROJECT + "-db")
COMPOSE = ["docker", "compose", "--env-file", "/dev/null", "-p", PROJECT,
           "-f", str(ROOT / "docker-compose.yml"),
           "-f", str(ROOT / "tests/compose.liquibase.yml")]
TABLES = re.findall(r"^CREATE TABLE (\w+)",
                    (ROOT / "migrations/001-tables.sql").read_text(), re.M)
CHANGESETS = sum(len(re.findall(r"^--changeset ", p.read_text(), re.M))
                 for p in (ROOT / "migrations").glob("*.sql"))


def run(*args, source=None, ok=True):
    result = subprocess.run(COMPOSE + list(args), cwd=ROOT, env=ENV, input=source,
                            text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                            timeout=180)
    if ok and result.returncode:
        raise AssertionError(result.stdout)
    if not ok and not result.returncode:
        raise AssertionError("Naredba je neocekivano uspjela: " + result.stdout)
    return result.stdout


def sql(source, user="root", ok=True):
    password_var = {"root": "MARIADB_ROOT_PASSWORD",
                    "eventhub_app": "EVENTHUB_APP_PASSWORD",
                    "eventhub_report": "EVENTHUB_REPORT_PASSWORD"}[user]
    return run("exec", "-T", "db", "bash", "-c",
               f'export MYSQL_PWD="${password_var}"; exec mariadb -h127.0.0.1 '
               f'-u{user} --batch --skip-column-names eventhub', source=source, ok=ok).strip()


def update(ok=True):
    return run("run", "--rm", "--no-deps", "liquibase", "update", ok=ok)


def snapshot(extra=False):
    names = TABLES + (["job_error_log"] if extra else [])
    # Usporedi svaku vrijednost, ukljucujuci NULL i generirani active_seat_id.
    # CHECKSUM TABLE nije zamjena za izravnu usporedbu svih redaka.
    return sql("\n".join(f"SELECT '{name}'; SELECT * FROM {name} ORDER BY id;"
                         for name in names))


def regressions():
    for name in ["tests/01_invalid_data.sql", "reports/02_verify_reports.sql"]:
        output = sql((ROOT / name).read_text())
        assert "PASS" in output and not re.search(r"\bFAIL\b", output), output
        print("PASS", name, flush=True)
    assert sql("SELECT COUNT(*) FROM reservation;", "eventhub_report") == "175"
    sql("SELECT * FROM v_event_capacity LIMIT 1;", "eventhub_app")
    for user, statement, error in [
        ("eventhub_app", "INSERT INTO city(name) VALUES ('ne smije proci');", "1142"),
        ("eventhub_report", "UPDATE city SET name='ne smije proci' WHERE 1=0;", "1142"),
        ("eventhub_report", "CALL confirm_reservation(999999);", "1370"),
    ]:
        assert error in sql(statement, user, ok=False)
    print("PASS korisnicke ovlasti i lozinke s posebnim znakovima", flush=True)


def procedure(name):
    source = (ROOT / "migrations/003-procedures-event.sql").read_text()
    return re.search(r"CREATE OR REPLACE PROCEDURE " + name +
                     r"\([\s\S]*?(?=\n--changeset|\Z)", source).group().strip()


try:
    run("up", "-d")
    run("wait", "liquibase")
    run("run", "--rm", "--no-deps", "liquibase", "validate")
    update()
    assert sql("SELECT COUNT(*) FROM DATABASECHANGELOG;") == str(CHANGESETS)
    assert sql("SELECT COUNT(*) FROM information_schema.TRIGGERS "
               "WHERE TRIGGER_SCHEMA=DATABASE();") == "19"
    assert sql("SELECT COUNT(*) FROM information_schema.ROUTINES "
               "WHERE ROUTINE_SCHEMA=DATABASE();") == "9"
    assert sql("SELECT COUNT(*) FROM information_schema.VIEWS "
               "WHERE TABLE_SCHEMA=DATABASE();") == "7"
    print(f"PASS nova baza: {CHANGESETS} changesetova", flush=True)

    sql((ROOT / "seed/01_seed.sql").read_text())
    regressions()
    before = snapshot()
    history = sql("SELECT ID, MD5SUM, EXECTYPE, DATEEXECUTED FROM DATABASECHANGELOG "
                  "ORDER BY ORDEREXECUTED;")
    update()
    assert snapshot() == before
    assert sql("SELECT ID, MD5SUM, EXECTYPE, DATEEXECUTED FROM DATABASECHANGELOG "
               "ORDER BY ORDEREXECUTED;") == history
    print("PASS ponovljeni update: podaci i evidencija nepromijenjeni", flush=True)

    # Simulacija postojece baze nakon kolegine rucne migracije:
    # aktualni trg_reservation_bu / v_ticket_stats, ali bez Liquibase evidencije;
    # starije procedure i stara tablica s podatkom koji se mora sacuvati.
    sql("DROP TABLE DATABASECHANGELOG; DROP TABLE DATABASECHANGELOGLOCK; "
        "CREATE TABLE job_error_log (id INT PRIMARY KEY, message VARCHAR(100)); "
        "INSERT INTO job_error_log VALUES (1, 'sacuvaj staru povijest'); "
        "ALTER EVENT ev_expire_reservations DISABLE;")
    old_create = procedure("create_reservation").replace("ENGINE=InnoDB", "ENGINE=MEMORY")
    old_create = old_create.replace("    ROLLBACK;\n    SET p_reservation_id", "    ROLLBACK;\n"
                                   "    DROP TEMPORARY TABLE IF EXISTS tmp_items;\n"
                                   "    DROP TEMPORARY TABLE IF EXISTS tmp_seats;\n"
                                   "    SET p_reservation_id")
    sql("DELIMITER //\n" + old_create.rstrip(";") + "//\nDELIMITER ;\n")
    sql("CREATE OR REPLACE PROCEDURE expire_reservations() "
        "INSERT INTO job_error_log VALUES (2, 'stara implementacija');")
    before = snapshot(extra=True)
    update()
    after = snapshot(extra=True)
    assert after == before, f"Prije:\n{before}\nPoslije:\n{after}"
    assert sql("SELECT COUNT(*) FROM DATABASECHANGELOG WHERE EXECTYPE='MARK_RAN';") == "11"
    assert sql("SELECT COUNT(*) FROM DATABASECHANGELOG;") == str(CHANGESETS)
    assert sql("SELECT STATUS FROM information_schema.EVENTS "
               "WHERE EVENT_SCHEMA=DATABASE() AND EVENT_NAME='ev_expire_reservations';") == "DISABLED"
    assert sql("SELECT ROUTINE_DEFINITION LIKE '%ENGINE=MEMORY%' "
               "FROM information_schema.ROUTINES WHERE ROUTINE_SCHEMA=DATABASE() "
               "AND ROUTINE_NAME='create_reservation';") == "0"
    assert sql("SELECT ROUTINE_DEFINITION LIKE '%job_error_log%' "
               "FROM information_schema.ROUTINES WHERE ROUTINE_SCHEMA=DATABASE() "
               "AND ROUTINE_NAME='expire_reservations';") == "0"
    print("PASS prijelaz postojece baze: 11 tablica preuzeto, svi podaci sacuvani", flush=True)
    regressions()

    # Nepoznata struktura mora pasti prije zamjene poslovnih objekata.
    sql("DROP TABLE DATABASECHANGELOG; DROP TABLE DATABASECHANGELOGLOCK; "
        "ALTER TABLE city ADD COLUMN unexpected_column INT NULL; "
        "CREATE OR REPLACE PROCEDURE expire_reservations() "
        "SELECT 'ne smije biti zamijenjeno';")
    before = snapshot(extra=True)
    output = update(ok=False)
    assert "precondition" in output.lower(), output
    assert sql("SELECT COUNT(*) FROM DATABASECHANGELOG;") == "0"
    assert snapshot(extra=True) == before
    assert sql("SELECT ROUTINE_DEFINITION LIKE '%ne smije biti zamijenjeno%' "
               "FROM information_schema.ROUTINES WHERE ROUTINE_SCHEMA=DATABASE() "
               "AND ROUTINE_NAME='expire_reservations';") == "1"
    print("PASS nepoznata struktura: update zaustavljen prije promjena", flush=True)
finally:
    # PROJECT je nov jedinstveni naziv; ova naredba nikad ne cilja glavni projekt.
    run("down", "-v", "--remove-orphans")
