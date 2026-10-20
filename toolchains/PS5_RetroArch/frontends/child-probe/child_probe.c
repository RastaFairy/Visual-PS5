/* PS5 RetroArch - what Sony's local processes could do for this title's frontends.
 *
 * Copyright (C) 2026 Mihawk
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * ../PS5_Proton proved on firmware 10.01 that a title can have Sony's service
 * start a fresh executable as a child of its application
 * (sceSystemServiceAddLocalProcess, a libc-only preload mask, a socket at the
 * child's descriptor 3, sceSystemServiceKillLocalProcess to close it). This probe
 * asks what that would be worth here, with the display, the memory and the LoadExec
 * handovers this title's frontends depend on. It runs as a frontend would: started
 * by eboot.bin through LoadExec (tools/run-title.sh --relaunch-image), drawing with
 * SDL2 and ../PS5_OpenGL. Every step is a line in /app0/es-de/child-probe.jsonl,
 * written and synced as it happens, so a crash still leaves the steps before it.
 *
 * First process:
 *   1. its identity and memory, then it opens the display and draws (blue);
 *   2. a headless child (frontends/child-probe-helper, libc-only preload) while the
 *      display is held: the child's PID and the memory it sees, the parent's memory
 *      with it alive, its close through the service;
 *   3. another headless child kept alive, the display released, and a LoadExec of
 *      this probe with the child's service id.
 * Second process (--ps5-child-probe=after):
 *   4. is the child still there after the parent's LoadExec? Closed if it is;
 *   5. the display opened and drawn (red), then released, and this probe started as
 *      a child with the full default preload (--ps5-child-probe=graphics): does a
 *      child get the display and the GPU, and draw (magenta)?
 *   6. the child closed, and the display opened and drawn again (green): does the
 *      parent get it back?
 *   then back to eboot.bin.
 * With /app0/es-de/child-probe-mode.txt reading "nogpu", the first process instead
 * never touches the display or the GPU and starts the graphics child at once: whether
 * a child can have the GPU at all, when its parent never had it.
 */
#include <SDL.h>
#include <GL/glcorearb.h>
#include <errno.h>
#include <poll.h>
#include <stdarg.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <time.h>
#include <unistd.h>

int sceSystemServiceHideSplashScreen(void);
int sceSystemServiceLoadExec(const char *path, const char *const *argv);
int sceSystemServiceGetAppStatus(void *status);
int sceSystemServiceGetLocalProcessStatusList(void *entries, unsigned capacity, unsigned *count);
int sceSystemServiceAddLocalProcess(int app, const char *path, const char *const *argv, const void *options);
int sceSystemServiceKillLocalProcess(int app, int process);
int sceKernelAvailableFlexibleMemorySize(size_t *size);
size_t sceKernelGetDirectMemorySize(void);
int sceKernelAvailableDirectMemorySize(long start, long end, size_t alignment, long *found, size_t *size);
int sceKernelUsleep(unsigned microseconds);

#define SELF "/app0/es-de/child-probe.bin"
#define HELPER "/app0/es-de/child-helper.bin"
#define RESULTS "/app0/es-de/child-probe.jsonl"

/* The service's request options, as ../PS5_Proton mapped them (docs/SERVICE_SPAWN.md):
 * 72 bytes, the child's socket at 0x4, crash reports at 0x8, -1 at 0xc, the preload
 * mask at 0x18. */
struct spawn_options
{
    uint32_t size;
    int32_t fd, crash_report;
    uint32_t other[15];
};

/* frontends/child-probe-helper/helper.c's report */
struct helper_report
{
    char magic[8];
    int32_t pid, socket_type;
    uint64_t flexible_free, direct_total, direct_largest_free;
};

/* A graphics child's report: this probe in --ps5-child-probe=graphics */
struct graphics_report
{
    char magic[8]; /* "PS5GRAPH" */
    int32_t pid, opened, frames, matched, width, height;
    uint64_t flexible_free;
};

struct memory
{
    uint64_t flexible_free, direct_total, direct_largest_free;
};

static double started;

static double now(void)
{
    struct timespec t;
    clock_gettime(CLOCK_MONOTONIC, &t);
    return (double)t.tv_sec + (double)t.tv_nsec / 1e9;
}

