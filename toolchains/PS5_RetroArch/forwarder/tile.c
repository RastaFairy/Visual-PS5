/* PS5 RetroArch - a Game Forwarder tile: the app each home screen tile the WebUI makes runs.
 *
 * Copyright (C) 2026 Mihawk
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * A tile is a title of its own (/data/homebrew/<its id>), and a title cannot start another:
 * sceSystemServiceLaunchApp answered a tile 0x8094000f, and sceLncUtilLaunchApp is a null
 * import for a title. So the tile hands the launch to a payload: it writes its own title id
 * into forwarder/launch.c's slot, sends that payload to the console's ELF loader on
 * 127.0.0.1:9021 as eboot.bin sends the WebUI's daemon (src/webui_link.cpp), and closes as
 * eboot.bin closes. The payload waits for it to go and starts RetroArch with the arguments
 * in the tile's forward.txt (--rom, --core, --exit-after-game: src/frontend_mode_ps5.cpp).
 * What happened is written to the tile's tile.log.
 */
#include <arpa/inet.h>
#include <errno.h>
#include <netinet/in.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <unistd.h>

#include "forwarder.h"

#ifndef FORWARDER_APP0
#define FORWARDER_APP0 "/app0"
#endif
#ifndef FORWARDER_LOADER_PORT
#define FORWARDER_LOADER_PORT 9021
#endif

int sceSystemServiceHideSplashScreen(void);
int sceSystemServiceLoadExec(const char *path, const char *const *argv);

/* The whole of a small file, NUL-terminated; NULL when it cannot be read. */
static char *read_file(const char *path, long *size)
{
    FILE *file = fopen(path, "rb");
    char *data = NULL;
    long length = -1;
    if (file && fseek(file, 0, SEEK_END) == 0 && (length = ftell(file)) >= 0 &&
        fseek(file, 0, SEEK_SET) == 0 && (data = malloc((size_t)length + 1)) &&
        fread(data, 1, (size_t)length, file) != (size_t)length)
    {
        free(data);
        data = NULL;
    }
    if (file)
        fclose(file);
    if (data)
    {
        data[length] = '\0';
        *size = length;
    }
    return data;
}

/* The "titleId" of this tile's param.json into id; 0 when there is no valid one. */
int forwarder_title_id(const char *param, char id[FORWARDER_ID_SIZE])
{
    const char *key = param ? strstr(param, "\"titleId\"") : NULL;
    const char *value = key ? strchr(key + 9, '"') : NULL;
    if (!value || !forwarder_valid_id(value + 1, 9) || value[10] != '"')
        return 0;
    memcpy(id, value + 1, 9);
    id[9] = '\0';
    return 1;
}

/* Writes id over the payload's slot, which must be there exactly once; 0 otherwise. */
int forwarder_stamp(char *payload, long size, const char *id)
{
    const size_t marker = strlen(FORWARDER_SLOT_MARKER);
    char *slot = NULL;
    for (long at = 0; at + (long)marker <= size; at++)
        if (memcmp(payload + at, FORWARDER_SLOT_MARKER, marker) == 0)
        {
            if (slot)
                return 0;
            slot = payload + at;
        }
    if (!slot)
        return 0;
    memset(slot, 0, marker);
    memcpy(slot, id, strlen(id));
    return 1;
}

/* Sends the payload, whole, to the loader; the bytes sent. */
static long send_to_loader(const char *payload, long size, int *error)
{
    long sent = 0;
    const int fd = socket(AF_INET, SOCK_STREAM, 0);
    struct sockaddr_in loader;
    memset(&loader, 0, sizeof(loader));
    loader.sin_family = AF_INET;
    loader.sin_port = htons(FORWARDER_LOADER_PORT);
    loader.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    *error = 0;
    if (fd < 0 || connect(fd, (struct sockaddr *)&loader, sizeof(loader)) != 0)
        *error = errno;
    else
        while (sent < size)
        {
            const ssize_t n = send(fd, payload + sent, (size_t)(size - sent), 0);
            if (n <= 0)
            {
                *error = errno;
                break;
            }
            sent += n;
        }
    if (fd >= 0)
        close(fd);
    return sent;
}

int main(int argc, char **argv)
{
    (void)argc;
    (void)argv;
    FILE *log = fopen(FORWARDER_APP0 "/tile.log", "w");
    sceSystemServiceHideSplashScreen();
    long param_size = 0, payload_size = 0;
    char *param = read_file(FORWARDER_APP0 "/sce_sys/param.json", &param_size);
    char *payload = read_file(FORWARDER_APP0 "/launch.elf", &payload_size);
    char id[FORWARDER_ID_SIZE] = "";
    if (!forwarder_title_id(param, id))
    {
        if (log)
            fprintf(log, "tile: no title id in sce_sys/param.json\n");
    }
    else if (!payload || !forwarder_stamp(payload, payload_size, id))
    {
        if (log)
            fprintf(log, "tile %s: launch.elf is missing or has no slot for the title id\n", id);
    }
    else
    {
        int error = 0;
        const long sent = send_to_loader(payload, payload_size, &error);
        if (log)
            fprintf(log, "tile %s: launch payload %ld bytes, %ld sent to 127.0.0.1:%d (errno %d)\n", id,
                    payload_size, sent, FORWARDER_LOADER_PORT, error);
    }
    free(param);
    free(payload);
    if (log)
        fflush(log);
    /* A title closes as eboot.bin does (src/main.cpp): returning from main ended one with
     * SIGSYS, which the console reports as an error in the game. */
    const int result = sceSystemServiceLoadExec("exit", NULL);
    if (log)
    {
        fprintf(log, "tile %s: LoadExec(exit) = %08x\n", id, (unsigned)result);
        fclose(log);
    }
    if (result >= 0)
        for (;;)
            usleep(100000); /* the shell ends the process asynchronously */
    return 0;
}
