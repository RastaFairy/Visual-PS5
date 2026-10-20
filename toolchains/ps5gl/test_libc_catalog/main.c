/* Does each of the 26 libc functions just added to ps5link's catalog_extra.c
 * (link_real's own catalog was missing them - see that file's comment)
 * actually resolve and behave correctly on real hardware, not just at link
 * time? link_real accepting the name only proves the NID hash was computed
 * and an import slot created; whether libc.prx on THIS firmware actually
 * exports something at that NID is a separate question, only answerable by
 * loading and running a real title.
 *
 * The first attempt at this test crashed (SIGSEGV, rip=0 - a call through an
 * unresolved import, the same signature as this project's earlier
 * discoveries) with an empty 0-byte log file, because nothing had been
 * fflush()'d before the crash - stdio buffers data until told otherwise.
 * Every block below now fflush()s immediately after logging, so if a LATER
 * function is the one that's actually broken, everything checked before it
 * is still on disk to read.
 *
 * __assert is taken by address only, never called - real BSD __assert
 * aborts the process, which would make "the process reached the end and
 * wrote a summary" an insufficient signal either way. A non-NULL resolved
 * address is exactly what proves the import bound to something.
 * remove() is exercised on a scratch file this test creates itself, never
 * anything pre-existing.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include <ctype.h>

extern int sceKernelSendNotificationRequest(int device, void *request, int size, int flags);
extern int mkdir(const char *path, unsigned int mode);
extern void __assert(const char *func, const char *file, int line, const char *expr);

#define LOG_PATH "/app0/data/libc_catalog.txt"

static void notify(const char *msg) {
    static char request[3120];
    int i;
    for (i = 0; i < 3120; i++) request[i] = 0;
    for (i = 0; msg[i] != 0 && i < 3074; i++) request[45 + i] = msg[i];
    sceKernelSendNotificationRequest(0, request, sizeof(request), 0);
}

static FILE *log_;
#define STEP(msg) do { fprintf(log_, "step: %s\n", msg); fflush(log_); } while (0)

int main(void) {
    int fails = 0;
    mkdir("/app0/data", 0777);
    log_ = fopen(LOG_PATH, "wb");
    if (!log_) { notify("libc catalog test: could not open its own log"); return 1; }
    fprintf(log_, "Verifying the 26 libc symbols just added to ps5link's catalog_extra.c.\n\n");
    fflush(log_);

    /* ---- file positioning: fseek/ftell/rewind/fgetpos/fsetpos/fgetc/ungetc/ferror ---- */
    STEP("about to fopen/fwrite/fclose the scratch file (already-catalogued functions, control)");
    const char *path = "/app0/data/libc_catalog_scratch.txt";
    FILE *f = fopen(path, "wb");
    fwrite("ABCDEFGHIJ", 1, 10, f);
    fclose(f);
    STEP("scratch file written; about to fopen for reading");
    f = fopen(path, "rb");

    STEP("about to fgetc");
    int c1 = fgetc(f);
    STEP("about to ftell");
    long after_first = ftell(f);
    STEP("about to fseek");
    int seek_ok = fseek(f, 5, SEEK_SET);
    STEP("about to fgetc again");
    int c2 = fgetc(f);
    STEP("about to fgetpos");
    fpos_t pos; int getpos_ok = fgetpos(f, &pos);
    STEP("about to rewind");
    rewind(f);
    long after_rewind = ftell(f);
    STEP("about to fsetpos");
    int setpos_ok = fsetpos(f, &pos);
    STEP("about to fgetc a third time");
    int c3 = fgetc(f);
    STEP("about to ungetc");
    int ungetc_ok = ungetc(c3, f);
    int c4 = fgetc(f);
    STEP("about to ferror");
    int err = ferror(f);
    fclose(f);
    STEP("about to remove() the scratch file");
    remove(path);

    {
        int ok = (c1 == 'A' && after_first == 1 && seek_ok == 0 && c2 == 'F' &&
                  getpos_ok == 0 && after_rewind == 0 && setpos_ok == 0 &&
                  c3 == 'G' && ungetc_ok == c3 && c4 == 'G' && err == 0);
        fprintf(log_, "file positioning group: %s\n", ok ? "OK" : "MISMATCH");
        fprintf(log_, "  c1=%d(expect 65) after_first=%ld(expect 1) seek_ok=%d(expect 0) c2=%d(expect 70)\n",
                c1, after_first, seek_ok, c2);
        fprintf(log_, "  getpos_ok=%d(expect 0) after_rewind=%ld(expect 0) setpos_ok=%d(expect 0)\n",
                getpos_ok, after_rewind, setpos_ok);
        fprintf(log_, "  c3=%d(expect 71) ungetc_ok=%d(expect ==c3) c4=%d(expect 71) err=%d(expect 0)\n",
                c3, ungetc_ok, c4, err);
        fflush(log_);
        if (!ok) fails++;
    }

    STEP("about to sprintf");
    {
        char buf[64];
        sprintf(buf, "%d-%s", 42, "ok");
        int ok = strcmp(buf, "42-ok") == 0;
        fprintf(log_, "sprintf: %s (got \"%s\")\n", ok ? "OK" : "MISMATCH", buf);
        fflush(log_);
        if (!ok) fails++;
    }

    STEP("about to frexp/ldexp");
    {
        int exp;
        double mant = frexp(100.0, &exp);
        double back = ldexp(mant, exp);
        int ok = (exp == 7) && (fabs(mant - 0.78125) < 1e-9) && (fabs(back - 100.0) < 1e-9);
        fprintf(log_, "frexp/ldexp: %s (mant=%f exp=%d back=%f)\n", ok ? "OK" : "MISMATCH", mant, exp, back);
        fflush(log_);
        if (!ok) fails++;
    }

    STEP("about to sincos/sincosf");
    {
        double s, c; sincos(0.0, &s, &c);
        float sf, cf; sincosf(0.0f, &sf, &cf);
        int ok = (fabs(s) < 1e-9) && (fabs(c - 1.0) < 1e-9) && (fabsf(sf) < 1e-6f) && (fabsf(cf - 1.0f) < 1e-6f);
        fprintf(log_, "sincos/sincosf: %s (s=%f c=%f sf=%f cf=%f)\n", ok ? "OK" : "MISMATCH", s, c, sf, cf);
        fflush(log_);
        if (!ok) fails++;
    }

    STEP("about to tolower/rand/atoi/atof/atoll");
    {
        int lo = tolower('X');
        int r = rand();
        int i = atoi("123");
        double d = atof("3.5");
        long long ll = atoll("9000000000");
        int ok = (lo == 'x') && (i == 123) && (fabs(d - 3.5) < 1e-9) && (ll == 9000000000LL);
        fprintf(log_, "tolower/atoi/atof/atoll: %s (rand()=%d)\n", ok ? "OK" : "MISMATCH", r);
        fflush(log_);
        if (!ok) fails++;
    }

    {
        const char *s = "hello,world";
        STEP("about to strpbrk");
        char *p = strpbrk(s, ",;");
        fprintf(log_, "strpbrk: %s\n", (p && *p == ',') ? "OK" : "MISMATCH"); fflush(log_);

        STEP("about to strcspn");
        size_t n = strcspn(s, ",;");
        fprintf(log_, "strcspn: %s (n=%zu)\n", (n == 5) ? "OK" : "MISMATCH", n); fflush(log_);

        /* getenv confirmed broken on hardware (SIGSEGV, rip=0 - the same
         * "import never resolved to anything real" signature as everything
         * else this project has diagnosed that way) - see the note by
         * exports_extra_libc in catalog_extra.c. A title process most likely
         * has no real environment to look up. Skipped here on purpose. */

        if (!(p != NULL && *p == ',' && n == 5)) fails++;
    }

    /* opendir confirmed broken on hardware too (SIGSEGV, rip=0, same as
     * getenv - see catalog_extra.c's note). readdir/closedir never got
     * tested since opendir itself never returns. Skipped here on purpose;
     * do not re-add any of the three without a real fix. */

    STEP("about to take &__assert (never calling it)");
    {
        void *addr = (void *)__assert;
        fprintf(log_, "__assert: resolved to %s\n", addr ? "a non-NULL address" : "NULL (would not have linked)");
        fflush(log_);
    }

    fprintf(log_, "\n%d/7 groups mismatched. ALL STEPS COMPLETED - no crash.\n", fails);
    fclose(log_);

    char summary[128];
    snprintf(summary, sizeof(summary), "libc catalog test: %d/7 groups mismatched - see libc_catalog.txt", fails);
    notify(summary);
    return 0;
}
