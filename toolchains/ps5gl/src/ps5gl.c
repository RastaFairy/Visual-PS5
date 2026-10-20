/* PS5GL implementation - see include/ps5gl.h for what is and isn't real here.
 * Backed entirely by backend/ps5gpu.c; every draw call ends up as exactly one
 * ps5gpu_draw(), and every texture/program id IS a ps5gpu id (no indirection
 * table for those - ps5gpu's own ids are already opaque small integers).
 */
#include <string.h>
#include <stdlib.h>

#include "ps5gl.h"
#include "ps5gpu.h"

/* Forward-declared: defined near the rest of the framebuffer state, much
 * later in this file, but needed by bind_program_and_textures() below. */
static void apply_bound_framebuffer(void);

/* ---- error state ---- */
static GLenum s_error = GL_NO_ERROR;
static void set_error(GLenum e) { if (s_error == GL_NO_ERROR) s_error = e; }
GLenum glGetError(void) { GLenum e = s_error; s_error = GL_NO_ERROR; return e; }

int ps5gl_init(void) { return ps5gpu_init(); }
const char *ps5gl_last_error(void) { return ps5gpu_last_error(); }
void ps5gl_begin_frame(void) { ps5gpu_begin_frame(); }
void ps5gl_end_frame(void) { ps5gpu_end_frame(); }

const GLubyte *glGetString(GLenum name) {
    switch (name) {
        case GL_VENDOR:   return (const GLubyte *)"PS5GL";
        case GL_RENDERER: return (const GLubyte *)"ps5gpu/AGC";
        case GL_VERSION:  return (const GLubyte *)"PS5GL 0.1 (subset, no GLSL compiler - see ps5gl.h)";
        case GL_EXTENSIONS: return (const GLubyte *)"";   /* none - see ps5gl.h */
        default: set_error(GL_INVALID_ENUM); return (const GLubyte *)"";
    }
}

/* ---- textures ----
 * A texture's GL name IS its ps5gpu id directly - ps5gpu_texture_new()
 * already hands out small opaque integers starting at 1, exactly what GL
 * texture names look like. Per-texture sampler parameters are tracked here,
 * since ps5gpu.c only has one GLOBAL sampler state (applied fresh before
 * each draw from whichever texture is bound - see apply_sampler_state()). */
#define MAX_GL_TEXTURES 1024
/* rt_index >= 0: this GL texture id was attached to a framebuffer's colour
 * attachment (see glFramebufferTexture2D) and is backed by a real
 * ps5gpu_target_create() render target instead of ordinary uploaded pixels -
 * sampling it (see bind_program_and_textures) must use
 * ps5gpu_target_texture(rt_index)'s id, not this GL id's own (which has no
 * real backend storage in that case). */
typedef struct { int wrap_s, wrap_t, min_filter, mag_filter, set, width, height, rt_index; } TexParams;
static TexParams s_tex_params[MAX_GL_TEXTURES];

/* 12 to match libmod_3d's real usage (GL_TEXTURE0..11 - a full PBR
 * material's worth of units), tracked for object-management purposes only.
 * Only unit 0 is ever forwarded to a draw - see GL_TEXTURE1..11's own
 * comment in ps5gl.h for why. */
#define UNIT_COUNT 12
static GLuint s_bound_texture[UNIT_COUNT];
static GLenum s_active_unit;   /* 0 or 1, from GL_TEXTURE0/GL_TEXTURE0+1 */

void glGenTextures(GLsizei n, GLuint *textures) {
    for (GLsizei i = 0; i < n; i++) {
        uint32_t id = ps5gpu_texture_new();
        textures[i] = id;
        if (id < MAX_GL_TEXTURES) { s_tex_params[id].set = 0; s_tex_params[id].rt_index = -1; }
    }
}

void glDeleteTextures(GLsizei n, const GLuint *textures) {
    /* ps5gpu.c has no texture free - ids are never reused within a run.
     * Matches its own model (see ps5gpu_texture_new's "ids start at 1" and
     * the comment on Texture retirement, which is about upload, not
     * deletion). Nothing to do here beyond forgetting our own parameters. */
    for (GLsizei i = 0; i < n; i++)
        if (textures[i] < MAX_GL_TEXTURES) s_tex_params[textures[i]].set = 0;
}

void glActiveTexture(GLenum texture) {
    if (texture < GL_TEXTURE0 || texture >= GL_TEXTURE0 + UNIT_COUNT) { set_error(GL_INVALID_ENUM); return; }
    s_active_unit = texture - GL_TEXTURE0;
}

void glBindTexture(GLenum target, GLuint texture) {
    if (target != GL_TEXTURE_2D) { set_error(GL_INVALID_ENUM); return; }
    s_bound_texture[s_active_unit] = texture;
}

void glTexImage2D(GLenum target, GLint level, GLint internalformat, GLsizei width, GLsizei height,
                   GLint border, GLenum format, GLenum type, const void *pixels) {
    (void)internalformat; (void)border;
    if (target != GL_TEXTURE_2D) { set_error(GL_INVALID_ENUM); return; }
    if (level != 0) return;   /* ps5gpu.c has no mip chain - level 0 only, others silently skipped */
    GLuint tex = s_bound_texture[s_active_unit];
    if (tex == 0) { set_error(GL_INVALID_OPERATION); return; }
    if (tex < MAX_GL_TEXTURES) { s_tex_params[tex].width = width; s_tex_params[tex].height = height; }
    /* NULL is real GL usage - "reserve this size, no initial data yet", the
     * standard way to size a texture before attaching it to a framebuffer
     * (see glFramebufferTexture2D) - including with format/type combinations
     * this backend cannot actually convert (GL_DEPTH_COMPONENT for a
     * depth-only FBO's texture, the standard shadow-map idiom, notably -
     * confirmed on hardware to matter: real code sizing a depth texture this
     * way got rejected here before this check moved below the NULL case,
     * leaving the render target never created). No data is ever touched for
     * a NULL call regardless of format, so there is nothing to validate -
     * recording the size above is all that needs doing. */
    if (pixels == NULL) return;
    if (format != GL_RGBA || type != GL_UNSIGNED_BYTE) {
        /* ps5gpu_texture_upload only ever takes RGBA8 - anything else would
         * need a CPU-side conversion this library does not implement yet.
         * Only reachable with real pixel data to upload - see above. */
        set_error(GL_INVALID_OPERATION);
        return;
    }
    ps5gpu_texture_upload(tex, (const uint8_t *)pixels, width, height);
}

/* Only correct for a sub-rectangle covering the whole texture - see ps5gl.h. */
void glTexSubImage2D(GLenum target, GLint level, GLint xoffset, GLint yoffset, GLsizei width, GLsizei height,
                      GLenum format, GLenum type, const void *pixels) {
    if (target != GL_TEXTURE_2D) { set_error(GL_INVALID_ENUM); return; }
    if (level != 0) return;
    if (format != GL_RGBA || type != GL_UNSIGNED_BYTE) { set_error(GL_INVALID_OPERATION); return; }
    GLuint tex = s_bound_texture[s_active_unit];
    if (tex == 0 || tex >= MAX_GL_TEXTURES || pixels == NULL) { set_error(GL_INVALID_OPERATION); return; }
    if (xoffset != 0 || yoffset != 0 || width != s_tex_params[tex].width || height != s_tex_params[tex].height) {
        set_error(GL_INVALID_OPERATION);   /* a true partial update would corrupt the rest - refused, see ps5gl.h */
        return;
    }
    ps5gpu_texture_upload(tex, (const uint8_t *)pixels, width, height);
}

void glCompressedTexImage2D(GLenum target, GLint level, GLenum internalformat, GLsizei width, GLsizei height,
                             GLint border, GLsizei imageSize, const void *data) {
    (void)target; (void)level; (void)internalformat; (void)width; (void)height;
    (void)border; (void)imageSize; (void)data;
    set_error(GL_INVALID_OPERATION);   /* no decompressor - see ps5gl.h */
}

