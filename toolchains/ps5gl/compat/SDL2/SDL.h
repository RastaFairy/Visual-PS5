/* PS5GL compatibility shim for <SDL2/SDL.h> / <SDL.h> - NOT real SDL2.
 *
 * Same idea as compat/GL/glew.h: covers exactly the SDL surface libmod_3d's
 * production code (not its standalone desktop test_*.c harnesses) actually
 * uses, wired to PS5's own kernel calls and ps5gpu.c instead of a real SDL2
 * port. Investigated and deliberately NOT using ps5-payload-sdk-pacbrew's
 * real libSDL2.a: its only PS5 GL backend is SDL_ps5osmesa.c - OSMesa,
 * Mesa's CPU software rasterizer - which would make every GL call through it
 * render on the CPU instead of ps5gpu.c's real AGC hardware path, and it
 * needs libOSMesa.so.8 present on the console, which nothing provides. Real
 * window/GL-context creation (SDL_CreateWindow, SDL_GL_CreateContext, etc.)
 * is only used by libmod_3d's desktop test_*.c files, never by the module
 * itself - ps5gpu_init() already brings up the display and AGC directly, so
 * those are harmless no-ops here, kept for completeness rather than because
 * anything in production calls them.
 *
 * Guarded on __PROSPERO__ exactly like the GL shims - see compat/GL/glew.h.
 */
#if !defined(__PROSPERO__)
#error "PS5GL/compat/SDL2/SDL.h is the PS5-only compatibility shim - do not add PS5GL/compat to the include path for a non-PS5 build."
#endif
#ifndef PS5GL_COMPAT_SDL_H
#define PS5GL_COMPAT_SDL_H

#include <stdint.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef int SDL_bool;
#define SDL_FALSE 0
#define SDL_TRUE  1

/* SDL's own fixed-width aliases - real SDL2 provides these too (for
 * compatibility with 1.2-era code); some of libmod_3d's files use them
 * directly instead of <stdint.h>'s own names. */
typedef uint8_t  Uint8;
typedef int8_t   Sint8;
typedef uint16_t Uint16;
typedef int16_t  Sint16;
typedef uint32_t Uint32;
typedef int32_t  Sint32;
typedef uint64_t Uint64;
typedef int64_t  Sint64;

/* SDL_endian.h - PS5's CPU (x86-64) is little-endian, always. Without this,
 * vendor/sdl-gpu's own "#if SDL_BYTEORDER == SDL_BIG_ENDIAN" checks compare
 * two undefined macros as 0 == 0 (true), silently taking its big-endian
 * branch on this little-endian target - confirmed the hard way: that branch
 * also has its own pixel-mask variables miscapitalized (rmask/gmask instead
 * of Rmask/Gmask), so it does not even compile, let alone run correctly. */
#define SDL_LIL_ENDIAN 1234
#define SDL_BIG_ENDIAN  4321
#define SDL_BYTEORDER   SDL_LIL_ENDIAN

/* SDL_pixels.h's struct - vendor/sdl-gpu's public SDL_gpu.h uses this by
 * value in several of its own function signatures. */
typedef struct SDL_Color { Uint8 r, g, b, a; } SDL_Color;

/* SDL_version.h - vendor/sdl-gpu's SDL_gpu.h checks SDL_VERSION_ATLEAST to
 * pick which of its own code paths to compile; reporting a recent, real SDL2
 * version here takes its modern paths, matching what this shim's actual
 * surface looks like. */
typedef struct SDL_version { Uint8 major, minor, patch; } SDL_version;
#define SDL_MAJOR_VERSION 2
#define SDL_MINOR_VERSION 28
#define SDL_PATCHLEVEL    0
#define SDL_VERSIONNUM(X,Y,Z) ((X)*1000 + (Y)*100 + (Z))
#define SDL_COMPILEDVERSION SDL_VERSIONNUM(SDL_MAJOR_VERSION, SDL_MINOR_VERSION, SDL_PATCHLEVEL)
#define SDL_VERSION_ATLEAST(X,Y,Z) (SDL_COMPILEDVERSION >= SDL_VERSIONNUM(X,Y,Z))

