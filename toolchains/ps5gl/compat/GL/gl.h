/* PS5GL compatibility shim for <GL/gl.h> - see glew.h in this same directory
 * for why this exists and the __PROSPERO__ guard below. */
#if !defined(__PROSPERO__)
#error "PS5GL/compat/GL/gl.h is the PS5-only compatibility shim - do not add PS5GL/compat to the include path for a non-PS5 build."
#endif
#ifndef PS5GL_COMPAT_GL_H
#define PS5GL_COMPAT_GL_H
#include "ps5gl.h"
#endif
