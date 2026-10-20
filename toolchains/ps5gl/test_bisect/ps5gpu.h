/* ps5gpu - a small GPU layer for PS5 homebrew built as a real title by ps5link.
 *
 * This is the reusable distillation of the bring-up work in
 * PS5SDK/tools/ps5link (clear_test.c, mesh_test.c, tex_test.c,
 * mesh_tex_test.c, mesh_depth_test.c), each of which proved one piece on
 * hardware. See the project_ps5link_gpu_render memory for how each register
 * value was arrived at - most of them were expensive to find.
 *
 * It offers exactly one shader pair: textured geometry multiplied by a
 * per-vertex colour. That is not a limitation of taste but of tooling - there
 * is no PSSL compiler here, so shaders are precompiled binaries lifted from
 * elsewhere. That one combination happens to cover most of what a renderer
 * like SM64's asks for.
 *
 * Unlike the bring-up tests, which recorded one draw per frame, this records
 * many draws with changing state, so it keeps a per-frame arena in
 * graphics-visible memory and emits register updates between draws.
 */
#ifndef PS5GPU_H
#define PS5GPU_H

#include <stdint.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

/* One vertex, laid out exactly as mesh_vs.sb reads it: position, then the
 * "normal" slot, then an unused texture-coordinate slot, then a packed colour.
 * The texture coordinates travel in the normal slot because that is the field
 * the vertex program forwards as the first interpolant, which is the one the
 * pixel program samples with - see ps5gpu_shaders.h. */
typedef struct {
    float    x, y, z;          /* position                                  */
    float    u, v, n_pad;      /* the normal slot: (u, v, 0)                */
    float    uv_unused[2];     /* the real uv slot, which mesh_vs ignores   */
    uint32_t color;            /* A<<24 | R<<16 | G<<8 | B                  */
} Ps5GpuVertex;

/* Texture addressing, matching the N64 tile modes the caller already has. */
#define PS5GPU_WRAP        0
#define PS5GPU_MIRROR      1
#define PS5GPU_CLAMP       2

/* Brings up the graphics device and the display, allocates the framebuffers
 * and the depth buffer, and prepares the shaders. Returns 0 on success, or a
 * negative value; ps5gpu_last_error() then names the step that failed. */
int         ps5gpu_init(void);
const char *ps5gpu_last_error(void);
void        ps5gpu_get_dimensions(uint32_t *width, uint32_t *height);

/* A frame: begin clears colour and depth and resets the arena, end submits the
 * recorded commands and queues the flip. */
void ps5gpu_begin_frame(void);
void ps5gpu_end_frame(void);

/* How many vertical blanks each frame is held for: 1 presents at the display's
 * rate, 2 at half of it. Paces a caller whose logic advances once per frame. */
void ps5gpu_set_frame_interval(int vblanks);

/* Frames presented a second, measured over the last whole second. */
int ps5gpu_measured_fps(void);

/* Image quality, taken when the next frame begins: the 4K display buffers or
 * the 1080p ones, and for 1080p whether the scene is supersampled - drawn at
 * twice the size each way and averaged down. 4K draws the scene at 3840x2160
 * and shows it one to one. The caller keeps working in 1920x1080 either way. */
void ps5gpu_set_quality(int output_4k, int supersample);
int  ps5gpu_4k_available(void);         /* whether the output took the 4K buffers */
int  ps5gpu_render_scale(void);         /* this frame's: 2, or 1 without supersampling */

/* Textures. Ids are opaque and start at 1; 0 is never a valid texture. */
uint32_t ps5gpu_texture_new(void);
void     ps5gpu_texture_upload(uint32_t id, const uint8_t *rgba32, int width, int height);
void     ps5gpu_texture_select(uint32_t id);
/* Selects the texture bound to unit 1, for a program that declares a second
 * texture (e.g. textured2_p_sb - PS5GL's base-times-lightmap program). Has no
 * effect on a program with only one texture. Both units share the sampler
 * state set by ps5gpu_sampler_set(). */
void     ps5gpu_texture_select2(uint32_t id);
void     ps5gpu_sampler_set(int linear_filter, uint32_t address_s, uint32_t address_t);

/* Pipeline state. Each takes effect on the next draw. */
void ps5gpu_set_viewport(int x, int y, int width, int height);
void ps5gpu_set_scissor(int x, int y, int width, int height);
void ps5gpu_set_depth_test(int enable);
void ps5gpu_set_depth_mask(int enable);
void ps5gpu_set_depth_decal(int enable);
/* PS5GPU_BLEND_NONE (0) and PS5GPU_BLEND_ALPHA (1) are the original two
 * values, unchanged - existing 0/1 callers keep working. PS5GPU_BLEND_MULTIPLY
 * (2) is the way PS5GL combines two textures the direct-user-data pixel
 * program can't (see ps5gpu_program_new): draw the base once normally, then
 * the same triangles again with the second texture selected and this blend
 * mode, so the processor computes dst = src * dst per pixel instead of the
 * shader doing it in one pass. For that second pass, disable depth writes
 * (ps5gpu_set_depth_mask(0)) so the identical depth values it writes don't
 * risk fighting the first pass's - depth TEST should stay on at
 * less-or-equal, which is this renderer's only depth mode, so the second
 * pass's fragments still pass. */
