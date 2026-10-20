/* Frame generation options shared by every menu (RetroArch's XMB and RGUI, ES-DE).
 *
 * The options live in /app0/config/framegen.cfg, in RetroArch's own config syntax, and the title
 * appends that file when it starts RetroArch (src/main.cpp), so a choice made in ES-DE or in
 * RetroArch's menu holds for the next game. Nothing here depends on RetroArch or ES-DE: a menu
 * reads and writes a struct ps5_fg_options and shows the names below.
 *
 * Copyright (C) 2026 Mihawk
 * SPDX-License-Identifier: GPL-3.0-or-later
 */
#ifndef PS5_FRAMEGEN_CONFIG_H
#define PS5_FRAMEGEN_CONFIG_H

#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define PS5_FG_CONFIG_PATH "/app0/config/framegen.cfg"

enum ps5_fg_item
{
    PS5_FG_ENABLE = 0,
    PS5_FG_TARGET,
    PS5_FG_METHOD,
    PS5_FG_CADENCE,
    PS5_FG_SIZE,
    PS5_FG_OSD,
    PS5_FG_RESET,
    PS5_FG_ITEM_COUNT
};

struct ps5_fg_options
{
    unsigned enable;  /* 0 off, 1 on */
    unsigned target;  /* 0 120 fps, 1 60 fps: the rate of the pictures the display gets */
    unsigned method;  /* 0 neural, 1 blend, 2 repeat */
    unsigned cadence; /* 0 measured, else core frames per new frame, 1 to 4 */
    unsigned size;    /* 0 4K, 1 1440p, 2 1080p, 3 720p: the most pixels the generator works at */
    unsigned osd;     /* 0 off, 1 status on screen */
};

static inline unsigned ps5_fg_choice_count(unsigned item)
{
    switch (item)
    {
    case PS5_FG_ENABLE:
    case PS5_FG_OSD:
        return 2;
    case PS5_FG_TARGET:
        return 2;
    case PS5_FG_METHOD:
        return 3;
    case PS5_FG_CADENCE:
        return 5;
    case PS5_FG_SIZE:
        return 4;
    default:
        return 1;
    }
}

static inline const char *ps5_fg_item_name(unsigned item)
{
    static const char *const names[PS5_FG_ITEM_COUNT] = {
        "Frame Generation",      "Target Framerate", "Method",
        "Content Frame Cadence", "Working Size",     "Status On Screen",
        "Recommended Settings",
    };
    return item < PS5_FG_ITEM_COUNT ? names[item] : "";
}

static inline const char *ps5_fg_item_help(unsigned item)
{
    static const char *const help[PS5_FG_ITEM_COUNT] = {
        "Makes the frames between a game's frames with a trained network, up to the Target "
        "Framerate.",
        "The frame rate of what you see. 120: a 60 fps game gets one made frame between each pair "
        "(30 fps games, three). "
        "60: a 30 fps game gets one; a 60 fps game is shown as it is. Changing it restarts the "
        "video output.",
        "Neural is the trained network. Blend and Repeat are the baselines to compare it with.",
        "Auto measures how often a game makes a new frame. Force 1 to 4 when a game's cadence is "
        "misjudged (30 fps games: 2).",
        "The most pixels the generator works at. Games that render larger are averaged down. "
        "Smaller is faster.",
        "Shows the method, the rate, the frame size and a count of generated frames over the game.",
        "Frame generation on, 120 fps, neural, auto cadence, up to 4K, status off.",
    };
    return item < PS5_FG_ITEM_COUNT ? help[item] : "";
}

/* The text of a choice (item's value index), or of the current value for an item with none. */
static inline const char *ps5_fg_choice_name(unsigned item, unsigned value)
{
    static const char *const on_off[] = {"Off", "On"};
    static const char *const rates[] = {"120 fps", "60 fps"};
    static const char *const methods[] = {"Neural", "Blend", "Repeat"};
    static const char *const cadence[] = {"Auto", "1", "2", "3", "4"};
    static const char *const sizes[] = {"Up to 4K", "Up to 1440p", "Up to 1080p", "Up to 720p"};
    switch (item)
    {
    case PS5_FG_ENABLE:
    case PS5_FG_OSD:
        return on_off[value & 1];
    case PS5_FG_TARGET:
        return value < 2 ? rates[value] : "";
    case PS5_FG_METHOD:
        return value < 3 ? methods[value] : "";
    case PS5_FG_CADENCE:
        return value < 5 ? cadence[value] : "";
    case PS5_FG_SIZE:
        return value < 4 ? sizes[value] : "";
    default:
        return "";
    }
}