static void record(const char *step, const char *format, ...)
{
    FILE *out = fopen(RESULTS, "a");
    if (!out)
        return;
    fprintf(out, "{\"pid\":%d,\"t\":%.2f,\"step\":\"%s\"", (int)getpid(), now() - started, step);
    if (format && *format)
    {
        va_list arguments;
        va_start(arguments, format);
        fputc(',', out);
        vfprintf(out, format, arguments);
        va_end(arguments);
    }
    fputs("}\n", out);
    fflush(out);
    fsync(fileno(out));
    fclose(out);
}

static struct memory memory_now(void)
{
    struct memory memory = {0, 0, 0};
    size_t flexible = 0, largest = 0;
    long found = 0;
    if (sceKernelAvailableFlexibleMemorySize(&flexible) == 0)
        memory.flexible_free = flexible;
    memory.direct_total = sceKernelGetDirectMemorySize();
    if (sceKernelAvailableDirectMemorySize(0, (long)memory.direct_total, 0, &found, &largest) == 0)
        memory.direct_largest_free = largest;
    return memory;
}

static int app_id(void)
{
    uint32_t status[4] = {0, 0, 0, 0};
    return sceSystemServiceGetAppStatus(status) == 0 ? (int)status[0] : -1;
}

/* The service's local processes of this application: whether id is among them. */
static int listed(int id, unsigned *count)
{
    struct
    {
        int32_t id;
        char name[32];
    } entries[16];
    memset(entries, 0, sizeof(entries));
    *count = 0;
    if (sceSystemServiceGetLocalProcessStatusList(entries, 16, count) != 0 || *count > 16)
    {
        *count = 99;
        return -1;
    }
    for (unsigned i = 0; i < *count; i++)
        if (entries[i].id == id)
            return 1;
    return 0;
}

static int ready(int fd, short events, int milliseconds)
{
    struct pollfd descriptor = {fd, events, 0};
    int result;
    do
        result = poll(&descriptor, 1, milliseconds);
    while (result < 0 && errno == EINTR);
    return result == 1 && (descriptor.revents & events);
}

/* Starts image as a local process with a socket; its service id, or a negative error. */
static int spawn(const char *image, const char *mode, uint64_t preload, int *socket_out)
{
    int pair[2] = {-1, -1};
    *socket_out = -1;
    if (socketpair(AF_UNIX, SOCK_SEQPACKET, 0, pair) != 0)
        return -2;
    struct spawn_options options;
    memset(&options, 0, sizeof(options));
    options.size = sizeof(options);
    options.fd = pair[1];
    options.crash_report = 1;
    options.other[0] = 0xffffffffu;
    options.other[3] = (uint32_t)preload;
    options.other[4] = (uint32_t)(preload >> 32);
    const char *const arguments[] = {image, mode, NULL};
    const int id = sceSystemServiceAddLocalProcess(app_id(), image, arguments, &options);
    close(pair[1]);
    if (id < 0)
    {
        close(pair[0]);
        return id;
    }
    *socket_out = pair[0];
    return id;
}

/* Closes a local process through the service and waits for it to leave the list. */
static void close_child(const char *step, int id)
{
    const int status = sceSystemServiceKillLocalProcess(app_id(), id);
    unsigned count = 0;
    int present = 1;
    for (int attempt = 0; attempt < 300 && present == 1; attempt++)
    {
        present = listed(id, &count);
        if (present == 1)
            sceKernelUsleep(10000);
    }
    record(step, "\"service_id\":%d,\"kill_status\":%d,\"present_after\":%d,\"list_count\":%u", id, status, present,
           count);
}

/* --- the display, through SDL2 and PS5_OpenGL --------------------------------- */

static SDL_Window *window;
static SDL_GLContext context;
static PFNGLCLEARCOLORPROC gl_clear_color;
static PFNGLCLEARPROC gl_clear;
static PFNGLREADPIXELSPROC gl_read_pixels;
static PFNGLVIEWPORTPROC gl_viewport;
static int drawable_width, drawable_height;

