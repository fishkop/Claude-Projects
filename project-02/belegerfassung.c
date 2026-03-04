/*
 * belegerfassung.c - Belegerfassungsprogramm mit PostgreSQL-Anbindung
 *
 * Verwendung:
 *   belegerfassung <Klasse> <Datum YYYY-MM-DD> <BruttoBetrag> [<Text oder /Pfad/Datei>]
 *
 * Kompilieren:
 *   make
 *
 * Voraussetzungen:
 *   - PostgreSQL-Datenbank 'myblob' mit setup.sql eingerichtet
 *   - Aktueller Unix-User als DB-User angelegt (peer-Authentifizierung)
 *   - libpq installiert (postgresql-devel / libpq-dev)
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <pwd.h>
#include <libpq-fe.h>

/* Erlaubte Dateiendungen für Bildanhänge */
static const char *ERLAUBTE_ENDUNGEN[] = {
    ".pdf", ".tiff", ".tif", ".png", ".jpeg", ".jpg", NULL
};

static void usage(const char *prog)
{
    fprintf(stderr,
        "Verwendung: %s <Klasse> <Datum> <BruttoBetrag> [<BelegText | /Pfad/Datei>]\n"
        "\n"
        "  Klasse       : Beleg-Klasse (muss in Tabelle beleg_klassen existieren)\n"
        "  Datum        : Belegdatum im Format YYYY-MM-DD\n"
        "  BruttoBetrag : Brutto-Betrag (z.B. 119.00)\n"
        "  BelegText    : Optionaler Text (ersetzt Default-Text)\n"
        "  /Pfad/Datei  : Beginnt mit '/' -> Datei wird als BLOB gespeichert\n"
        "                 Erlaubt: .pdf .tiff .tif .png .jpeg .jpg\n"
        "\n"
        "Beispiele:\n"
        "  %s Buero 2026-03-04 59.50\n"
        "  %s IT 2026-03-04 1190.00 \"Laptop Dell XPS\"\n"
        "  %s Bewirtung 2026-03-04 85.00 /home/user/belege/quittung.pdf\n",
        prog, prog, prog, prog);
    exit(EXIT_FAILURE);
}

static int endung_erlaubt(const char *pfad)
{
    const char *punkt;
    int i;

    punkt = strrchr(pfad, '.');
    if (!punkt)
        return 0;

    for (i = 0; ERLAUBTE_ENDUNGEN[i] != NULL; i++) {
        /* Vergleich ohne Groß-/Kleinschreibung */
        if (strcasecmp(punkt, ERLAUBTE_ENDUNGEN[i]) == 0)
            return 1;
    }
    return 0;
}

static unsigned char *datei_lesen(const char *pfad, size_t *laenge)
{
    FILE          *f;
    long           groesse;
    unsigned char *puffer;
    size_t         gelesen;

    f = fopen(pfad, "rb");
    if (!f) {
        fprintf(stderr, "Fehler: Datei '%s' konnte nicht geöffnet werden.\n", pfad);
        return NULL;
    }

    if (fseek(f, 0, SEEK_END) != 0) {
        fprintf(stderr, "Fehler: Dateigröße von '%s' nicht ermittelbar.\n", pfad);
        fclose(f);
        return NULL;
    }
    groesse = ftell(f);
    if (groesse <= 0) {
        fprintf(stderr, "Fehler: Datei '%s' ist leer oder Fehler beim Lesen.\n", pfad);
        fclose(f);
        return NULL;
    }
    rewind(f);

    puffer = malloc((size_t)groesse);
    if (!puffer) {
        fprintf(stderr, "Fehler: Nicht genügend Speicher für Datei '%s'.\n", pfad);
        fclose(f);
        return NULL;
    }

    gelesen = fread(puffer, 1, (size_t)groesse, f);
    fclose(f);

    if (gelesen != (size_t)groesse) {
        fprintf(stderr, "Fehler: Datei '%s' konnte nicht vollständig gelesen werden.\n", pfad);
        free(puffer);
        return NULL;
    }

    *laenge = (size_t)groesse;
    return puffer;
}

static const char *unix_username(void)
{
    const char    *name;
    struct passwd *pw;

    /* getlogin() schlägt in manchen Umgebungen fehl, daher Fallback auf getpwuid */
    name = getlogin();
    if (name)
        return name;

    pw = getpwuid(getuid());
    if (pw)
        return pw->pw_name;

    return NULL;
}