static inline void ps5_fg_defaults(struct ps5_fg_options *o)
{
    o->enable = 1;
    o->target = 0;
    o->method = 0;
    o->cadence = 0;
    o->size = 0;
    o->osd = 0;
}

/* An item's value as its choice index. */
static inline unsigned ps5_fg_get(const struct ps5_fg_options *o, unsigned item)
{
    switch (item)
    {
    case PS5_FG_ENABLE:
        return o->enable;
    case PS5_FG_TARGET:
        return o->target ? 1 : 0;
    case PS5_FG_METHOD:
        return o->method;
    case PS5_FG_CADENCE:
        return o->cadence;
    case PS5_FG_SIZE:
        return o->size;
    case PS5_FG_OSD:
        return o->osd;
    default:
        return 0;
    }
}

static inline void ps5_fg_set(struct ps5_fg_options *o, unsigned item, unsigned value)
{
    if (item == PS5_FG_RESET)
    {
        ps5_fg_defaults(o);
        return;
    }
    value %= ps5_fg_choice_count(item);
    switch (item)
    {
    case PS5_FG_ENABLE:
        o->enable = value;
        break;
    case PS5_FG_TARGET:
        o->target = value;
        break;
    case PS5_FG_METHOD:
        o->method = value;
        break;
    case PS5_FG_CADENCE:
        o->cadence = value;
        break;
    case PS5_FG_SIZE:
        o->size = value;
        break;
    case PS5_FG_OSD:
        o->osd = value;
        break;
    default:
        break;
    }
}

/* Moves an item by one choice, wrapping. */
static inline void ps5_fg_step(struct ps5_fg_options *o, unsigned item, int direction)
{
    const unsigned count = ps5_fg_choice_count(item);
    if (item == PS5_FG_RESET)
    {
        ps5_fg_defaults(o);
        return;
    }
    ps5_fg_set(o, item, (ps5_fg_get(o, item) + (direction < 0 ? count - 1 : 1)) % count);
}

/* The most pixels the generator works at for a size choice. */
static inline unsigned long ps5_fg_size_pixels(unsigned size)
{
    static const unsigned long pixels[] = {3840ul * 2160ul, 2560ul * 1440ul, 1920ul * 1080ul,
                                           1280ul * 720ul};
    return pixels[size < 4 ? size : 0];
}

static inline int ps5_fg_save(const struct ps5_fg_options *o)
{
    FILE *file = fopen(PS5_FG_CONFIG_PATH, "w");
    if (!file)
        return -1;
    fprintf(file, "video_framegen = \"%s\"\n", o->enable ? "true" : "false");
    fprintf(file, "video_framegen_auto = \"true\"\n");
    fprintf(file, "video_framegen_target = \"%u\"\n", o->target ? 60 : 120);
    fprintf(file, "video_framegen_method = \"%u\"\n", o->method);
    fprintf(file, "video_framegen_cadence = \"%u\"\n", o->cadence);
    fprintf(file, "video_framegen_size = \"%u\"\n", o->size);
    fprintf(file, "video_framegen_osd = \"%s\"\n", o->osd ? "true" : "false");
    return fclose(file);
}

/* Reads the file; what it lacks keeps the value given in o. */
static inline void ps5_fg_load(struct ps5_fg_options *o)
{
    char line[160];
    FILE *file = fopen(PS5_FG_CONFIG_PATH, "r");
    if (!file)
        return;
    while (fgets(line, sizeof(line), file))
    {
        char *equals = strchr(line, '=');
        char *value;
        unsigned number;
        if (!equals)
            continue;
        *equals = '\0';
        value = equals + 1;
        while (*value == ' ' || *value == '"')
            value++;
        number = (unsigned)strtoul(value, NULL, 10);
        if (strstr(line, "video_framegen_method"))
            o->method = number % 3;
        else if (strstr(line, "video_framegen_cadence"))
            o->cadence = number % 5;
        else if (strstr(line, "video_framegen_size"))
            o->size = number % 4;
        else if (strstr(line, "video_framegen_osd"))
            o->osd = strncmp(value, "true", 4) == 0;
        else if (strstr(line, "video_framegen_target"))
            o->target = number == 60;
        else if (strstr(line, "video_framegen_auto"))
            continue; /* (older files: the rate is the target's now) */
        else if (strstr(line, "video_framegen"))
            o->enable = strncmp(value, "true", 4) == 0;
    }
    fclose(file);
}

#endif
