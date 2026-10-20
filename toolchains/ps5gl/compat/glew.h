/* PS5GL compatibility shim - redirects the bare <glew.h> spelling (used by
 * vendor/sdl-gpu's own SDL_gpu_OpenGL_3.h/_4.h) to the canonical
 * compat/GL/glew.h - see its own comment for why this shim exists. */
#if !defined(__PROSPERO__)
#error "PS5GL/compat/glew.h is the PS5-only compatibility shim - do not add PS5GL/compat to the include path for a non-PS5 build."
#endif
#include "GL/glew.h"
