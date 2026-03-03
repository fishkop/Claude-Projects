#!/bin/bash
# =============================================================================
# setup_helloKitty.sh
# PostgreSQL Setup: Datenbank helloKitty, User, Tabelle MeineKitties
# =============================================================================

set -e

PGUSER="sire"
PGDB_ADMIN="postgres"
DB="helloKitty"

echo "=== 1. Aufräumen: alte DB und User entfernen ==="

psql -U "$PGUSER" -d "$PGDB_ADMIN" -v ON_ERROR_STOP=1 <<SQL
DROP DATABASE IF EXISTS "$DB";
DROP USER IF EXISTS kitty_admin_user;
DROP USER IF EXISTS kitty_reader_user;
DROP ROLE IF EXISTS kitty_readwrite;
DROP ROLE IF EXISTS kitty_readonly;
SQL

echo "=== 2. Gruppen, User und Datenbank anlegen ==="

psql -U "$PGUSER" -d "$PGDB_ADMIN" -v ON_ERROR_STOP=1 <<SQL
-- Gruppen (Rollen ohne Login)
CREATE ROLE kitty_readwrite;
CREATE ROLE kitty_readonly;

-- User mit Passwort
CREATE USER kitty_admin_user  WITH PASSWORD 'AdminPass123!';
CREATE USER kitty_reader_user WITH PASSWORD 'ReaderPass123!';

-- Rollen zuweisen
GRANT kitty_readwrite TO kitty_admin_user;
GRANT kitty_readonly  TO kitty_reader_user;

-- Datenbank anlegen
CREATE DATABASE "$DB" OWNER kitty_admin_user;
SQL

echo "=== 3. Tabelle anlegen und Berechtigungen setzen ==="

psql -U "$PGUSER" -d "$DB" -v ON_ERROR_STOP=1 <<'SQL'

-- Enum-Typ für Geschlecht
CREATE TYPE geschlecht_typ AS ENUM ('männlich', 'weiblich', 'divers');

-- Sequenz: Start 3000, Schritt 10
CREATE SEQUENCE meineKitties_id_seq
  START WITH 3000
  INCREMENT BY 10
  NO MINVALUE
  NO MAXVALUE
  CACHE 1;

-- Tabelle
CREATE TABLE "MeineKitties" (
  id           INTEGER        NOT NULL DEFAULT nextval('meineKitties_id_seq'),
  name         VARCHAR(100)   NOT NULL UNIQUE CHECK (TRIM(name) <> ''),
  geburtsdatum CHAR(6),                     -- Format TTMMJJ
  rasse        VARCHAR(100),
  geschlecht   geschlecht_typ,
  farbe        VARCHAR(50),
  wert         NUMERIC(10,2),
  CONSTRAINT pk_meineKitties PRIMARY KEY (id)
);

ALTER SEQUENCE meineKitties_id_seq OWNED BY "MeineKitties".id;

-- Berechtigungen für kitty_readwrite (Vollzugriff auf Tabelle)
GRANT USAGE  ON SCHEMA public                        TO kitty_readwrite;
GRANT SELECT, INSERT, UPDATE, DELETE
             ON "MeineKitties"                        TO kitty_readwrite;
GRANT USAGE, SELECT ON SEQUENCE meineKitties_id_seq  TO kitty_readwrite;

-- Berechtigungen für kitty_readonly (nur lesen)
GRANT USAGE  ON SCHEMA public  TO kitty_readonly;
GRANT SELECT ON "MeineKitties" TO kitty_readonly;

SQL

echo "=== 4. Testdaten einfügen ==="

psql -U "$PGUSER" -d "$DB" -v ON_ERROR_STOP=1 <<'SQL'

INSERT INTO "MeineKitties" (name, geburtsdatum, rasse, geschlecht, farbe, wert) VALUES
  ('Mimi',     '150320', 'Perser',                'weiblich', 'weiß',       350.00),
  ('Tiger',    '220118', 'Bengale',               'männlich', 'gestreift',  500.00),
  ('Luna',     '010521', 'Siamkatze',             'weiblich', 'cremefarben',420.00),
  ('Max',      '300619', 'Maine Coon',            'männlich', 'grau',       600.00),
  ('Bella',    '171222', 'Britisch Kurzhaar',     'weiblich', 'blau-grau',  480.00),
  ('Simba',    '040815', 'Savannah',              'männlich', 'gefleckt',   750.00),
  ('Cleo',     '110923', 'Ragdoll',               'weiblich', 'weiß-braun', 390.00),
  ('Shadow',   '290217', 'Norwegische Waldkatze', 'divers',   'schwarz',    310.00),
  ('Nala',     '060720', 'Abessinier',            'weiblich', 'orange',     440.00),
  ('Pünktchen','130416', 'Devon Rex',             'divers',   'gepunktet',  520.00);

SQL

echo ""
echo "=== 5. Ergebnis prüfen ==="

psql -U "$PGUSER" -d "$DB" -c 'SELECT * FROM "MeineKitties" ORDER BY id;'

echo ""
echo "=== Setup abgeschlossen ==="
echo "  Datenbank      : $DB"
echo "  Tabelle        : MeineKitties"
echo "  Gruppe (RW)    : kitty_readwrite  → kitty_admin_user  / AdminPass123!"
echo "  Gruppe (RO)    : kitty_readonly   → kitty_reader_user / ReaderPass123!"
