/* PS5 RetroArch - the relaunch test: the first proof of the frontend handover.
 *
 * Copyright (C) 2026 Mihawk
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * Why this exists. The frontend picker (RetroArch or EmulationStation) is to hand
 * over by restarting the title: the picker, a frontend and a game each start in a
 * fresh process, through sceSystemServiceLoadExec with this title's own image and
 * the next mode's arguments. A fresh process runs RetroArch exactly as a launch
 * from the home screen does, where calling rarch_main a second time in one process
 * would depend on every static of RetroArch and its drivers starting over. But
 * this title has only ever called LoadExec with "exit", so the restart is measured
 * before anything is built on it.
 *
 * /app0/relaunch-test.txt ("<count> <run id> [image]", written by tools/run-title.sh
 * --relaunch-test, with --relaunch-image naming another image of the title in /app0)
 * arms it; each line after the first (--relaunch-arg) is one more argument the restarts
 * carry, as a home screen forwarder's --rom and --core do (src/frontend_mode_ps5.cpp).
 * Each process the test starts appends one line to
 * /app0/relaunch-test.jsonl: its generation, which is the number of this run's
 * lines already in the file (so a restart that lost its arguments still counts,
 * and cannot loop), the generation its arguments name, argc and argv, the
 * flexible memory free on entry, its pid and the monotonic clock. Until <count>
 * restarts are recorded the process restarts the title; the last one disarms the
 * test and continues into RetroArch as any launch does. A LoadExec that returns an
 * error, or that is accepted but leaves this process running, is recorded too, and
 * the test is disarmed so the launch still ends in RetroArch.
 */
extern "C" void ps5_permissions_settle(); /* src/permissions_ps5.cpp */
#include "relaunch_ps5.h"

#include <cerrno>
#include <cstddef>
#include <cstdio>
#include <cstring>
#include <ctime>
#include <string>
#include <unistd.h>

#include "trace.hpp"

extern "C" int sceSystemServiceLoadExec(const char *path, const char *const *argv);
extern "C" int sceKernelAvailableFlexibleMemorySize(std::size_t *size);

