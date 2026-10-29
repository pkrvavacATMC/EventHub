--liquibase formatted sql

--changeset eventhub:006-buyer-keycloak dbms:mariadb
--comment: Keycloak owns authentication; buyer retains business data and an optional UUID sub.
ALTER TABLE buyer
  DROP CONSTRAINT IF EXISTS chk_buyer_password_hash,
  DROP CONSTRAINT IF EXISTS chk_buyer_failed_login_attempts,
  DROP COLUMN IF EXISTS password_hash,
  DROP COLUMN IF EXISTS email_verified_at,
  DROP COLUMN IF EXISTS failed_login_attempts,
  DROP COLUMN IF EXISTS locked_until,
  DROP COLUMN IF EXISTS is_active,
  DROP COLUMN IF EXISTS last_login_at,
  ADD COLUMN IF NOT EXISTS external_id CHAR(36) NULL,
  ADD CONSTRAINT uq_buyer_external_id UNIQUE (external_id),
  ADD CONSTRAINT chk_buyer_external_id CHECK (
    external_id IS NULL OR (
      CHAR_LENGTH(external_id) = 36
      AND external_id NOT REGEXP '[[:space:]]'
      AND external_id REGEXP BINARY '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
    )
  );

-- Back up before update; rollback also removes any Keycloak links added after update.
--rollback ALTER TABLE buyer DROP CONSTRAINT IF EXISTS chk_buyer_external_id, DROP INDEX IF EXISTS uq_buyer_external_id, DROP COLUMN IF EXISTS external_id, ADD COLUMN IF NOT EXISTS password_hash VARCHAR(255) NULL, ADD COLUMN IF NOT EXISTS email_verified_at TIMESTAMP NULL DEFAULT NULL, ADD COLUMN IF NOT EXISTS is_active BOOLEAN NOT NULL DEFAULT TRUE, ADD COLUMN IF NOT EXISTS failed_login_attempts INT NOT NULL DEFAULT 0, ADD COLUMN IF NOT EXISTS locked_until TIMESTAMP NULL DEFAULT NULL, ADD COLUMN IF NOT EXISTS last_login_at TIMESTAMP NULL DEFAULT NULL, ADD CONSTRAINT chk_buyer_password_hash CHECK (  password_hash IS NULL OR (password_hash NOT REGEXP '[[:space:]]' AND password_hash REGEXP BINARY  '^([$]2[aby][$](0[4-9]|[12][0-9]|3[01])[$][./A-Za-z0-9]{53}|[$]argon2id[$]v=19[$]m=[1-9][0-9]*,t=[1-9][0-9]*,p=[1-9][0-9]*[$][A-Za-z0-9+/]+[$][A-Za-z0-9+/]+)$')),  ADD CONSTRAINT chk_buyer_failed_login_attempts CHECK (failed_login_attempts >= 0);