/* ---- surfaces ----
 * Deliberately shaped like real SDL_Surface's own layout (format/w/h/pixels/
 * pitch at the top level, format->palette/BytesPerPixel nested) since
 * libmod_3d_texture.c's surface_to_g3d() reads those fields directly, not
 * through an accessor. Images this shim decodes (see SDL2/SDL_image.h) are
 * always plain RGBA8 from stb_image, which never keeps a palette - so
 * format->palette is always NULL here and that branch in surface_to_g3d()
 * (the one converting palette images to ABGR8888) never actually triggers
 * for anything this shim produces, even though it is left in place. */
/* Every surface this shim ever produces is 32bpp RGBA8, byte order R,G,B,A
 * (matching SDL_PIXELFORMAT_RGBA32's own definition) - so the legacy
 * mask/shift/loss fields below are constants, not really "per format"
 * despite the struct shape, since there is only ever the one real format. */
typedef struct SDL_PixelFormat {
    void *palette;         /* always NULL - see above */
    uint8_t BytesPerPixel;
    uint32_t format;       /* always SDL_PIXELFORMAT_RGBA32 */
    uint8_t BitsPerPixel;
    uint32_t Rmask, Gmask, Bmask, Amask;
    uint8_t Rshift, Gshift, Bshift, Ashift;
    uint8_t Rloss, Gloss, Bloss, Aloss;   /* always 0 - full 8 bits/channel, nothing lost */
} SDL_PixelFormat;
/* Real: this shim's surfaces are always non-palette RGBA8, which always has
 * an alpha channel - true unconditionally, not just for the RGBA32 constant
 * specifically. */
#define SDL_ISPIXELFORMAT_ALPHA(format) ((void)(format), 1)
#define SDL_SWSURFACE 0   /* only surface "type" this shim has - accepted, ignored */

typedef struct SDL_Surface {
    SDL_PixelFormat *format;
    int w, h;
    int pitch;
    void *pixels;
    int owns_pixels;       /* internal: SDL_FreeSurface frees pixels+format only if this is set */
} SDL_Surface;

#define SDL_PIXELFORMAT_ABGR8888 0x376761ABu
#define SDL_PIXELFORMAT_RGBA32   0x36726758u

/* Real: builds a fresh RGBA8 surface (see the struct comment above - the
 * mask arguments are accepted but this shim only ever produces its one real
 * layout, same as everywhere else surfaces are created here). */
SDL_Surface *SDL_CreateRGBSurface(uint32_t flags, int width, int height, int depth,
                                   uint32_t Rmask, uint32_t Gmask, uint32_t Bmask, uint32_t Amask);
/* Real for the one case that matters, same as SDL_ConvertSurfaceFormat: a
 * non-palette RGBA8 source (everything this shim produces) is handed back as
 * a plain copy rather than genuinely reformatted, since there is only ever
 * the one real layout to convert to or from here. */
SDL_Surface *SDL_ConvertSurface(SDL_Surface *src, const SDL_PixelFormat *fmt, uint32_t flags);
/* Real: packs r/g/b (and always-opaque alpha) into this shim's one pixel
 * layout - fmt's own fields are trusted (matches whatever this shim itself
 * already set them to), not re-derived from scratch. */
uint32_t SDL_MapRGB(const SDL_PixelFormat *fmt, uint8_t r, uint8_t g, uint8_t b);

/* Real: builds a surface over EXISTING memory (does not copy or take
 * ownership) - matches libmod_3d_paint.c's use (wrapping its own canvas
 * pixels to hand to IMG_SavePNG). depth/pitch are trusted as given; only
 * 32bpp RGBA8 is meaningful to anything else in this shim. */
SDL_Surface *SDL_CreateRGBSurfaceWithFormatFrom(void *pixels, int width, int height, int depth, int pitch, uint32_t format);
/* Real for the one case that matters (see the palette note above): a
 * non-palette surface is returned as-is (a new reference, safe to
 * SDL_FreeSurface independently) rather than actually reformatting pixels,
 * since nothing this shim produces ever needs reformatting in practice. A
 * genuinely non-RGBA source would need real conversion this does not do. */
SDL_Surface *SDL_ConvertSurfaceFormat(SDL_Surface *src, uint32_t pixel_format, uint32_t flags);
void SDL_FreeSurface(SDL_Surface *surface);

