# Schulungsdemo: PostgreSQL-Datenbank `helloKitty`

Eine kleine, vollständige Übung: Datenbank anlegen, Rechte über Gruppenrollen
vergeben, eine Tabelle mit Regeln bauen und anschließend ausprobieren, was
erlaubt ist und was nicht.

Dauer: etwa 30 bis 45 Minuten. Getestet mit PostgreSQL 16.

## Lernziele

Nach der Übung können die Teilnehmenden

1. Gruppenrollen und Login-Rollen unterscheiden und Rechte über Gruppen vergeben,
2. einer Rolle nur Lesezugriff geben und das nachweisen,
3. Regeln direkt in der Tabelle hinterlegen (Pflichtfeld, Eindeutigkeit, Format, Werteliste),
4. eine fortlaufende Nummer mit eigenem Startwert und eigener Schrittweite erzeugen,
5. ein Setup-Skript so schreiben, dass es mehrfach laufen kann,
6. erklären, warum Benutzernamen und Kennwörter nicht in Skripte gehören.

## Die Aufgabe

- Neue Datenbank `helloKitty`.
- Zwei Benutzer für diese Datenbank, einer davon darf nur lesen. Die Rechte
  laufen über Gruppen.
- Tabelle `MeineKitties`:

| Spalte | Regel |
|---|---|
| `kitty_id` | eindeutige Nummer, beginnt bei 3000, erhöht sich um 10 |
| `name` | Pflichtfeld, darf nur einmal vorkommen |
| `geburtsdatum` | Format TTMMJJ |
| `rasse` | freier Text |
| `geschlecht` | männlich, weiblich oder divers |
| `farbe` | freier Text |
| `wert` | Betrag, nicht negativ |

- Zehn Beispieldatensätze.

## Aufbau der Lösung

```
kitty_schreiben (Gruppe)  ──  SELECT, INSERT, UPDATE, DELETE
      └── kitty_app   (Login)

kitty_lesen (Gruppe)      ──  SELECT
      └── kitty_leser (Login)
```

Die Rechte hängen an den Gruppen. Kommt später eine weitere Person dazu, wird
sie nur in die passende Gruppe aufgenommen; an der Tabelle ändert sich nichts.

## Dateien

| Datei | Zweck |
|---|---|
| `setup_hellokitty.sh` | legt alles an; mit `--reset` neu aufbauen, mit `--drop` aufräumen |
| `test_rechte.sql` | zeigt Schritt für Schritt, was erlaubt ist und was scheitert |
| `README.md` | diese Unterlage |

## Voraussetzungen

- Ein laufender PostgreSQL-Server (Version 12 oder neuer) und `psql`.
- Ein Datenbank-Konto mit Superuser-Rechten für die Dauer der Übung.

Die Skripte nennen weder einen Benutzer noch ein Kennwort. `psql` verbindet
sich als der gerade angemeldete Betriebssystem-Benutzer. Wer ein anderes Konto
oder einen anderen Server braucht, setzt vorher die üblichen Variablen:

```bash
export PGHOST=...   PGPORT=...   PGUSER=...
```

Ein nötiges Kennwort fragt `psql` dann selbst ab, oder es steht in der
geschützten Datei `~/.pgpass`. Es wird nie auf der Kommandozeile übergeben.

## Ablauf

### Schritt 1: Anlegen

```bash
./setup_hellokitty.sh
```

Das Skript arbeitet in vier Abschnitten (Rollen und Datenbank, Tabelle, Rechte,
Beispieldaten) und zeigt am Ende die zehn Datensätze mit den Nummern 3000 bis 3090.

### Schritt 2: Noch einmal starten

```bash
./setup_hellokitty.sh
```

Es passiert nichts Schlimmes: Das Skript legt nur an, was fehlt.
**Frage an die Gruppe:** Woran liegt das? (Stichworte: `IF NOT EXISTS`,
`WHERE NOT EXISTS … \gexec`, `ON CONFLICT DO NOTHING`.)