static int display_open(void)
{
    SDL_SetMainReady();
    if (SDL_Init(SDL_INIT_VIDEO | SDL_INIT_TIMER) < 0)
        return 0;
    SDL_GL_SetAttribute(SDL_GL_CONTEXT_MAJOR_VERSION, 3);
    SDL_GL_SetAttribute(SDL_GL_CONTEXT_MINOR_VERSION, 3);
    SDL_GL_SetAttribute(SDL_GL_CONTEXT_PROFILE_MASK, SDL_GL_CONTEXT_PROFILE_CORE);
    SDL_GL_SetAttribute(SDL_GL_DOUBLEBUFFER, 1);
    SDL_DisplayMode mode;
    if (SDL_GetDesktopDisplayMode(0, &mode) < 0)
        return 0;
    window = SDL_CreateWindow("PS5 RetroArch child probe", SDL_WINDOWPOS_UNDEFINED, SDL_WINDOWPOS_UNDEFINED, mode.w,
                              mode.h, SDL_WINDOW_OPENGL | SDL_WINDOW_FULLSCREEN);
    if (!window || !(context = SDL_GL_CreateContext(window)) || SDL_GL_MakeCurrent(window, context) < 0)
        return 0;
    gl_clear_color = (PFNGLCLEARCOLORPROC)SDL_GL_GetProcAddress("glClearColor");
    gl_clear = (PFNGLCLEARPROC)SDL_GL_GetProcAddress("glClear");
    gl_read_pixels = (PFNGLREADPIXELSPROC)SDL_GL_GetProcAddress("glReadPixels");
    gl_viewport = (PFNGLVIEWPORTPROC)SDL_GL_GetProcAddress("glViewport");
    if (!gl_clear_color || !gl_clear || !gl_read_pixels || !gl_viewport)
        return 0;
    SDL_GL_GetDrawableSize(window, &drawable_width, &drawable_height);
    SDL_GL_SetSwapInterval(1);
    gl_viewport(0, 0, drawable_width, drawable_height);
    return 1;
}

/* Draws frames of one colour; how many read back as that colour at the centre. */
static int display_draw(unsigned char r, unsigned char g, unsigned char b, int frames)
{
    int matched = 0;
    for (int frame = 0; frame < frames; frame++)
    {
        SDL_Event event;
        while (SDL_PollEvent(&event))
        {
        }
        gl_clear_color(r / 255.0f, g / 255.0f, b / 255.0f, 1.0f);
        gl_clear(GL_COLOR_BUFFER_BIT);
        unsigned char pixel[4] = {0, 0, 0, 0};
        gl_read_pixels(drawable_width / 2, drawable_height / 2, 1, 1, GL_RGBA, GL_UNSIGNED_BYTE, pixel);
        matched += abs(pixel[0] - r) <= 2 && abs(pixel[1] - g) <= 2 && abs(pixel[2] - b) <= 2;
        SDL_GL_SwapWindow(window);
    }
    return matched;
}

static void display_close(void)
{
    if (context)
    {
        SDL_GL_MakeCurrent(NULL, NULL);
        SDL_GL_DeleteContext(context);
        context = NULL;
    }
    if (window)
    {
        SDL_DestroyWindow(window);
        window = NULL;
    }
    SDL_Quit();
}

static void display_step(const char *step, unsigned char r, unsigned char g, unsigned char b)
{
    const double began = now();
    const int opened = display_open();
    const int matched = opened ? display_draw(r, g, b, 120) : 0;
    record(step, "\"opened\":%d,\"width\":%d,\"height\":%d,\"frames\":%d,\"matched\":%d,\"seconds\":%.2f,\"error\":\"%s\"",
           opened, drawable_width, drawable_height, opened ? 120 : 0, matched, now() - began,
           opened ? "" : SDL_GetError());
}

/* --- the three processes --------------------------------------------------------- */

static int read_helper(int socket, struct helper_report *report)
{
    memset(report, 0, sizeof(*report));
    return ready(socket, POLLIN, 8000) && recv(socket, report, sizeof(*report), 0) == (ssize_t)sizeof(*report) &&
           memcmp(report->magic, "PS5CHILD", 8) == 0;
}

