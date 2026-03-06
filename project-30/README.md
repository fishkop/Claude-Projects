# project-30 — conn_storm: PostgreSQL Connection Storm Simulator

Ein in Standard-C geschriebenes Werkzeug, das eine Verbindungslawine (Connection Storm)
gegen einen PostgreSQL-Server simuliert. Alle Verbindungen laufen ausschliesslich ueber
**TLS 1.3** — erzwungen serverseitig durch `postgresql.conf` und `pg_hba.conf`.

---

## Dateien

| Datei | Beschreibung |
|---|---|
| `conn_storm.c` | Hauptprogramm (C99, pthreads, libpq) |
| `Makefile` | Build-Skript |
| `postgresql_tls13.conf` | postgresql.conf-Ausschnitt (TLS 1.3 erzwingen) |
| `pg_hba_tls13.conf` | pg_hba.conf-Ausschnitt (nur hostssl, plain TCP ablehnen) |
| `setup.sql` | Rollen anlegen (testuser, sire) |
| `setup.sh` | Einmaliges Setup-Skript |

---

## Voraussetzungen

- PostgreSQL >= 12 (getestet mit PostgreSQL 18.3 auf macOS)
- libpq + Header (`pg_config` muss im PATH sein)
- macOS: `brew install libpq && export PATH="/usr/local/opt/libpq/bin:$PATH"`
- Debian/Ubuntu: `apt install libpq-dev`

---

## Build

```sh
make
```

Intern fuehrt das Makefile aus:

```sh
gcc -Wall -Wextra -O2 -g \
    -I$(pg_config --includedir) \
    $(pg_config --cflags) \
    -o conn_storm conn_storm.c \
    -L$(pg_config --libdir) \
    $(pg_config --libs) -lpq -lpthread
```

**Wichtig:** `pg_config --cflags` liefert kein `-I` fuer den Header-Pfad — deshalb wird
`--includedir` explizit ergaenzt. Gleiches gilt fuer `--libdir`.

---

## Serverkonfiguration (einmalig)

### postgresql.conf

```ini
ssl = on
ssl_min_protocol_version = 'TLSv1.3'
ssl_max_protocol_version = 'TLSv1.3'
```

Vollstaendiger Ausschnitt in `postgresql_tls13.conf`. Anwenden (Neustart erforderlich):

```sh
cat postgresql_tls13.conf >> /usr/local/var/postgresql@18/postgresql.conf
pg_ctl restart -D /usr/local/var/postgresql@18
```

| Parameter | Wert | Bedeutung |
|---|---|---|
| `ssl` | `on` | TLS im Server aktivieren |
| `ssl_min_protocol_version` | `'TLSv1.3'` | Aeltere Protokolle (1.0/1.1/1.2) ablehnen |
| `ssl_max_protocol_version` | `'TLSv1.3'` | Auf genau 1.3 festlegen |
| `ssl_cert_file` | `'server.crt'` | Serverzertifikat |
| `ssl_key_file` | `'server.key'` | Privater Schluessel |

### pg_hba.conf

**Wichtig:** Die testuser/sire-Regeln muessen **vor** den generischen
`host all all ... trust`-Zeilen stehen, da pg_hba.conf nach dem
First-Match-Wins-Prinzip arbeitet.

```
# testuser: nur SSL erlaubt (IPv4 + IPv6)
hostssl    all   testuser   0.0.0.0/0    scram-sha-256
hostssl    all   testuser   ::/0         scram-sha-256
host       all   testuser   0.0.0.0/0    reject
host       all   testuser   ::/0         reject

# sire (Superuser): nur SSL, nur loopback
hostssl    all   sire       127.0.0.1/32 scram-sha-256
hostssl    all   sire       ::1/128      scram-sha-256
host       all   sire       127.0.0.1/32 reject
host       all   sire       ::1/128      reject

# Erst danach: generische Regeln fuer alle anderen User
local   all   all                        trust
host    all   all   127.0.0.1/32         trust
host    all   all   ::1/128              trust
```

Warum diese Reihenfolge?

