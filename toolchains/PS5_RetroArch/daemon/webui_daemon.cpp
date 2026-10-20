/* PS5 RetroArch - the WebUI daemon, /app0/webui/ps5-retroarch-webui.elf.
 *
 * Copyright (C) 2026 Mihawk
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * A payload, started through the console's ELF loader by the first program of the
 * title that finds none running (src/webui_link.cpp): it serves the WebUI
 * (src/webui_ps5.cpp) on 6769 from the title's folder for as long as the title is
 * open, whichever frontend it shows, so a frontend change (a LoadExec, which ends the
 * program it leaves) never cuts an upload or a page. The protocol is in
 * src/webui_link.h.
 *
 * It stops when no program of the title has been linked for kIdleSeconds and no
 * request is being answered: the title closed. An update the WebUI is asked to
 * install makes every linked program close the title; once none is left, this
 * installs it (ps5_update::install), the way eboot.bin did after RetroArch quit.
 * What the Game Forwarder page's tiles left for the title's close (removals and new names
 * or icons, src/ps5_forwarders.h) is done once no program of the title is linked: tried at
 * once and every few seconds while ShadowMountPlus refuses, and at the stop.
 *
 * Its own record is <title>/webui-daemon.txt (the last run's is webui-daemon.1.txt).
 * tests/test_webui_daemon.py builds it for the host, with its folder, ports and idle
 * time its own.
 */
#include "../src/webui_ps5.h"
#include "../src/webui_update.h"

#include <arpa/inet.h>
#include <cerrno>
#include <csignal>
#include <cstdarg>
#include <cstdio>
#include <cstring>
#include <ctime>
#include <fcntl.h>
#include <netinet/in.h>
#include <poll.h>
#include <pthread.h>
#include <atomic>
#include <string>
#include <sys/mount.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <unistd.h>
#include <vector>

#include "../src/webui_link.h"

#ifndef PS5_WEBUI_HOMEBREW
#define PS5_WEBUI_HOMEBREW "/data/homebrew"
#endif
#ifndef PS5_WEBUI_HTTP_PORT
#define PS5_WEBUI_HTTP_PORT 6769
#endif
#ifndef PS5_WEBUI_IDLE_SECONDS
#define PS5_WEBUI_IDLE_SECONDS 20.0
#endif

#ifdef __PROSPERO__
/* What the daemon creates in the title's folder is given 0777, as eboot.bin gives
 * everything under /app0 (src/permissions_ps5.cpp), so FTP can change it: open,
 * mkdir and fopen are wrapped at link time (tools/build-webui-daemon.sh). */
extern "C"
{
    int __real_mkdir(const char *, mode_t);
    int __real_open(const char *, int, ...);
    std::FILE *__real_fopen(const char *, const char *);

    int __wrap_mkdir(const char *path, mode_t mode)
    {
        const int result = __real_mkdir(path, mode | 0777);
        if (result == 0)
            chmod(path, 0777);
        return result;
    }
    int __wrap_open(const char *path, int flags, ...)
    {
        if ((flags & O_CREAT) == 0)
            return __real_open(path, flags);
        va_list arguments;
        va_start(arguments, flags);
        const int mode = va_arg(arguments, int);
        va_end(arguments);
        const int fd = __real_open(path, flags, mode | 0777);
        if (fd >= 0)
            fchmod(fd, 0777);
        return fd;
    }
    std::FILE *__wrap_fopen(const char *path, const char *mode)
    {
        std::FILE *const file = __real_fopen(path, mode);
        if (file && mode && std::strpbrk(mode, "wa+"))
            fchmod(fileno(file), 0777);
        return file;
    }
}
#endif

