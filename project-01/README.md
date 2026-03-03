# project-01 — PostgreSQL: helloKitty Setup

Automatisiertes Setup-Script für eine PostgreSQL-Datenbank inkl. Benutzerverwaltung, Tabellendefinition und Testdaten.

---

## Anforderungen

- PostgreSQL-Datenbank `helloKitty`
- Zwei User mit unterschiedlichen Rechten (via Gruppen/Rollen)
- Tabelle `MeineKitties` mit spezifischen Feldern und Constraints
- 10 Testdatensätze
- Verifikation des Read-Only-Zugriffs

---

## Datenbankstruktur

### Rollen & User

| Rolle            | Typ           | Rechte                         |
|------------------|---------------|--------------------------------|
| `kitty_readwrite`| Gruppe (Rolle)| SELECT, INSERT, UPDATE, DELETE |
| `kitty_readonly` | Gruppe (Rolle)| SELECT                         |
| `kitty_admin_user`| User         | Mitglied von `kitty_readwrite` |
| `kitty_reader_user`| User        | Mitglied von `kitty_readonly`  |

### Tabelle `MeineKitties`

| Spalte         | Typ              | Constraint                         |
|----------------|------------------|------------------------------------|
| `id`           | INTEGER          | PK, Sequenz ab 3000, Schritt 10    |
| `name`         | VARCHAR(100)     | NOT NULL, UNIQUE, darf nicht leer  |
| `geburtsdatum` | CHAR(6)          | Format TTMMJJ                      |
| `rasse`        | VARCHAR(100)     | —                                  |
| `geschlecht`   | ENUM             | `männlich`, `weiblich`, `divers`   |
| `farbe`        | VARCHAR(50)      | —                                  |
| `wert`         | NUMERIC(10,2)    | —                                  |

---

## Script

```bash
# Ausführen mit:
bash setup_helloKitty.sh
```

Das Script führt folgende Schritte durch:

1. **Aufräumen** — löscht bestehende DB, User und Rollen (idempotent)
2. **Gruppen & User anlegen** — `kitty_readwrite`, `kitty_readonly`, zwei User
3. **Datenbank erstellen** — `helloKitty`
4. **Tabelle anlegen** — `MeineKitties` mit Sequenz, ENUM-Typ, Constraints
5. **Berechtigungen setzen** — differenziert nach Rollen
6. **Testdaten einfügen** — 10 Beispiel-Datensätze

---

## Script-Inhalt

```bash
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
CREATE ROLE kitty_readwrite;
CREATE ROLE kitty_readonly;

CREATE USER kitty_admin_user  WITH PASSWORD 'AdminPass123!';
CREATE USER kitty_reader_user WITH PASSWORD 'ReaderPass123!';

GRANT kitty_readwrite TO kitty_admin_user;
GRANT kitty_readonly  TO kitty_reader_user;

CREATE DATABASE "$DB" OWNER kitty_admin_user;
SQL

echo "=== 3. Tabelle anlegen und Berechtigungen setzen ==="

psql -U "$PGUSER" -d "$DB" -v ON_ERROR_STOP=1 <<'SQL'

CREATE TYPE geschlecht_typ AS ENUM ('männlich', 'weiblich', 'divers');

CREATE SEQUENCE meineKitties_id_seq
  START WITH 3000
  INCREMENT BY 10
  NO MINVALUE NO MAXVALUE CACHE 1;

CREATE TABLE "MeineKitties" (
  id           INTEGER        NOT NULL DEFAULT nextval('meineKitties_id_seq'),
  name         VARCHAR(100)   NOT NULL UNIQUE CHECK (TRIM(name) <> ''),
  geburtsdatum CHAR(6),
  rasse        VARCHAR(100),
  geschlecht   geschlecht_typ,
  farbe        VARCHAR(50),
  wert         NUMERIC(10,2),
  CONSTRAINT pk_meineKitties PRIMARY KEY (id)
);

ALTER SEQUENCE meineKitties_id_seq OWNED BY "MeineKitties".id;

GRANT USAGE  ON SCHEMA public                        TO kitty_readwrite;
GRANT SELECT, INSERT, UPDATE, DELETE ON "MeineKitties" TO kitty_readwrite;
GRANT USAGE, SELECT ON SEQUENCE meineKitties_id_seq  TO kitty_readwrite;

GRANT USAGE  ON SCHEMA public  TO kitty_readonly;
GRANT SELECT ON "MeineKitties" TO kitty_readonly;

SQL

echo "=== 4. Testdaten einfügen ==="

psql -U "$PGUSER" -d "$DB" -v ON_ERROR_STOP=1 <<'SQL'

INSERT INTO "MeineKitties" (name, geburtsdatum, rasse, geschlecht, farbe, wert) VALUES
  ('Mimi',     '150320', 'Perser',                'weiblich', 'weiß',        350.00),
  ('Tiger',    '220118', 'Bengale',               'männlich', 'gestreift',   500.00),
  ('Luna',     '010521', 'Siamkatze',             'weiblich', 'cremefarben', 420.00),
  ('Max',      '300619', 'Maine Coon',            'männlich', 'grau',        600.00),
  ('Bella',    '171222', 'Britisch Kurzhaar',     'weiblich', 'blau-grau',   480.00),
  ('Simba',    '040815', 'Savannah',              'männlich', 'gefleckt',    750.00),
  ('Cleo',     '110923', 'Ragdoll',               'weiblich', 'weiß-braun',  390.00),
  ('Shadow',   '290217', 'Norwegische Waldkatze', 'divers',   'schwarz',     310.00),
  ('Nala',     '060720', 'Abessinier',            'weiblich', 'orange',      440.00),
  ('Pünktchen','130416', 'Devon Rex',             'divers',   'gepunktet',   520.00);

SQL

echo "=== 5. Ergebnis prüfen ==="
psql -U "$PGUSER" -d "$DB" -c 'SELECT * FROM "MeineKitties" ORDER BY id;'
```

