/*
 * Ghostship for the PlayStation 5 - what runs before the game's main.
 *
 * The game's main is its own (vendor/ghostship/src/port/Game.cpp), so the
 * console's start-up is a constructor: standard error into klog and the
 * shell's splash dismissed, and where a title may keep its files.
 *
 * A title sees its own folder (/app0, which is /data/homebrew/<TITLE_ID>) and
 * nothing else of /data:
 *
 *   /app0/sm64.o2r         the game's data, made from your own copy of Super Mario 64
 *                          (or baserom.us.z64 itself, which the title converts once)
 *   /app0/ghostship.o2r    Ghostship's own assets
 *   /app0/userdata/        settings, saves, logs, mods/
 *   /app0/env.txt          optional: NAME=value lines for the environment
 *
 * SPDX-License-Identifier: MIT
 */
#include <SDL_stdinc.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

#include "platform.h"

/* Both copies of the environment: the console's libc keeps what setenv sets
 * apart from the `environ` SDL copies. */
static void
set(const char *name, const char *value, int overwrite)
{
   setenv(name, value, overwrite);
   SDL_setenv(name, value, overwrite);
}

/* The game leaves through exit() from many places (its Quit, a first-run prompt
 * answered No): the shell is asked to close the title, as when main returns.
 * Without that the console shows a title that ended by itself as crashed. */
void catchReturnFromMain(int status);

static void
leave(void)
{
   static int left;

   if (!left++)
      catchReturnFromMain(0);
}

__attribute__((constructor)) static void
ps5_startup(void)
{
   platform_init(PS5_TITLE_NAME);
   atexit(leave);
   mkdir("/app0/userdata", 0777);
   /* PS5 DevLoop's grab takes the title's pictures from here, and removes them */
   mkdir("/app0/userdata/screenshots", 0777);
   chmod("/app0/userdata/screenshots", 0777);

   FILE *file = fopen("/app0/env.txt", "r");
   if (file) {
      char line[512];
      while (fgets(line, sizeof line, file)) {
         line[strcspn(line, "\r\n")] = 0;
         char *equals = strchr(line, '=');
         if (line[0] == '#' || !equals || equals == line)
            continue;
         *equals = 0;
         set(line, equals + 1, 1);
         say("env.txt: %s=%s", line, equals + 1);
      }
      fclose(file);
   }
}
