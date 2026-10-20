/* PS5GL compatibility shim for <SDL2/SDL_image.h> - NOT real SDL2_image.
 *
 * Real image decode/encode, backed by stb_image / stb_image_write
 * (compat/stb/) instead of libpng/libjpeg - already proven working on this
 * exact toolchain (see the ps5link-sdk README's "build stb_image with
 * STBI_NO_THREAD_LOCALS" note, and SM64_PS5/ps5gpu/third_party/stb_image.h,
 * the very copy this shim reuses). Deliberately not linking
 * ps5-payload-sdk-pacbrew's real libSDL2_image.a - see SDL.h's comment for
 * why the SDL2 package it comes bundled with is the wrong foundation here;
 * decoding alone might have worked from it, but pulling in one library from
 * a set built as a matched whole, when a known-good decoder already exists
 * for this toolchain, is not worth the risk for no real gain.
 *
 * Guarded on __PROSPERO__ exactly like the other shims.
 */
#if !defined(__PROSPERO__)
#error "PS5GL/compat/SDL2/SDL_image.h is the PS5-only compatibility shim - do not add PS5GL/compat to the include path for a non-PS5 build."
#endif
#ifndef PS5GL_COMPAT_SDL_IMAGE_H
#define PS5GL_COMPAT_SDL_IMAGE_H

#include "SDL.h"

#ifdef __cplusplus
extern "C" {
#endif

/* Decodes PNG/JPG/BMP/etc bytes (whatever stb_image itself recognises) into
 * an SDL_Surface, always as tightly-packed RGBA8 (stb_image asked for 4
 * channels regardless of the source format) - see SDL.h's comment on why
 * format->palette is therefore always NULL. NULL on failure; IMG_GetError()
 * then names it. */
SDL_Surface *IMG_Load(const char *file);
/* freesrc: nonzero frees rw (via SDL_free) after decoding, matching real
 * SDL_image's own convention - libmod_3d always passes 1. */
SDL_Surface *IMG_Load_RW(SDL_RWops *rw, int freesrc);
const char *IMG_GetError(void);

/* Encodes an RGBA8 surface to a PNG file via stb_image_write. Returns 0 on
 * success (matching real SDL_image's convention, which libmod_3d_paint.c's
 * own `== 0` check already assumes), nonzero on failure. Only 32bpp RGBA
 * surfaces are supported - anything else fails rather than writing garbage. */
int IMG_SavePNG(SDL_Surface *surface, const char *file);

#ifdef __cplusplus
}
#endif

#endif
