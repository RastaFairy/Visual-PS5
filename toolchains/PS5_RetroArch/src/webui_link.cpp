/* PS5 RetroArch - the link between the title's programs and the WebUI daemon
 * (src/webui_link.h says why).
 *
 * Copyright (C) 2026 Mihawk
 * SPDX-License-Identifier: GPL-3.0-or-later
 */
#include "webui_link.h"

#include <arpa/inet.h>
#include <atomic>
#include <cerrno>
#include <chrono>
#include <cstdarg>
#include <cstdio>
#include <cstring>
#include <fcntl.h>
#include <mutex>
#include <netinet/in.h>
#include <poll.h>
#include <pthread.h>
#include <string>
#include <sys/socket.h>
#include <unistd.h>
#include <vector>

/* Named, not anonymous: the picker compiles this file into its own (frontends/picker/
 * picker.cpp), beside an anonymous namespace of its own. */
namespace ps5_webui_link_detail
{
enum
{
    unknown,
    linked,
    alone
};
std::atomic<int> state{unknown}, sending{0}, install{0}, started{0};
std::mutex lock;
std::string frontend_now;
int link_fd = -1;
void (*install_callback)(void);
void (*log_callback)(const char *);

void say(const char *format, ...)
{
    if (!log_callback)
        return;
    char line[256];
    va_list arguments;
    va_start(arguments, format);
    std::vsnprintf(line, sizeof line, format, arguments);
    va_end(arguments);
    log_callback(line);
}

double now_ms()
{
    return std::chrono::duration<double, std::milli>(
               std::chrono::steady_clock::now().time_since_epoch())
        .count();
}

int connect_local(unsigned short port)
{
    const int fd = socket(AF_INET, SOCK_STREAM, 0);
    if (fd < 0)
        return -1;
    sockaddr_in address{};
    address.sin_family = AF_INET;
    address.sin_port = htons(port);
    address.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    if (connect(fd, reinterpret_cast<sockaddr *>(&address), sizeof address) != 0)
    {
        close(fd);
        return -1;
    }
    return fd;
}

bool write_all(int fd, const char *data, size_t size)
{
    while (size)
    {
        const ssize_t sent = send(fd, data, size, 0);
        if (sent <= 0)
        {
            if (sent < 0 && errno == EINTR)
                continue;
            return false;
        }
        data += sent;
        size -= size_t(sent);
    }
    return true;
}

/* One line from fd, waiting at most timeout_ms (-1: as long as it takes); false at
 * the end of the connection or the timeout. */
bool read_line(int fd, std::string &pending, std::string &line, int timeout_ms)
{
    for (;;)
    {
        const size_t end = pending.find('\n');
        if (end != std::string::npos)
        {
            line = pending.substr(0, end);
            pending.erase(0, end + 1);
            return true;
        }
        pollfd wait{fd, POLLIN, 0};
        const int ready = poll(&wait, 1, timeout_ms);
        if (ready < 0 && errno == EINTR)
            continue;
        if (ready <= 0)
            return false;
        char buffer[256];
        const ssize_t got = recv(fd, buffer, sizeof buffer, 0);
        if (got <= 0)
            return false;
        pending.append(buffer, size_t(got));
        if (pending.size() > 4096)
            return false;
    }
}

/* The title's id, from its param.json ("PPSA99169"); empty when unreadable. */
std::string title_id()
{
    std::string text;
    if (std::FILE *file = std::fopen(PS5_WEBUI_APP0 "/sce_sys/param.json", "rb"))
    {
        char buffer[4096];
        const size_t got = std::fread(buffer, 1, sizeof buffer, file);
        text.assign(buffer, got);
        std::fclose(file);
    }
    const size_t key = text.find("\"titleId\"");
    const size_t open = key == std::string::npos ? key : text.find('"', text.find(':', key));
    const size_t close = open == std::string::npos ? open : text.find('"', open + 1);
    if (close == std::string::npos || close - open != 10)
        return "";
    std::string id = text.substr(open + 1, 9);
    for (char c : id)
        if (!((c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9')))
            return "";
    return id;
}

/* Sends the daemon's ELF to the loader on PS5_WEBUI_LOADER_PORT, whole, and closes:
 * the loader runs it. */
bool send_to_loader()
{
    std::vector<char> elf;
    if (std::FILE *file = std::fopen(PS5_WEBUI_DAEMON, "rb"))
    {
        char buffer[65536];
        size_t got;
        while ((got = std::fread(buffer, 1, sizeof buffer, file)) > 0 && elf.size() < (32u << 20))
            elf.insert(elf.end(), buffer, buffer + got);
        std::fclose(file);
    }
    if (elf.size() < 64 || std::memcmp(elf.data(),
                                       "\x7f"
                                       "ELF",
                                       4) != 0)
    {
        say("webui link: no daemon to start (%s unreadable)", PS5_WEBUI_DAEMON);
        return false;
    }
    const int fd = connect_local(PS5_WEBUI_LOADER_PORT);
    if (fd < 0)
    {
        say("webui link: no ELF loader on %d (errno %d)", PS5_WEBUI_LOADER_PORT, errno);
        return false;
    }
    const bool sent = write_all(fd, elf.data(), elf.size());
    shutdown(fd, SHUT_WR);
    close(fd);
    say("webui link: daemon (%zu bytes) %s the loader on %d", elf.size(),
        sent ? "sent to" : "NOT sent whole to", PS5_WEBUI_LOADER_PORT);
    return sent;
}

/* Asks the homebrew launcher (ps5-payload-dev's websrv, /hbldr) to run the daemon
 * from the title's folder as the console sees it, the title's own mount
 * (/system_ex/app/<id>), as a daemon of its own. */
bool ask_launcher(const std::string &id)
{
    const int fd = connect_local(PS5_WEBUI_LAUNCHER_PORT);
    if (fd < 0)
    {
        say("webui link: no homebrew launcher on %d (errno %d)", PS5_WEBUI_LAUNCHER_PORT, errno);
        return false;
    }
    const std::string request =
        "GET /hbldr?daemon=1&pipe=0&path=/system_ex/app/" + id +
        "/webui/ps5-retroarch-webui.elf HTTP/1.0\r\nHost: 127.0.0.1\r\n\r\n";
    std::string pending, status;
    const bool asked =
        write_all(fd, request.data(), request.size()) && read_line(fd, pending, status, 5000);
    close(fd);
    if (!status.empty() && status.back() == '\r')
        status.pop_back();
    const bool started = asked && status.find(" 200") != std::string::npos;
    say("webui link: the launcher on %d answered \"%s\"", PS5_WEBUI_LAUNCHER_PORT,
        asked ? status.c_str() : "nothing");
    return started;
}

bool start_daemon(const std::string &id)
{
    return send_to_loader() || ask_launcher(id);
}

void *run(void *)
{
    const std::string id = title_id();
    if (id.empty())
    {
        say("webui link: the title id is unreadable; no daemon");
        state = alone;
        return nullptr;
    }
    bool loader_tried = false;
    unsigned unanswered = 0;
    for (;;)
    {
        int fd = connect_local(PS5_WEBUI_LINK_PORT);
        if (fd < 0)
        {
            if (loader_tried)
                break;
            loader_tried = true;
            sending = 1;
            const bool sent = start_daemon(id);
            sending = 0;
            if (!sent)
                break;
            const double start = now_ms();
            while (fd < 0 && now_ms() - start < 6000.0)
            {
                usleep(100000);
                fd = connect_local(PS5_WEBUI_LINK_PORT);
            }
            if (fd < 0)
            {
                say("webui link: the daemon did not answer within 6 s of its start");
                break;
            }
            say("webui link: the daemon answered %.0f ms after its start", now_ms() - start);
        }
        std::string frontend;
        {
            std::lock_guard<std::mutex> guard(lock);
            frontend = frontend_now;
        }
        const std::string hello = "hello " + frontend + ' ' + id + '\n';
        std::string pending, reply;
        if (!write_all(fd, hello.data(), hello.size()) || !read_line(fd, pending, reply, 5000))
        {
            /* A daemon busy starting (or loaded) answers late: asked again, never given up
             * on while it is there, so the title is never left unlinked (it would stop). */
            close(fd);
            if (++unanswered == 1 || unanswered % 10 == 0)
                say("webui link: the daemon did not answer the hello (%u); asking again",
                    unanswered);
            usleep(1000000);
            continue;
        }
        unanswered = 0;
        if (reply == "stale")
        {
            /* A daemon of another build of the title (one just updated): it stops once
             * its transfers end, and this build's is started in its place. */
            close(fd);
            say("webui link: the daemon is another build's; waiting for it to stop");
            for (int i = 0; i < 600 && (fd = connect_local(PS5_WEBUI_LINK_PORT)) >= 0; ++i)
            {
                close(fd);
                usleep(500000);
            }
            loader_tried = false;
            continue;
        }
        if (reply != "ok")
        {
            close(fd);
            say("webui link: the daemon refused this title (%s)", reply.c_str());
            break;
        }
        {
            std::lock_guard<std::mutex> guard(lock);
            link_fd = fd;
            if (frontend_now != frontend)
            {
                const std::string line = "frontend " + frontend_now + '\n';
                write_all(fd, line.data(), line.size());
            }
        }
        state = linked;
        loader_tried = false;
        say("webui link: connected as %s; the daemon serves the WebUI", frontend.c_str());
        std::string line;
        while (read_line(fd, pending, line, -1))
            if (line == "install" && !install.exchange(1))
            {
                say("webui link: the daemon asks for the title to close to install the update");
                if (install_callback)
                    install_callback();
            }
        {
            std::lock_guard<std::mutex> guard(lock);
            link_fd = -1;
        }
        close(fd);
        state = unknown;
        say("webui link: the daemon closed the link; reconnecting");
    }
    state = alone;
    say("webui link: no daemon; the WebUI is eboot.bin's own while RetroArch runs");
    return nullptr;
}
} // namespace ps5_webui_link_detail

namespace webui_link = ps5_webui_link_detail;

extern "C" void ps5_webui_link_start(const char *frontend, void (*on_install)(void),
                                     void (*log)(const char *line))
{
    if (webui_link::started.exchange(1))
        return;
    {
        std::lock_guard<std::mutex> guard(webui_link::lock);
        webui_link::frontend_now = frontend && *frontend ? frontend : "title";
    }
    webui_link::install_callback = on_install;
    webui_link::log_callback = log;
    pthread_t thread;
    pthread_attr_t attributes;
    pthread_attr_init(&attributes);
    pthread_attr_setstacksize(&attributes, 128 * 1024);
    if (pthread_create(&thread, &attributes, webui_link::run, nullptr) == 0)
        pthread_detach(thread);
    else
    {
        webui_link::state = webui_link::alone;
        webui_link::say("webui link: its thread could not start");
    }
    pthread_attr_destroy(&attributes);
}

extern "C" void ps5_webui_link_frontend(const char *frontend)
{
    if (!frontend || !*frontend || std::strchr(frontend, ' ') || std::strchr(frontend, '\n'))
        return;
    std::lock_guard<std::mutex> guard(webui_link::lock);
    webui_link::frontend_now = frontend;
    if (webui_link::link_fd >= 0)
    {
        const std::string line = "frontend " + webui_link::frontend_now + '\n';
        webui_link::write_all(webui_link::link_fd, line.data(), line.size());
    }
}

extern "C" int ps5_webui_link_wait(unsigned timeout_ms)
{
    const double start = webui_link::now_ms();
    while (webui_link::state.load() == webui_link::unknown &&
           webui_link::now_ms() - start < double(timeout_ms))
        usleep(20000);
    return webui_link::state.load() == webui_link::linked;
}

extern "C" void ps5_webui_link_settle(void)
{
    const double start = webui_link::now_ms();
    while (webui_link::sending.load() && webui_link::now_ms() - start < 3000.0)
        usleep(10000);
}

extern "C" int ps5_webui_link_install_requested(void)
{
    return webui_link::install.load();
}

extern "C" int ps5_webui_link_connected(void)
{
    return webui_link::state.load() == webui_link::linked;
}