static void first_process(void)
{
    const struct memory before = memory_now();
    unsigned count = 0;
    listed(-1, &count);
    record("start", "\"app\":%d,\"list_count\":%u,\"flexible_free\":%llu,\"direct_total\":%llu,\"direct_largest_free\":%llu",
           app_id(), count, (unsigned long long)before.flexible_free, (unsigned long long)before.direct_total,
           (unsigned long long)before.direct_largest_free);

    /* 1. the display, held */
    const int opened = display_open();
    const int matched = opened ? display_draw(0, 0, 255, 120) : 0;
    record("display_held", "\"opened\":%d,\"width\":%d,\"height\":%d,\"matched\":%d", opened, drawable_width,
           drawable_height, matched);

    /* 2. a headless child while the display is held */
    int socket = -1;
    const double began = now();
    int id = spawn(HELPER, "--headless", 0x8000000000000002ull, &socket);
    struct helper_report report;
    int reported = id > 0 && read_helper(socket, &report);
    struct memory with_child = memory_now();
    const int child_listed = id > 0 ? listed(id, &count) : -1;
    record("headless_child", "\"service_id\":%d,\"reported\":%d,\"seconds\":%.2f,\"child_pid\":%d,\"socket_type\":%d,"
           "\"child_flexible_free\":%llu,\"child_direct_total\":%llu,\"child_direct_largest_free\":%llu,"
           "\"parent_flexible_free\":%llu,\"parent_direct_largest_free\":%llu,\"listed\":%d,\"list_count\":%u",
           id, reported, now() - began, report.pid, report.socket_type, (unsigned long long)report.flexible_free,
           (unsigned long long)report.direct_total, (unsigned long long)report.direct_largest_free,
           (unsigned long long)with_child.flexible_free, (unsigned long long)with_child.direct_largest_free, child_listed,
           count);
    if (id > 0)
    {
        const char done = 'D';
        char answer = 0;
        const int answered = ready(socket, POLLOUT, 2000) && send(socket, &done, 1, MSG_NOSIGNAL) == 1 &&
                             ready(socket, POLLIN, 5000) && recv(socket, &answer, 1, 0) == 1 && answer == 'K';
        record("headless_child_answer", "\"answered\":%d", answered);
        close_child("headless_child_closed", id);
        close(socket);
    }

    /* 3. a child kept alive across this process's LoadExec */
    id = spawn(HELPER, "--headless", 0x8000000000000002ull, &socket);
    reported = id > 0 && read_helper(socket, &report);
    record("live_child", "\"service_id\":%d,\"reported\":%d,\"child_pid\":%d", id, reported, report.pid);
    display_close();
    char argument[48];
    snprintf(argument, sizeof(argument), "--ps5-child-probe-id=%d", id);
    const char *const arguments[] = {"--ps5-child-probe=after", argument, NULL};
    record("loadexec_with_live_child", "\"service_id\":%d", id);
    const int result = sceSystemServiceLoadExec(SELF, arguments);
    record("loadexec_returned", "\"result\":%d", result);
    for (int waited = 0; waited < 600; waited++)
        sceKernelUsleep(100000);
    record("loadexec_did_not_replace", "");
}

static void second_process(int child)
{
    /* 4. the child after the parent's LoadExec */
    unsigned count = 0;
    const int present = child > 0 ? listed(child, &count) : -1;
    const struct memory memory = memory_now();
    record("after_loadexec", "\"service_id\":%d,\"child_listed\":%d,\"list_count\":%u,\"flexible_free\":%llu", child,
           present, count, (unsigned long long)memory.flexible_free);
    if (present == 1)
        close_child("after_loadexec_child_closed", child);

    /* 5. the display, then a graphics child with it released */
    display_step("display_before_handover", 255, 0, 0);
    display_close();
    record("display_released", "");
    int socket = -1;
    const double began = now();
    const int id = spawn(SELF, "--ps5-child-probe=graphics", 0, &socket);
    record("graphics_child_spawned", "\"service_id\":%d", id);
    if (id > 0)
    {
        struct graphics_report report;
        memset(&report, 0, sizeof(report));
        const int reported = ready(socket, POLLIN, 45000) &&
                             recv(socket, &report, sizeof(report), 0) == (ssize_t)sizeof(report) &&
                             memcmp(report.magic, "PS5GRAPH", 8) == 0;
        record("graphics_child", "\"service_id\":%d,\"reported\":%d,\"seconds\":%.2f,\"child_pid\":%d,\"opened\":%d,"
               "\"frames\":%d,\"matched\":%d,\"width\":%d,\"height\":%d,\"child_flexible_free\":%llu",
               id, reported, now() - began, report.pid, report.opened, report.frames, report.matched, report.width,
               report.height, (unsigned long long)report.flexible_free);
        close_child("graphics_child_closed", id);
        close(socket);
    }

    /* 6. the display back to the parent */
    display_step("display_reacquired", 0, 255, 0);
    display_close();
    record("done", "");
    const char *const arguments[] = {"", NULL};
    sceSystemServiceLoadExec("/app0/eboot.bin", arguments);
    for (;;)
        sceKernelUsleep(100000);
}