namespace ps5::relaunch
{
namespace
{
constexpr const char *token = "--ps5-relaunch=";
constexpr unsigned max_count = 20;

bool read_file(const std::string &path, std::string &out)
{
    std::FILE *file = std::fopen(path.c_str(), "rb");
    if (!file)
        return false;
    char buffer[4096];
    std::size_t read;
    out.clear();
    while ((read = std::fread(buffer, 1, sizeof buffer, file)) > 0)
        out.append(buffer, read);
    std::fclose(file);
    return true;
}

/* One line, written, flushed and synced before the next step: the line must be
 * on the console's storage before this process asks to be replaced. */
bool append_line(const std::string &path, const std::string &line)
{
    std::FILE *file = std::fopen(path.c_str(), "ab");
    if (!file)
        return false;
    bool ok = std::fwrite(line.data(), 1, line.size(), file) == line.size() &&
              std::fputc('\n', file) != EOF && std::fflush(file) == 0;
    ok = fsync(fileno(file)) == 0 && ok;
    return std::fclose(file) == 0 && ok;
}

void json_string(std::string &out, const char *text)
{
    out += '"';
    for (const unsigned char *at = reinterpret_cast<const unsigned char *>(text); *at; at++)
    {
        if (*at == '"' || *at == '\\')
        {
            out += '\\';
            out += static_cast<char>(*at);
        }
        else if (*at < 0x20)
        {
            char escaped[8];
            std::snprintf(escaped, sizeof escaped, "\\u%04x", *at);
            out += escaped;
        }
        else
            out += static_cast<char>(*at);
    }
    out += '"';
}

std::string line_start(const std::string &run, unsigned generation)
{
    std::string line = "{\"run\":";
    json_string(line, run.c_str());
    line += ",\"generation\":" + std::to_string(generation);
    return line;
}

unsigned long long monotonic_ns()
{
    timespec now{};
    clock_gettime(CLOCK_MONOTONIC, &now);
    return static_cast<unsigned long long>(now.tv_sec) * 1000000000ull +
           static_cast<unsigned long long>(now.tv_nsec);
}
} // namespace

bool parse_arm(const std::string &text, Arm &arm)
{
    unsigned count = 0;
    char run[48] = {};
    char image[256] = {};
    const std::size_t first_end = text.find('\n');
    const int fields =
        std::sscanf(text.substr(0, first_end).c_str(), "%u %47s %255s", &count, run, image);
    if (fields < 2 || count == 0 || count > max_count)
        return false;
    for (const char *at = run; *at; at++)
        if (!((*at >= 'a' && *at <= 'z') || (*at >= 'A' && *at <= 'Z') ||
              (*at >= '0' && *at <= '9') || *at == '-' || *at == '_'))
            return false;
    /* Another image of the title: a path in /app0, never one that climbs out. */
    if (fields == 3 && (std::strncmp(image, "/app0/", 6) != 0 || std::strstr(image, "..") ||
                        std::strpbrk(image, "\"\\")))
        return false;
    /* The lines after the first are arguments for the restarts, one a line. */
    std::vector<std::string> arguments;
    for (std::size_t at = first_end; at != std::string::npos && at + 1 < text.size();)
    {
        const std::size_t end = text.find('\n', at + 1);
        std::string argument = text.substr(at + 1, end == std::string::npos ? end : end - at - 1);
        at = end;
        if (!argument.empty() && argument.back() == '\r')
            argument.pop_back();
        if (argument.empty())
            continue;
        if (arguments.size() == 8 || argument.size() > 255)
            return false;
        for (const char c : argument)
            if (static_cast<unsigned char>(c) < 0x20)
                return false;
        arguments.push_back(argument);
    }
    arm.count = count;
    arm.run = run;
    arm.image = fields == 3 ? image : "";
    arm.arguments = arguments;
    return true;
}

unsigned generation(const std::string &results, const std::string &run)
{
    const std::string needle = line_start(run, 0).substr(0, line_start(run, 0).rfind(':') + 1);
    unsigned found = 0;
    std::size_t at = 0;
    while (at < results.size())
    {
        std::size_t end = results.find('\n', at);
        if (end == std::string::npos)
            end = results.size();
        /* Only a process's own entry line counts: the lines that report what a
         * LoadExec did carry "event" and belong to the generation before. */
        const std::string line = results.substr(at, end - at);
        if (line.compare(0, needle.size(), needle) == 0 &&
            line.find("\"event\"") == std::string::npos)
            found++;
        at = end + 1;
    }
    return found;
}

int argument_generation(int argc, char **argv)
{
    /* From argv[0]: this console starts a process with LoadExec's arguments as
     * its whole argv, with no program name in front (2026-10-04: a restart got
     * argc=1, argv[0]="--ps5-relaunch=1"; a launch from the home screen gets
     * argc=1, argv[0]=""). */
    for (int i = 0; i < argc && argv && argv[i]; i++)
    {
        unsigned value = 0;
        char tail = 0;
        if (std::strncmp(argv[i], token, std::strlen(token)) == 0 &&
            std::sscanf(argv[i] + std::strlen(token), "%u%c", &value, &tail) == 1)
            return static_cast<int>(value);
    }
    return -1;
}

std::string entry_line(const Arm &arm, unsigned generation, int named, int argc, char **argv,
                       long long flexible_free, long long pid, unsigned long long clock_ns,
                       const char *action)
{
    std::string line = line_start(arm.run, generation);
    line += ",\"count\":" + std::to_string(arm.count);
    if (!arm.image.empty())
    {
        line += ",\"image\":";
        json_string(line, arm.image.c_str());
    }
    line += ",\"argument_generation\":" + std::to_string(named);
    line += ",\"argc\":" + std::to_string(argc) + ",\"argv\":[";
    for (int i = 0; i < argc && argv && argv[i]; i++)
    {
        if (i)
            line += ',';
        json_string(line, argv[i]);
    }
    line += "],\"flexible_free\":" + std::to_string(flexible_free);
    line += ",\"pid\":" + std::to_string(pid);
    line += ",\"monotonic_ns\":" + std::to_string(clock_ns);
    line += ",\"action\":";
    json_string(line, action);
    line += '}';
    return line;
}

bool run_test(const Paths &paths, int argc, char **argv, unsigned replaced_wait_seconds)
{
    std::string text;
    Arm arm;
    if (!read_file(paths.arm, text))
        return false;
    if (!parse_arm(text, arm))
    {
        ps5::debug::mark("relaunch test: unreadable arm file; disarmed");
        std::remove(paths.arm.c_str());
        return false;
    }
    std::string results;
    read_file(paths.results, results);
    const unsigned current = generation(results, arm.run);
    const int named = argument_generation(argc, argv);
    std::size_t flexible = 0;
    const long long flexible_free = sceKernelAvailableFlexibleMemorySize(&flexible) == 0
                                        ? static_cast<long long>(flexible)
                                        : -1;
    const bool restart = current < arm.count;
    const char *action = restart ? "restart" : "continue";
    char mark[96];
    std::snprintf(mark, sizeof mark, "relaunch test: generation %u of %u (arguments name %d), %s",
                  current, arm.count, named, action);
    ps5::debug::mark(mark);
    if (!append_line(paths.results,
                     entry_line(arm, current, named, argc, argv, flexible_free,
                                static_cast<long long>(getpid()), monotonic_ns(), action)) ||
        !restart)
    {
        /* Done, or a line that could not be kept: never restart without a record. */
        std::remove(paths.arm.c_str());
        if (restart)
            ps5::debug::mark("relaunch test: the record could not be written; disarmed");
        return false;
    }

    const std::string next = std::string(token) + std::to_string(current + 1);
    std::vector<const char *> arguments{next.c_str()};
    for (const std::string &argument : arm.arguments)
        arguments.push_back(argument.c_str());
    arguments.push_back(nullptr);
    std::fflush(nullptr);
    const std::string &image = arm.image.empty() ? paths.image : arm.image;
    ps5_permissions_settle();
    const int result = sceSystemServiceLoadExec(image.c_str(), arguments.data());
    std::string event = line_start(arm.run, current) +
                        ",\"event\":\"loadexec\",\"result\":" + std::to_string(result);
    if (result >= 0)
    {
        /* Accepted: the shell replaces this process asynchronously, as it ends it
         * for "exit". Wait for that, but not for ever: a process still here after
         * the wait says so and ends the test in RetroArch. */
        for (unsigned waited = 0; waited < replaced_wait_seconds * 10; waited++)
            usleep(100000);
        event += ",\"still_running_after_s\":" + std::to_string(replaced_wait_seconds);
    }
    event += '}';
    append_line(paths.results, event);
    ps5::debug::mark_value("relaunch test: LoadExec did not replace the process; result", result);
    std::remove(paths.arm.c_str());
    return true;
}
} // namespace ps5::relaunch

extern "C" void ps5_relaunch_test_if_requested(int argc, char **argv)
{
    const ps5::relaunch::Paths paths{"/app0/relaunch-test.txt", "/app0/relaunch-test.jsonl",
                                     "/app0/eboot.bin"};
    ps5::relaunch::run_test(paths, argc, argv, 60);
}
