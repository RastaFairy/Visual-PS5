/* PS5 RetroArch - the Game Forwarder's launch payload.
 *
 * Copyright (C) 2026 Mihawk
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * Run by the console's ELF loader, sent there by a tile (forwarder/tile.c) with that tile's
 * title id written into tile_slot. A payload may start a title where the tile may not, so
 * this waits for the tile to close (up to 15 s), then starts RetroArch (FORWARDER_TARGET)
 * with the arguments in /data/homebrew/<tile>/forward.txt, one a line, through the launch
 * calls the console tooling's control payload uses: sceLncUtilLaunchApp as the foreground
 * user, then sceSystemServiceLaunchApp. Each step is written to the tile's launch.log.
 */
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>

#include "forwarder.h"

#ifndef FORWARDER_HOMEBREW
#define FORWARDER_HOMEBREW "/data/homebrew"
#endif
#ifndef FORWARDER_TARGET
#define FORWARDER_TARGET "PPSA99169"
#endif
#ifndef FORWARDER_WAIT_STEP_US
#define FORWARDER_WAIT_STEP_US 250000
#endif

typedef struct
{
    uint32_t size;
    int user_id;
    uint32_t app_opt;
    uint64_t crash_report;
    uint64_t check_flag;
} lnc_app_param_t;

int sceSystemServiceLaunchApp(const char *title_id, const char *argv[], lnc_app_param_t *param);
int sceLncUtilLaunchApp(const char *title_id, const char *argv[], lnc_app_param_t *param);
uint32_t sceLncUtilGetAppIdOfRunningBigApp(void);
int sceLncUtilGetAppTitleId(uint32_t app_id, char *title_id);
int sceUserServiceInitialize(void *param);
int sceUserServiceGetForegroundUser(int *user_id);

/* The tile writes its title id over the marker in these bytes (forwarder.h). */
__attribute__((used)) char tile_slot[FORWARDER_SLOT_SIZE] = FORWARDER_SLOT_MARKER;

/* The running big app's title id, or "" when none runs. */
static void running_title(char title[16])
{
    const uint32_t app = sceLncUtilGetAppIdOfRunningBigApp();
    memset(title, 0, 16);
    if (app != 0 && app != 0xffffffffu && sceLncUtilGetAppTitleId(app, title) != 0)
        memset(title, 0, 16);
    title[15] = '\0';
}

int main(void)
{
    char tile[FORWARDER_ID_SIZE];
    memcpy(tile, (const char *)tile_slot, sizeof(tile) - 1);
    tile[sizeof(tile) - 1] = '\0';
    if (!forwarder_valid_id(tile, strlen(tile)))
    {
        printf("forwarder payload: no tile's title id in the slot; nothing launched\n");
        return 1;
    }
    char path[256];
    snprintf(path, sizeof(path), FORWARDER_HOMEBREW "/%s/launch.log", tile);
    FILE *log = fopen(path, "w");
    char lines[FORWARDER_MAX_ARGUMENTS][FORWARDER_MAX_ARGUMENT];
    const char *arguments[FORWARDER_MAX_ARGUMENTS + 1];
    int count = 0;
    snprintf(path, sizeof(path), FORWARDER_HOMEBREW "/%s/forward.txt", tile);
    FILE *input = fopen(path, "r");
    while (input && count < FORWARDER_MAX_ARGUMENTS && fgets(lines[count], sizeof lines[count], input))
    {
        lines[count][strcspn(lines[count], "\r\n")] = '\0';
        if (lines[count][0])
        {
            arguments[count] = lines[count];
            count++;
        }
    }
    if (input)
        fclose(input);
    arguments[count] = NULL;
    if (log)
        fprintf(log, "launch %s: %d argument(s) from forward.txt%s\n", tile, count,
                input ? "" : " (none: the file could not be read)");
    const int init = sceUserServiceInitialize(NULL);
    int user = -1;
    const int foreground = sceUserServiceGetForegroundUser(&user);
    char title[16];
    int waited = 0;
    for (running_title(title); strcmp(title, tile) == 0 && waited < 60; waited++)
    {
        usleep(FORWARDER_WAIT_STEP_US);
        running_title(title);
    }
    if (log)
    {
        fprintf(log, "launch %s: user service %08x, foreground user %d (%08x); waited %d step(s) for the tile, "
                     "running now: '%s'\n",
                tile, (unsigned)init, user, (unsigned)foreground, waited, title);
        fflush(log);
    }
    lnc_app_param_t param = {sizeof(param), user, 0, 0, 0};
    int result = sceLncUtilLaunchApp(FORWARDER_TARGET, arguments, &param);
    if (log)
        fprintf(log, "launch %s: sceLncUtilLaunchApp(%s) = %08x\n", tile, FORWARDER_TARGET, (unsigned)result);
    if (result < 0)
    {
        result = sceSystemServiceLaunchApp(FORWARDER_TARGET, arguments, &param);
        if (log)
            fprintf(log, "launch %s: sceSystemServiceLaunchApp(%s) = %08x\n", tile, FORWARDER_TARGET,
                    (unsigned)result);
    }
    if (log)
        fclose(log);
    return result < 0;
}