void glTexParameteri(GLenum target, GLenum pname, GLint param) {
    if (target != GL_TEXTURE_2D) { set_error(GL_INVALID_ENUM); return; }
    GLuint tex = s_bound_texture[s_active_unit];
    if (tex >= MAX_GL_TEXTURES) return;
    TexParams *p = &s_tex_params[tex];
    p->set = 1;
    switch (pname) {
        case GL_TEXTURE_WRAP_S: p->wrap_s = param; break;
        case GL_TEXTURE_WRAP_T: p->wrap_t = param; break;
        case GL_TEXTURE_MIN_FILTER: p->min_filter = param; break;
        case GL_TEXTURE_MAG_FILTER: p->mag_filter = param; break;
        default: set_error(GL_INVALID_ENUM);
    }
}

static uint32_t gl_wrap_to_ps5gpu(int wrap) {
    if (wrap == GL_MIRRORED_REPEAT) return PS5GPU_MIRROR;
    if (wrap == GL_CLAMP_TO_EDGE || wrap == GL_CLAMP_TO_BORDER) return PS5GPU_CLAMP;   /* no real border colour - see GL_TEXTURE_BORDER_COLOR */
    return PS5GPU_WRAP;   /* GL_REPEAT, and the default for a texture with no glTexParameteri call */
}

/* Tracked, never applied - ps5gpu.c has no border-colour concept. */
void glTexParameterfv(GLenum target, GLenum pname, const GLfloat *params) {
    (void)params;
    if (target != GL_TEXTURE_2D) { set_error(GL_INVALID_ENUM); return; }
    if (pname != GL_TEXTURE_BORDER_COLOR) set_error(GL_INVALID_ENUM);
}

/* Sampler objects: same shape as TexParams, bound per unit, taking priority
 * over that unit's texture's own glTexParameteri settings while bound - see
 * ps5gl.h. ps5gpu.c still only has one global sampler slot either way. */
#define MAX_GL_SAMPLERS 256
static TexParams s_samplers[MAX_GL_SAMPLERS];
static int s_sampler_count = 1;
static GLuint s_bound_sampler[UNIT_COUNT];

void glGenSamplers(GLsizei n, GLuint *samplers) {
    for (GLsizei i = 0; i < n; i++) {
        if (s_sampler_count >= MAX_GL_SAMPLERS) { samplers[i] = 0; continue; }
        int id = s_sampler_count++;
        memset(&s_samplers[id], 0, sizeof(TexParams));
        samplers[i] = (GLuint)id;
    }
}
void glDeleteSamplers(GLsizei n, const GLuint *samplers) {
    for (GLsizei i = 0; i < n; i++) if (samplers[i] < MAX_GL_SAMPLERS) s_samplers[samplers[i]].set = 0;
}
void glBindSampler(GLuint unit, GLuint sampler) { if (unit < UNIT_COUNT) s_bound_sampler[unit] = sampler; }
void glSamplerParameteri(GLuint sampler, GLenum pname, GLint param) {
    if (sampler >= MAX_GL_SAMPLERS) { set_error(GL_INVALID_VALUE); return; }
    TexParams *p = &s_samplers[sampler];
    p->set = 1;
    switch (pname) {
        case GL_TEXTURE_WRAP_S: p->wrap_s = param; break;
        case GL_TEXTURE_WRAP_T: p->wrap_t = param; break;
        case GL_TEXTURE_MIN_FILTER: p->min_filter = param; break;
        case GL_TEXTURE_MAG_FILTER: p->mag_filter = param; break;
        default: set_error(GL_INVALID_ENUM);
    }
}

/* Applies unit 0's sampler state, since ps5gpu.c has only one global sampler
 * slot: the sampler object bound to unit 0 if there is one, else unit 0's
 * texture's own glTexParameteri settings, else a bilinear/repeat default.
 * Called once per draw, right before it. */
static void apply_sampler_state(void) {
    TexParams *p = NULL;
    if (s_bound_sampler[0] != 0 && s_bound_sampler[0] < MAX_GL_SAMPLERS && s_samplers[s_bound_sampler[0]].set)
        p = &s_samplers[s_bound_sampler[0]];
    else {
        GLuint tex = s_bound_texture[0];
        if (tex < MAX_GL_TEXTURES && s_tex_params[tex].set) p = &s_tex_params[tex];
    }
    if (p) {
        int linear = (p->mag_filter == GL_LINEAR || p->min_filter == GL_LINEAR ||
                      p->min_filter == GL_LINEAR_MIPMAP_LINEAR || p->min_filter == GL_LINEAR_MIPMAP_NEAREST);
        ps5gpu_sampler_set(linear, gl_wrap_to_ps5gpu(p->wrap_s), gl_wrap_to_ps5gpu(p->wrap_t));
    } else {
        ps5gpu_sampler_set(1, PS5GPU_WRAP, PS5GPU_WRAP);   /* bilinear/repeat default */
    }
}

/* ---- buffers ----
 * No persistent GPU buffer objects exist underneath - ps5gpu_draw copies
 * vertex data into its own per-frame arena on every call. A "buffer object"
 * here is just a CPU-side byte blob glBufferData/glBufferSubData fill, that
 * glVertexAttribPointer/glDrawElements later read back out of at draw time -
 * the same round trip a real GL driver's client-side fallback would do. */
#define MAX_GL_BUFFERS 256
typedef struct { unsigned char *data; intptr_t size; } Buffer;
static Buffer s_buffers[MAX_GL_BUFFERS];
static int s_buffer_count = 1;   /* 0 is never a valid buffer name, matching GL */
static GLuint s_bound_array_buffer, s_bound_element_buffer;

void glGenBuffers(GLsizei n, GLuint *buffers) {
    for (GLsizei i = 0; i < n; i++) {
        if (s_buffer_count >= MAX_GL_BUFFERS) { buffers[i] = 0; continue; }
        buffers[i] = (GLuint)s_buffer_count++;
    }
}

void glDeleteBuffers(GLsizei n, const GLuint *buffers) {
    for (GLsizei i = 0; i < n; i++) {
        GLuint b = buffers[i];
        if (b > 0 && b < MAX_GL_BUFFERS && s_buffers[b].data) { free(s_buffers[b].data); s_buffers[b].data = NULL; s_buffers[b].size = 0; }
    }
}

static GLuint *bound_buffer_slot(GLenum target) {
    if (target == GL_ARRAY_BUFFER) return &s_bound_array_buffer;
    if (target == GL_ELEMENT_ARRAY_BUFFER) return &s_bound_element_buffer;
    return NULL;
}

void glBindBuffer(GLenum target, GLuint buffer) {
    GLuint *slot = bound_buffer_slot(target);
    if (!slot) { set_error(GL_INVALID_ENUM); return; }
    *slot = buffer;
}

void glBufferData(GLenum target, intptr_t size, const void *data, GLenum usage) {
    (void)usage;
    GLuint *slot = bound_buffer_slot(target);
    if (!slot || *slot == 0 || *slot >= MAX_GL_BUFFERS) { set_error(GL_INVALID_OPERATION); return; }
    Buffer *b = &s_buffers[*slot];
    free(b->data);
    b->data = (unsigned char *)malloc((size_t)size);
    b->size = size;
    if (b->data && data) memcpy(b->data, data, (size_t)size);
}

void glBufferSubData(GLenum target, intptr_t offset, intptr_t size, const void *data) {
    GLuint *slot = bound_buffer_slot(target);
    if (!slot || *slot == 0 || *slot >= MAX_GL_BUFFERS) { set_error(GL_INVALID_OPERATION); return; }
    Buffer *b = &s_buffers[*slot];
    if (!b->data || offset + size > b->size) { set_error(GL_INVALID_VALUE); return; }
    memcpy(b->data + offset, data, (size_t)size);
}

/* ---- vertex arrays ----
 * Exactly 3 attribute slots are meaningful, matching Ps5GpuVertex's actual
 * fields - not a generic N-attribute system:
 *   0 = position (2 or 3 floats)
 *   1 = texcoord (2 floats)
 *   2 = colour   (4 floats 0..1, or 4 normalized unsigned bytes)
 * Any other index is accepted (so calling code that also sets, say, a
 * normal at index 3 does not crash) but ignored at draw time. */
