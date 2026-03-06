/*
 * conn_storm.c
 *
 * PostgreSQL Connection Storm Simulator — TLS 1.3 only
 *
 * Every connection is made via a libpq URI with:
 *   sslmode=require
 *
 * TLS 1.3 is enforced server-side via ssl_min_protocol_version = 'TLSv1.3'
 * in postgresql.conf; hostssl entries in pg_hba.conf reject plain TCP.
 *
 * Build:
 *   gcc -o conn_storm conn_storm.c $(pg_config --cflags) $(pg_config --libs) -lpq -lpthread
 *   (or just: make)
 *
 * Usage:
 *   ./conn_storm [OPTIONS]
 *
 * Options:
 *   -h HOST     PostgreSQL host              (default: 127.0.0.1)
 *   -p PORT     PostgreSQL port              (default: 5432)
 *   -d DBNAME   Database name               (default: postgres)
 *   -U USER     Database user               (default: testuser)
 *   -W PASSWORD Password
 *   -n NUM      Number of connections        (default: 50)
 *   -t SECONDS  Duration of storm in seconds (default: 30)
 *   -m MODE     idle | idle_in_transaction | active  (default: idle)
 *   -S SSLMODE  require | verify-ca | verify-full    (default: require)
 *   -v          Verbose: print per-thread status
 *
 * Example:
 *   ./conn_storm -h 127.0.0.1 -p 5432 -d postgres -U testuser -W secret \
 *                -n 100 -t 60 -m idle_in_transaction -S require
 *
 * The URI sent to libpq looks like:
 *   postgresql://testuser:secret@127.0.0.1:5432/postgres
 *     ?sslmode=require
 *     &sslminprotocolversion=TLSv1.3
 *     &sslmaxprotocolversion=TLSv1.3
 *     &connect_timeout=5
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <pthread.h>
#include <time.h>
#include <signal.h>
#include <libpq-fe.h>

/* ─── Defaults ───────────────────────────────────────────────────────── */

#define DEFAULT_HOST      "127.0.0.1"
#define DEFAULT_PORT      "5432"
#define DEFAULT_DB        "postgres"
#define DEFAULT_USER      "testuser"
#define DEFAULT_PASSWORD  ""
#define DEFAULT_NUM       50
#define DEFAULT_DURATION  30
#define DEFAULT_SSLMODE   "require"

/* ─── Connection modes ───────────────────────────────────────────────── */

#define MODE_IDLE       0
#define MODE_IDLE_IN_TX 1
#define MODE_ACTIVE     2

/* ─── Per-thread state ───────────────────────────────────────────────── */

typedef struct {
    int  id;
    char host[256];
    char port[16];
    char dbname[256];
    char user[256];
    char password[256];
    char sslmode[32];
    int  mode;
    int  duration;
    int  verbose;
    /* filled by thread */
    int  connected;
    char error[512];
    int  queries_run;
    char tls_version[32];   /* reported by server after handshake */
} ThreadArg;

static volatile int g_stop = 0;
static pthread_mutex_t g_print_mutex = PTHREAD_MUTEX_INITIALIZER;

/* ─── Signal handler ─────────────────────────────────────────────────── */

static void handle_sigint(int sig) { (void)sig; g_stop = 1; }

/* ─── URL percent-encoder ────────────────────────────────────────────── */
/*
 * RFC 3986 unreserved characters are passed through unchanged.
 * Everything else (including '@', ':', '/', '?', '#', ' ', ...) is
 * percent-encoded so that passwords with special characters are safe
 * inside a postgresql:// URI.
 */
