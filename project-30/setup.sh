#!/usr/bin/env bash
# setup.sh
#
# One-shot setup for conn_storm on macOS with Homebrew PostgreSQL 18.
#
# What this script does:
#   1. Generates a self-signed TLS certificate in PGDATA
#   2. Appends TLS 1.3 settings to postgresql.conf (idempotent)
#   3. Appends pg_hba.conf rules for testuser / sire (idempotent)
#   4. Restarts the cluster via brew services
#   5. Runs setup.sql to create testuser (connect as sire via Unix socket)
#
# Run:
#   chmod +x setup.sh
#   ./setup.sh
#
# To set a different password for testuser, pass it as an env variable:
#   TESTUSER_PASS=mypassword ./setup.sh

set -euo pipefail

PGDATA="/usr/local/var/postgresql@18"
PG_SERVICE="postgresql@18"
PGUSER="sire"                          # superuser
TESTUSER_PASS="${TESTUSER_PASS:-change_me_testuser}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# ── Colour helpers ────────────────────────────────────────────────────
info()  { printf '\033[1;34m[INFO]\033[0m  %s\n' "$*"; }
ok()    { printf '\033[1;32m[ OK ]\033[0m  %s\n' "$*"; }
warn()  { printf '\033[1;33m[WARN]\033[0m  %s\n' "$*"; }
die()   { printf '\033[1;31m[ERR ]\033[0m  %s\n' "$*" >&2; exit 1; }

# ── Pre-flight checks ─────────────────────────────────────────────────
[[ -d "$PGDATA" ]] || die "PGDATA not found: $PGDATA"
command -v openssl  >/dev/null 2>&1 || die "openssl not found"
command -v psql     >/dev/null 2>&1 || die "psql not found"
command -v brew     >/dev/null 2>&1 || die "brew not found"

info "PGDATA = $PGDATA"

# ── Step 1: TLS certificate ───────────────────────────────────────────
CERT="$PGDATA/server.crt"
KEY="$PGDATA/server.key"

if [[ -f "$CERT" && -f "$KEY" ]]; then
    warn "Certificate already exists — skipping generation."
    warn "  cert: $CERT"
    warn "  key : $KEY"
else
    info "Generating self-signed TLS certificate..."
    openssl req -new -x509 -days 365 -nodes \
        -subj "/CN=localhost" \
        -keyout "$KEY" \
        -out    "$CERT"
    chmod 600 "$KEY"
    ok "Certificate generated."
fi

# ── Step 2: postgresql.conf ───────────────────────────────────────────
PG_CONF="$PGDATA/postgresql.conf"
MARKER="# BEGIN conn_storm TLS1.3"

if grep -qF "$MARKER" "$PG_CONF" 2>/dev/null; then
    warn "postgresql.conf already patched — skipping."
else
    info "Appending TLS 1.3 settings to $PG_CONF ..."
    cat >> "$PG_CONF" << EOF

$MARKER
ssl = on
ssl_cert_file = 'server.crt'
ssl_key_file  = 'server.key'
ssl_min_protocol_version = 'TLSv1.3'
ssl_max_protocol_version = 'TLSv1.3'
idle_in_transaction_session_timeout = '30s'
statement_timeout = '5s'
# END conn_storm TLS1.3
EOF
    ok "postgresql.conf updated."
fi

# ── Step 3: pg_hba.conf ───────────────────────────────────────────────
HBA_CONF="$PGDATA/pg_hba.conf"
HBA_MARKER="# BEGIN conn_storm hba"

if grep -qF "$HBA_MARKER" "$HBA_CONF" 2>/dev/null; then
    warn "pg_hba.conf already patched — skipping."
else
    info "Appending TLS-only rules to $HBA_CONF ..."
    cat >> "$HBA_CONF" << EOF

$HBA_MARKER
# testuser: allow TLS, reject plain TCP
hostssl    all   testuser   0.0.0.0/0      scram-sha-256
hostssl    all   testuser   ::/0           scram-sha-256
host       all   testuser   0.0.0.0/0      reject
host       all   testuser   ::/0           reject

# sire (superuser): allow TLS from loopback only, reject plain TCP
hostssl    all   sire       127.0.0.1/32   scram-sha-256
hostssl    all   sire       ::1/128        scram-sha-256
host       all   sire       127.0.0.1/32   reject
host       all   sire       ::1/128        reject
# END conn_storm hba
EOF
    ok "pg_hba.conf updated."
fi

# ── Step 4: restart cluster ───────────────────────────────────────────
info "Restarting $PG_SERVICE via brew services..."
brew services restart "$PG_SERVICE"
sleep 3   # give the postmaster a moment to start

# verify it came up
if ! pg_isready -h 127.0.0.1 -p 5432 -q; then
    die "PostgreSQL did not come up after restart. Check: brew services list"
fi
ok "Cluster is up."

# ── Step 5: create users ──────────────────────────────────────────────
info "Creating roles via Unix socket (no password needed for sire)..."

# Inject the testuser password into the SQL on the fly
PGPASSWORD="" psql -U "$PGUSER" -d postgres -v ON_ERROR_STOP=1 << SQL

-- sire (superuser)
DO \$\$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'sire') THEN
        CREATE ROLE sire WITH LOGIN SUPERUSER PASSWORD 'change_me_sire';
        RAISE NOTICE 'Role sire created.';
    ELSE
        RAISE NOTICE 'Role sire already exists — skipped.';
    END IF;
END
\$\$;

-- testuser
DO \$\$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'testuser') THEN
        CREATE ROLE testuser WITH LOGIN PASSWORD '$TESTUSER_PASS';
        RAISE NOTICE 'Role testuser created.';
    ELSE
        -- update password in case it changed
        ALTER ROLE testuser PASSWORD '$TESTUSER_PASS';
        RAISE NOTICE 'Role testuser already exists — password updated.';
    END IF;
END
\$\$;

GRANT CONNECT ON DATABASE postgres TO testuser;
GRANT pg_monitor TO testuser;

SELECT rolname, rolsuper, rolcanlogin
FROM pg_roles
WHERE rolname IN ('sire', 'testuser')
ORDER BY rolname;
SQL

ok "Roles ready."

# ── Step 6: smoke test ────────────────────────────────────────────────
info "Smoke test: TLS 1.3 connection as testuser..."
PGPASSWORD="$TESTUSER_PASS" psql \
    "postgresql://testuser@127.0.0.1:5432/postgres?sslmode=require&sslminprotocolversion=TLSv1.3&sslmaxprotocolversion=TLSv1.3" \
    -c "SELECT ssl, version, cipher FROM pg_stat_ssl WHERE pid = pg_backend_pid();"

ok "Done. Run the storm:"
echo ""
echo "  ./conn_storm -U testuser -W $TESTUSER_PASS -n 50 -t 30 -m idle -v"
echo ""