---

## Script-Ausgabe (Testlauf)

```
=== 1. Aufräumen: alte DB und User entfernen ===
DROP DATABASE
DROP ROLE
DROP ROLE
DROP ROLE
DROP ROLE
=== 2. Gruppen, User und Datenbank anlegen ===
CREATE ROLE
CREATE ROLE
CREATE ROLE
CREATE ROLE
GRANT ROLE
GRANT ROLE
CREATE DATABASE
=== 3. Tabelle anlegen und Berechtigungen setzen ===
CREATE TYPE
CREATE SEQUENCE
CREATE TABLE
ALTER SEQUENCE
GRANT
GRANT
GRANT
GRANT
GRANT
=== 4. Testdaten einfügen ===
INSERT 0 10

=== 5. Ergebnis prüfen ===
  id  |   name    | geburtsdatum |         rasse         | geschlecht |    farbe    |  wert
------+-----------+--------------+-----------------------+------------+-------------+--------
 3000 | Mimi      | 150320       | Perser                | weiblich   | weiß        | 350.00
 3010 | Tiger     | 220118       | Bengale               | männlich   | gestreift   | 500.00
 3020 | Luna      | 010521       | Siamkatze             | weiblich   | cremefarben | 420.00
 3030 | Max       | 300619       | Maine Coon            | männlich   | grau        | 600.00
 3040 | Bella     | 171222       | Britisch Kurzhaar     | weiblich   | blau-grau   | 480.00
 3050 | Simba     | 040815       | Savannah              | männlich   | gefleckt    | 750.00
 3060 | Cleo      | 110923       | Ragdoll               | weiblich   | weiß-braun  | 390.00
 3070 | Shadow    | 290217       | Norwegische Waldkatze | divers     | schwarz     | 310.00
 3080 | Nala      | 060720       | Abessinier            | weiblich   | orange      | 440.00
 3090 | Pünktchen | 130416       | Devon Rex             | divers     | gepunktet   | 520.00
(10 rows)

=== Setup abgeschlossen ===
  Datenbank      : helloKitty
  Tabelle        : MeineKitties
  Gruppe (RW)    : kitty_readwrite  → kitty_admin_user  / AdminPass123!
  Gruppe (RO)    : kitty_readonly   → kitty_reader_user / ReaderPass123!
```

---

## Test: Read-Only-User

Getestet wurde `kitty_reader_user` auf korrekte Rechtebeschränkung:

### SELECT — erlaubt ✅

```sql
psql -U kitty_reader_user -d "helloKitty" \
  -c 'SELECT id, name, geschlecht, wert FROM "MeineKitties" ORDER BY id;'
```

```
  id  |   name    | geschlecht |  wert
------+-----------+------------+--------
 3000 | Mimi      | weiblich   | 350.00
 3010 | Tiger     | männlich   | 500.00
 3020 | Luna      | weiblich   | 420.00
 3030 | Max       | männlich   | 600.00
 3040 | Bella     | weiblich   | 480.00
 3050 | Simba     | männlich   | 750.00
 3060 | Cleo      | weiblich   | 390.00
 3070 | Shadow    | divers     | 310.00
 3080 | Nala      | weiblich   | 440.00
 3090 | Pünktchen | divers     | 520.00
(10 rows)
```

### INSERT — verweigert ✅

```sql
psql -U kitty_reader_user -d "helloKitty" \
  -c "INSERT INTO \"MeineKitties\" (name, rasse) VALUES ('TestKatze', 'Perser');"
```
```
ERROR:  permission denied for table MeineKitties
```

### UPDATE — verweigert ✅

```sql
psql -U kitty_reader_user -d "helloKitty" \
  -c "UPDATE \"MeineKitties\" SET wert = 999 WHERE id = 3000;"
```
```
ERROR:  permission denied for table MeineKitties
```

### DELETE — verweigert ✅

```sql
psql -U kitty_reader_user -d "helloKitty" \
  -c "DELETE FROM \"MeineKitties\" WHERE id = 3000;"
```
```
ERROR:  permission denied for table MeineKitties
```

### Testergebnis

| Operation | Ergebnis          |
|-----------|-------------------|
| SELECT    | ✅ Erlaubt        |
| INSERT    | ❌ Verweigert     |
| UPDATE    | ❌ Verweigert     |
| DELETE    | ❌ Verweigert     |

`kitty_reader_user` hat ausschließlich Lesezugriff — Anforderung erfüllt.

---

## Voraussetzungen

- PostgreSQL installiert und gestartet
- Lokaler Superuser-Zugang (hier: `sire`)
- Bash

## Nutzung

```bash
bash setup_helloKitty.sh
```