- `hostssl` greift **nur** bei SSL/TLS-Verbindungen — scram-sha-256-Authentifizierung.
- `host reject` greift bei **allen** TCP-Verbindungen (SSL und plain).
- Da `hostssl` zuerst steht, werden TLS-Verbindungen authentifiziert;
  plain-TCP-Verbindungen erreichen die `reject`-Zeile und werden abgelehnt.
- Stehen die generischen `host all all ... trust`-Regeln **vor** den
  testuser-Regeln, matchen sie zuerst — die reject-Regeln werden nie erreicht.

Reload nach Aenderung (kein Neustart noetig):

```sh
psql -U sire -d postgres -c "SELECT pg_reload_conf();"
```

---

## Verwendung

```
./conn_storm [OPTIONS]

  -h HOST     PostgreSQL-Host              (Default: 127.0.0.1)
  -p PORT     PostgreSQL-Port              (Default: 5432)
  -d DBNAME   Datenbankname               (Default: postgres)
  -U USER     Datenbankbenutzer           (Default: testuser)
  -W PASS     Passwort
  -n NUM      Anzahl gleichzeitiger Verbindungen  (Default: 50)
  -t SECS     Laufzeit in Sekunden        (Default: 30)
  -m MODE     idle | idle_in_transaction | active  (Default: idle)
  -S SSLMODE  require | verify-ca | verify-full    (Default: require)
  -v          Verbose: pro Thread eine Statuszeile
  --help      Diese Hilfe
```

### Verbindungsmodi

| Modus | Thread-Verhalten | Testzweck |
|---|---|---|
| `idle` | Verbindung offen halten, kein Query | max_connections, Speicher pro Backend |
| `idle_in_transaction` | BEGIN, nie COMMIT | Lock-Slots, Autovacuum, Session-Timeouts |
| `active` | Dauerschleife `SELECT 1` | CPU, Query-Overhead, TLS-Durchsatz |

### Beispiele

```sh
# 20 idle-Verbindungen fuer 15 Sekunden
./conn_storm -U testuser -W change_me_testuser -n 20 -t 15 -m idle -v

# 20 offene Transaktionen (idle_in_transaction)
./conn_storm -U testuser -W change_me_testuser -n 20 -t 15 -m idle_in_transaction -v

# 20 aktive Verbindungen (SELECT 1 in Dauerschleife)
./conn_storm -U testuser -W change_me_testuser -n 20 -t 15 -m active -v
```

---

## URI-Format (intern)

Jeder Thread baut folgende URI:

```
postgresql://testuser:change_me_testuser@127.0.0.1:5432/postgres
  ?connect_timeout=5
```

User und Passwort werden RFC-3986-konform percent-encodiert (Sonderzeichen
`@`, `:`, `#`, Leerzeichen usw. werden als `%XX` kodiert).

**Warum kein `sslmode=require`?**
Der Server erzwingt TLS bereits auf zwei Ebenen:
1. `ssl_min_protocol_version = 'TLSv1.3'` in postgresql.conf
2. `hostssl ... reject` in pg_hba.conf

libpq bevorzugt SSL standardmaessig (`sslmode=prefer`). Da der Server SSL
unterstuetzt, wird TLS automatisch verwendet — ein explizites `sslmode=require`
ist redundant. Ausserdem ist `sslminprotocolversion` kein gueltiger
libpq-URI-Query-Parameter und wuerde einen Verbindungsfehler verursachen.

---

## PostgreSQL-Beobachtungsqueries

Waehrend conn_storm laeuft, in einem zweiten Terminal:

### Verbindungsstatus-Uebersicht

```sql
SELECT state, count(*)
FROM pg_stat_activity
GROUP BY state
ORDER BY 2 DESC;
```

### TLS-Version aller testuser-Verbindungen

```sql
SELECT ssl, version, cipher, count(*)
FROM pg_stat_ssl
JOIN pg_stat_activity USING (pid)
WHERE usename = 'testuser'
GROUP BY ssl, version, cipher;
```

Erwartetes Ergebnis: eine Zeile mit `ssl=t`, `version=TLSv1.3`.

### Offene Transaktionen (idle_in_transaction)