#define ATTR_COUNT 8
typedef struct {
    int enabled;
    GLint size;
    GLenum type;
    GLboolean normalized;
    GLsizei stride;
    GLuint buffer;          /* which GL_ARRAY_BUFFER was bound at glVertexAttribPointer time */
    intptr_t offset;
    GLuint divisor;         /* 0 = advances per vertex (default); N>0 = advances once per N instances */
} Attrib;

#define MAX_VAOS 64
typedef struct { Attrib attrib[ATTR_COUNT]; int used; } Vao;
static Vao s_vaos[MAX_VAOS];
static int s_vao_count = 1;   /* 0 is the default VAO, always valid */
static GLuint s_bound_vao;

void glGenVertexArrays(GLsizei n, GLuint *arrays) {
    for (GLsizei i = 0; i < n; i++) {
        if (s_vao_count >= MAX_VAOS) { arrays[i] = 0; continue; }
        int id = s_vao_count++;
        memset(&s_vaos[id], 0, sizeof(Vao));
        s_vaos[id].used = 1;
        arrays[i] = (GLuint)id;
    }
}

void glDeleteVertexArrays(GLsizei n, const GLuint *arrays) {
    for (GLsizei i = 0; i < n; i++) { GLuint a = arrays[i]; if (a > 0 && a < MAX_VAOS) s_vaos[a].used = 0; }
}

void glBindVertexArray(GLuint array) {
    if (array >= MAX_VAOS || (array != 0 && !s_vaos[array].used)) { set_error(GL_INVALID_OPERATION); return; }
    s_bound_vao = array;
}

void glVertexAttribPointer(GLuint index, GLint size, GLenum type, GLboolean normalized,
                            GLsizei stride, const void *pointer) {
    if (index >= ATTR_COUNT) return;
    Attrib *a = &s_vaos[s_bound_vao].attrib[index];
    a->size = size; a->type = type; a->normalized = normalized; a->stride = stride;
    a->buffer = s_bound_array_buffer;
    a->offset = (intptr_t)pointer;   /* a byte offset into that buffer, GL's own convention when one is bound */
}

void glEnableVertexAttribArray(GLuint index) { if (index < ATTR_COUNT) s_vaos[s_bound_vao].attrib[index].enabled = 1; }
void glDisableVertexAttribArray(GLuint index) { if (index < ATTR_COUNT) s_vaos[s_bound_vao].attrib[index].enabled = 0; }
void glVertexAttribDivisor(GLuint index, GLuint divisor) {
    if (index < ATTR_COUNT) s_vaos[s_bound_vao].attrib[index].divisor = divisor;
}

/* ---- shaders / programs (see ps5gl.h - GLSL is never actually compiled) ---- */
#define MAX_GL_SHADERS 64
#define MAX_GL_PROGRAMS 64
typedef struct { GLenum type; int used; } Shader;
typedef struct { int used; int precompiled_id; } Program;   /* precompiled_id: -1 = built-in program 0 */
static Shader s_shaders[MAX_GL_SHADERS];
static Program s_gl_programs[MAX_GL_PROGRAMS];
static int s_shader_count = 1, s_program_count = 1;
static GLuint s_current_program;

GLuint glCreateShader(GLenum type) {
    if (type != GL_VERTEX_SHADER && type != GL_FRAGMENT_SHADER) { set_error(GL_INVALID_ENUM); return 0; }
    if (s_shader_count >= MAX_GL_SHADERS) return 0;
    GLuint id = (GLuint)s_shader_count++;
    s_shaders[id].type = type; s_shaders[id].used = 1;
    return id;
}
void glDeleteShader(GLuint shader) { if (shader < MAX_GL_SHADERS) s_shaders[shader].used = 0; }
void glShaderSource(GLuint shader, GLsizei count, const char *const *string, const GLint *length) {
    (void)shader; (void)count; (void)string; (void)length;   /* text is never read - see ps5gl.h */
}
void glCompileShader(GLuint shader) { (void)shader; /* always "succeeds" - see ps5gl.h */ }
void glGetShaderiv(GLuint shader, GLenum pname, GLint *params) {
    if (pname == GL_COMPILE_STATUS) { *params = (shader < MAX_GL_SHADERS && s_shaders[shader].used) ? GL_TRUE : GL_FALSE; return; }
    if (pname == GL_INFO_LOG_LENGTH) { *params = 0; return; }   /* always empty - see glGetShaderInfoLog */
    set_error(GL_INVALID_ENUM);
}

GLuint glCreateProgram(void) {
    if (s_program_count >= MAX_GL_PROGRAMS) return 0;
    GLuint id = (GLuint)s_program_count++;
    s_gl_programs[id].used = 1; s_gl_programs[id].precompiled_id = -1;
    return id;
}
void glDeleteProgram(GLuint program) { if (program < MAX_GL_PROGRAMS) s_gl_programs[program].used = 0; }
void glAttachShader(GLuint program, GLuint shader) { (void)program; (void)shader; /* no-op - see ps5gl.h */ }
void glLinkProgram(GLuint program) { (void)program; /* always "succeeds" */ }
void glGetProgramiv(GLuint program, GLenum pname, GLint *params) {
    if (pname == GL_LINK_STATUS) { *params = (program < MAX_GL_PROGRAMS && s_gl_programs[program].used) ? GL_TRUE : GL_FALSE; return; }
    if (pname == GL_INFO_LOG_LENGTH) { *params = 0; return; }
    set_error(GL_INVALID_ENUM);
}
void glUseProgram(GLuint program) {
    if (program != 0 && (program >= MAX_GL_PROGRAMS || !s_gl_programs[program].used)) { set_error(GL_INVALID_OPERATION); return; }
    s_current_program = program;
}

int ps5gl_program_use_precompiled(GLuint program, const unsigned char *container, unsigned int length) {
    if (program == 0 || program >= MAX_GL_PROGRAMS || !s_gl_programs[program].used) return 0;
    int id = ps5gpu_program_new(container, length);
    if (id == 0) return 0;
    s_gl_programs[program].precompiled_id = id;
    return 1;
}

int ps5gl_debug_texture_rt_index(GLuint texture) {
    return texture < MAX_GL_TEXTURES ? s_tex_params[texture].rt_index : -1;
}

/* ---- uniforms - only "mvp" does anything, see ps5gl.h ---- */
#define MVP_LOCATION 1
GLint glGetUniformLocation(GLuint program, const char *name) {
    (void)program;
    return strcmp(name, "mvp") == 0 ? MVP_LOCATION : -1;
}
void glUniformMatrix4fv(GLint location, GLsizei count, GLboolean transpose, const GLfloat *value) {
    (void)count;
    if (location != MVP_LOCATION) return;   /* silently discarded - see ps5gl.h */
    if (transpose) { ps5gpu_set_mvp(value); return; }
    /* GL's default (transpose=GL_FALSE) hands a column-major matrix; ps5gpu's
     * vertex program reads row-major acting on row vectors - the transpose
     * of the same matrix, bit for bit. */
    float t[16];
    for (int r = 0; r < 4; r++) for (int c = 0; c < 4; c++) t[r * 4 + c] = value[c * 4 + r];
    ps5gpu_set_mvp(t);
}
void glUniform1i(GLint location, GLint v0) { (void)location; (void)v0; }
void glUniform1f(GLint location, GLfloat v0) { (void)location; (void)v0; }
void glUniform4f(GLint location, GLfloat v0, GLfloat v1, GLfloat v2, GLfloat v3) {
    (void)location; (void)v0; (void)v1; (void)v2; (void)v3;
}

/* ---- state ---- */
static int s_depth_test, s_blend_enabled, s_cull_face, s_scissor_test, s_polygon_offset_fill;
static int s_blend_mode = PS5GPU_BLEND_ALPHA;   /* which mode glBlendFunc last selected */