namespace
{
constexpr double kIdleSeconds = PS5_WEBUI_IDLE_SECONDS; /* no program linked: closed */
constexpr double kInstallSeconds = 5.0;                 /* no program linked, an install asked */
constexpr double kNoHelloSeconds = 30.0;                /* started, and no program ever linked */

struct Link
{
    int fd;
    std::string pending, frontend;
    bool hello = false;
};

std::string root, title, version, log_path;
std::vector<std::string> early_lines;

double now_s()
{
    timespec now{};
    clock_gettime(CLOCK_MONOTONIC, &now);
    return double(now.tv_sec) + double(now.tv_nsec) / 1e9;
}

void say(const char *format, ...)
{
    char line[512];
    va_list arguments;
    va_start(arguments, format);
    std::vsnprintf(line, sizeof line, format, arguments);
    va_end(arguments);
    std::fprintf(stderr, "[webui-daemon] %s\n", line);
    if (log_path.empty())
    {
        early_lines.emplace_back(line);
        return;
    }
    if (std::FILE *file = std::fopen(log_path.c_str(), "a"))
    {
        std::time_t t = std::time(nullptr);
        char stamp[32];
        std::strftime(stamp, sizeof stamp, "%Y-%m-%d %H:%M:%S", std::gmtime(&t));
        /* The process: a stale daemon still finishing writes to the same file. */
        std::fprintf(file, "%s [%d] %s\n", stamp, int(getpid()), line);
        std::fclose(file);
    }
}

std::string read_small(const std::string &path)
{
    std::string out;
    if (std::FILE *file = std::fopen(path.c_str(), "rb"))
    {
        char buffer[4096];
        size_t got;
        while ((got = std::fread(buffer, 1, sizeof buffer, file)) > 0 && out.size() < 65536)
            out.append(buffer, got);
        std::fclose(file);
    }
    return out;
}

bool is_file(const std::string &path)
{
    struct stat st{};
    return stat(path.c_str(), &st) == 0 && S_ISREG(st.st_mode);
}

bool valid_id(const std::string &id)
{
    if (id.size() != 9)
        return false;
    for (char c : id)
        if (!((c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9')))
            return false;
    return true;
}

/* The title's folder: what is mounted as its application folder
 * (/data/homebrew/PPSA99169 -> /system_ex/app/PPSA99169, docs/FINDINGS.md), else
 * the usual place; either only when it holds this title's eboot.bin and WebUI. */
std::string title_folder(const std::string &id)
{
    std::vector<std::string> candidates;
#ifdef __PROSPERO__
    struct statfs *mounts = nullptr;
    const int count = getmntinfo(&mounts, MNT_NOWAIT);
    const std::string app = "/system_ex/app/" + id;
    for (int i = 0; i < count; ++i)
        if (app == mounts[i].f_mntonname && mounts[i].f_mntfromname[0] == '/')
            candidates.emplace_back(mounts[i].f_mntfromname);
#endif
    candidates.push_back(PS5_WEBUI_HOMEBREW "/" + id);
    for (const auto &folder : candidates)
        if (is_file(folder + "/eboot.bin") && is_file(folder + "/webui/index.html") &&
            read_small(folder + "/sce_sys/param.json").find(id) != std::string::npos)
            return folder;
    return "";
}

bool send_line(int fd, const char *line)
{
    const size_t size = std::strlen(line);
    return send(fd, line, size, 0) == ssize_t(size);
}

int listen_local(unsigned short port)
{
    const int fd = socket(AF_INET, SOCK_STREAM, 0);
    if (fd < 0)
        return -1;
    int yes = 1;
    setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &yes, sizeof yes);
    sockaddr_in address{};
    address.sin_family = AF_INET;
    address.sin_port = htons(port);
    address.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    if (bind(fd, reinterpret_cast<sockaddr *>(&address), sizeof address) != 0 || listen(fd, 8) != 0)
    {
        close(fd);
        return -1;
    }
    return fd;
}

void show_frontend(const std::vector<Link> &links)
{
    const char *shown = "";
    for (const auto &link : links)
        if (link.hello)
            shown = link.frontend.c_str();
    ps5_webui_set_frontend(shown);
}
} // namespace

int main()
{
    std::signal(SIGPIPE, SIG_IGN);
    int listener = listen_local(PS5_WEBUI_LINK_PORT);
    if (listener < 0)
    {
        std::fprintf(stderr, "[webui-daemon] another daemon has %d; this one stops\n",
                     PS5_WEBUI_LINK_PORT);
        return 0;
    }
    ps5_webui_set_frontend("");
    std::vector<Link> links;
    bool serving = false, stale = false, install_sent = false, installed = false, closed = false;
    bool tiles_done = false;
    const double started = now_s();
    double idle_since = started, installed_at = 0, last_serve_try = 0, last_tiles = 0;
    unsigned serve_failures = 0;
    /* The WebUI starts on a thread of its own (reading the library and the saved scraping
     * jobs takes seconds): the title's hello is answered meanwhile. 0 idle, 1 starting,
     * 2 serving, 3 failed. */
    static std::atomic<int> start_state{0};
    static std::string start_folder;
    pthread_t starter{};
    bool starter_running = false;
    say("started; listening for the title on 127.0.0.1:%d", PS5_WEBUI_LINK_PORT);

    for (;;)
    {
        std::vector<pollfd> waits;
        if (listener >= 0)
            waits.push_back({listener, POLLIN, 0});
        for (const auto &link : links)
            waits.push_back({link.fd, POLLIN, 0});
        poll(waits.data(), waits.size(), 250);

        if (listener >= 0 && (waits[0].revents & POLLIN))
        {
            const int fd = accept(listener, nullptr, nullptr);
            if (fd >= 0 && links.size() < 16)
                links.push_back({fd, "", "", false});
            else if (fd >= 0)
                close(fd);
        }
        for (auto &link : links)
        {
            pollfd wait{link.fd, POLLIN, 0};
            if (poll(&wait, 1, 0) <= 0)
                continue;
            char buffer[512];
            const ssize_t got = recv(link.fd, buffer, sizeof buffer, 0);
            if (got <= 0 || link.pending.size() > 4096)
            {
                close(link.fd);
                link.fd = -1;
                continue;
            }
            link.pending.append(buffer, size_t(got));
            size_t end;
            while (link.fd >= 0 && (end = link.pending.find('\n')) != std::string::npos)
            {
                const std::string line = link.pending.substr(0, end);
                link.pending.erase(0, end + 1);
                char word[16] = {}, frontend[32] = {}, id[16] = {};
                const int fields = std::sscanf(line.c_str(), "%15s %31s %15s", word, frontend, id);
                if (fields == 3 && std::strcmp(word, "hello") == 0)
                {
                    const char *reply = "ok\n";
                    if (stale)
                        reply = "stale\n";
                    else if (root.empty())
                    {
                        const std::string folder = valid_id(id) ? title_folder(id) : "";
                        if (folder.empty())
                        {
                            say("hello from %s of %s: no folder of that title found", frontend, id);
                            reply = "unknown\n";
                        }
                        else
                        {
                            root = folder;
                            title = id;
                            version = read_small(root + "/webui/version.json");
                            log_path = root + "/webui-daemon.txt";
                            rename(log_path.c_str(), (root + "/webui-daemon.1.txt").c_str());
                            for (const auto &early : early_lines)
                                say("%s", early.c_str());
                            early_lines.clear();
                            say("the title is %s, in %s", title.c_str(), root.c_str());
                        }
                    }
                    else if (title != id)
                        reply = "other\n";
                    else if (read_small(root + "/webui/version.json") != version)
                    {
                        say("hello from another build of the title: this daemon stops once "
                            "its requests end");
                        stale = true;
                        reply = "stale\n";
                    }
                    send_line(link.fd, reply);
                    if (std::strcmp(reply, "ok\n") == 0)
                    {
                        link.hello = true;
                        link.frontend = frontend;
                        say("linked: %s (%zu linked)", frontend, links.size());
                        if (install_sent)
                            send_line(link.fd, "install\n");
                    }
                    else
                    {
                        close(link.fd);
                        link.fd = -1;
                    }
                }
                else if (fields >= 2 && std::strcmp(word, "frontend") == 0 && link.hello)
                {
                    link.frontend = frontend;
                    say("frontend: %s", frontend);
                }
            }
        }
        for (auto it = links.begin(); it != links.end();)
            if (it->fd < 0)
            {
                if (it->hello)
                    say("unlinked: %s", it->frontend.c_str());
                it = links.erase(it);
            }
            else
                ++it;
        show_frontend(links);

        const double now = now_s();
        bool linked = false;
        for (const auto &link : links)
            linked |= link.hello;
        if (linked)
            idle_since = 0;
        else if (idle_since == 0)
            idle_since = now;
        /* What a Game Forwarder tile waits for (a removal, a new name or picture, which
         * ShadowMountPlus refuses while a game runs): tried once no program of the title is
         * linked, and every few seconds after, not only at the stop kIdleSeconds later */
        if (linked)
            tiles_done = false; /* the page can leave more while the title runs */
        else if (serving && !tiles_done && now - last_tiles >= 3.0)
        {
            last_tiles = now;
            tiles_done = ps5_webui_finish_forwarders([](const char *line) { say("%s", line); });
        }

        if (start_state == 2 || start_state == 3)
        {
            if (starter_running)
                pthread_join(starter, nullptr);
            starter_running = false;
            serving = start_state == 2;
            start_state = 0;
            if (serving)
                say("serving the WebUI on %d from %s (%u s busy before)", PS5_WEBUI_HTTP_PORT,
                    root.c_str(), serve_failures);
            else if (serve_failures++ == 0)
                say("%d is busy (another daemon's last transfer?); trying every second",
                    PS5_WEBUI_HTTP_PORT);
        }
        if (!serving && start_state == 0 && !root.empty() && !stale && now - last_serve_try >= 1.0)
        {
            last_serve_try = now;
            start_state = 1;
            start_folder = root;
            /* A payload's default thread stack is small; the library scan needs more. */
            pthread_attr_t attributes;
            pthread_attr_init(&attributes);
            pthread_attr_setstacksize(&attributes, 4u << 20);
            starter_running =
                pthread_create(
                    &starter, &attributes,
                    [](void *) -> void *
                    {
#ifdef PS5_WEBUI_TEST_START_DELAY_MS /* the tests: a start as slow as a big library's */
                        usleep(PS5_WEBUI_TEST_START_DELAY_MS * 1000);
#endif
                        start_state =
                            ps5_webui_start(start_folder.c_str(), PS5_WEBUI_HTTP_PORT, false) ? 2
                                                                                              : 3;
                        return nullptr;
                    },
                    nullptr) == 0;
            pthread_attr_destroy(&attributes);
            if (!starter_running)
                start_state = 3;
        }
        if (serving && !install_sent && ps5_update::exit_requested())
        {
            install_sent = true;
            say("install requested: asking %zu linked program(s) to close the title", links.size());
            for (const auto &link : links)
                if (link.hello)
                    send_line(link.fd, "install\n");
        }
        if (install_sent && !installed && !linked && now - idle_since >= kInstallSeconds)
        {
            installed = true;
            installed_at = now;
            const bool ok = ps5_update::install();
            say("install: %s", ok ? "done" : "failed (see .update-result)");
            stale = true; /* this daemon is the old build's now */
        }

        // What must not be cut: transfers in flight, not an open page's idle keep-alive
        // connections (counting those, a stale daemon kept 6769 from the new build).
        const unsigned busy = ps5_webui_transfers();
        const std::string update = ps5_update::status().state;
        // A download, or a scraping job, goes on with the title closed and no page open.
        const bool updating =
            update == "downloading" || update == "verifying" || ps5_webui_scraping();
        bool stop = false;
        if (root.empty() && !linked && now - started >= kNoHelloSeconds)
        {
            say("no program of a title linked within %.0f s", kNoHelloSeconds);
            stop = true;
        }
        else if (stale && !busy && !linked && (!installed || now - installed_at >= 15.0))
        {
            say("stopping for the new build's daemon (no transfer in flight%s)",
                ps5_webui_scraping() ? "; the scraping job is saved and resumes there" : "");
            stop = true;
        }
        else if (!root.empty() && !linked && !busy && !updating && !install_sent &&
                 now - idle_since >= kIdleSeconds)
        {
            say("no program of the title linked for %.0f s: the title is closed", kIdleSeconds);
            stop = closed = true;
        }
        if (stale && listener >= 0 && !installed)
        {
            close(listener); /* the new build's daemon can start meanwhile */
            listener = -1;
        }
        if (stop)
            break;
    }
    if (starter_running)
        pthread_join(starter, nullptr); /* a start under way ends before the stop */
    for (const auto &link : links)
        close(link.fd);
    if (listener >= 0)
        close(listener);
    ps5_webui_stop();
    /* ShadowMountPlus refuses to uninstall while a game runs, and RetroArch is one */
    if (closed && !tiles_done)
        ps5_webui_finish_forwarders([](const char *line) { say("%s", line); });
    say("stopped");
    return 0;
}
