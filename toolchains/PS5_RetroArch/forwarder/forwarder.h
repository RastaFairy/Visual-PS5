/* PS5 RetroArch - what a Game Forwarder tile (forwarder/tile.c) and its launch payload
 * (forwarder/launch.c) share.
 *
 * Copyright (C) 2026 Mihawk
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * A tile tells the payload which tile it is by writing its title id over
 * FORWARDER_SLOT_MARKER in the payload's bytes before it sends them; the payload then reads
 * that tile's forward.txt. No file is written for the hand-over, so two tiles cannot race.
 */
#ifndef PS5_RETROARCH_FORWARDER_H
#define PS5_RETROARCH_FORWARDER_H

#include <stddef.h>

/* The payload's slot holds this until a tile writes its title id over it. */
#define FORWARDER_SLOT_MARKER "PS5RA-FORWARDER-TILE-ID-SLOT"
#define FORWARDER_SLOT_SIZE 32
/* A title id and its NUL: four capitals and five digits (PPSA99170). */
#define FORWARDER_ID_SIZE 10
/* The arguments a tile's forward.txt may hold, one a line, and the longest line. */
#define FORWARDER_MAX_ARGUMENTS 16
#define FORWARDER_MAX_ARGUMENT 512

static inline int forwarder_valid_id(const char *id, size_t length)
{
    if (!id || length != 9)
        return 0;
    for (size_t i = 0; i < 9; i++)
        if (i < 4 ? !(id[i] >= 'A' && id[i] <= 'Z') : !(id[i] >= '0' && id[i] <= '9'))
            return 0;
    return 1;
}

int forwarder_title_id(const char *param, char id[FORWARDER_ID_SIZE]);
int forwarder_stamp(char *payload, long size, const char *id);

#endif
