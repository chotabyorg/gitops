-- Run once by the database owner through an approved, audited administration
-- channel. This file intentionally never creates or prints a password.
BEGIN;

DO $create_backup_role$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'repetly_backup') THEN
    CREATE ROLE repetly_backup LOGIN;
  END IF;
END
$create_backup_role$;

ALTER ROLE repetly_backup
  NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS
  NOINHERIT LOGIN CONNECTION LIMIT 2;

-- Avoid direct privileges beyond the explicit read-only contract below.
REVOKE ALL PRIVILEGES ON DATABASE repetly FROM repetly_backup;
GRANT CONNECT ON DATABASE repetly TO repetly_backup;
-- This removes a direct role grant only. PostgreSQL commonly grants TEMPORARY
-- through PUBLIC; changing that database-wide default is outside this operation.
REVOKE TEMPORARY ON DATABASE repetly FROM repetly_backup;

REVOKE ALL PRIVILEGES ON SCHEMA public FROM repetly_backup;
GRANT USAGE ON SCHEMA public TO repetly_backup;
REVOKE CREATE ON SCHEMA public FROM repetly_backup;

REVOKE ALL PRIVILEGES ON ALL TABLES IN SCHEMA public FROM repetly_backup;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO repetly_backup;
REVOKE ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public FROM repetly_backup;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO repetly_backup;

-- The owner named here must remain the owner that creates Repetly objects.
-- If ownership changes, update this clause and rerun through the same channel.
ALTER DEFAULT PRIVILEGES FOR ROLE repetly IN SCHEMA public
  REVOKE ALL ON TABLES FROM repetly_backup;
ALTER DEFAULT PRIVILEGES FOR ROLE repetly IN SCHEMA public
  GRANT SELECT ON TABLES TO repetly_backup;
ALTER DEFAULT PRIVILEGES FOR ROLE repetly IN SCHEMA public
  REVOKE ALL ON SEQUENCES FROM repetly_backup;
ALTER DEFAULT PRIVILEGES FOR ROLE repetly IN SCHEMA public
  GRANT USAGE, SELECT ON SEQUENCES TO repetly_backup;

COMMIT;