void glEnable(GLenum cap) {
    switch (cap) {
        case GL_DEPTH_TEST: s_depth_test = 1; ps5gpu_set_depth_test(1); break;
        case GL_BLEND: s_blend_enabled = 1; ps5gpu_set_blend(s_blend_mode); break;
        case GL_CULL_FACE: s_cull_face = 1; break;   /* ps5gpu.c never culls - see its emit_frame_state comment */
        case GL_SCISSOR_TEST: s_scissor_test = 1; break;
        case GL_POLYGON_OFFSET_FILL: s_polygon_offset_fill = 1; ps5gpu_set_depth_decal(1); break;
        default: set_error(GL_INVALID_ENUM);
    }
}
void glDisable(GLenum cap) {
    switch (cap) {
        case GL_DEPTH_TEST: s_depth_test = 0; ps5gpu_set_depth_test(0); break;
        case GL_BLEND: s_blend_enabled = 0; ps5gpu_set_blend(PS5GPU_BLEND_NONE); break;
        case GL_CULL_FACE: s_cull_face = 0; break;
        case GL_SCISSOR_TEST: s_scissor_test = 0; break;
        case GL_POLYGON_OFFSET_FILL: s_polygon_offset_fill = 0; ps5gpu_set_depth_decal(0); break;
        default: set_error(GL_INVALID_ENUM);
    }
}
GLboolean glIsEnabled(GLenum cap) {
    switch (cap) {
        case GL_DEPTH_TEST: return s_depth_test;
        case GL_BLEND: return s_blend_enabled;
        case GL_CULL_FACE: return s_cull_face;
        case GL_SCISSOR_TEST: return s_scissor_test;
        case GL_POLYGON_OFFSET_FILL: return s_polygon_offset_fill;
        default: set_error(GL_INVALID_ENUM); return GL_FALSE;
    }
}
void glDepthFunc(GLenum func) { if (func != GL_LEQUAL) set_error(GL_INVALID_ENUM); }
static GLboolean s_depth_writemask = GL_TRUE;
void glDepthMask(GLboolean flag) { s_depth_writemask = flag; ps5gpu_set_depth_mask(flag ? 1 : 0); }

void glBlendFunc(GLenum sfactor, GLenum dfactor) {
    if (sfactor == GL_SRC_ALPHA && dfactor == GL_ONE_MINUS_SRC_ALPHA) s_blend_mode = PS5GPU_BLEND_ALPHA;
    else if (sfactor == GL_DST_COLOR && dfactor == GL_ZERO) s_blend_mode = PS5GPU_BLEND_MULTIPLY;
    else { set_error(GL_INVALID_OPERATION); return; }   /* only these two combinations exist underneath */
    if (s_blend_enabled) ps5gpu_set_blend(s_blend_mode);
}

/* ps5gpu.c has no viewport getter, so this shadows what glViewport last set
 * purely for GL_VIEWPORT's sake (see glGetIntegerv). */
static GLint s_viewport[4];
void glViewport(GLint x, GLint y, GLsizei width, GLsizei height) {
    s_viewport[0] = x; s_viewport[1] = y; s_viewport[2] = width; s_viewport[3] = height;
    ps5gpu_set_viewport(x, y, width, height);
}
void glScissor(GLint x, GLint y, GLsizei width, GLsizei height) { ps5gpu_set_scissor(x, y, width, height); }

static float s_clear_r, s_clear_g, s_clear_b, s_clear_a = 1.0f;
void glClearColor(GLfloat r, GLfloat g, GLfloat b, GLfloat a) { s_clear_r = r; s_clear_g = g; s_clear_b = b; s_clear_a = a; }
void glClear(GLbitfield mask) {
    /* ps5gpu_begin_frame() already clears colour (to opaque black) and depth
     * every frame on its own - there is no separate clear call to forward
     * to, and no support for a caller-chosen clear colour yet. Accepted so
     * calling code's ordinary clear-then-draw structure does not need
     * special-casing for this backend. */
    (void)mask; (void)s_clear_r; (void)s_clear_g; (void)s_clear_b; (void)s_clear_a;
}

/* ---- drawing ----
 * Gathers whatever the bound VAO's enabled attributes describe into
 * Ps5GpuVertex structs, applies the bound texture(s)/program/sampler, and
 * issues exactly one ps5gpu_draw(). */
#define MAX_DRAW_VERTICES 8192
static Ps5GpuVertex s_draw_buf[MAX_DRAW_VERTICES];

static float read_float_component(const unsigned char *base, GLenum type, GLboolean normalized) {
    switch (type) {
        case GL_FLOAT: { float f; memcpy(&f, base, 4); return f; }
        case GL_UNSIGNED_BYTE: return normalized ? (float)base[0] / 255.0f : (float)base[0];
        default: return 0.0f;
    }
}

/* Generic vertex attribute "current values" - real GL context state, set by
 * glVertexAttrib1f/2f/3f/4f, used below by gather_vertex whenever a slot is
 * disabled - matching real GL's "disabled array -> use the constant"
 * behaviour. Declared here (ahead of the functions that set it, later in
 * this file) so gather_vertex can read it; not part of any Vao, per spec. */
static float s_attrib_constant[ATTR_COUNT][4] = {
    { 0,0,0,1 }, { 0,0,0,1 }, { 1,1,1,1 }, { 0,0,0,1 }, { 0,0,0,1 }, { 0,0,0,1 }, { 0,0,0,1 }, { 0,0,0,1 },
};

static void gather_vertex(GLint vertex_index, GLuint instance_index, Ps5GpuVertex *out) {
    Vao *vao = &s_vaos[s_bound_vao];
    out->x = s_attrib_constant[0][0]; out->y = s_attrib_constant[0][1]; out->z = s_attrib_constant[0][2];
    out->u = s_attrib_constant[1][0]; out->v = s_attrib_constant[1][1]; out->n_pad = 0.0f;
    out->uv_unused[0] = out->uv_unused[1] = 0.0f;
    { float *c = s_attrib_constant[2];
      out->color = ((uint32_t)(c[3]*255.0f)<<24) | ((uint32_t)(c[0]*255.0f)<<16) | ((uint32_t)(c[1]*255.0f)<<8) | (uint32_t)(c[2]*255.0f); }

    for (int slot = 0; slot < 3; slot++) {
        Attrib *a = &vao->attrib[slot];
        if (!a->enabled || a->buffer == 0 || a->buffer >= MAX_GL_BUFFERS || !s_buffers[a->buffer].data) continue;
        int comp_size = (a->type == GL_FLOAT) ? 4 : 1;
        intptr_t stride = a->stride ? a->stride : (intptr_t)a->size * comp_size;
        /* divisor>0: this attribute advances once every `divisor` instances
         * instead of once per vertex - the standard glVertexAttribDivisor
         * meaning, done here in software since ps5gpu.c has no GPU
         * instancing of its own (see ps5gl.h). */
        GLint index = a->divisor ? (GLint)(instance_index / a->divisor) : vertex_index;
        const unsigned char *base = s_buffers[a->buffer].data + a->offset + (intptr_t)index * stride;

        if (slot == 0) {
            out->x = read_float_component(base + 0 * comp_size, a->type, a->normalized);
            out->y = read_float_component(base + 1 * comp_size, a->type, a->normalized);
            out->z = (a->size >= 3) ? read_float_component(base + 2 * comp_size, a->type, a->normalized) : 0.0f;
        } else if (slot == 1) {
            out->u = read_float_component(base + 0 * comp_size, a->type, a->normalized);
            out->v = read_float_component(base + 1 * comp_size, a->type, a->normalized);
        } else if (slot == 2) {
            float rgba[4] = { 1, 1, 1, 1 };
            for (int c = 0; c < a->size && c < 4; c++) rgba[c] = read_float_component(base + c * comp_size, a->type, a->normalized);
            uint32_t r = (uint32_t)(rgba[0] * 255.0f), g = (uint32_t)(rgba[1] * 255.0f);
            uint32_t b = (uint32_t)(rgba[2] * 255.0f), al = (uint32_t)(rgba[3] * 255.0f);
            out->color = (al << 24) | (r << 16) | (g << 8) | b;
        }
    }
}

static void bind_program_and_textures(void) {
    apply_bound_framebuffer();
    Program *p = (s_current_program < MAX_GL_PROGRAMS) ? &s_gl_programs[s_current_program] : NULL;
    ps5gpu_set_program(p && p->precompiled_id >= 0 ? p->precompiled_id : 0);
    GLuint tex = s_bound_texture[0];
    /* Redirect an FBO-backed texture to its real render target's texture id -
     * see glFramebufferTexture2D's own comment. */
    if (tex < MAX_GL_TEXTURES && s_tex_params[tex].rt_index >= 0) {
        int real = ps5gpu_target_texture(s_tex_params[tex].rt_index);
        if (real >= 0) tex = (GLuint)real;
    }
    ps5gpu_texture_select(tex);
    apply_sampler_state();
}

