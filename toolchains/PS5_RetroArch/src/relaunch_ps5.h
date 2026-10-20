/* PS5 RetroArch - the relaunch test (src/relaunch_ps5.cpp says why).
 *
 * Copyright (C) 2026 Mihawk
 * SPDX-License-Identifier: GPL-3.0-or-later
 */
#ifndef PS5_RETROARCH_RELAUNCH_PS5_H
#define PS5_RETROARCH_RELAUNCH_PS5_H

#ifdef __cplusplus
#include <string>
#include <vector>

namespace ps5::relaunch
{
/* "<count> <run id> [image]": restart the title <count> times (1 to 20) under one
 * run id (letters, digits, '-' and '_'), through the image named, a path in /app0,
 * or the title's own eboot.bin when none is. Each line after the first is one more
 * argument for the restarts (at most 8, printable, under 256 bytes). */
struct Arm
{
    unsigned count = 0;
    std::string run;
    std::string image;
    std::vector<std::string> arguments;
};

struct Paths
{
    std::string arm;     /* the test's arm file, removed when the test ends */
    std::string results; /* one JSON line a process, appended */
    std::string image;   /* what LoadExec starts: the title's own eboot.bin */
};

bool parse_arm(const std::string &text, Arm &arm);
/* The run's entry lines already in the results: the generation of this process. */
unsigned generation(const std::string &results, const std::string &run);
/* The generation the process arguments name (--ps5-relaunch=N), or -1. */
int argument_generation(int argc, char **argv);
std::string entry_line(const Arm &arm, unsigned generation, int named, int argc, char **argv,
                       long long flexible_free, long long pid, unsigned long long clock_ns,
                       const char *action);
/* Runs one generation of an armed test. It returns only when this launch is to
 * continue into RetroArch: unarmed, done, or a restart that did not happen
 * (true then). A restart that happens never returns. */
bool run_test(const Paths &paths, int argc, char **argv, unsigned replaced_wait_seconds);
} // namespace ps5::relaunch

extern "C"
{
#endif

    void ps5_relaunch_test_if_requested(int argc, char **argv);

#ifdef __cplusplus
}
#endif

#endif
