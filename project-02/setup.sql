-- =============================================================================
-- Belegerfassungssystem - Datenbank-Setup
-- Ausführen als PostgreSQL-Superuser:
--   psql -U postgres -f setup.sql
-- =============================================================================

-- Datenbank anlegen
CREATE DATABASE myblob;

\c myblob

-- Zeitbasierte UUIDs (v1 enthält Datum + Uhrzeit)
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- =============================================================================
-- Rollen und Benutzer
-- =============================================================================

-- Gruppe für alle Belegerfasser
CREATE ROLE belegerfasser_gruppe NOLOGIN;

-- Beispiel-Benutzer 'Erfasser' (Unix-Login = DB-Login, peer-Authentifizierung)
-- Weitere Benutzer analog anlegen: CREATE ROLE "maxmuster" LOGIN IN ROLE belegerfasser_gruppe;
CREATE ROLE "Erfasser" LOGIN IN ROLE belegerfasser_gruppe;

-- =============================================================================
-- Sequence für Belegnummern (6-stellig, beginnt bei 2000)
-- =============================================================================

CREATE SEQUENCE belegnummer_seq
    START WITH 2000
    INCREMENT BY 1
    MINVALUE 2000
    MAXVALUE 999999
    NO CYCLE;

-- =============================================================================
-- Tabellen
-- =============================================================================

CREATE TABLE beleg_klassen (
    klasse       VARCHAR(50)    PRIMARY KEY,
    mwst_satz    NUMERIC(5,2)   NOT NULL
                                CHECK (mwst_satz >= 0 AND mwst_satz <= 100),
    default_text TEXT           NOT NULL
);

CREATE TABLE buchung (
    belegnummer      INT            PRIMARY KEY
                                    DEFAULT nextval('belegnummer_seq'),
    beleg_klasse     VARCHAR(50)    NOT NULL
                                    REFERENCES beleg_klassen(klasse),
    beleg_datum      DATE           NOT NULL,
    brutto_betrag    NUMERIC(12,2)  NOT NULL CHECK (brutto_betrag > 0),
    mwst_betrag      NUMERIC(12,2),
    netto_betrag     NUMERIC(12,2),
    beleg_text       TEXT,
    -- UUID v1: zeitbasiert, enthält Datum und Uhrzeit
    uuid_key         UUID           NOT NULL DEFAULT uuid_generate_v1(),
    erfasst_am       TIMESTAMPTZ    NOT NULL DEFAULT NOW(),
    erfasser_user_id TEXT           NOT NULL,
    bilddatei        BYTEA
);

-- =============================================================================
-- Trigger: MwSt und Netto berechnen, Default-Text setzen
-- Formel: MwSt = Brutto * Satz / (100 + Satz)
--         Netto = Brutto - MwSt
-- =============================================================================

CREATE OR REPLACE FUNCTION fn_calc_mwst_netto()
RETURNS TRIGGER AS $$
DECLARE
    v_mwst_satz    NUMERIC(5,2);
    v_default_text TEXT;
BEGIN
    SELECT mwst_satz, default_text
      INTO v_mwst_satz, v_default_text
      FROM beleg_klassen
     WHERE klasse = NEW.beleg_klasse;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Beleg-Klasse "%" nicht gefunden', NEW.beleg_klasse;
    END IF;

    NEW.mwst_betrag  := ROUND(NEW.brutto_betrag * v_mwst_satz / (100 + v_mwst_satz), 2);
    NEW.netto_betrag := ROUND(NEW.brutto_betrag - NEW.mwst_betrag, 2);

    IF NEW.beleg_text IS NULL OR NEW.beleg_text = '' THEN
        NEW.beleg_text := v_default_text;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_calc_mwst_netto
BEFORE INSERT OR UPDATE ON buchung
FOR EACH ROW EXECUTE FUNCTION fn_calc_mwst_netto();

-- =============================================================================
-- Materialized Views: Monat, Quartal, Jahr
-- =============================================================================

CREATE MATERIALIZED VIEW mv_buchung_monat AS
SELECT
    TO_CHAR(DATE_TRUNC('month', beleg_datum), 'YYYY-MM') AS monat,
    beleg_klasse,
    COUNT(*)              AS anzahl,
    SUM(brutto_betrag)    AS summe_brutto,
    SUM(mwst_betrag)      AS summe_mwst,
    SUM(netto_betrag)     AS summe_netto