### Schritt 3: Rechte und Regeln ausprobieren

```bash
psql -X -a -d helloKitty -f test_rechte.sql
```

Die Option `-a` zeigt jeden Befehl vor seinem Ergebnis. Die Fehlermeldungen
sind gewollt. Erwartetes Ergebnis:

| Test | Rolle | Befehl | Ergebnis |
|---|---|---|---|
| A1 | `kitty_leser` | SELECT | erlaubt |
| A2 bis A4 | `kitty_leser` | INSERT, UPDATE, DELETE | `permission denied` |
| B1, B2 | `kitty_app` | INSERT, UPDATE, DELETE | erlaubt |
| B3 | `kitty_app` | DROP TABLE | `must be owner of table` |
| C1 | `kitty_app` | Name doppelt | `duplicate key value` |
| C2 | `kitty_app` | Name fehlt | `null value in column "name"` |
| C3 | `kitty_app` | Datum als `2020-01-01` | `value too long for type character(6)` |
| C4 | `kitty_app` | Datum `310220` | `date/time field value out of range` |
| C5 | `kitty_app` | Geschlecht `unbekannt` | `violates check constraint` |
| C6 | `kitty_app` | Nummer selbst vorgeben | `cannot insert a non-DEFAULT value` |

Am Ende stehen unverändert zehn Datensätze in der Tabelle.

### Schritt 4: Beobachtung zur Nummer

In Teil B bekommt die Testkatze nicht die Nummer 3100, sondern eine höhere.
**Frage an die Gruppe:** Warum?

Auflösung: Der Zähler läuft außerhalb von Transaktionen. Jeder Versuch
verbraucht eine Nummer, auch ein abgelehnter oder zurückgerollter. Lücken sind
normal; eine fortlaufende Nummer ist eindeutig, aber nicht lückenlos.

### Schritt 5: Anmeldung der beiden Benutzer (Besprechung)

Die Login-Rollen `kitty_app` und `kitty_leser` haben absichtlich kein Kennwort.
Für die Tests reicht `SET ROLE`. Soll sich später wirklich jemand anmelden,
vergibt die Administration das Kennwort interaktiv:

```
\password kitty_leser
```

`psql` fragt das Kennwort verdeckt ab und überträgt nur dessen Hash. So landet
es weder in einem Skript noch in der Versionsverwaltung noch im
Befehlsverlauf der Shell.

### Schritt 6: Aufräumen

```bash
./setup_hellokitty.sh --drop
```

## Übungen zum Weiterarbeiten

1. Lege eine dritte Login-Rolle `kitty_gast` an, die nur lesen darf. Wie viele
   Befehle brauchst du?
2. Füge eine Spalte `chip_nr` hinzu, die eindeutig sein muss, aber leer bleiben darf.
3. Die Leser sollen die Spalte `wert` nicht sehen. Löse das mit Spaltenrechten
   oder mit einer Sicht.
4. Ändere die Regel für `geschlecht` so, dass auch `unbekannt` erlaubt ist.
   Welcher Befehl ist dafür nötig?
5. Was passiert bei `./setup_hellokitty.sh --reset`, während noch jemand mit
   der Datenbank verbunden ist?

## Hinweise für die Kursleitung

- Das Datumsformat TTMMJJ ist Teil der Aufgabe und ein guter Anlass für die
  Diskussion, warum man in der Praxis den Typ `date` nimmt.
- `REVOKE ALL ON DATABASE … FROM PUBLIC` wird oft übersehen: Ohne diese Zeile
  darf sich jede Rolle des Servers mit der Datenbank verbinden.
- Die Nummer ist als Identitätsspalte gelöst (`GENERATED ALWAYS AS IDENTITY`).
  Dafür brauchen die Schreiber kein eigenes Recht auf den Zähler.