static int gather_elements(GLenum type, const void *indices, GLsizei count, GLuint instance_index) {
    const unsigned char *idx_base = s_buffers[s_bound_element_buffer].data + (intptr_t)indices;
    for (GLsizei i = 0; i < count; i++) {
        GLuint vi;
        if (type == GL_UNSIGNED_SHORT) { unsigned short v; memcpy(&v, idx_base + i * 2, 2); vi = v; }
        else if (type == GL_UNSIGNED_INT) { unsigned int v; memcpy(&v, idx_base + i * 4, 4); vi = v; }
        else { set_error(GL_INVALID_ENUM); return 0; }
        gather_vertex((GLint)vi, instance_index, &s_draw_buf[i]);
    }
    return 1;
}

void glDrawArrays(GLenum mode, GLint first, GLsizei count) {
    if (mode != GL_TRIANGLES) { set_error(GL_INVALID_ENUM); return; }
    if (count <= 0) return;
    if (count > MAX_DRAW_VERTICES) count = MAX_DRAW_VERTICES;
    for (GLsizei i = 0; i < count; i++) gather_vertex(first + i, 0, &s_draw_buf[i]);
    bind_program_and_textures();
    ps5gpu_draw(s_draw_buf, count);
}

void glDrawElements(GLenum mode, GLsizei count, GLenum type, const void *indices) {
    if (mode != GL_TRIANGLES) { set_error(GL_INVALID_ENUM); return; }
    if (count <= 0) return;
    if (s_bound_element_buffer == 0 || s_bound_element_buffer >= MAX_GL_BUFFERS || !s_buffers[s_bound_element_buffer].data) {
        set_error(GL_INVALID_OPERATION); return;
    }
    if (count > MAX_DRAW_VERTICES) count = MAX_DRAW_VERTICES;
    if (!gather_elements(type, indices, count, 0)) return;
    bind_program_and_textures();
    ps5gpu_draw(s_draw_buf, count);
}

/* Instancing done entirely on the CPU: one ps5gpu_draw() per instance,
 * re-gathering attributes each time - see ps5gl.h. */
void glDrawArraysInstanced(GLenum mode, GLint first, GLsizei count, GLsizei instancecount) {
    if (mode != GL_TRIANGLES) { set_error(GL_INVALID_ENUM); return; }
    if (count <= 0 || instancecount <= 0) return;
    if (count > MAX_DRAW_VERTICES) count = MAX_DRAW_VERTICES;
    bind_program_and_textures();
    for (GLsizei inst = 0; inst < instancecount; inst++) {
        for (GLsizei i = 0; i < count; i++) gather_vertex(first + i, (GLuint)inst, &s_draw_buf[i]);
        ps5gpu_draw(s_draw_buf, count);
    }
}

void glDrawElementsInstanced(GLenum mode, GLsizei count, GLenum type, const void *indices, GLsizei instancecount) {
    if (mode != GL_TRIANGLES) { set_error(GL_INVALID_ENUM); return; }
    if (count <= 0 || instancecount <= 0) return;
    if (s_bound_element_buffer == 0 || s_bound_element_buffer >= MAX_GL_BUFFERS || !s_buffers[s_bound_element_buffer].data) {
        set_error(GL_INVALID_OPERATION); return;
    }
    if (count > MAX_DRAW_VERTICES) count = MAX_DRAW_VERTICES;
    bind_program_and_textures();
    for (GLsizei inst = 0; inst < instancecount; inst++) {
        if (!gather_elements(type, indices, count, (GLuint)inst)) return;
        ps5gpu_draw(s_draw_buf, count);
    }
}

/* ---- more uniforms - discarded except "mvp", see ps5gl.h ---- */
void glUniform2f(GLint location, GLfloat v0, GLfloat v1) { (void)location; (void)v0; (void)v1; }
void glUniform3f(GLint location, GLfloat v0, GLfloat v1, GLfloat v2) { (void)location; (void)v0; (void)v1; (void)v2; }
void glUniform4fv(GLint location, GLsizei count, const GLfloat *value) { (void)location; (void)count; (void)value; }
void glUniform4uiv(GLint location, GLsizei count, const GLuint *value) { (void)location; (void)count; (void)value; }
void glUniformMatrix3fv(GLint location, GLsizei count, GLboolean transpose, const GLfloat *value) {
    (void)location; (void)count; (void)transpose; (void)value;
}

/* ---- info logs - always empty, see ps5gl.h ---- */
void glGetShaderInfoLog(GLuint shader, GLsizei bufSize, GLsizei *length, char *infoLog) {
    (void)shader; (void)bufSize; (void)infoLog;
    if (length) *length = 0;
}
void glGetProgramInfoLog(GLuint program, GLsizei bufSize, GLsizei *length, char *infoLog) {
    (void)program; (void)bufSize; (void)infoLog;
    if (length) *length = 0;
}

/* ---- cull/front face - tracked, never applied, see ps5gl.h ---- */
static GLenum s_cull_mode = GL_BACK, s_front_face = GL_CCW;
/* Tracked, never applied - see GL_FILL/GL_LINE's own comment in ps5gl.h. */
void glPolygonMode(GLenum face, GLenum mode) {
    if (face != GL_FRONT_AND_BACK) { set_error(GL_INVALID_ENUM); return; }
    if (mode != GL_FILL && mode != GL_LINE) set_error(GL_INVALID_ENUM);
}
void glBegin(GLenum mode) { (void)mode; /* never actually invoked - see ps5gl.h */ }
void glEnd(void) { }
void glCullFace(GLenum mode) {
    if (mode != GL_FRONT && mode != GL_BACK) { set_error(GL_INVALID_ENUM); return; }
    s_cull_mode = mode;
}
void glFrontFace(GLenum mode) {
    if (mode != GL_CW && mode != GL_CCW) { set_error(GL_INVALID_ENUM); return; }
    s_front_face = mode;
}

/* glPolygonOffset itself: factor/units are accepted but ignored - only
 * whether GL_POLYGON_OFFSET_FILL is enabled matters (see glEnable/glDisable
 * above, which call ps5gpu_set_depth_decal), matching ps5gpu.c's fixed-offset
 * decal concept rather than GL's arbitrary factor/units. */
void glPolygonOffset(GLfloat factor, GLfloat units) { (void)factor; (void)units; }

/* ---- colour mask - tracked, never applied: ps5gpu.c always writes RGBA ---- */
static GLboolean s_color_mask[4] = { GL_TRUE, GL_TRUE, GL_TRUE, GL_TRUE };
void glColorMask(GLboolean red, GLboolean green, GLboolean blue, GLboolean alpha) {
    s_color_mask[0] = red; s_color_mask[1] = green; s_color_mask[2] = blue; s_color_mask[3] = alpha;
}

/* ---- blend equation / separate factors ---- */
void glBlendEquation(GLenum mode) { if (mode != GL_FUNC_ADD) set_error(GL_INVALID_OPERATION); }
void glBlendFuncSeparate(GLenum srcRGB, GLenum dstRGB, GLenum srcAlpha, GLenum dstAlpha) {
    (void)srcAlpha; (void)dstAlpha;   /* no independent alpha path underneath - see ps5gl.h */
    glBlendFunc(srcRGB, dstRGB);
}

/* ---- pixel store - no-op, see ps5gl.h ---- */
void glPixelStorei(GLenum pname, GLint param) {
    (void)param;
    if (pname != GL_UNPACK_ALIGNMENT && pname != GL_PACK_ALIGNMENT && pname != GL_UNPACK_ROW_LENGTH) set_error(GL_INVALID_ENUM);
}

/* Forward-declared: the real definition (with s_bound_rbo alongside it) is
 * down with the rest of the framebuffer state; glGetIntegerv needs it here. */
static GLuint s_bound_fbo;

