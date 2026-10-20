/* PS5 RetroArch - the RetroAchievements password the WebUI saved, forgotten once used.
 *
 * The WebUI writes a new password into /app0/config/webui.cfg (with an empty token, so the
 * new account signs in with it), and the title appends that file to RetroArch's config at
 * every start. Once RetroArch has signed in it keeps a token and clears its password, but
 * only in its own settings, and retroarch.cfg holds the old password until RetroArch next
 * saves it: patches/series 0130 calls this then, so the password stays in neither file
 * (/app0/config, a folder FTP can read). retroarch.cfg keeps its token.
 * Copyright (C) 2026 Mihawk
 * SPDX-License-Identifier: GPL-3.0-or-later
 */
#include <stdio.h>
#include <string.h>

/* Whether a config line sets the key name ("  cheevos_password = ..."). */
static int sets(const char *line, const char *name)
{
    const size_t length = strlen(name);
    while (*line == ' ' || *line == '\t')
        line++;
    if (strncmp(line, name, length) != 0)
        return 0;
    line += length;
    while (*line == ' ' || *line == '\t')
        line++;
    return *line == '=';
}

/* Removes the cheevos_password line, and the cheevos_token line when token_too, from the
 * config at path. Returns the lines removed, 0 when there were none (the file is left
 * alone), -1 when it could not be rewritten (the file is left alone too). */
int ps5_cheevos_forget_password(const char *path, int token_too)
{
    char line[1024], temporary[512];
    int removed = 0;
    FILE *in = fopen(path, "r"), *out;
    if (!in)
        return 0;
    snprintf(temporary, sizeof(temporary), "%s.tmp", path);
    out = fopen(temporary, "w");
    if (!out)
    {
        fclose(in);
        return -1;
    }
    /* shortcut: a line over 1023 bytes is copied in pieces, each checked as a line; the
     * WebUI writes no such line (its values have no line breaks and are short). */
    while (fgets(line, sizeof(line), in))
    {
        if (sets(line, "cheevos_password") || (token_too && sets(line, "cheevos_token")))
            removed++;
        else
            fputs(line, out);
    }
    fclose(in);
    if (fclose(out) != 0 || removed == 0)
    {
        remove(temporary);
        return removed ? -1 : 0;
    }
    return rename(temporary, path) == 0 ? removed : -1;
}
