/* Implementation of the SDL/SDL_image compatibility shims - see
 * compat/SDL2/SDL.h and compat/SDL2/SDL_image.h for what these are and why
 * they exist. Only built for PS5 (__PROSPERO__), same as the headers. */
#if !defined(__PROSPERO__)
#error "ps5gl_sdl_compat.c is PS5-only - see compat/SDL2/SDL.h"
#endif

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "SDL.h"
#include "SDL_image.h"
#include "GL/glew.h"

#define STB_IMAGE_IMPLEMENTATION
#define STBI_NO_THREAD_LOCALS   /* the console's libc has no __emutls_get_address - see FINDINGS.md */
#include "stb_image.h"

#define STB_IMAGE_WRITE_IMPLEMENTATION
#include "stb_image_write.h"

extern unsigned long long sceKernelGetProcessTimeCounter(void);
extern unsigned long long sceKernelGetProcessTimeCounterFrequency(void);
extern int nanosleep(const void *req, void *rem);

/* ---- surfaces ----
 * Every SDL_PixelFormat this shim ever hands out describes the one real
 * layout it works in - see the struct's own comment in SDL.h. */
static void fill_rgba32_format(SDL_PixelFormat *f) {
    f->palette = NULL;
    f->BytesPerPixel = 4;
    f->format = SDL_PIXELFORMAT_RGBA32;
    f->BitsPerPixel = 32;
    f->Rmask = 0x000000FFu; f->Gmask = 0x0000FF00u; f->Bmask = 0x00FF0000u; f->Amask = 0xFF000000u;
    f->Rshift = 0; f->Gshift = 8; f->Bshift = 16; f->Ashift = 24;
    f->Rloss = 0; f->Gloss = 0; f->Bloss = 0; f->Aloss = 0;
}

SDL_Surface *SDL_CreateRGBSurfaceWithFormatFrom(void *pixels, int width, int height, int depth, int pitch, uint32_t format) {
    (void)depth; (void)format;   /* only 32bpp RGBA8 is meaningful here - see SDL.h */
    SDL_Surface *s = (SDL_Surface *)malloc(sizeof(SDL_Surface));
    SDL_PixelFormat *f = (SDL_PixelFormat *)malloc(sizeof(SDL_PixelFormat));
    if (!s || !f) { free(s); free(f); return NULL; }
    fill_rgba32_format(f);
    s->format = f;
    s->w = width; s->h = height; s->pitch = pitch;
    s->pixels = pixels;
    s->owns_pixels = 0;   /* wraps caller memory - SDL_FreeSurface must not free it */
    return s;
}

/* Real for the one layout that exists here - see fill_rgba32_format. */
SDL_Surface *SDL_CreateRGBSurface(uint32_t flags, int width, int height, int depth,
                                   uint32_t Rmask, uint32_t Gmask, uint32_t Bmask, uint32_t Amask) {
    (void)flags; (void)depth; (void)Rmask; (void)Gmask; (void)Bmask; (void)Amask;
    void *pixels = malloc((size_t)width * (size_t)height * 4);
    if (!pixels) return NULL;
    SDL_Surface *s = (SDL_Surface *)malloc(sizeof(SDL_Surface));
    SDL_PixelFormat *f = (SDL_PixelFormat *)malloc(sizeof(SDL_PixelFormat));
    if (!s || !f) { free(s); free(f); free(pixels); return NULL; }
    fill_rgba32_format(f);
    s->format = f; s->w = width; s->h = height; s->pitch = width * 4;
    s->pixels = pixels;
    s->owns_pixels = 1;
    return s;
}

/* Real for the one case that matters - see its own comment in SDL.h. */
SDL_Surface *SDL_ConvertSurface(SDL_Surface *src, const SDL_PixelFormat *fmt, uint32_t flags) {
    (void)fmt; (void)flags;
    if (!src) return NULL;
    SDL_Surface *s = (SDL_Surface *)malloc(sizeof(SDL_Surface));
    SDL_PixelFormat *f = (SDL_PixelFormat *)malloc(sizeof(SDL_PixelFormat));
    size_t bytes = (size_t)src->pitch * (size_t)src->h;
    void *pixels = malloc(bytes);
    if (!s || !f || !pixels) { free(s); free(f); free(pixels); return NULL; }
    fill_rgba32_format(f);
    memcpy(pixels, src->pixels, bytes);
    s->format = f; s->w = src->w; s->h = src->h; s->pitch = src->pitch;
    s->pixels = pixels;
    s->owns_pixels = 1;
    return s;
}

