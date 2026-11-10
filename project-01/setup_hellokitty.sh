#!/usr/bin/env bash
# =============================================================================
# setup_hellokitty.sh  -  Schulungsdemo PostgreSQL
#
# Legt die Datenbank "helloKitty" mit Gruppenrollen, Login-Rollen, der Tabelle
# "MeineKitties" und zehn Beispieldatensaetzen an.
#
# Aufruf:
#   ./setup_hellokitty.sh            anlegen (mehrfach ausfuehrbar)
#   ./setup_hellokitty.sh --reset    alles loeschen und neu anlegen
#   ./setup_hellokitty.sh --drop     nur aufraeumen
#
# Verbindung: Das Skript nennt weder Benutzer noch Kennwort. Es nutzt die
# Standardwege von psql (aktueller Betriebssystem-Benutzer oder die Variablen
# PGHOST, PGPORT, PGUSER). Das verwendete Konto braucht Superuser-Rechte.
# =============================================================================
set -euo pipefail

DB_NAME="${DB_NAME:-helloKitty}"
ADMIN_DB="${ADMIN_DB:-postgres}"
MODE="${1:-setup}"

run_psql() {   # $1 = Zieldatenbank, SQL kommt ueber die Standardeingabe
  PGOPTIONS="-c client_min_messages=warning" \
    psql -X -q -v ON_ERROR_STOP=1 -v db="$DB_NAME" -d "$1"
}

aufraeumen() {
  echo "=== Aufraeumen: Datenbank und Rollen entfernen ==="
  run_psql "$ADMIN_DB" <<'SQL'
DROP DATABASE IF EXISTS :"db";
DROP ROLE IF EXISTS kitty_app;
DROP ROLE IF EXISTS kitty_leser;
DROP ROLE IF EXISTS kitty_schreiben;
DROP ROLE IF EXISTS kitty_lesen;
SQL
}

case "$MODE" in
  --drop)  aufraeumen; echo "Fertig."; exit 0 ;;
  --reset) aufraeumen ;;
  setup)   ;;
  *) echo "Unbekannte Option: $MODE (erlaubt: --reset, --drop)" >&2; exit 2 ;;
esac

# -----------------------------------------------------------------------------
echo "=== 1/4 Rollen und Datenbank ==="
# Gruppenrollen (NOLOGIN) tragen die Rechte, Login-Rollen erben sie.
# Die Login-Rollen bekommen hier bewusst KEIN Kennwort (siehe README, Schritt 5).
# \gexec fuehrt das Ergebnis der Abfrage als Befehl aus: so wird nur angelegt,
# was noch fehlt.
run_psql "$ADMIN_DB" <<'SQL'
SELECT 'CREATE ROLE kitty_schreiben NOLOGIN'
 WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'kitty_schreiben') \gexec
SELECT 'CREATE ROLE kitty_lesen NOLOGIN'
 WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'kitty_lesen') \gexec
SELECT 'CREATE ROLE kitty_app LOGIN'
 WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'kitty_app') \gexec
SELECT 'CREATE ROLE kitty_leser LOGIN'
 WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'kitty_leser') \gexec

GRANT kitty_schreiben TO kitty_app;
GRANT kitty_lesen     TO kitty_leser;

SELECT format('CREATE DATABASE %I', :'db')
 WHERE NOT EXISTS (SELECT 1 FROM pg_database WHERE datname = :'db') \gexec
SQL

# -----------------------------------------------------------------------------
echo "=== 2/4 Tabelle ==="
run_psql "$DB_NAME" <<'SQL'
CREATE TABLE IF NOT EXISTS "MeineKitties" (
  -- eindeutige Nummer: beginnt bei 3000, erhoeht sich um 10
  kitty_id     integer GENERATED ALWAYS AS IDENTITY
               (START WITH 3000 INCREMENT BY 10) PRIMARY KEY,
  -- Pflichtfeld, darf nur einmal vorkommen, nicht leer
  name         text NOT NULL UNIQUE CHECK (btrim(name) <> ''),
  -- Format TTMMJJ: sechs Ziffern, die ein gueltiges Datum ergeben
  geburtsdatum char(6) NOT NULL CHECK (
                 geburtsdatum ~ '^[0-9]{6}$'
                 AND to_char(to_date(geburtsdatum, 'DDMMYY'), 'DDMMYY') = geburtsdatum),
  rasse        text,
  geschlecht   text NOT NULL CHECK (geschlecht IN ('männlich', 'weiblich', 'divers')),
  farbe        text,
  wert         numeric(10,2) CHECK (wert >= 0)
);
SQL

# -----------------------------------------------------------------------------
echo "=== 3/4 Rechte ==="
run_psql "$DB_NAME" <<'SQL'
-- Standardmaessig darf sich jede Rolle verbinden: das nehmen wir zurueck.
REVOKE ALL ON DATABASE :"db" FROM PUBLIC;
GRANT CONNECT ON DATABASE :"db" TO kitty_schreiben, kitty_lesen;
GRANT USAGE ON SCHEMA public TO kitty_schreiben, kitty_lesen;

GRANT SELECT, INSERT, UPDATE, DELETE ON "MeineKitties" TO kitty_schreiben;
GRANT SELECT                         ON "MeineKitties" TO kitty_lesen;
SQL

# -----------------------------------------------------------------------------
echo "=== 4/4 Beispieldaten ==="
run_psql "$DB_NAME" <<'SQL'
INSERT INTO "MeineKitties" (name, geburtsdatum, rasse, geschlecht, farbe, wert) VALUES
  ('Minka', '010123', 'Europäisch Kurzhaar',   'weiblich', 'schwarz',        150.00),
  ('Simba', '120822', 'Maine Coon',            'männlich', 'rot',            900.00),
  ('Luna',  '230521', 'Siam',                  'weiblich', 'creme',          700.00),
  ('Felix', '040720', 'Britisch Kurzhaar',     'männlich', 'grau',           650.00),
  ('Nala',  '151119', 'Bengal',                'weiblich', 'goldbraun',     1200.00),
  ('Oreo',  '060618', 'Ragdoll',               'divers',   'schwarz-weiß',   800.00),
  ('Kira',  '171017', 'Norwegische Waldkatze', 'weiblich', 'getigert',       500.00),
  ('Tiger', '280916', 'Sibirisch',             'männlich', 'braun',          550.00),
  ('Coco',  '090815', 'Perser',                'divers',   'weiß',           450.00),
  ('Milo',  '201214', 'Abessinier',            'männlich', 'rehbraun',       750.00)
ON CONFLICT (name) DO NOTHING;
SQL

echo
psql -X -d "$DB_NAME" -c 'SELECT kitty_id, name, geburtsdatum, geschlecht, wert FROM "MeineKitties" ORDER BY kitty_id'
echo "Fertig. Weiter mit:  psql -X -a -d $DB_NAME -f test_rechte.sql"
