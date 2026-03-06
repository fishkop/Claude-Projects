-- setup.sql
--
-- Run as superuser (sire) to prepare the database for conn_storm.
--
-- Usage:
--   psql "postgresql://sire@127.0.0.1:5432/postgres?sslmode=require" -f setup.sql
--
-- Adjust IDENTIFIED BY password as needed.

-- ── Superuser sire ────────────────────────────────────────────────────
-- If sire does not exist yet (e.g. fresh cluster), create it.
-- Skip if sire was created via initdb --username=sire.
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'sire') THEN
        CREATE ROLE sire WITH LOGIN SUPERUSER PASSWORD 'change_me_sire';
        RAISE NOTICE 'Role sire created.';
    ELSE
        RAISE NOTICE 'Role sire already exists — skipped.';
    END IF;
END
$$;

-- ── Test user ─────────────────────────────────────────────────────────
-- testuser has no superuser privileges; it only needs CONNECT on the
-- target database and LOGIN.
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'testuser') THEN
        CREATE ROLE testuser WITH LOGIN PASSWORD 'change_me_testuser';
        RAISE NOTICE 'Role testuser created.';
    ELSE
        RAISE NOTICE 'Role testuser already exists — skipped.';
    END IF;
END
$$;

-- Allow testuser to connect to the target database.
-- Change 'postgres' to whatever database you are testing against.
GRANT CONNECT ON DATABASE postgres TO testuser;

-- Optional: allow testuser to read system catalog views needed for
-- the TLS verification query in conn_storm (pg_stat_ssl).
GRANT pg_monitor TO testuser;

-- ── Verify ────────────────────────────────────────────────────────────
SELECT rolname, rolsuper, rolcanlogin
FROM pg_roles
WHERE rolname IN ('sire', 'testuser')
ORDER BY rolname;
