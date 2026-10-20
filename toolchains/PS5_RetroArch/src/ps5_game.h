/* PS5 RetroArch - game mode: how every frontend starts a game in RetroArch.
 *
 * Copyright (C) 2026 Mihawk
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * A frontend never runs a game itself: it asks the title to run the game in
 * RetroArch, in a process of its own, and to come back to it afterwards
 * (docs/FRONTENDS.md, approach B). This header and src/ps5_game.c are that
 * contract. They are compiled into eboot.bin (src/) and into every frontend
 * executable (tools/build-frontend.sh), so there is one implementation of it:
 *
 *   1. the frontend calls ps5_game_launch with the content, the core (or none),
 *      its own executable and a state string of its own (where it was). The
 *      request is written to /app0/game-request.txt, and the title restarts as
 *      eboot.bin with --ps5-mode=game;
 *   2. eboot.bin takes the request (src/frontend_mode_ps5.cpp) and checks it. The
 *      core is the one RetroArch's playlists associate with that content, when they
 *      do (RetroArch's choice is the user's), else the frontend's; then RetroArch
 *      runs the game, and Close Content quits it;
 *   3. when RetroArch has quit, eboot.bin writes /app0/game-result.txt (the
 *      request, the core used, RetroArch's status and the seconds it ran) and
 *      restarts the title as the frontend;
 *   4. the frontend, starting, takes that result with ps5_game_take_result and
 *      goes back to where its state says.
 *
 * Everything RetroArch keeps applies during the game: its configuration and
 * overrides, shaders, overlays, remaps, cheats, saves, states and achievements.
 * A frontend keeps none of them.
 *
 * A frontend's launch command, on the PS5, is RetroArch's own command line:
 *
 *     /app0/eboot.bin -L /app0/cores/<core>_libretro.so <content>
 *
 * the content one shell word (quoted, or with backslash escapes, as a frontend
 * expands it), the -L pair optional. ps5_game_parse_command reads one, so a
 * frontend that configures its launches as command lines needs nothing else.
 */
#ifndef PS5_RETROARCH_PS5_GAME_H
#define PS5_RETROARCH_PS5_GAME_H

#include <stddef.h>

#ifdef __cplusplus
extern "C"
{
#endif

#define PS5_GAME_EBOOT "/app0/eboot.bin"
#define PS5_GAME_PLAYLISTS "/app0/playlists"
/* The host test (tests/ps5_game_test.c) moves these into a scratch folder. */
#ifndef PS5_GAME_CORES
#define PS5_GAME_CORES "/app0/cores/"
#endif
#ifndef PS5_GAME_REQUEST_PATH
#define PS5_GAME_REQUEST_PATH "/app0/game-request.txt"
#endif
#ifndef PS5_GAME_RESULT_PATH
#define PS5_GAME_RESULT_PATH "/app0/game-result.txt"
#endif
#define PS5_GAME_PATH_MAX 1024
#define PS5_GAME_STATE_MAX 2048

    /* A game for RetroArch: a request, and the result it becomes. */
    struct ps5_game
    {
        char core[PS5_GAME_PATH_MAX];     /* a request's: the frontend's default, or empty */
        char content[PS5_GAME_PATH_MAX];  /* the game, an absolute path */
        char frontend[PS5_GAME_PATH_MAX]; /* the executable to come back to */
        char state[PS5_GAME_STATE_MAX];   /* the frontend's own, handed back unchanged */
        int status;      /* a result: RetroArch's exit status, or -1 when refused */
        long seconds;    /* a result: how long RetroArch ran */
        char error[256]; /* a result: why it was refused */
    };

    /* The request or result in a file of "key=value" lines; a value has no line break.
     * Written to a temporary file and renamed, so a reader sees all of it or none. */
    int ps5_game_write(const char *path, const struct ps5_game *game, int result);
    /* 0 when the file holds a game (*result says whether it is a result), -1 when not. */
    int ps5_game_read(const char *path, struct ps5_game *game, int *result);

    /* A launch command: "/app0/eboot.bin [-L <core>] <content>" as shell words. Fills
     * core (empty when none) and content; 0, or -1 with the reason in game->error. */
    int ps5_game_parse_command(const char *command, struct ps5_game *game);

    /* A request RetroArch can run: content an absolute path to a file that exists, core
     * empty or /app0/cores/<name>_libretro.so and present, frontend an absolute path to
     * a file that exists, no value with a line break. 0, or -1 with the reason in
     * game->error. */
    int ps5_game_check(struct ps5_game *game);

    /* The core RetroArch's playlists (the .lpl files in a folder) associate with this
     * content: 1 and the core's path when an entry names it with a core, else 0. */
    int ps5_game_playlist_core(const char *playlists, const char *content, char *core, size_t size);

    /* The frontend's side. Writes the request and restarts the title as eboot.bin in
     * game mode. It returns only when that did not happen: -1, with the reason in
     * request->error. The frontend has released its display and saved its state first. */
    int ps5_game_launch(struct ps5_game *request);
    /* At the frontend's start: 1 and the result when RetroArch has just run a game for
     * this frontend (the result file is removed), 0 when not. */
    int ps5_game_take_result(const char *frontend, struct ps5_game *result);

#ifdef __cplusplus
}
#endif

#endif
