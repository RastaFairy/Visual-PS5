/* Copyright (C) 2026 Mihawk; SPDX-License-Identifier: GPL-3.0-or-later */
#pragma once
// The server owns no emulator state; saved WebUI settings load on next launch.
// apply_settings: the WebUI's pending core settings go into the cores' files now; only
// before RetroArch starts (eboot.bin), never from the daemon while a core may run.
bool ps5_webui_start(const char *root, unsigned short port = 6769, bool apply_settings = true);
void ps5_webui_stop();
// Once no program of the title is linked (the daemon): what the Game Forwarder page's
// tiles left for the title's close, removals and new names or icons
// (src/ps5_forwarders.h). True once nothing waits any more.
bool ps5_webui_finish_forwarders(void (*say)(const char *line));
// The title's side when the daemon serves (src/webui_link.h): the folder core option
// metadata is written to, and the saved core settings applied before RetroArch reads them.
void ps5_webui_prepare(const char *root);
// The frontend the title shows now, for the status ("picker", "retroarch", "es-de").
void ps5_webui_set_frontend(const char *frontend);
// Requests being answered now (an upload or a download among them).
unsigned ps5_webui_connections();
// A scraping job the console drives is running (the daemon stays up for it).
bool ps5_webui_scraping();
// Transfers in flight (uploads, upload sessions' parts, helper deliveries): what must
// not be cut. Idle keep-alive connections of an open page are not counted.
unsigned ps5_webui_transfers();

struct retro_core_options_v2;
struct retro_variable;
extern "C" void ps5_webui_core_options(const char *, const retro_core_options_v2 *);
extern "C" void ps5_webui_core_variables(const char *, const retro_variable *);