static void nogpu_parent(void)
{
    unsigned count = 0;
    listed(-1, &count);
    record("nogpu_start", "\"app\":%d,\"list_count\":%u", app_id(), count);
    int socket = -1;
    const double began = now();
    const int id = spawn(SELF, "--ps5-child-probe=graphics", 0, &socket);
    record("nogpu_graphics_child_spawned", "\"service_id\":%d", id);
    if (id > 0)
    {
        struct graphics_report report;
        memset(&report, 0, sizeof(report));
        const int reported = ready(socket, POLLIN, 45000) &&
                             recv(socket, &report, sizeof(report), 0) == (ssize_t)sizeof(report) &&
                             memcmp(report.magic, "PS5GRAPH", 8) == 0;
        record("nogpu_graphics_child", "\"service_id\":%d,\"reported\":%d,\"seconds\":%.2f,\"child_pid\":%d,"
               "\"opened\":%d,\"frames\":%d,\"matched\":%d,\"width\":%d,\"height\":%d",
               id, reported, now() - began, report.pid, report.opened, report.frames, report.matched, report.width,
               report.height);
        close_child("nogpu_graphics_child_closed", id);
        close(socket);
    }
    record("done", "");
    const char *const arguments[] = {"", NULL};
    sceSystemServiceLoadExec("/app0/eboot.bin", arguments);
    for (;;)
        sceKernelUsleep(100000);
}

static void graphics_child(void)
{
    struct graphics_report report;
    memset(&report, 0, sizeof(report));
    memcpy(report.magic, "PS5GRAPH", 8);
    report.pid = (int32_t)getpid();
    record("graphics_child_start", "");
    report.opened = display_open();
    record("graphics_child_display", "\"opened\":%d,\"error\":\"%s\"", report.opened,
           report.opened ? "" : SDL_GetError());
    if (report.opened)
    {
        report.frames = 180;
        report.matched = display_draw(255, 0, 255, report.frames);
        report.width = drawable_width;
        report.height = drawable_height;
    }
    report.flexible_free = memory_now().flexible_free;
    display_close();
    if (ready(3, POLLOUT, 5000))
        (void)send(3, &report, sizeof(report), MSG_NOSIGNAL);
    record("graphics_child_reported", "\"matched\":%d", report.matched);
    for (;;)
        sceKernelUsleep(100000);
}

int main(int argc, char **argv)
{
    started = now();
    sceSystemServiceHideSplashScreen();
    int graphics = 0, after = 0, child = -1;
    for (int i = 0; i < argc && argv && argv[i]; i++)
    {
        if (strcmp(argv[i], "--ps5-child-probe=graphics") == 0)
            graphics = 1;
        else if (strcmp(argv[i], "--ps5-child-probe=after") == 0)
            after = 1;
        else if (strncmp(argv[i], "--ps5-child-probe-id=", 21) == 0)
            child = atoi(argv[i] + 21);
    }
    if (graphics)
        graphics_child();
    else if (after)
        second_process(child);
    else
    {
        char mode[16] = "";
        FILE *file = fopen("/app0/es-de/child-probe-mode.txt", "r");
        if (file)
        {
            if (!fgets(mode, sizeof(mode), file))
                mode[0] = '\0';
            fclose(file);
        }
        if (strncmp(mode, "nogpu", 5) == 0)
            nogpu_parent();
        else
            first_process();
    }
    return 0;
}