/* ---- integer queries ---- */
void glGetIntegerv(GLenum pname, GLint *params) {
    switch (pname) {
        case GL_MAX_TEXTURE_SIZE: *params = 4096; break;              /* ps5gpu.c's own render targets top out well below this */
        case GL_MAX_VERTEX_ATTRIBS: *params = ATTR_COUNT; break;
        case GL_MAX_COMBINED_TEXTURE_IMAGE_UNITS: *params = UNIT_COUNT; break;
        case GL_ARRAY_BUFFER_BINDING: *params = (GLint)s_bound_array_buffer; break;
        case GL_TEXTURE_BINDING_2D: *params = (GLint)s_bound_texture[s_active_unit]; break;
        case GL_CURRENT_PROGRAM: *params = (GLint)s_current_program; break;
        case GL_FRAMEBUFFER_BINDING: *params = (GLint)s_bound_fbo; break;
        case GL_VIEWPORT: params[0] = s_viewport[0]; params[1] = s_viewport[1]; params[2] = s_viewport[2]; params[3] = s_viewport[3]; break;
        case GL_NUM_EXTENSIONS: *params = 0; break;
        case GL_DEPTH_WRITEMASK: *params = s_depth_writemask; break;
        case GL_MAJOR_VERSION: *params = 3; break;
        case GL_MINOR_VERSION: *params = 3; break;
        default: set_error(GL_INVALID_ENUM);
    }
}
const GLubyte *glGetStringi(GLenum name, GLuint index) { (void)name; (void)index; return NULL; }

/* ---- occlusion queries - stub, always "fully visible", see ps5gl.h ---- */
#define MAX_GL_QUERIES 256
typedef struct { int used; GLenum target; } Query;
static Query s_queries[MAX_GL_QUERIES];
static int s_query_count = 1;
static GLuint s_active_query;

void glGenQueries(GLsizei n, GLuint *ids) {
    for (GLsizei i = 0; i < n; i++) {
        if (s_query_count >= MAX_GL_QUERIES) { ids[i] = 0; continue; }
        int id = s_query_count++;
        s_queries[id].used = 1;
        ids[i] = (GLuint)id;
    }
}
void glDeleteQueries(GLsizei n, const GLuint *ids) { for (GLsizei i = 0; i < n; i++) if (ids[i] < MAX_GL_QUERIES) s_queries[ids[i]].used = 0; }
void glBeginQuery(GLenum target, GLuint id) {
    if (target != GL_SAMPLES_PASSED && target != GL_ANY_SAMPLES_PASSED) { set_error(GL_INVALID_ENUM); return; }
    if (id == 0 || id >= MAX_GL_QUERIES || !s_queries[id].used) { set_error(GL_INVALID_OPERATION); return; }
    s_queries[id].target = target;
    s_active_query = id;
}
void glEndQuery(GLenum target) { (void)target; s_active_query = 0; }
void glGetQueryObjectuiv(GLuint id, GLenum pname, GLuint *params) {
    if (id == 0 || id >= MAX_GL_QUERIES || !s_queries[id].used) { set_error(GL_INVALID_OPERATION); return; }
    if (pname == GL_QUERY_RESULT_AVAILABLE) { *params = GL_TRUE; return; }
    if (pname == GL_QUERY_RESULT) { *params = 0xFFFFFFFFu; return; }   /* "fully visible" - see ps5gl.h */
    set_error(GL_INVALID_ENUM);
}

/* ---- framebuffers / renderbuffers - tracked, NOT wired to real render
 * targets, see the long comment in ps5gl.h. ---- */
#define MAX_GL_FBOS 64
#define MAX_GL_RBOS 64
/* rt_index >= 0 once glFramebufferTexture2D has actually backed color_tex
 * with a real ps5gpu_target_create() render target - see there. */
typedef struct { int used; GLuint color_tex, depth_tex, depth_rbo; int rt_index; } Fbo;
typedef struct { int used; GLenum internalformat; GLsizei width, height; } Rbo;
static Fbo s_fbos[MAX_GL_FBOS];
static Rbo s_rbos[MAX_GL_RBOS];
static int s_fbo_count = 1, s_rbo_count = 1;   /* 0 is the (real) default framebuffer */
static GLuint s_bound_rbo;   /* s_bound_fbo is forward-declared above, next to glGetIntegerv */

void glGenFramebuffers(GLsizei n, GLuint *framebuffers) {
    for (GLsizei i = 0; i < n; i++) {
        if (s_fbo_count >= MAX_GL_FBOS) { framebuffers[i] = 0; continue; }
        int id = s_fbo_count++;
        memset(&s_fbos[id], 0, sizeof(Fbo));
        s_fbos[id].used = 1;
        s_fbos[id].rt_index = -1;
        framebuffers[i] = (GLuint)id;
    }
}
void glDeleteFramebuffers(GLsizei n, const GLuint *framebuffers) {
    for (GLsizei i = 0; i < n; i++) if (framebuffers[i] < MAX_GL_FBOS) s_fbos[framebuffers[i]].used = 0;
}
/* Real: 0 returns to the main scene; a complete FBO (see
 * glFramebufferTexture2D) actually selects its ps5gpu_target_create() render
 * target via ps5gpu_set_target(). An incomplete FBO falls back to the scene
 * too, same as an unrecognised `target` value elsewhere in this file - drawn
 * somewhere visible rather than silently going nowhere. As with a real
 * user target (see ps5gpu.h), the caller must still set its own
 * glViewport/glScissor to match the FBO's size - this does not do it
 * automatically, matching real GL's own division of responsibility.
 *
 * The actual ps5gpu_set_target() call is DEFERRED to the next draw (see
 * bind_program_and_textures), not made here - real GL code routinely calls
 * glBindFramebuffer + glFramebufferTexture2D to set an attachment up before
 * any frame has begun (this test title's own first attempt did exactly
 * that), and ps5gpu_set_target()/emit_frame_state() touch the per-frame
 * command buffer, which ps5gpu_begin_frame() has not initialized yet that
 * early - confirmed on hardware as a hard crash (SIGSEGV jumping to address
 * 0, the DCB's out-of-space callback being NULL) before this was deferred. */
void glBindFramebuffer(GLenum target, GLuint framebuffer) {
    (void)target;
    s_bound_fbo = framebuffer;
}

/* Applies whatever glBindFramebuffer last selected, right before a draw -
 * see its own comment on why this can't happen at bind time. Called once
 * per draw from bind_program_and_textures(); ps5gpu_set_target() itself is
 * cheap to call repeatedly (the fixed targets already rely on that for the
 * "sky, then world" pattern), so no dirty-tracking is needed here. */
static void apply_bound_framebuffer(void) {
    if (s_bound_fbo == 0) { ps5gpu_set_target(PS5GPU_TARGET_SCENE); return; }
    if (s_bound_fbo >= MAX_GL_FBOS || !s_fbos[s_bound_fbo].used || s_fbos[s_bound_fbo].rt_index < 0) {
        ps5gpu_set_target(PS5GPU_TARGET_SCENE);
        return;
    }
    ps5gpu_set_target(PS5GPU_TARGET_USER0 + s_fbos[s_bound_fbo].rt_index);
}

/* Real: backs the attached texture with an actual ps5gpu_target_create()
 * render target, sized from whatever glTexImage2D last recorded for it (even
 * a NULL-data call, which is the normal way to size a texture meant for this
 * - see glTexImage2D's own comment). From then on, sampling that texture
 * (bind it and draw - see bind_program_and_textures) reads back what was
 * actually rendered into the target, through the redirection
 * TexParams.rt_index records.
 *
 * GL_COLOR_ATTACHMENT0 is the ordinary case. A GL_DEPTH_ATTACHMENT with no
 * colour attachment (the standard shadow-map pattern: a depth-only FBO,
 * glDrawBuffer(GL_NONE)) is ALSO real, but through the same convention
 * ps5gpu.c's own built-in shadow target already uses: ps5gpu.c has no true
 * GPU depth-buffer-as-sampled-texture path (see PS5GPU_TARGET_SHADOW's own
 * comment - "packed into two colour channels", not read from the Z-buffer
 * directly), so the depth texture is backed by an ordinary render target and
 * the CALLER'S OWN SHADER must write depth as a colour output for anything
 * meaningful to end up there - the depth values ps5gpu.c's real Z-buffer
 * computes during that pass are not what a later sample of this texture
 * sees. A caller expecting genuine hardware depth-comparison sampling
 * (sampler2DShadow, GL_TEXTURE_COMPARE_MODE) will not get it.
 *
 * If BOTH a colour and a depth texture are attached to the same FBO, the
 * colour attachment wins (matches what a real render normally wants) and the
 * depth one is tracked only, same as ps5gpu_target_create's own single depth
 * buffer already covers ordinary depth testing during that pass. */
