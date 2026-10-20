/* PS5GL compatibility shim for <GL/glew.h> - NOT a real GLEW.
 *
 * Exists so callers written against desktop GL (which typically #include
 * <GL/glew.h> for its function-pointer-loading trick) can target PS5GL
 * without a source change: this shim's directory must be added to the
 * PS5-target build's include path AHEAD of any real GLEW, so this file is
 * found instead. It never activates by accident on another platform - the
 * #error below guards on __PROSPERO__, which only ps5-payload-sdk's
 * prospero-clang predefines; a stray -I into this directory on a normal
 * Linux/Windows build fails the build loudly here rather than silently
 * replacing the real GLEW.
 *
 * Unlike real GLEW, PS5GL's gl* entry points are plain functions (see
 * ps5gl.h), not runtime-loaded function pointers - there is exactly one
 * implementation, known at link time, so there is nothing for glewInit() to
 * actually load. It exists only so calling code's own
 * "glewInit(); if (result != GLEW_OK) ..." pattern still compiles and passes.
 */
#if !defined(__PROSPERO__)
#error "PS5GL/compat/GL/glew.h is the PS5-only compatibility shim - do not add PS5GL/compat to the include path for a non-PS5 build."
#endif
#ifndef PS5GL_COMPAT_GLEW_H
#define PS5GL_COMPAT_GLEW_H

#include "ps5gl.h"

#define GLEW_OK 0

#ifdef __cplusplus
extern "C" {
#endif

/* Real GLEW code often checks/sets this before glewInit(). Kept as a real,
 * writable variable so that code compiles and runs unchanged; PS5GL ignores
 * its value. */
extern GLboolean glewExperimental;

/* Always returns GLEW_OK - there is no loading step to fail (see above). */
GLenum glewInit(void);
const GLubyte *glewGetErrorString(GLenum error);

/* Always returns 0 (false/unsupported) - honestly, not as a stub: PS5GL has
 * no optional GL extensions at all (see glGetString(GL_EXTENSIONS) in
 * ps5gl.h, which always answers ""), so every extension really is
 * unsupported. This is what lets vendor/sdl-gpu's own isExtensionSupported()
 * (renderer_GL_common.inl) compile and run against PS5GL unmodified - it
 * already falls back correctly when an extension is reported missing, since
 * real GL drivers report that too. */
int glewIsExtensionSupported(const char *name);

#ifdef __cplusplus
}
#endif

#endif