/* ---- byte source ----
 * Real, but minimal: either a fixed const-memory span (SDL_RWFromConstMem,
 * for IMG_Load_RW - see SDL2/SDL_image.h) or an open FILE* (SDL_RWFromFile,
 * for vendor/sdl-gpu's own asset loading), with just enough of real SDL2's
 * generic RWops surface (read/seek/close) for that - no write, no generic
 * vtable a caller could install its own backend into. */
typedef struct SDL_RWops {
    const unsigned char *data;   /* NULL if file-backed - see below */
    long size;
    void *file;                  /* a FILE*, or NULL if memory-backed */
    long pos;                    /* memory-backed only: current read position */
} SDL_RWops;
SDL_RWops *SDL_RWFromConstMem(const void *mem, int size);
SDL_RWops *SDL_RWFromFile(const char *file, const char *mode);
long SDL_RWread(SDL_RWops *rw, void *ptr, size_t size, size_t maxnum);   /* returns objects read, like fread */
#define RW_SEEK_SET 0
#define RW_SEEK_CUR 1
#define RW_SEEK_END 2
long SDL_RWseek(SDL_RWops *rw, long offset, int whence);
int SDL_RWclose(SDL_RWops *rw);
/* File-backed only (the real use here: GPU_SaveSurface_RW saving to a file
 * opened via SDL_RWFromFile) - a memory-backed SDL_RWops is fixed-size and
 * read-only by construction in this shim (see SDL_RWFromConstMem), so
 * writing to one always reports 0 bytes written rather than corrupting
 * memory it does not own. */
size_t SDL_RWwrite(SDL_RWops *rw, const void *ptr, size_t size, size_t num);

/* No-op: this shim's surfaces never have a real palette (always NULL - see
 * the SDL_Surface/SDL_PixelFormat comments above), so there is nothing for
 * this to actually set. Takes a bare pointer rather than a real SDL_Palette*
 * (not implemented) since the one caller (vendor/sdl-gpu's own grayscale
 * image loader) only ever passes NULL through it here anyway. */
int SDL_SetPaletteColors(void *palette, const SDL_Color *colors, int firstcolor, int ncolors);

/* ---- files ---- */
void *SDL_LoadFile(const char *file, size_t *datasize);
void SDL_free(void *mem);
const char *SDL_GetError(void);

/* ---- time - real, via the same kernel calls ps5gpu.c's own fps counter
 * and the jit_test milestones already used. ---- */
uint32_t SDL_GetTicks(void);
void SDL_Delay(uint32_t ms);

/* ---- mouse - PS5 has none; DualSense input is a separate, not-yet-done
 * port. Both always report "no movement" rather than leaving the x/y
 * outputs uninitialized, so callers that only ever branch on the delta
 * being nonzero see consistently "nothing happened" instead of garbage. ---- */
SDL_bool SDL_GetRelativeMouseState(int *x, int *y);
void SDL_SetRelativeMouseMode(SDL_bool enabled);

/* ---- window / GL context - see the file comment: not used by the module
 * itself, only by its desktop test_*.c harnesses. Real windowing/GL-context
 * concepts do not exist in ps5gpu.c's model (it brings up the display and
 * AGC directly in ps5gpu_init(), no window involved) - these hand back
 * distinguishable non-NULL dummy values so calling code's own success
 * checks pass, and otherwise do nothing. ---- */
typedef struct SDL_Window SDL_Window;
typedef void *SDL_GLContext;
#define SDL_INIT_VIDEO 0x00000020u
#define SDL_WINDOW_OPENGL 0x00000002u
#define SDL_WINDOW_HIDDEN  0x00000008u
#define SDL_GL_CONTEXT_MAJOR_VERSION 17
#define SDL_GL_CONTEXT_MINOR_VERSION 18
#define SDL_GL_CONTEXT_PROFILE_MASK  21
#define SDL_GL_CONTEXT_PROFILE_COMPATIBILITY 0x2
#define SDL_GL_DEPTH_SIZE 6
int SDL_Init(uint32_t flags);
void SDL_Quit(void);
/* Subsystem tracking - real SDL2 lets a caller ask "is X already up" and
 * init/quit subsystems independently; this shim has exactly one subsystem
 * (video, brought up for real by ps5gl_init()/ps5gpu_init(), not by these),
 * always reported as already initialized so callers doing the standard
 * "only SDL_Init if nothing has" dance don't redundantly call SDL_Init. */