uint32_t SDL_MapRGB(const SDL_PixelFormat *fmt, uint8_t r, uint8_t g, uint8_t b) {
    return ((uint32_t)r << fmt->Rshift) | ((uint32_t)g << fmt->Gshift) | ((uint32_t)b << fmt->Bshift) | (0xFFu << fmt->Ashift);
}

SDL_Surface *SDL_ConvertSurfaceFormat(SDL_Surface *src, uint32_t pixel_format, uint32_t flags) {
    (void)pixel_format; (void)flags;
    /* Real conversion is not implemented - see SDL.h's comment on why the
     * one caller of this (the palette branch in surface_to_g3d) never
     * actually triggers for anything this shim's IMG_Load produces. If it
     * ever is reached, refusing is safer than silently handing back
     * mis-tagged pixel data. */
    if (src && src->format && src->format->palette) return NULL;
    if (!src) return NULL;
    SDL_Surface *s = (SDL_Surface *)malloc(sizeof(SDL_Surface));
    SDL_PixelFormat *f = (SDL_PixelFormat *)malloc(sizeof(SDL_PixelFormat));
    if (!s || !f) { free(s); free(f); return NULL; }
    *f = *src->format;
    *s = *src;
    s->format = f;
    s->owns_pixels = 0;   /* shares src's pixel memory - caller must not double-free */
    return s;
}

void SDL_FreeSurface(SDL_Surface *surface) {
    if (!surface) return;
    if (surface->owns_pixels) free(surface->pixels);
    free(surface->format);
    free(surface);
}

/* ---- RWops ---- */
SDL_RWops *SDL_RWFromConstMem(const void *mem, int size) {
    SDL_RWops *rw = (SDL_RWops *)malloc(sizeof(SDL_RWops));
    if (!rw) return NULL;
    rw->data = (const unsigned char *)mem;
    rw->size = size;
    rw->file = NULL;
    rw->pos = 0;
    return rw;
}

SDL_RWops *SDL_RWFromFile(const char *file, const char *mode) {
    FILE *f = fopen(file, mode);
    if (!f) return NULL;
    SDL_RWops *rw = (SDL_RWops *)malloc(sizeof(SDL_RWops));
    if (!rw) { fclose(f); return NULL; }
    rw->data = NULL;
    rw->size = 0;
    rw->file = f;
    rw->pos = 0;
    return rw;
}

long SDL_RWread(SDL_RWops *rw, void *ptr, size_t size, size_t maxnum) {
    if (!rw || size == 0) return 0;
    if (rw->file) return (long)fread(ptr, size, maxnum, (FILE *)rw->file);
    long avail = rw->size - rw->pos;
    if (avail < 0) avail = 0;
    long want_bytes = (long)(size * maxnum);
    long bytes = want_bytes < avail ? want_bytes : avail;
    bytes -= bytes % (long)size;   /* only whole objects, matching fread's own contract */
    if (bytes > 0) memcpy(ptr, rw->data + rw->pos, (size_t)bytes);
    rw->pos += bytes;
    return bytes / (long)size;
}

long SDL_RWseek(SDL_RWops *rw, long offset, int whence) {
    if (!rw) return -1;
    if (rw->file) {
        int w = whence == RW_SEEK_SET ? SEEK_SET : whence == RW_SEEK_CUR ? SEEK_CUR : SEEK_END;
        if (fseek((FILE *)rw->file, offset, w) != 0) return -1;
        return ftell((FILE *)rw->file);
    }
    long base = whence == RW_SEEK_SET ? 0 : whence == RW_SEEK_CUR ? rw->pos : rw->size;
    long np = base + offset;
    if (np < 0 || np > rw->size) return -1;
    rw->pos = np;
    return np;
}