int main(int argc, char *argv[])
{
    const char    *klasse;
    const char    *datum;
    const char    *brutto;
    const char    *text_oder_pfad;
    const char    *username;
    char           connstr[512];
    PGconn        *conn;
    unsigned char *datei_puffer;
    size_t         datei_groesse;
    char          *escaped_bytea;
    int            hat_datei;
    const char    *sql;
    const char    *params[6];
    int            nparams;
    PGresult      *res;

    if (argc < 4 || argc > 5)
        usage(argv[0]);

    klasse         = argv[1];
    datum          = argv[2];
    brutto         = argv[3];
    text_oder_pfad = (argc == 5) ? argv[4] : NULL;

    /* Unix-Benutzername = Datenbankbenutzer */
    username = unix_username();
    if (!username) {
        fprintf(stderr, "Fehler: Unix-Benutzername nicht ermittelbar.\n");
        return EXIT_FAILURE;
    }

    /* Datenbankverbindung: peer-Authentifizierung über Unix-Socket */
    snprintf(connstr, sizeof(connstr), "dbname=myblob user=%s", username);

    conn = PQconnectdb(connstr);
    if (PQstatus(conn) != CONNECTION_OK) {
        fprintf(stderr, "Datenbankverbindung fehlgeschlagen: %s\n",
                PQerrorMessage(conn));
        PQfinish(conn);
        return EXIT_FAILURE;
    }

    /* --- Datei-BLOB vorbereiten -------------------------------------------- */
    datei_puffer  = NULL;
    datei_groesse = 0;
    escaped_bytea = NULL;
    hat_datei     = 0;

    if (text_oder_pfad && text_oder_pfad[0] == '/') {
        if (!endung_erlaubt(text_oder_pfad)) {
            fprintf(stderr,
                "Fehler: Dateiendung nicht erlaubt. Erlaubt: .pdf .tiff .tif .png .jpeg .jpg\n");
            PQfinish(conn);
            return EXIT_FAILURE;
        }

        datei_puffer = datei_lesen(text_oder_pfad, &datei_groesse);
        if (!datei_puffer) {
            PQfinish(conn);
            return EXIT_FAILURE;
        }

        {
        size_t escaped_len = 0;
        escaped_bytea = (char *)PQescapeByteaConn(conn,
                                                   datei_puffer,
                                                   datei_groesse,
                                                   &escaped_len);
        free(datei_puffer);
        datei_puffer = NULL;

        if (!escaped_bytea) {
            fprintf(stderr, "Fehler beim Escapen der Binärdaten: %s\n",
                    PQerrorMessage(conn));
            PQfinish(conn);
            return EXIT_FAILURE;
        }
        hat_datei = 1;
        } /* escaped_len scope */
    }

    /* --- SQL aufbauen --------------------------------------------------------
     * Der BEFORE-INSERT-Trigger berechnet mwst_betrag und netto_betrag
     * und setzt beleg_text auf den Default wenn kein Text übergeben wird.
     * RETURNING liefert die vergebene Belegnummer zurück.
     * ---------------------------------------------------------------------- */
    sql    = NULL;
    nparams = 0;

    if (hat_datei) {
        /*
         * Text mit '/' = Datei-Referenz:
         * beleg_text speichert den Pfad als Referenz,
         * bilddatei speichert den Dateiinhalt als BLOB.
         */
        sql =
            "INSERT INTO buchung "
            "  (beleg_klasse, beleg_datum, brutto_betrag, "
            "   beleg_text, erfasser_user_id, bilddatei) "
            "VALUES ($1, $2, $3, $4, $5, $6::bytea) "
            "RETURNING belegnummer, uuid_key, erfasst_am";

        params[0] = klasse;
        params[1] = datum;
        params[2] = brutto;
        params[3] = text_oder_pfad;   /* Pfad als Referenz-Text */
        params[4] = username;
        params[5] = escaped_bytea;
        nparams   = 6;

    } else if (text_oder_pfad) {
        /* Freier Beleg-Text übergeben */
        sql =
            "INSERT INTO buchung "
            "  (beleg_klasse, beleg_datum, brutto_betrag, "
            "   beleg_text, erfasser_user_id) "
            "VALUES ($1, $2, $3, $4, $5) "
            "RETURNING belegnummer, uuid_key, erfasst_am";

        params[0] = klasse;
        params[1] = datum;
        params[2] = brutto;
        params[3] = text_oder_pfad;
        params[4] = username;
        nparams   = 5;

    } else {
        /* Kein Text -> Trigger setzt Default-Text */
        sql =
            "INSERT INTO buchung "
            "  (beleg_klasse, beleg_datum, brutto_betrag, erfasser_user_id) "
            "VALUES ($1, $2, $3, $4) "
            "RETURNING belegnummer, uuid_key, erfasst_am";

        params[0] = klasse;
        params[1] = datum;
        params[2] = brutto;
        params[3] = username;
        nparams   = 4;
    }

    res = PQexecParams(conn,
                                  sql,
                                  nparams,
                                  NULL,   /* Parametertypen: Postgres leitet ab */
                                  params,
                                  NULL,   /* Parameterlängen (Text-Format) */
                                  NULL,   /* Parameterformate (Text) */
                                  0);     /* Ergebnisformat: Text */

    if (escaped_bytea) {
        PQfreemem(escaped_bytea);
        escaped_bytea = NULL;
    }

    if (PQresultStatus(res) != PGRES_TUPLES_OK) {
        fprintf(stderr, "Fehler beim Speichern: %s\n", PQerrorMessage(conn));
        PQclear(res);
        PQfinish(conn);
        return EXIT_FAILURE;
    }

    /* Erfolgsmeldung mit Belegnummer und UUID */
    printf("Beleg erfolgreich gespeichert.\n");
    printf("  Belegnummer : %s\n", PQgetvalue(res, 0, 0));
    printf("  UUID-Key    : %s\n", PQgetvalue(res, 0, 1));
    printf("  Erfasst am  : %s\n", PQgetvalue(res, 0, 2));

    PQclear(res);
    PQfinish(conn);
    return EXIT_SUCCESS;
}
