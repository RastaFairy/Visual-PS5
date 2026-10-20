/*
 * Dusklight for the PlayStation 5 - what runs before the game's main.
 *
 * Dusklight's main is its own (vendor/dusklight/src/dusk/main.cpp), so the
 * console's start-up is a constructor: standard error into klog and the
 * shell's splash dismissed, and the folder SDL derives its paths from.
 *
 * SPDX-License-Identifier: MIT
 */
#include <SDL3/SDL_stdinc.h>

#include "platform.h"

__attribute__((constructor)) static void
ps5_startup(void)
{
   platform_init(PS5_TITLE_NAME);
   /* SDL_GetPrefPath is $XDG_DATA_HOME/<org>/<app>/: saves and settings. A title
    * sees its own folder (/app0, which is /data/homebrew/<TITLE_ID>) and nothing
    * else of /data, so they live there. Set in SDL's own copy of the environment,
    * which is all SDL_getenv reads: the console's libc keeps what setenv sets
    * apart from the `environ` SDL copies. */
   SDL_SetEnvironmentVariable(SDL_GetEnvironment(), "XDG_DATA_HOME", "/app0/userdata", true);
   SDL_SetEnvironmentVariable(SDL_GetEnvironment(), "HOME", "/app0/userdata", true);
}