#define SDL_INIT_EVERYTHING 0x0000FFFFu
#define SDL_INIT_TIMER 0x00000001u
int SDL_WasInit(uint32_t flags);
int SDL_InitSubSystem(uint32_t flags);
void SDL_QuitSubSystem(uint32_t flags);

/* Filesystem/locale queries libmod_misc calls but PS5 has no meaningful
 * answer for (no real user profile paths, no OS locale service) - NULL is
 * real SDL2's own documented failure return for both path functions, and an
 * empty locale list is SDL_GetPreferredLocales()'s documented "unknown"
 * return, so callers already written against real SDL2 handle these. */
char *SDL_GetBasePath(void);
char *SDL_GetPrefPath(const char *org, const char *app);
typedef struct SDL_Locale { const char *language; const char *country; } SDL_Locale;
SDL_Locale *SDL_GetPreferredLocales(void);
int SDL_GL_SetAttribute(int attr, int value);
SDL_Window *SDL_CreateWindow(const char *title, int x, int y, int w, int h, uint32_t flags);
void SDL_DestroyWindow(SDL_Window *window);
SDL_GLContext SDL_GL_CreateContext(SDL_Window *window);
void SDL_GL_DeleteContext(SDL_GLContext context);
/* No-op: presentation for real happens through ps5gl_end_frame/
 * ps5gpu_end_frame, not a window swap - a caller relying on this call alone
 * to present a frame will need its render loop routed through ps5gl_end_frame
 * instead when this is wired up for real, not just made to compile. */
void SDL_GL_SwapWindow(SDL_Window *window);

/* More window/context surface, pulled in by vendor/sdl-gpu's own
 * renderer_GL_common.inl (SDL_gpu's real GL3/GL4 backend - see its own
 * comment history in ps5gl.h for why this exists at all). Same story as
 * everything above: there is exactly one "window", the whole display
 * ps5gpu_init() already owns, so these report fixed 1920x1080 and otherwise
 * do nothing real. A caller expecting an actual second window, multiple
 * windows, or real fullscreen toggling will not get one. */
#define SDL_GL_DOUBLEBUFFER 5
#define SDL_GL_CONTEXT_PROFILE_CORE 0x1
#define SDL_GL_RED_SIZE   1
#define SDL_GL_GREEN_SIZE 2
#define SDL_GL_BLUE_SIZE  3
#define SDL_GL_ALPHA_SIZE 4
#define SDL_WINDOW_SHOWN             0x00000004u
#define SDL_WINDOW_FULLSCREEN        0x00000001u
#define SDL_WINDOW_FULLSCREEN_DESKTOP 0x00001001u
#define SDL_WINDOWPOS_CENTERED 0x2FFF0000
typedef uint32_t SDL_WindowID;
SDL_Window *SDL_GetWindowFromID(SDL_WindowID id);
SDL_WindowID SDL_GetWindowID(SDL_Window *window);
void SDL_GetWindowSize(SDL_Window *window, int *w, int *h);
void SDL_SetWindowSize(SDL_Window *window, int w, int h);
void SDL_GL_GetDrawableSize(SDL_Window *window, int *w, int *h);
uint32_t SDL_GetWindowFlags(SDL_Window *window);
int SDL_SetWindowFullscreen(SDL_Window *window, uint32_t flags);
int SDL_GL_MakeCurrent(SDL_Window *window, SDL_GLContext context);
int SDL_GL_SetSwapInterval(int interval);
uint32_t SDL_GetColorKey(SDL_Surface *surface, uint32_t *key);   /* always returns nonzero (no colour key set) */

/* SDL's own allocator alias - real SDL2 lets a caller override the
 * underlying allocator; this shim always uses the plain libc one.
 * SDL_free above already covers the free side, real SDL2's own name too. */
void *SDL_malloc(size_t size);

#ifdef __cplusplus
}
#endif

#endif
