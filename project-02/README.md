# Belegerfassungsprogramm

C-Programm zur Belegerfassung mit PostgreSQL-Datenbank.
Belege werden per CLI eingegeben, MwSt und Netto werden automatisch berechnet.
Optionale Bilddateien (PDF, TIFF, PNG, JPEG) werden als BLOB in der Datenbank gespeichert.

---

## Voraussetzungen

| Komponente | Version |
|---|---|
| PostgreSQL | 17 oder 18 |
| GCC | ab 9 |
| libpq-dev | passend zur PostgreSQL-Version |

**macOS (Homebrew):**
```bash
brew install libpq
```

**Linux (Debian/Ubuntu):**
```bash
sudo apt install libpq-dev
```

---

## Datenbank einrichten

Einmalig als PostgreSQL-Superuser ausführen:

```bash
psql -U <superuser> -d postgres -f setup.sql
```

Das Skript legt an:
- Datenbank `myblob`
- Gruppe `belegerfasser_gruppe`
- Beispiel-User `Erfasser`
- Tabellen, Trigger und Materialized Views

### Weiteren Belegerfasser hinzufügen

Der Unix-Login-Name muss identisch mit dem Datenbankbenutzer sein
(PostgreSQL peer-Authentifizierung über Unix-Socket):

```sql
\c myblob
CREATE ROLE "maxmuster" LOGIN IN ROLE belegerfasser_gruppe;
```

---

## Kompilieren

```bash
make
```

Optional systemweit installieren:

```bash
sudo make install
```

---

## Verwendung

```
belegerfassung <Klasse> <Datum> <BruttoBetrag> [<BelegText | /Pfad/Datei>]
```

| Argument | Beschreibung |
|---|---|
| `Klasse` | Beleg-Klasse (muss in `beleg_klassen` existieren) |
| `Datum` | Belegdatum im Format `YYYY-MM-DD` |
| `BruttoBetrag` | Brutto-Betrag (z.B. `119.00`) |
| `BelegText` | Optional: ersetzt den Default-Text der Klasse |
| `/Pfad/Datei` | Optional: Beginnt mit `/` → Datei wird als BLOB gespeichert |

**Erlaubte Dateiendungen:** `.pdf` `.tiff` `.tif` `.png` `.jpeg` `.jpg`

### Beispiele

```bash
# Ohne Text → Default-Text aus Beleg-Klasse wird verwendet
belegerfassung Buero 2026-03-04 59.50

# Eigener Beleg-Text
belegerfassung IT 2026-03-04 1190.00 "Laptop Dell XPS"

# Mit Bilddatei als BLOB
belegerfassung Bewirtung 2026-03-04 85.00 /belege/quittung.pdf
```

### Ausgabe

```
Beleg erfolgreich gespeichert.
  Belegnummer : 2000
  UUID-Key    : 13184a5c-17bf-11f1-ae58-acde48001122
  Erfasst am  : 2026-03-04 12:41:25+01
```

---

## Datenbankstruktur

### Tabelle `beleg_klassen`

| Spalte | Typ | Beschreibung |
|---|---|---|
| `klasse` | VARCHAR(50) PK | Name der Beleg-Klasse |
| `mwst_satz` | NUMERIC(5,2) | MwSt-Satz in Prozent (z.B. `19.00`) |
| `default_text` | TEXT | Standard-Belegtext für diese Klasse |

**Vordefinierte Klassen:**

| Klasse | MwSt | Default-Text |
|---|---|---|
| Buero | 19 % | Büromaterial Einkauf |
| Reise | 0 % | Reisekostenabrechnung |
| Bewirtung | 19 % | Bewirtungsbeleg |
| IT | 19 % | IT-Hardware Einkauf |
| Dienstleistung | 19 % | Externe Dienstleistung |
| Porto | 0 % | Porto / Versandkosten |

### Tabelle `buchung`

| Spalte | Typ | Beschreibung |
|---|---|---|
| `belegnummer` | INT PK | 6-stellig, eindeutig, beginnt bei 2000 |
| `beleg_klasse` | VARCHAR(50) FK | Referenz auf `beleg_klassen` |
| `beleg_datum` | DATE | Datum des Belegs |
| `brutto_betrag` | NUMERIC(12,2) | Eingabe durch Benutzer |
| `mwst_betrag` | NUMERIC(12,2) | Berechnet durch Trigger |
| `netto_betrag` | NUMERIC(12,2) | Berechnet durch Trigger |
| `beleg_text` | TEXT | Freitext oder Default-Text |
| `uuid_key` | UUID | Zeitbasierter UUID v1 (Datum + Uhrzeit) |
| `erfasst_am` | TIMESTAMPTZ | Erfassungszeitpunkt |
| `erfasser_user_id` | TEXT | Unix-Loginname des Erfassers |
| `bilddatei` | BYTEA | Optionaler Bildanhang als BLOB |

---

## Automatische Berechnungen (Trigger)

Der `BEFORE INSERT/UPDATE`-Trigger `trg_calc_mwst_netto` berechnet:

```
MwSt  = ROUND(Brutto × Satz / (100 + Satz), 2)
Netto = ROUND(Brutto − MwSt, 2)
```

Beispiel bei 19 % MwSt und 119,00 € Brutto:
- MwSt = 119,00 × 19 / 119 = **19,00 €**
- Netto = 119,00 − 19,00 = **100,00 €**

---

## Materialized Views

Nach jedem `INSERT` oder `UPDATE` werden drei Views automatisch aktualisiert:

| View | Inhalt |
|---|---|
| `mv_buchung_monat` | Summen je Monat und Beleg-Klasse |
| `mv_buchung_quartal` | Summen je Quartal (`2026-Q1`) und Beleg-Klasse |
| `mv_buchung_jahr` | Summen je Jahr und Beleg-Klasse |

```sql
SELECT * FROM mv_buchung_monat;
SELECT * FROM mv_buchung_quartal;
SELECT * FROM mv_buchung_jahr;
```

---

## Berechtigungen

| Rolle | Rechte |
|---|---|
| `belegerfasser_gruppe` | INSERT + SELECT auf `buchung` |
| `belegerfasser_gruppe` | SELECT auf `beleg_klassen` |
| `belegerfasser_gruppe` | SELECT auf alle Materialized Views |

Die Refresh-Funktion läuft mit `SECURITY DEFINER` (Superuser-Rechte),
sodass Belegerfasser keine direkten Refresh-Rechte auf die Views benötigen.

---

## Dateistruktur

```
project-02/
├── setup.sql          # Datenbank-Setup (einmalig als Superuser ausführen)
├── belegerfassung.c   # C-Quellcode des CLI-Programms
├── Makefile           # Build-Konfiguration
└── README.md          # Diese Dokumentation
```
