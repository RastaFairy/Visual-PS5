/* PS5 RetroArch - the link between the title's programs and the WebUI daemon.
 *
 * Copyright (C) 2026 Mihawk
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * The WebUI must not stop when the title changes frontend: LoadExec ends the program
 * it leaves (RetroArch's eboot.bin, the picker, EmulationStation), and a server inside
 * it with every connection and upload it held. So the WebUI is its own process, the
 * daemon (daemon/webui_daemon.cpp, /app0/webui/ps5-retroarch-webui.elf), which a
 * LoadExec does not touch, and every program of the title keeps one connection to it
 * open while it runs (127.0.0.1:6770):
 *
 *   - the program says which frontend it is and which title it belongs to
 *     ("hello <frontend> <title id>"); the daemon finds the title's folder from the
 *     title's mount and serves it on 6769, and answers "ok";
 *   - while some program of the title is connected the daemon runs; with none for a
 *     while (the title closed) and no transfer left, it stops;
 *   - the daemon says "install" when the WebUI's update is to be installed: the
 *     program closes the title, and the daemon installs once no program is left.
 *
 * With no daemon answering, the link starts one, once, and waits for it: it sends
 * the ELF to the console's ELF loader (127.0.0.1:9021, etaHEN's or elfldr's), or,
 * with none, asks the homebrew launcher (ps5-payload-dev's websrv, 127.0.0.1:8080)
 * to run it from the title's folder. With neither, eboot.bin serves the WebUI itself as it always
 * has (src/main.cpp), and only then does a frontend change interrupt it.
 *
 * Compiled into eboot.bin, the picker and EmulationStation alike: plain sockets and
 * pthreads, nothing of the title's own. */
#ifndef PS5_RETROARCH_WEBUI_LINK_H
#define PS5_RETROARCH_WEBUI_LINK_H

#ifdef __cplusplus
extern "C"
{
#endif

/* Overridable for the host test (tests/webui_link_test.cpp). */
#ifndef PS5_WEBUI_APP0
#define PS5_WEBUI_APP0 "/app0"
#endif
#ifndef PS5_WEBUI_LINK_PORT
#define PS5_WEBUI_LINK_PORT 6770
#endif
#ifndef PS5_WEBUI_LOADER_PORT
#define PS5_WEBUI_LOADER_PORT 9021
#endif
#ifndef PS5_WEBUI_LAUNCHER_PORT
#define PS5_WEBUI_LAUNCHER_PORT 8080
#endif
#define PS5_WEBUI_DAEMON PS5_WEBUI_APP0 "/webui/ps5-retroarch-webui.elf"

    /* Starts the link in its own thread: frontend is "title" (eboot.bin before it has
     * decided), "retroarch", "picker" or "es-de". on_install, if given, is called from
     * the link's thread when the daemon asks for the update to be installed: the
     * program then closes the title, and the daemon installs once it has closed. log,
     * if given, receives the link's lines (no newline). */
    void ps5_webui_link_start(const char *frontend, void (*on_install)(void),
                              void (*log)(const char *line));
    /* The frontend this program is now (sent to the daemon when connected). */
    void ps5_webui_link_frontend(const char *frontend);
    /* Waits at most timeout_ms for the link to know whether a daemon serves the WebUI:
     * 1 connected, 0 none (or not known in time). */
    int ps5_webui_link_wait(unsigned timeout_ms);
    /* Before a LoadExec: waits, at most 3 s, for a daemon being sent to the loader to
     * be sent whole, so the loader never runs half an ELF. */
    void ps5_webui_link_settle(void);
    /* 1 once the daemon asked for the update to be installed. */
    int ps5_webui_link_install_requested(void);
    /* 1 while connected to the daemon. */
    int ps5_webui_link_connected(void);

#ifdef __cplusplus
}
#endif

#endif
