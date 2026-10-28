--liquibase formatted sql

-- Lozinke dolaze iz Compose secrets datoteka, nikad iz SQL-a ili Gita.
-- CREATE USER IF NOT EXISTS cuva lozinke postojecih korisnika.

--changeset eventhub:005-user-eventhub_app dbms:mariadb
--preconditions onFail:HALT onError:HALT
--precondition-sql-check expectedResult:1 SELECT COALESCE(OCTET_LENGTH(LOAD_FILE('/run/secrets/eventhub_app_password')) > 0, 0);
SET @previous_sql_mode = @@SESSION.sql_mode;
SET SESSION sql_mode = '';
SET @create_user = CONCAT('CREATE USER IF NOT EXISTS ''eventhub_app''@''%'' IDENTIFIED BY ', QUOTE(LOAD_FILE('/run/secrets/eventhub_app_password')));
PREPARE create_user_statement FROM @create_user;
EXECUTE create_user_statement;
DEALLOCATE PREPARE create_user_statement;
SET @create_user = NULL;
SET SESSION sql_mode = @previous_sql_mode;

--changeset eventhub:005-user-eventhub_report dbms:mariadb
--preconditions onFail:HALT onError:HALT
--precondition-sql-check expectedResult:1 SELECT COALESCE(OCTET_LENGTH(LOAD_FILE('/run/secrets/eventhub_report_password')) > 0, 0);
SET @previous_sql_mode = @@SESSION.sql_mode;
SET SESSION sql_mode = '';
SET @create_user = CONCAT('CREATE USER IF NOT EXISTS ''eventhub_report''@''%'' IDENTIFIED BY ', QUOTE(LOAD_FILE('/run/secrets/eventhub_report_password')));
PREPARE create_user_statement FROM @create_user;
EXECUTE create_user_statement;
DEALLOCATE PREPARE create_user_statement;
SET @create_user = NULL;
SET SESSION sql_mode = @previous_sql_mode;

