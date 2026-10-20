/* PS5 RetroArch - EmulationStation's games, in RetroArch (game mode).
 *
 * Copyright (C) 2026 Mihawk
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * ES-DE starts a game through the title's game mode (src/ps5_game.h), the same
 * contract every frontend uses. Its launch command, from es_systems.xml
 * (written from RetroArch's playlists by library_ps5.cpp), is RetroArch's own command line,
 * "/app0/eboot.bin -L <core> <content>", which ES-DE expands as it does on a PC;
 * the ES-DE patch (patches/0001, FileData::launchGame) saves its game lists, releases
 * the display and calls ps5_esde_launch_game with it in place of starting a process.
 *
 * The state handed to RetroArch and back is "<system>\t<game path>": the system the
 * game was started from (a collection too) and the game. When the title comes back,
 * main_ps5.cpp takes the result before ES-DE starts, and ES-DE's start
 * (patches/0001, ViewController::goToStart) asks ps5_esde_game_return for it: it
 * counts the play, adds the time RetroArch ran, and opens that system's game list
 * on that game.
 */
#include "ps5_game.h"

#include <cstdio>
#include <cstring>

namespace
{
constexpr const char *executable = "/app0/es-de/es-de.bin";
struct ps5_game returned;
bool has_return = false;
bool started_from_game = false;
} // namespace

extern "C" int ps5_esde_take_game_result(void)
{
    has_return = started_from_game = ps5_game_take_result(executable, &returned) == 1;
    return has_return;
}

extern "C" int ps5_esde_started_from_game(void)
{
    return started_from_game;
}

extern "C" int ps5_esde_launch_game(const char *command, const char *system, const char *path, char *error,
                                    size_t error_size)
{
    struct ps5_game game = {};
    if (ps5_game_parse_command(command, &game) == 0)
    {
        std::snprintf(game.frontend, sizeof(game.frontend), "%s", executable);
        std::snprintf(game.state, sizeof(game.state), "%s\t%s", system, path);
        ps5_game_launch(&game); /* returns only when the title did not restart */
    }
    std::snprintf(error, error_size, "%s", game.error);
    return -1;
}

extern "C" int ps5_esde_game_return(char *system, size_t system_size, char *path, size_t path_size, long *seconds,
                                    int *status, char *error, size_t error_size)
{
    if (!has_return)
        return 0;
    has_return = false; /* once */
    const char *tab = std::strchr(returned.state, '\t');
    if (!tab)
        return 0;
    std::snprintf(system, system_size, "%.*s", static_cast<int>(tab - returned.state), returned.state);
    std::snprintf(path, path_size, "%s", tab + 1);
    *seconds = returned.seconds;
    *status = returned.status;
    std::snprintf(error, error_size, "%s", returned.error);
    return 1;
}
