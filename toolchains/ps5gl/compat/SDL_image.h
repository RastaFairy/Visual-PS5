/* PS5GL compatibility shim - redirects the bare <SDL_image.h> spelling to the
 * canonical compat/SDL2/SDL_image.h - see its own comment for why this
 * shim exists. */
#if !defined(__PROSPERO__)
#error "PS5GL/compat/SDL_image.h is the PS5-only compatibility shim - do not add PS5GL/compat to the include path for a non-PS5 build."
#endif
#include "SDL2/SDL_image.h"