int SDL_RWclose(SDL_RWops *rw) {
    if (!rw) return 0;
    if (rw->file) fclose((FILE *)rw->file);
    free(rw);
    return 0;
}

void SDL_GL_SwapWindow(SDL_Window *window) { (void)window; /* no-op - see SDL.h */ }

size_t SDL_RWwrite(SDL_RWops *rw, const void *ptr, size_t size, size_t num) {
    if (!rw || !rw->file) return 0;   /* memory-backed is read-only - see SDL.h */
    return fwrite(ptr, size, num, (FILE *)rw->file);
}

int SDL_SetPaletteColors(void *palette, const SDL_Color *colors, int firstcolor, int ncolors) {
    (void)palette; (void)colors; (void)firstcolor; (void)ncolors;
    return 0;   /* no-op - see SDL.h */
}

int SDL_WasInit(uint32_t flags) { (void)flags; return (int)SDL_INIT_EVERYTHING; }
int SDL_InitSubSystem(uint32_t flags) { (void)flags; return 0; }
void SDL_QuitSubSystem(uint32_t flags) { (void)flags; }

char *SDL_GetBasePath(void) { return NULL; }
char *SDL_GetPrefPath(const char *org, const char *app) { (void)org; (void)app; return NULL; }
SDL_Locale *SDL_GetPreferredLocales(void) { return NULL; }

/* ---- files ---- */
void *SDL_LoadFile(const char *file, size_t *datasize) {
    FILE *f = fopen(file, "rb");
    if (!f) return NULL;
    fseek(f, 0, SEEK_END);
    long size = ftell(f);
    fseek(f, 0, SEEK_SET);
    if (size < 0) { fclose(f); return NULL; }
    void *buf = malloc((size_t)size);
    if (!buf) { fclose(f); return NULL; }
    size_t got = fread(buf, 1, (size_t)size, f);
    fclose(f);
    if (got != (size_t)size) { free(buf); return NULL; }
    if (datasize) *datasize = (size_t)size;
    return buf;
}
void SDL_free(void *mem) { free(mem); }

static const char *s_sdl_error = "";
const char *SDL_GetError(void) { return s_sdl_error; }

/* ---- time ---- */
uint32_t SDL_GetTicks(void) {
    static unsigned long long freq;
    if (!freq) freq = sceKernelGetProcessTimeCounterFrequency();
    unsigned long long now = sceKernelGetProcessTimeCounter();
    return (uint32_t)((now * 1000ULL) / (freq ? freq : 1));
}
void SDL_Delay(uint32_t ms) {
    struct { long sec; long nsec; } ts;
    ts.sec = ms / 1000; ts.nsec = (long)(ms % 1000) * 1000000L;
    nanosleep(&ts, NULL);
}

/* ---- mouse - always "no movement", see SDL.h ---- */
SDL_bool SDL_GetRelativeMouseState(int *x, int *y) { if (x) *x = 0; if (y) *y = 0; return SDL_FALSE; }
void SDL_SetRelativeMouseMode(SDL_bool enabled) { (void)enabled; }

/* ---- window / GL context - inert, see SDL.h ---- */
int SDL_Init(uint32_t flags) { (void)flags; return 0; }
void SDL_Quit(void) {}
int SDL_GL_SetAttribute(int attr, int value) { (void)attr; (void)value; return 0; }
SDL_Window *SDL_CreateWindow(const char *title, int x, int y, int w, int h, uint32_t flags) {
    (void)title; (void)x; (void)y; (void)w; (void)h; (void)flags;
    return (SDL_Window *)1;   /* SDL_Window is opaque (matches real SDL2) - a dummy non-NULL value, never dereferenced */
}
void SDL_DestroyWindow(SDL_Window *window) { (void)window; }
SDL_GLContext SDL_GL_CreateContext(SDL_Window *window) { (void)window; return (SDL_GLContext)1; }
void SDL_GL_DeleteContext(SDL_GLContext context) { (void)context; }

/* One "window", the whole 1920x1080 display ps5gpu_init() already owns - see
 * SDL.h's own comment on this whole block. */
