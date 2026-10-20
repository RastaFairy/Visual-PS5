/* PS5GL compatibility shim for <GL/glext.h> - see glew.h in this same
 * directory for why this exists and the __PROSPERO__ guard below. Everything
 * PS5GL offers is already declared by ps5gl.h; nothing extra to add here. */
#if !defined(__PROSPERO__)
#error "PS5GL/compat/GL/glext.h is the PS5-only compatibility shim - do not add PS5GL/compat to the include path for a non-PS5 build."
#endif
#ifndef PS5GL_COMPAT_GLEXT_H
#define PS5GL_COMPAT_GLEXT_H
#include "ps5gl.h"
#endif
