/* PS5 RetroArch - the frontend the title starts with (docs/FRONTENDS.md).
 *
 * Copyright (C) 2026 Mihawk
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * /app0/config/frontend.cfg holds one line, in RetroArch's configuration style:
 *
 *   frontend_start = "ask"         the picker, at every launch from the home screen
 *   frontend_start = "retroarch"   RetroArch, straight away
 *   frontend_start = "es-de"       EmulationStation, straight away
 *
 * The picker writes it (its Remember switch), and so does the WebUI's "Start with"
 * setting; eboot.bin reads it at a launch from the home screen, where holding L1 while
 * the title starts opens the picker anyway (src/frontend_mode_ps5.cpp). A missing file,
 * or one that says anything else, is "ask". Header-only, so the picker, which is built
 * the template's way (tools/build-picker.sh), carries the same code.
 */
#ifndef PS5_RETROARCH_FRONTEND_CHOICE_H
#define PS5_RETROARCH_FRONTEND_CHOICE_H

#include <stdio.h>
#include <string.h>
#include <sys/stat.h>

#define PS5_FRONTEND_CHOICE_PATH "/app0/config/frontend.cfg"
#define PS5_FRONTEND_CHOICE_KEY "frontend_start"
#define PS5_FRONTEND_CHOICE_SIZE 16

/* The choice a value names ("ask", "retroarch", "es-de"), or NULL. */
static inline const char *ps5_frontend_choice_name(const char *value)
{
    static const char *const names[] = {"ask", "retroarch", "es-de"};
    for (size_t i = 0; value && i < sizeof(names) / sizeof(names[0]); i++)
        if (strcmp(value, names[i]) == 0)
            return names[i];
    return NULL;
}

/* The choice the file holds; "ask" when it holds none. */
static inline const char *ps5_frontend_choice_read(const char *path)
{
    const char *choice = "ask";
    FILE *file = fopen(path, "r");
    if (!file)
        return choice;
    char line[256];
    while (fgets(line, sizeof(line), file))
    {
        char key[64], value[PS5_FRONTEND_CHOICE_SIZE];
        if (sscanf(line, " %63[^= ] = \"%15[^\"]\"", key, value) == 2 &&
            strcmp(key, PS5_FRONTEND_CHOICE_KEY) == 0 && ps5_frontend_choice_name(value))
            choice = ps5_frontend_choice_name(value);
    }
    fclose(file);
    return choice;
}

/* Writes the choice (a temporary file renamed over the old one); 0, or -1 when the
 * choice is not one or the file cannot be written. */
static inline int ps5_frontend_choice_write(const char *path, const char *choice)
{
    const char *name = ps5_frontend_choice_name(choice);
    char temporary[512];
    if (!name || snprintf(temporary, sizeof(temporary), "%s.tmp", path) >= (int)sizeof(temporary))
        return -1;
    FILE *file = fopen(temporary, "w");
    if (!file)
        return -1;
    const int written = fprintf(file, "%s = \"%s\"\n", PS5_FRONTEND_CHOICE_KEY, name);
    if (fclose(file) != 0 || written <= 0)
    {
        remove(temporary);
        return -1;
    }
    /* FTP runs as another user: the file stays reachable, as the title's others are. */
    chmod(temporary, 0777); /* FTP's reach: the title's files are 0777 */
    if (rename(temporary, path) != 0)
    {
        remove(temporary);
        return -1;
    }
    return 0;
}

#endif