FROM buchung
GROUP BY DATE_TRUNC('month', beleg_datum), beleg_klasse
ORDER BY DATE_TRUNC('month', beleg_datum), beleg_klasse;

-- Eindeutiger Index für CONCURRENTLY-Refresh
CREATE UNIQUE INDEX idx_mv_monat ON mv_buchung_monat (monat, beleg_klasse);


CREATE MATERIALIZED VIEW mv_buchung_quartal AS
SELECT
    TO_CHAR(DATE_TRUNC('quarter', beleg_datum), 'YYYY') || '-Q' ||
        TO_CHAR(DATE_TRUNC('quarter', beleg_datum), 'Q') AS quartal,
    beleg_klasse,
    COUNT(*)              AS anzahl,
    SUM(brutto_betrag)    AS summe_brutto,
    SUM(mwst_betrag)      AS summe_mwst,
    SUM(netto_betrag)     AS summe_netto
FROM buchung
GROUP BY DATE_TRUNC('quarter', beleg_datum), beleg_klasse
ORDER BY DATE_TRUNC('quarter', beleg_datum), beleg_klasse;

CREATE UNIQUE INDEX idx_mv_quartal ON mv_buchung_quartal (quartal, beleg_klasse);


CREATE MATERIALIZED VIEW mv_buchung_jahr AS
SELECT
    EXTRACT(YEAR FROM beleg_datum)::INT   AS jahr,
    beleg_klasse,
    COUNT(*)              AS anzahl,
    SUM(brutto_betrag)    AS summe_brutto,
    SUM(mwst_betrag)      AS summe_mwst,
    SUM(netto_betrag)     AS summe_netto
FROM buchung
GROUP BY EXTRACT(YEAR FROM beleg_datum), beleg_klasse
ORDER BY EXTRACT(YEAR FROM beleg_datum), beleg_klasse;

CREATE UNIQUE INDEX idx_mv_jahr ON mv_buchung_jahr (jahr, beleg_klasse);

-- =============================================================================
-- Trigger: Materialized Views nach INSERT/UPDATE aktualisieren
-- SECURITY DEFINER: läuft mit Rechten des Funktions-Eigentümers (Superuser),
-- damit Belegerfasser keine direkten Refresh-Rechte benötigen.
-- =============================================================================

CREATE OR REPLACE FUNCTION fn_refresh_views()
RETURNS TRIGGER AS $$
BEGIN
    REFRESH MATERIALIZED VIEW CONCURRENTLY mv_buchung_monat;
    REFRESH MATERIALIZED VIEW CONCURRENTLY mv_buchung_quartal;
    REFRESH MATERIALIZED VIEW CONCURRENTLY mv_buchung_jahr;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- FOR EACH STATEMENT: Views nur einmal pro Statement aktualisieren
CREATE TRIGGER trg_refresh_views
AFTER INSERT OR UPDATE ON buchung
FOR EACH STATEMENT EXECUTE FUNCTION fn_refresh_views();

-- =============================================================================
-- Berechtigungen
-- =============================================================================

GRANT USAGE ON SCHEMA public TO belegerfasser_gruppe;

-- Beleg-Klassen: nur lesen (benötigt für Trigger und CLI-Validierung)
GRANT SELECT ON beleg_klassen TO belegerfasser_gruppe;

-- Buchung: nur einfügen (und eigene Einträge lesen)
GRANT INSERT, SELECT ON buchung TO belegerfasser_gruppe;
GRANT USAGE, SELECT ON SEQUENCE belegnummer_seq TO belegerfasser_gruppe;

-- Materialized Views: nur lesen
GRANT SELECT ON mv_buchung_monat   TO belegerfasser_gruppe;
GRANT SELECT ON mv_buchung_quartal TO belegerfasser_gruppe;
GRANT SELECT ON mv_buchung_jahr    TO belegerfasser_gruppe;

-- =============================================================================
-- Beispieldaten Beleg-Klassen
-- =============================================================================

INSERT INTO beleg_klassen (klasse, mwst_satz, default_text) VALUES
    ('Buero',          19.00, 'Büromaterial Einkauf'),
    ('Reise',           0.00, 'Reisekostenabrechnung'),
    ('Bewirtung',      19.00, 'Bewirtungsbeleg'),
    ('IT',             19.00, 'IT-Hardware Einkauf'),
    ('Dienstleistung', 19.00, 'Externe Dienstleistung'),
    ('Porto',           0.00, 'Porto / Versandkosten');
