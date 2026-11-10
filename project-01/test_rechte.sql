-- =============================================================================
-- test_rechte.sql  -  Schulungsdemo: Rechte und Regeln ausprobieren
--
-- Aufruf:  psql -X -a -d helloKitty -f test_rechte.sql
--
-- Die Option -a zeigt jeden Befehl vor seinem Ergebnis. Fehlermeldungen sind
-- hier gewollt: sie zeigen, dass Rechte und Regeln greifen.
-- Ein Rollenwechsel mit SET ROLE braucht kein Kennwort.
-- Am Ende ist der Datenbestand unveraendert.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- Teil A: die Nur-Lese-Rolle
-- ---------------------------------------------------------------------------
SET ROLE kitty_leser;
SELECT current_user;

-- A1  Lesen: erlaubt
SELECT count(*) AS anzahl FROM "MeineKitties";

-- A2  Einfuegen: ERWARTET "permission denied"
INSERT INTO "MeineKitties" (name, geburtsdatum, geschlecht) VALUES ('Schnurri', '010120', 'weiblich');

-- A3  Aendern: ERWARTET "permission denied"
UPDATE "MeineKitties" SET wert = 1 WHERE name = 'Minka';

-- A4  Loeschen: ERWARTET "permission denied"
DELETE FROM "MeineKitties" WHERE name = 'Minka';

RESET ROLE;

-- ---------------------------------------------------------------------------
-- Teil B: die Schreib-Rolle (in einer Transaktion, die am Ende verworfen wird)
-- ---------------------------------------------------------------------------
SET ROLE kitty_app;
BEGIN;

-- B1  Einfuegen: erlaubt. Die Nummer vergibt die Datenbank selbst.
INSERT INTO "MeineKitties" (name, geburtsdatum, rasse, geschlecht, farbe, wert)
VALUES ('Schnurri', '010120', 'Hauskatze', 'weiblich', 'grau', 80.00)
RETURNING kitty_id, name;

-- B2  Aendern und Loeschen: erlaubt
UPDATE "MeineKitties" SET wert = wert + 50 WHERE name = 'Schnurri';
DELETE FROM "MeineKitties" WHERE name = 'Schnurri';

-- B3  Tabelle loeschen: ERWARTET "must be owner"
--     (danach ist die Transaktion abgebrochen; ROLLBACK raeumt auf)
DROP TABLE "MeineKitties";

ROLLBACK;

-- ---------------------------------------------------------------------------
-- Teil C: die Regeln der Tabelle (jeder Befehl fuer sich, jeder scheitert)
-- ---------------------------------------------------------------------------

-- C1  Name doppelt: ERWARTET "duplicate key value"
INSERT INTO "MeineKitties" (name, geburtsdatum, geschlecht) VALUES ('Minka', '010120', 'weiblich');

-- C2  Name fehlt: ERWARTET "null value in column"
INSERT INTO "MeineKitties" (geburtsdatum, geschlecht) VALUES ('010120', 'weiblich');

-- C3  Datum im falschen Format (JJJJ-MM-TT statt TTMMJJ): ERWARTET einen Fehler
INSERT INTO "MeineKitties" (name, geburtsdatum, geschlecht) VALUES ('Mohrle', '2020-01-01', 'weiblich');

-- C4  Datum unmoeglich (31. Februar): ERWARTET einen Fehler
INSERT INTO "MeineKitties" (name, geburtsdatum, geschlecht) VALUES ('Mohrle', '310220', 'weiblich');

-- C5  Geschlecht nicht in der Liste: ERWARTET "violates check constraint"
INSERT INTO "MeineKitties" (name, geburtsdatum, geschlecht) VALUES ('Mohrle', '010120', 'unbekannt');

-- C6  Nummer selbst vorgeben: ERWARTET "cannot insert a non-DEFAULT value"
INSERT INTO "MeineKitties" (kitty_id, name, geburtsdatum, geschlecht) VALUES (1, 'Mohrle', '010120', 'weiblich');

RESET ROLE;

-- ---------------------------------------------------------------------------
-- Kontrolle: weiterhin zehn Datensaetze, Nummern 3000 bis 3090
-- ---------------------------------------------------------------------------
SELECT count(*) AS anzahl, min(kitty_id) AS erste, max(kitty_id) AS letzte FROM "MeineKitties";