SDL_Window *SDL_GetWindowFromID(SDL_WindowID id) { (void)id; return (SDL_Window *)1; }
SDL_WindowID SDL_GetWindowID(SDL_Window *window) { (void)window; return 1; }
void SDL_GetWindowSize(SDL_Window *window, int *w, int *h) { (void)window; if (w) *w = 1920; if (h) *h = 1080; }
void SDL_SetWindowSize(SDL_Window *window, int w, int h) { (void)window; (void)w; (void)h; }
void SDL_GL_GetDrawableSize(SDL_Window *window, int *w, int *h) { (void)window; if (w) *w = 1920; if (h) *h = 1080; }
uint32_t SDL_GetWindowFlags(SDL_Window *window) { (void)window; return SDL_WINDOW_SHOWN | SDL_WINDOW_OPENGL; }
int SDL_SetWindowFullscreen(SDL_Window *window, uint32_t flags) { (void)window; (void)flags; return 0; }
int SDL_GL_MakeCurrent(SDL_Window *window, SDL_GLContext context) { (void)window; (void)context; return 0; }
int SDL_GL_SetSwapInterval(int interval) { (void)interval; return 0; }
uint32_t SDL_GetColorKey(SDL_Surface *surface, uint32_t *key) { (void)surface; (void)key; return 1; /* no colour key set, matches SDL's own error return */ }
void *SDL_malloc(size_t size) { return malloc(size); }

/* ---- SDL_image ---- */
static SDL_Surface *surface_from_stb(unsigned char *pixels, int w, int h) {
    if (!pixels) return NULL;
    SDL_Surface *s = (SDL_Surface *)malloc(sizeof(SDL_Surface));
    SDL_PixelFormat *f = (SDL_PixelFormat *)malloc(sizeof(SDL_PixelFormat));
    if (!s || !f) { free(s); free(f); stbi_image_free(pixels); return NULL; }
    fill_rgba32_format(f);   /* stb_image always decodes to plain RGBA8 - see SDL.h */
    s->format = f; s->w = w; s->h = h; s->pitch = w * 4;
    s->pixels = pixels;
    s->owns_pixels = 1;   /* SDL_FreeSurface must stbi_image_free this - see below */
    return s;
}

SDL_Surface *IMG_Load(const char *file) {
    int w, h, channels;
    unsigned char *pixels = stbi_load(file, &w, &h, &channels, 4);
    if (!pixels) { s_sdl_error = stbi_failure_reason(); return NULL; }
    return surface_from_stb(pixels, w, h);
}

SDL_Surface *IMG_Load_RW(SDL_RWops *rw, int freesrc) {
    if (!rw) return NULL;
    /* Memory-backed only - see SDL.h. A file-backed SDL_RWops (from
     * SDL_RWFromFile) would need reading through SDL_RWread first; nothing
     * in this codebase combines the two, so that path is not implemented. */
    int w, h, channels;
    unsigned char *pixels = rw->file ? NULL : stbi_load_from_memory(rw->data, (int)rw->size, &w, &h, &channels, 4);
    if (freesrc) SDL_RWclose(rw);   /* not free(rw) directly - correctly closes a file-backed one too */
    if (!pixels) { s_sdl_error = stbi_failure_reason(); return NULL; }
    return surface_from_stb(pixels, w, h);
}

const char *IMG_GetError(void) { return s_sdl_error; }

int IMG_SavePNG(SDL_Surface *surface, const char *file) {
    if (!surface || !surface->pixels || surface->format->BytesPerPixel != 4) return 1;
    return stbi_write_png(file, surface->w, surface->h, 4, surface->pixels, surface->pitch) ? 0 : 1;
}

/* ---- GLEW compatibility shim (compat/GL/glew.h) - not real GLEW, see there ---- */
GLboolean glewExperimental = GL_FALSE;
GLenum glewInit(void) { return GLEW_OK; }
const GLubyte *glewGetErrorString(GLenum error) { (void)error; return (const GLubyte *)"PS5GL: glewInit never fails, see compat/GL/glew.h"; }
int glewIsExtensionSupported(const char *name) { (void)name; return 0; }