static void url_encode(const char *src, char *dst, size_t dstlen)
{
    static const char hex[] = "0123456789ABCDEF";
    size_t i = 0;
    while (*src && i + 4 < dstlen) {
        unsigned char c = (unsigned char)*src++;
        if ((c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') ||
            (c >= '0' && c <= '9') ||
            c == '-' || c == '_' || c == '.' || c == '~') {
            dst[i++] = (char)c;
        } else {
            dst[i++] = '%';
            dst[i++] = hex[c >> 4];
            dst[i++] = hex[c & 0xF];
        }
    }
    dst[i] = '\0';
}

/* ─── Worker thread ──────────────────────────────────────────────────── */

static void *worker(void *arg)
{
    ThreadArg *a = (ThreadArg *)arg;

    /* Percent-encode user and password for safe URI embedding */
    char enc_user[768], enc_pass[768];
    url_encode(a->user,     enc_user, sizeof(enc_user));
    url_encode(a->password, enc_pass, sizeof(enc_pass));

    /*
     * Build the connection URI:
     *
     *   postgresql://<user>:<password>@<host>:<port>/<dbname>
     *     ?sslmode=<sslmode>
     *     &sslminprotocolversion=TLSv1.3
     *     &sslmaxprotocolversion=TLSv1.3
     *     &connect_timeout=5
     *
     * sslminprotocolversion / sslmaxprotocolversion pin the TLS version
     * to 1.3 on the client side (libpq / OpenSSL).  The server enforces
     * the same via ssl_min_protocol_version in postgresql.conf.
     */
    char uri[2048];
    snprintf(uri, sizeof(uri),
             "postgresql://%s:%s@%s:%s/%s"
             "?connect_timeout=5",
             enc_user, enc_pass,
             a->host, a->port, a->dbname);

    PGconn *conn = PQconnectdb(uri);

    if (PQstatus(conn) != CONNECTION_OK) {
        a->connected = 0;
        /* strip trailing newline from error message */
        snprintf(a->error, sizeof(a->error), "%s", PQerrorMessage(conn));
        size_t len = strlen(a->error);
        if (len > 0 && a->error[len - 1] == '\n')
            a->error[len - 1] = '\0';
        PQfinish(conn);
        return NULL;
    }

    a->connected = 1;

    /* Record the negotiated TLS protocol version */
    PGresult *tls_res = PQexec(conn,
        "SELECT ssl, version FROM pg_stat_ssl WHERE pid = pg_backend_pid()");
    if (PQresultStatus(tls_res) == PGRES_TUPLES_OK && PQntuples(tls_res) > 0) {
        snprintf(a->tls_version, sizeof(a->tls_version),
                 "%s/%s", PQgetvalue(tls_res, 0, 0), PQgetvalue(tls_res, 0, 1));
    }
    PQclear(tls_res);

    if (a->verbose) {
        pthread_mutex_lock(&g_print_mutex);
        printf("  [thread %3d] connected  backend_pid=%-6d  tls=%s\n",
               a->id, PQbackendPID(conn), a->tls_version);
        pthread_mutex_unlock(&g_print_mutex);
    }

    /* idle_in_transaction: open a transaction and never commit */
    if (a->mode == MODE_IDLE_IN_TX) {
        PGresult *r = PQexec(conn, "BEGIN");
        PQclear(r);
    }

    time_t deadline = time(NULL) + a->duration;

    while (!g_stop) {
        if (time(NULL) >= deadline)
            break;
        if (a->mode == MODE_ACTIVE) {
            PGresult *r = PQexec(conn, "SELECT 1");
            if (PQresultStatus(r) == PGRES_TUPLES_OK)
                a->queries_run++;
            PQclear(r);
        } else {
            sleep(1);
        }
    }

    PQfinish(conn);
    return NULL;
}

/* ─── Helpers ────────────────────────────────────────────────────────── */

static void usage(const char *prog)
{
    fprintf(stderr,
        "Usage: %s [OPTIONS]\n"
        "\n"
        "  -h HOST     PostgreSQL host              (default: " DEFAULT_HOST ")\n"
        "  -p PORT     PostgreSQL port              (default: " DEFAULT_PORT ")\n"
        "  -d DBNAME   Database name               (default: " DEFAULT_DB ")\n"
        "  -U USER     Database user               (default: " DEFAULT_USER ")\n"
        "  -W PASS     Password\n"
        "  -n NUM      Number of connections        (default: %d)\n"
        "  -t SECS     Duration in seconds          (default: %d)\n"
        "  -m MODE     idle | idle_in_transaction | active  (default: idle)\n"
        "  -S SSLMODE  require | verify-ca | verify-full    (default: " DEFAULT_SSLMODE ")\n"
        "  -v          Verbose per-thread output\n"
        "  --help      Show this help\n",
        prog, DEFAULT_NUM, DEFAULT_DURATION);
}

static int parse_mode(const char *s)
{
    if (strcmp(s, "idle") == 0)               return MODE_IDLE;
    if (strcmp(s, "idle_in_transaction") == 0) return MODE_IDLE_IN_TX;
    if (strcmp(s, "active") == 0)             return MODE_ACTIVE;
    fprintf(stderr, "Unknown mode '%s'. Use: idle | idle_in_transaction | active\n", s);
    exit(1);
}

static void validate_sslmode(const char *s)
{
    if (strcmp(s, "require")     == 0) return;
    if (strcmp(s, "verify-ca")   == 0) return;
    if (strcmp(s, "verify-full") == 0) return;
    fprintf(stderr, "Unknown sslmode '%s'. Use: require | verify-ca | verify-full\n", s);
    exit(1);
}

static const char *mode_name(int m)
{
    switch (m) {
    case MODE_IDLE:       return "idle";
    case MODE_IDLE_IN_TX: return "idle_in_transaction";
    case MODE_ACTIVE:     return "active";
    default:              return "?";
    }
}

/* ─── Main ───────────────────────────────────────────────────────────── */

int main(int argc, char *argv[])
{
    char host[256]     = DEFAULT_HOST;
    char port[16]      = DEFAULT_PORT;
    char dbname[256]   = DEFAULT_DB;
    char user[256]     = DEFAULT_USER;
    char password[256] = DEFAULT_PASSWORD;
    char sslmode[32]   = DEFAULT_SSLMODE;
    int  num           = DEFAULT_NUM;
    int  duration      = DEFAULT_DURATION;
    int  mode          = MODE_IDLE;
    int  verbose       = 0;

    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "--help") == 0) { usage(argv[0]); return 0; }
        else if (strcmp(argv[i], "-h") == 0 && i+1 < argc) { strncpy(host,     argv[++i], 255); }
        else if (strcmp(argv[i], "-p") == 0 && i+1 < argc) { strncpy(port,     argv[++i],  15); }
        else if (strcmp(argv[i], "-d") == 0 && i+1 < argc) { strncpy(dbname,   argv[++i], 255); }
        else if (strcmp(argv[i], "-U") == 0 && i+1 < argc) { strncpy(user,     argv[++i], 255); }
        else if (strcmp(argv[i], "-W") == 0 && i+1 < argc) { strncpy(password, argv[++i], 255); }
        else if (strcmp(argv[i], "-n") == 0 && i+1 < argc) { num      = atoi(argv[++i]); }
        else if (strcmp(argv[i], "-t") == 0 && i+1 < argc) { duration = atoi(argv[++i]); }
        else if (strcmp(argv[i], "-m") == 0 && i+1 < argc) { mode     = parse_mode(argv[++i]); }
        else if (strcmp(argv[i], "-S") == 0 && i+1 < argc) {
            strncpy(sslmode, argv[++i], 31);
            validate_sslmode(sslmode);
        }
        else if (strcmp(argv[i], "-v") == 0) { verbose = 1; }
        else { fprintf(stderr, "Unknown option: %s\n", argv[i]); usage(argv[0]); return 1; }
    }

    if (num <= 0 || duration <= 0) {
        fprintf(stderr, "Error: -n and -t must be positive integers.\n");
        return 1;
    }

    signal(SIGINT, handle_sigint);

    pthread_t *threads = calloc((size_t)num, sizeof(pthread_t));
    ThreadArg *args    = calloc((size_t)num, sizeof(ThreadArg));
    if (!threads || !args) { perror("calloc"); return 1; }

    printf("=================================================\n");
    printf("  conn_storm  --  PostgreSQL Connection Storm\n");
    printf("=================================================\n");
    printf("  URI      : postgresql://%s:***@%s:%s/%s\n",
           user, host, port, dbname);
    printf("  TLS      : 1.3 only  (sslmode=%s)\n", sslmode);
    printf("  Threads  : %d\n", num);
    printf("  Duration : %d s\n", duration);
    printf("  Mode     : %s\n", mode_name(mode));
    printf("-------------------------------------------------\n");
    printf("  Spawning threads...\n");
    fflush(stdout);

    time_t t_start = time(NULL);

    for (int i = 0; i < num; i++) {
        ThreadArg *a = &args[i];
        a->id       = i + 1;
        a->mode     = mode;
        a->duration = duration;
        a->verbose  = verbose;
        strncpy(a->host,     host,     255);
        strncpy(a->port,     port,      15);
        strncpy(a->dbname,   dbname,   255);
        strncpy(a->user,     user,     255);
        strncpy(a->password, password, 255);
        strncpy(a->sslmode,  sslmode,   31);
        pthread_create(&threads[i], NULL, worker, a);
    }

    printf("  All %d threads launched. Waiting %d s (Ctrl-C to abort)...\n",
           num, duration);
    fflush(stdout);

    for (int i = 0; i < num; i++)
        pthread_join(threads[i], NULL);

    time_t elapsed = time(NULL) - t_start;

    int ok = 0, fail = 0, total_queries = 0;
    for (int i = 0; i < num; i++) {
        if (args[i].connected) ok++;
        else                   fail++;
        total_queries += args[i].queries_run;
    }

    /* Show TLS version from the first successful thread */
    const char *seen_tls = "n/a";
    for (int i = 0; i < num; i++) {
        if (args[i].connected && args[i].tls_version[0]) {
            seen_tls = args[i].tls_version;
            break;
        }
    }

    printf("-------------------------------------------------\n");
    printf("  Storm finished after %ld s\n", (long)elapsed);
    printf("  TLS version reported  : %s\n", seen_tls);
    printf("  Connections succeeded : %d\n", ok);
    printf("  Connections failed    : %d\n", fail);
    if (mode == MODE_ACTIVE)
        printf("  Total SELECT 1 queries: %d\n", total_queries);
    if (fail > 0) {
        printf("\n  First failure message:\n");
        for (int i = 0; i < num; i++) {
            if (!args[i].connected) {
                printf("    %s\n", args[i].error);
                break;
            }
        }
    }
    printf("=================================================\n");

    free(threads);
    free(args);
    return (fail == 0) ? 0 : 2;
}