void glFramebufferTexture2D(GLenum target, GLenum attachment, GLenum textarget, GLuint texture, GLint level) {
    (void)target; (void)textarget; (void)level;
    if (s_bound_fbo == 0 || s_bound_fbo >= MAX_GL_FBOS) { set_error(GL_INVALID_OPERATION); return; }
    Fbo *fb = &s_fbos[s_bound_fbo];
    if (attachment == GL_COLOR_ATTACHMENT0) {
        fb->color_tex = texture;
        if (texture > 0 && texture < MAX_GL_TEXTURES && s_tex_params[texture].width > 0) {
            int idx = ps5gpu_target_create(s_tex_params[texture].width, s_tex_params[texture].height);
            fb->rt_index = idx;   /* -1 on failure - glCheckFramebufferStatus then reports incomplete */
            s_tex_params[texture].rt_index = idx;
        } else {
            fb->rt_index = -1;   /* texture never sized via glTexImage2D - nothing to create yet */
        }
    } else if (attachment == GL_DEPTH_ATTACHMENT) {
        fb->depth_tex = texture;
        if (fb->color_tex == 0 && fb->rt_index < 0 &&
            texture > 0 && texture < MAX_GL_TEXTURES && s_tex_params[texture].width > 0) {
            int idx = ps5gpu_target_create(s_tex_params[texture].width, s_tex_params[texture].height);
            fb->rt_index = idx;
            s_tex_params[texture].rt_index = idx;   /* see the function comment: depth-as-colour, same as the built-in shadow target */
        }
    } else {
        set_error(GL_INVALID_ENUM);
    }
}
GLenum glCheckFramebufferStatus(GLenum target) {
    (void)target;
    if (s_bound_fbo == 0) return GL_FRAMEBUFFER_COMPLETE;
    if (s_bound_fbo >= MAX_GL_FBOS || !s_fbos[s_bound_fbo].used) return GL_FRAMEBUFFER_UNSUPPORTED;
    return s_fbos[s_bound_fbo].rt_index >= 0 ? GL_FRAMEBUFFER_COMPLETE : GL_FRAMEBUFFER_UNSUPPORTED;
}
void glGenRenderbuffers(GLsizei n, GLuint *renderbuffers) {
    for (GLsizei i = 0; i < n; i++) {
        if (s_rbo_count >= MAX_GL_RBOS) { renderbuffers[i] = 0; continue; }
        int id = s_rbo_count++;
        memset(&s_rbos[id], 0, sizeof(Rbo));
        s_rbos[id].used = 1;
        renderbuffers[i] = (GLuint)id;
    }
}
void glDeleteRenderbuffers(GLsizei n, const GLuint *renderbuffers) {
    for (GLsizei i = 0; i < n; i++) if (renderbuffers[i] < MAX_GL_RBOS) s_rbos[renderbuffers[i]].used = 0;
}
void glBindRenderbuffer(GLenum target, GLuint renderbuffer) { (void)target; s_bound_rbo = renderbuffer; }
void glRenderbufferStorage(GLenum target, GLenum internalformat, GLsizei width, GLsizei height) {
    (void)target;
    if (s_bound_rbo == 0 || s_bound_rbo >= MAX_GL_RBOS) { set_error(GL_INVALID_OPERATION); return; }
    s_rbos[s_bound_rbo].internalformat = internalformat;
    s_rbos[s_bound_rbo].width = width;
    s_rbos[s_bound_rbo].height = height;
}
void glFramebufferRenderbuffer(GLenum target, GLenum attachment, GLenum renderbuffertarget, GLuint renderbuffer) {
    (void)target; (void)renderbuffertarget;
    if (s_bound_fbo == 0 || s_bound_fbo >= MAX_GL_FBOS) { set_error(GL_INVALID_OPERATION); return; }
    if (attachment == GL_DEPTH_ATTACHMENT) s_fbos[s_bound_fbo].depth_rbo = renderbuffer;
    else set_error(GL_INVALID_ENUM);
}
void glGenerateMipmap(GLenum target) { (void)target; /* no-op - see ps5gl.h */ }
void glDrawBuffer(GLenum buf) { (void)buf; /* no-op - see ps5gl.h */ }
void glReadBuffer(GLenum src) { (void)src; /* no-op - see ps5gl.h */ }

/* ---- generic attribute locations - real, fixed mapping, see ps5gl.h ---- */
void glBindAttribLocation(GLuint program, GLuint index, const char *name) { (void)program; (void)index; (void)name; }
GLint glGetAttribLocation(GLuint program, const char *name) {
    (void)program;
    if (strcmp(name, "gpu_Vertex") == 0) return 0;
    if (strcmp(name, "gpu_TexCoord") == 0) return 1;
    if (strcmp(name, "gpu_Color") == 0) return 2;
    return -1;
}
void glDetachShader(GLuint program, GLuint shader) { (void)program; (void)shader; }

/* ---- constant vertex attribute values - see the s_attrib_constant array
 * declared earlier, next to gather_vertex(), which actually reads it. ---- */
void glVertexAttrib1f(GLuint index, GLfloat v0) { if (index < ATTR_COUNT) { s_attrib_constant[index][0] = v0; s_attrib_constant[index][1] = 0; s_attrib_constant[index][2] = 0; s_attrib_constant[index][3] = 1; } }
void glVertexAttrib2f(GLuint index, GLfloat v0, GLfloat v1) { if (index < ATTR_COUNT) { s_attrib_constant[index][0] = v0; s_attrib_constant[index][1] = v1; s_attrib_constant[index][2] = 0; s_attrib_constant[index][3] = 1; } }
void glVertexAttrib3f(GLuint index, GLfloat v0, GLfloat v1, GLfloat v2) { if (index < ATTR_COUNT) { s_attrib_constant[index][0] = v0; s_attrib_constant[index][1] = v1; s_attrib_constant[index][2] = v2; s_attrib_constant[index][3] = 1; } }
void glVertexAttrib4f(GLuint index, GLfloat v0, GLfloat v1, GLfloat v2, GLfloat v3) { if (index < ATTR_COUNT) { s_attrib_constant[index][0] = v0; s_attrib_constant[index][1] = v1; s_attrib_constant[index][2] = v2; s_attrib_constant[index][3] = v3; } }

/* ---- more uniform variants - discarded, see ps5gl.h ---- */
void glUniform1iv(GLint location, GLsizei count, const GLint *value) { (void)location; (void)count; (void)value; }
void glUniform2iv(GLint location, GLsizei count, const GLint *value) { (void)location; (void)count; (void)value; }
void glUniform3iv(GLint location, GLsizei count, const GLint *value) { (void)location; (void)count; (void)value; }
void glUniform4iv(GLint location, GLsizei count, const GLint *value) { (void)location; (void)count; (void)value; }
void glUniform1ui(GLint location, GLuint v0) { (void)location; (void)v0; }
void glUniform2uiv(GLint location, GLsizei count, const GLuint *value) { (void)location; (void)count; (void)value; }
void glUniform3uiv(GLint location, GLsizei count, const GLuint *value) { (void)location; (void)count; (void)value; }
void glUniformMatrix2fv(GLint location, GLsizei count, GLboolean transpose, const GLfloat *value) { (void)location; (void)count; (void)transpose; (void)value; }
void glUniformMatrix2x3fv(GLint location, GLsizei count, GLboolean transpose, const GLfloat *value) { (void)location; (void)count; (void)transpose; (void)value; }
void glUniformMatrix2x4fv(GLint location, GLsizei count, GLboolean transpose, const GLfloat *value) { (void)location; (void)count; (void)transpose; (void)value; }
void glUniformMatrix3x2fv(GLint location, GLsizei count, GLboolean transpose, const GLfloat *value) { (void)location; (void)count; (void)transpose; (void)value; }
void glUniformMatrix3x4fv(GLint location, GLsizei count, GLboolean transpose, const GLfloat *value) { (void)location; (void)count; (void)transpose; (void)value; }
void glUniformMatrix4x2fv(GLint location, GLsizei count, GLboolean transpose, const GLfloat *value) { (void)location; (void)count; (void)transpose; (void)value; }
void glUniformMatrix4x3fv(GLint location, GLsizei count, GLboolean transpose, const GLfloat *value) { (void)location; (void)count; (void)transpose; (void)value; }
void glGetUniformfv(GLuint program, GLint location, GLfloat *params) { (void)program; (void)location; *params = 0.0f; set_error(GL_INVALID_OPERATION); }
void glGetUniformiv(GLuint program, GLint location, GLint *params) { (void)program; (void)location; *params = 0; set_error(GL_INVALID_OPERATION); }
void glGetUniformuiv(GLuint program, GLint location, GLuint *params) { (void)program; (void)location; *params = 0; set_error(GL_INVALID_OPERATION); }