#define PS5GPU_BLEND_NONE     0
#define PS5GPU_BLEND_ALPHA    1
#define PS5GPU_BLEND_MULTIPLY 2
void ps5gpu_set_blend(int mode);
/* Drops pixels whose alpha is below one half, depth included - an alpha test,
 * for cut-out textures. */
void ps5gpu_set_alpha_test(int enable);

/* Draws a triangle list. The vertices are copied into this frame's arena, so
 * the caller's buffer can be reused immediately. */
void ps5gpu_draw(const Ps5GpuVertex *vertices, int vertex_count);

/* The position matrix for the draws that follow: row-major, acting on row
 * vectors (p' = p * M), as the vertex program's mvp does. Identity by default.
 * A matrix whose last column is not (0, 0, 0, 1) hands the processor a real w,
 * so it divides and interpolates with perspective itself. */
void ps5gpu_set_mvp(const float m[16]);

/* Pixel programs. 0 is the built-in one, texture times colour. Another comes
 * from a shader container with the same resources - one texture and one
 * sampler - and is linked with the built-in vertex program, which also
 * forwards the vertex's n_pad as attr0.z. Returns the new program's id, or 0
 * if it could not be created, so a failure falls back to the built-in one. */
int  ps5gpu_program_new(const unsigned char *container, unsigned int length);
void ps5gpu_set_program(int id);

/* Debug-only: the raw user-data dword offsets ps5gpu_program_new() resolved
 * for a program's resources, for diagnosing a container whose resources bind
 * to the wrong place. tex1/smp1 are -1 if the program has no second texture. */
void ps5gpu_debug_program_slots(int id, int *tex_dwo, int *smp_dwo, int *tex1_dwo, int *smp1_dwo);

/* Render targets. A frame draws into the scene unless told otherwise. The
 * reflection is a second target of the display's size with a depth buffer of
 * its own; the first selection in a frame clears both, and the draws that follow go there until
 * the scene is selected again. Its image is read back as a texture through
 * ps5gpu_reflection_texture(). The pipeline state carries over either way. */
#define PS5GPU_TARGET_SCENE      0
#define PS5GPU_TARGET_REFLECTION 1
#define PS5GPU_TARGET_SHADOW     2   /* square, always drawn whole; its border is never drawn */
/* A caller-sized target from ps5gpu_target_create(), selected by
 * PS5GPU_TARGET_USER0 + the index it returned. UNTESTED ON HARDWARE - unlike
 * every other register value in this file, this generalization (arbitrary
 * size/address instead of one of three fixed, already-proven targets) has
 * not yet been confirmed on a real console. Try it expecting to need a
 * build-and-test cycle or several, the same way the multi-texture container
 * in agcpack.py did. */
#define PS5GPU_TARGET_USER0     100
#define PS5GPU_MAX_USER_TARGETS 4
void     ps5gpu_set_target(int target);
uint32_t ps5gpu_reflection_texture(void);
uint32_t ps5gpu_shadow_texture(void);

/* Allocates a new render target of the caller's own size, with its own depth
 * buffer. Returns an index (0..PS5GPU_MAX_USER_TARGETS-1) to draw into it
 * with ps5gpu_set_target(PS5GPU_TARGET_USER0 + index), or -1 on failure (out
 * of memory, or every slot already in use). Unlike the fixed
 * scene/reflection/shadow targets, a user target is never auto-cleared - the
 * caller clears it itself (typically by drawing a full-screen quad) before
 * relying on its contents; the first frame it's rendered into holds whatever
 * the allocation happened to contain. See the UNTESTED note on
 * PS5GPU_TARGET_USER0 above. */
int ps5gpu_target_create(int width, int height);
/* The texture id a user target's contents can be sampled through afterward -
 * same id space ps5gpu_texture_new() hands out, usable with
 * ps5gpu_texture_select() like any other texture. -1 if index is not a
 * target ps5gpu_target_create() returned. */
int ps5gpu_target_texture(int index);

/* Debug-only: reads one pixel directly from a user target's CPU-mapped
 * memory (DirectMem is CPU-readable, so this bypasses the GPU sampling path
 * entirely) - for telling apart "nothing was ever rendered into it" from
 * "rendering worked but reading it back as a texture is what's wrong".
 * Writes 0,0,0,0 and returns 0 if index/x/y are invalid; 1 on success. */
int ps5gpu_debug_read_target_pixel(int index, int x, int y, unsigned char rgba[4]);
/* Which half of the shadow map the draws that follow go into: 0 near, 1 far. */
void     ps5gpu_set_shadow_cascade(int cascade);

/* Moves the scene's drawing right by this many display pixels - for a
 * narrower picture in the middle of the screen, 4:3 say. The caller then
 * reports the narrower width to its renderer. */
void ps5gpu_set_view_offset_x(int display_pixels);

/* Triangles drawn over the finished frame at the display's resolution, in
 * clip space, with one texture and blending on: a menu. Taken for the next
 * frame only; the vertices must stay valid until it ends. */
void ps5gpu_set_overlay(const Ps5GpuVertex *vertices, int vertex_count, uint32_t texture);

/* A line of text on the system's notification overlay - the only output
 * channel a real title has without a console. */
void ps5gpu_notify(const char *message);

#ifdef __cplusplus
}
#endif

#endif
