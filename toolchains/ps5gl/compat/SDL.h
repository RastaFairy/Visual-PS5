/* PS5GL compatibility shim - redirects the bare <SDL.h> spelling to the
 * canonical compat/SDL2/SDL.h (some libmod_3d files use one spelling, some
 * the other - see its own comment for why this shim exists). */
#if !defined(__PROSPERO__)
#error "PS5GL/compat/SDL.h is the PS5-only compatibility shim - do not add PS5GL/compat to the include path for a non-PS5 build."
#endif
#include "SDL2/SDL.h"
