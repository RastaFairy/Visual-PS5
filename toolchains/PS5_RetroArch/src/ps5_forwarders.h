/* PS5 RetroArch - Game Forwarder tiles: home screen tiles that each start one game.
 *
 * Copyright (C) 2026 Mihawk
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * A tile is a title of its own, /data/homebrew/<id>, with an id from the range this port
 * keeps for tiles (PPSA99170 to PPSA99269), its name and icon, the app forwarder/tile.c
 * builds, the payload forwarder/launch.c builds, and the arguments that payload gives
 * RetroArch (forward.txt: --rom, --core and --exit-after-game, src/frontend_mode_ps5.cpp).
 * forwarder.json beside them is what the WebUI shows and edits; a folder without one is
 * never listed, changed or removed here.
 *
 * ShadowMountPlus puts a tile on the home screen: the folder goes into its manual list
 * through its HTTP API on 127.0.0.1:10101, and it installs the tile once no game runs.
 * Removing one asks ShadowMountPlus to uninstall it, which it refuses while a game runs,
 * and RetroArch runs whenever the WebUI does: the removal is then marked in the tile's
 * folder, and the WebUI's daemon finishes it once the title has closed
 * (daemon/webui_daemon.cpp, finish_pending). A new name or icon on an installed tile is
 * re-registered the same way, since the home screen keeps what it installed.
 */
#pragma once

#include <string>

namespace ps5_forwarders
{
struct Paths
{
    std::string homebrew = "/data/homebrew"; /* where tiles are made */
    std::string title; /* RetroArch's folder: forwarder/, cores/, content/, ... */
    std::string shadowmount_host = "127.0.0.1";
    unsigned short shadowmount_port = 10101;
};
struct Tile
{
    std::string name, system, game, rom, core;
    bool exit_after_game = true;
};
/* The WebUI's view: whether ShadowMountPlus answers, the id range, and every tile with its
 * state (installed, waiting for RetroArch to close, removing). */
std::string list_json(const Paths &paths);
/* A tile from the WebUI's JSON (name, system, game, rom, core, exit_after_game). */
bool parse_tile(const std::string &json, Tile &tile, std::string &why);
/* Makes a tile and hands it to ShadowMountPlus: its id, or false and why. */
bool create(const Paths &paths, const Tile &tile, std::string &id, std::string &why);
bool update(const Paths &paths, const std::string &id, const Tile &tile, std::string &why);
/* A 512x512 PNG for the tile's icon. */
bool set_icon(const Paths &paths, const std::string &id, const std::string &png, std::string &why);
/* The tile's icon file, or "" when it is not a tile. */
std::string icon_file(const Paths &paths, const std::string &id);
/* "removed", "pending" (finished once the title has closed), or "" and why. */
std::string remove(const Paths &paths, const std::string &id, std::string &why);
/* Once the title has closed: removals and re-registrations that had to wait, and every
 * tile's app and payload brought up to this build's. say gets one line an action. True
 * once nothing waits any more; false while ShadowMountPlus still refuses (a game runs). */
bool finish_pending(const Paths &paths, void (*say)(const char *line));
} // namespace ps5_forwarders