/* ---- real: answers from the same TexParams glTexParameteri already fills ---- */
void glGetTexParameteriv(GLenum target, GLenum pname, GLint *params) {
    if (target != GL_TEXTURE_2D) { set_error(GL_INVALID_ENUM); return; }
    GLuint tex = s_bound_texture[s_active_unit];
    if (tex >= MAX_GL_TEXTURES) { set_error(GL_INVALID_OPERATION); return; }
    TexParams *p = &s_tex_params[tex];
    switch (pname) {
        case GL_TEXTURE_WRAP_S: *params = p->wrap_s; break;
        case GL_TEXTURE_WRAP_T: *params = p->wrap_t; break;
        case GL_TEXTURE_MIN_FILTER: *params = p->min_filter; break;
        case GL_TEXTURE_MAG_FILTER: *params = p->mag_filter; break;
        default: set_error(GL_INVALID_ENUM);
    }
}

/* ---- buffer mapping - real, see ps5gl.h ---- */
void *glMapBuffer(GLenum target, GLenum access) {
    (void)access;
    GLuint *slot = bound_buffer_slot(target);
    if (!slot || *slot == 0 || *slot >= MAX_GL_BUFFERS || !s_buffers[*slot].data) { set_error(GL_INVALID_OPERATION); return NULL; }
    return s_buffers[*slot].data;
}
GLboolean glUnmapBuffer(GLenum target) {
    GLuint *slot = bound_buffer_slot(target);
    if (!slot || *slot == 0 || *slot >= MAX_GL_BUFFERS) { set_error(GL_INVALID_OPERATION); return GL_FALSE; }
    return GL_TRUE;
}

/* ---- not implemented - no readback path, see ps5gl.h ---- */
void glReadPixels(GLint x, GLint y, GLsizei width, GLsizei height, GLenum format, GLenum type, void *pixels) {
    (void)x; (void)y; (void)width; (void)height; (void)format; (void)type; (void)pixels;
    set_error(GL_INVALID_OPERATION);
}
void glCopyTexImage2D(GLenum target, GLint level, GLenum internalformat, GLint x, GLint y,
                       GLsizei width, GLsizei height, GLint border) {
    (void)target; (void)level; (void)internalformat; (void)x; (void)y; (void)width; (void)height; (void)border;
    set_error(GL_INVALID_OPERATION);
}
void glCopyTexSubImage2D(GLenum target, GLint level, GLint xoffset, GLint yoffset, GLint x, GLint y,
                          GLsizei width, GLsizei height) {
    (void)target; (void)level; (void)xoffset; (void)yoffset; (void)x; (void)y; (void)width; (void)height;
    set_error(GL_INVALID_OPERATION);
}
void glGetTexImage(GLenum target, GLint level, GLenum format, GLenum type, void *pixels) {
    (void)target; (void)level; (void)format; (void)type; (void)pixels;
    set_error(GL_INVALID_OPERATION);
}

void glLineWidth(GLfloat width) { (void)width; /* no-op - ps5gpu.c never draws lines, see ps5gl.h */ }

void glBlendEquationSeparate(GLenum modeRGB, GLenum modeAlpha) {
    (void)modeAlpha;
    if (modeRGB != GL_FUNC_ADD) set_error(GL_INVALID_OPERATION);
}

void glGetTexLevelParameteriv(GLenum target, GLint level, GLenum pname, GLint *params) {
    if (target != GL_TEXTURE_2D || level != 0) { set_error(GL_INVALID_ENUM); return; }
    GLuint tex = s_bound_texture[s_active_unit];
    if (tex >= MAX_GL_TEXTURES) { set_error(GL_INVALID_OPERATION); return; }
    switch (pname) {
        case GL_TEXTURE_WIDTH: *params = s_tex_params[tex].width; break;
        case GL_TEXTURE_HEIGHT: *params = s_tex_params[tex].height; break;
        default: set_error(GL_INVALID_ENUM);
    }
}

void glUniform1fv(GLint location, GLsizei count, const GLfloat *value) { (void)location; (void)count; (void)value; }
void glUniform2fv(GLint location, GLsizei count, const GLfloat *value) { (void)location; (void)count; (void)value; }
void glUniform3fv(GLint location, GLsizei count, const GLfloat *value) { (void)location; (void)count; (void)value; }
void glUniform1uiv(GLint location, GLsizei count, const GLuint *value) { (void)location; (void)count; (void)value; }
void glVertexAttribI1i(GLuint index, GLint v0) { (void)index; (void)v0; }
void glVertexAttribI1ui(GLuint index, GLuint v0) { (void)index; (void)v0; }
void glVertexAttribI2i(GLuint index, GLint v0, GLint v1) { (void)index; (void)v0; (void)v1; }
void glVertexAttribI2ui(GLuint index, GLuint v0, GLuint v1) { (void)index; (void)v0; (void)v1; }
void glVertexAttribI3i(GLuint index, GLint v0, GLint v1, GLint v2) { (void)index; (void)v0; (void)v1; (void)v2; }
void glVertexAttribI3ui(GLuint index, GLuint v0, GLuint v1, GLuint v2) { (void)index; (void)v0; (void)v1; (void)v2; }
void glVertexAttribI4i(GLuint index, GLint v0, GLint v1, GLint v2, GLint v3) { (void)index; (void)v0; (void)v1; (void)v2; (void)v3; }
void glVertexAttribI4ui(GLuint index, GLuint v0, GLuint v1, GLuint v2, GLuint v3) { (void)index; (void)v0; (void)v1; (void)v2; (void)v3; }

/* ---- not implemented - no cube map or 3D texture resource path in
 * ps5gpu.c, see the GL_TEXTURE_CUBE_MAP comment in ps5gl.h ---- */
void glTexImage3D(GLenum target, GLint level, GLint internalformat, GLsizei width, GLsizei height,
                   GLsizei depth, GLint border, GLenum format, GLenum type, const void *pixels) {
    (void)target; (void)level; (void)internalformat; (void)width; (void)height;
    (void)depth; (void)border; (void)format; (void)type; (void)pixels;
    set_error(GL_INVALID_OPERATION);
}

/* ---- not implemented - no tessellation or compute pipeline in ps5gpu.c,
 * see ps5gl.h's own comment on why. ---- */
void glPatchParameteri(GLenum pname, GLint value) { (void)pname; (void)value; set_error(GL_INVALID_OPERATION); }
void glDispatchCompute(GLuint num_groups_x, GLuint num_groups_y, GLuint num_groups_z) {
    (void)num_groups_x; (void)num_groups_y; (void)num_groups_z;
    set_error(GL_INVALID_OPERATION);
}
void glMemoryBarrier(GLbitfield barriers) { (void)barriers; set_error(GL_INVALID_OPERATION); }
void glBindImageTexture(GLuint unit, GLuint texture, GLint level, GLboolean layered, GLint layer, GLenum access, GLenum format) {
    (void)unit; (void)texture; (void)level; (void)layered; (void)layer; (void)access; (void)format;
    set_error(GL_INVALID_OPERATION);
}

void glFinish(void) { /* no-op - see ps5gl.h */ }
void glDebugMessageCallback(GLDEBUGPROC callback, const void *userParam) { (void)callback; (void)userParam; /* never invoked - see ps5gl.h */ }