```sql
SELECT pid, usename, state, now() - xact_start AS xact_age
FROM pg_stat_activity
WHERE state = 'idle in transaction'
ORDER BY xact_start;
```

### Veraltete Transaktionen beenden

```sql
SELECT pg_terminate_backend(pid)
FROM pg_stat_activity
WHERE state = 'idle in transaction'
  AND now() - xact_start > interval '5 minutes';
```

### Praevention per Rolle / Datenbank

```sql
ALTER ROLE testuser SET idle_in_transaction_session_timeout = '60s';
ALTER DATABASE postgres SET statement_timeout = '5s';
```

---

## Testergebnisse (PostgreSQL 18.3, macOS, 2026-03-06)

| Schritt | Test | Ergebnis |
|---|---|---|
| 1 | Build (`make`) | Erfolgreich, 3 harmlose Compiler-Warnungen |
| 2 | TLS 1.3 Smoke-Test (psql) | `ssl=t`, `version=TLSv1.3`, Cipher: `TLS_AES_256_GCM_SHA384` |
| 3 | Plain TCP abgelehnt | `pg_hba.conf rejects connection ... no encryption` |
| 4 | `idle` 20×15 s | 20/20 Verbindungen, alle TLSv1.3 |
| 5 | `idle_in_transaction` 20×15 s | 20/20 Verbindungen, alle TLSv1.3 |
| 6 | `active` 20×15 s | 20/20 Verbindungen, **1.570.731 SELECT-1-Queries** |

---

## Programmarchitektur

```
main()
  |
  +-- Argumente parsen
  |
  +-- N pthreads starten
  |     |
  |     +-- url_encode(user, password)    -- RFC-3986-sichere URI
  |     |
  |     +-- PQconnectdb(uri)              -- TCP + TLS-Handshake + Auth
  |     |
  |     +-- pg_stat_ssl abfragen          -- TLS-Version protokollieren
  |     |
  |     +-- je nach Modus:
  |           idle              -> sleep(1) in Schleife
  |           idle_in_transaction-> BEGIN, dann sleep(1)
  |           active            -> SELECT 1 in Dauerschleife
  |
  +-- pthread_join (alle Threads abwarten)
  |
  +-- Zusammenfassung ausgeben
```

### Wichtige libpq-Funktionen

| Funktion | Zweck |
|---|---|
| `PQconnectdb(uri)` | TCP-Verbindung oeffnen, TLS-Handshake, Authentifizierung |
| `PQstatus(conn)` | `CONNECTION_OK` oder `CONNECTION_BAD` |
| `PQbackendPID(conn)` | Backend-PID (Quervergleich mit `pg_stat_activity.pid`) |
| `PQexec(conn, sql)` | SQL synchron ausfuehren |
| `PQresultStatus(res)` | Ergebnis pruefen: `PGRES_TUPLES_OK`, `PGRES_COMMAND_OK` |
| `PQclear(res)` | Ergebnisspeicher freigeben |
| `PQerrorMessage(conn)` | Letzter Fehlertext (z.B. `FATAL: SSL error`) |
| `PQfinish(conn)` | Verbindung schliessen, Ressourcen freigeben |

---

## Exit-Codes

| Code | Bedeutung |
|---|---|
| `0` | Alle Verbindungen erfolgreich |
| `2` | Mindestens eine Verbindung fehlgeschlagen |

---

## Bekannte Hinweise

- Die drei Compiler-Warnungen (`mixing declarations and code`) kommen durch
  `-Wdeclaration-after-statement` in `pg_config --cflags` — der Code ist
  valides C99, die Warnungen sind harmlos.
- LSP-Editoren melden `libpq-fe.h not found`, da `/usr/local/opt/libpq/include`
  nicht im Standard-Include-Pfad liegt. Der Compiler findet den Header
  korrekt ueber `-I$(pg_config --includedir)`.
- `sslminprotocolversion` und `sslmaxprotocolversion` sind **keine** gueltigen
  libpq-URI-Query-Parameter und duerften nicht im URI verwendet werden.
  Die TLS-Version wird ausschliesslich serverseitig erzwungen.
