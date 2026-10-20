/* PS5GL - a small OpenGL-shaped API over ps5gpu.c (AGC), for PS5 homebrew
 * titles built with ps5link. Milestone 2 of the project: milestone 1 found
 * that combining two textures needs PS5GPU_BLEND_MULTIPLY multi-pass
 * blending rather than a two-texture pixel program - AMD GCN/RDNA only
 * delivers 16 dwords of user data directly per shader stage, and 2 textures
 * + 2 samplers need 24 (see backend/ps5gpu.c's ps5gpu_program_new and the
 * PS5GPU_BLEND_MULTIPLY comment in ps5gpu.h for the full story).
 *
 * IMPORTANT - what this is NOT: there is no GLSL compiler for AGC anywhere
 * in this toolchain (investigated at length before this library was
 * started - Mesa's RADV/ACO needs either real AMD hardware or a from-source
 * Mesa build neither available here, and generic tools like llvm-spirv only
 * support the OpenCL extended instruction set, not GLSL's). So:
 *
 *   glCreateShader / glShaderSource / glCompileShader DO NOT compile GLSL.
 *   They exist so calling code has somewhere to put a source string, but
 *   compilation always "succeeds" trivially and glGetShaderiv(COMPILE_STATUS)
 *   always reports success - the real program only becomes runnable once
 *   ps5gl_program_use_precompiled() attaches a real AGC container to it (see
 *   below). A caller ignoring that and expecting its GLSL text to run will
 *   silently get the built-in texture*colour program instead.
 *
 * Everything else here - buffers, textures, vertex arrays, draw calls, blend
 * and depth state - is real: it drives ps5gpu.c the same way a hand-written
 * title already does, just through GL-shaped entry points so code written
 * against desktop GL needs less rewriting to target this renderer.
 */
#ifndef PS5GL_H
#define PS5GL_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* ---- standard GL type names, defined locally: no GL headers exist in this
 * toolchain, but keeping the same names/widths means code written against
 * desktop GL can mostly recompile unchanged. ---- */
typedef unsigned int   GLenum;
typedef unsigned char  GLboolean;
typedef unsigned int   GLbitfield;
typedef signed char    GLbyte;
typedef short          GLshort;
typedef int            GLint;
typedef int            GLsizei;
typedef unsigned char  GLubyte;
typedef unsigned short GLushort;
typedef unsigned int   GLuint;
typedef float          GLfloat;
typedef float          GLclampf;
typedef void           GLvoid;
typedef intptr_t       GLsizeiptr;
typedef intptr_t       GLintptr;
typedef char           GLchar;
/* Real GL headers define this as the platform calling convention (only
 * meaningful on Windows' stdcall ABI); empty here, same as on every other
 * platform's GL headers. */
#define APIENTRY

#define GL_FALSE 0
#define GL_TRUE  1

/* Primitives - only triangle lists are wired to ps5gpu.c (the only topology
 * ps5gpu_draw's index buffer sets up); other values are accepted as real GL
 * enums (so calling code compiles) but refused as a no-op draw by
 * glDrawArrays/glDrawElements, rather than silently drawing the wrong shape. */
#define GL_TRIANGLES 0x0004
#define GL_TRIANGLE_STRIP 0x0005
#define GL_POINTS 0x0000
/* Tessellation input/output primitives - see glPatchParameteri's own comment
 * on why these exist but tessellation itself does not work. */
#define GL_PATCHES 0x000E

/* Buffers */
#define GL_ARRAY_BUFFER         0x8892
#define GL_ELEMENT_ARRAY_BUFFER 0x8893
#define GL_STATIC_DRAW          0x88E4
#define GL_DYNAMIC_DRAW         0x88E8
#define GL_STREAM_DRAW          0x88E0

/* Vertex attribute types */
#define GL_BYTE           0x1400
#define GL_UNSIGNED_BYTE  0x1401
#define GL_SHORT          0x1402
#define GL_UNSIGNED_SHORT 0x1403
#define GL_UNSIGNED_INT   0x1405
#define GL_FLOAT          0x1406

/* Texturing.
 * GL_TEXTURE0..11: libmod_3d's real shaders bind up to 12 units at once (a
 * PBR material's albedo/normal/metal-rough/AO/emissive plus shadow maps and
 * more) - numbers only, real GL values, so object-management code (which
 * unit is bound where) works. Only unit 0 actually reaches a draw, though:
 * ps5gpu.c's hardware ceiling of 16 direct user-data dwords per shader stage
 * (see PS5GPU_BLEND_MULTIPLY's own comment in ps5gpu.h) means even 2 full
 * texture+sampler pairs already do not fit directly, let alone 12 - nothing
 * close to a real fix exists yet, so binding textures to units 1-11 is
 * accepted and remembered, but has no visible effect on what gets drawn. */
#define GL_TEXTURE_2D       0x0DE1
#define GL_TEXTURE0         0x84C0
#define GL_TEXTURE1         0x84C1
#define GL_TEXTURE2         0x84C2
#define GL_TEXTURE3         0x84C3
#define GL_TEXTURE4         0x84C4
#define GL_TEXTURE5         0x84C5
#define GL_TEXTURE6         0x84C6
#define GL_TEXTURE7         0x84C7
#define GL_TEXTURE8         0x84C8
#define GL_TEXTURE9         0x84C9
#define GL_TEXTURE10        0x84CA
#define GL_TEXTURE11        0x84CB
#define GL_TEXTURE_WRAP_S   0x2802
#define GL_TEXTURE_WRAP_T   0x2803
#define GL_TEXTURE_MIN_FILTER 0x2801
#define GL_TEXTURE_MAG_FILTER 0x2800
#define GL_TEXTURE_BORDER_COLOR 0x1004   /* tracked (glTexParameterfv), never applied - ps5gpu.c has no border colour concept */
#define GL_NEAREST          0x2600
#define GL_LINEAR           0x2601
/* Mipmap filter modes: accepted by glTexParameteri and treated as their
 * non-mipmap equivalent (GL_LINEAR/GL_NEAREST) - ps5gpu.c textures have
 * exactly one mip level (see glGenerateMipmap), so there is never a chain to
 * pick a mip filter within. */
#define GL_NEAREST_MIPMAP_NEAREST 0x2700
#define GL_LINEAR_MIPMAP_NEAREST  0x2701
#define GL_NEAREST_MIPMAP_LINEAR  0x2702
#define GL_LINEAR_MIPMAP_LINEAR   0x2703
#define GL_REPEAT           0x2901
#define GL_CLAMP_TO_EDGE    0x812F
#define GL_CLAMP_TO_BORDER  0x812D   /* accepted by glTexParameteri, treated as GL_CLAMP_TO_EDGE - see gl_wrap_to_ps5gpu in ps5gl.c */
#define GL_MIRRORED_REPEAT  0x8370
#define GL_RED              0x1903
#define GL_RGB              0x1907
#define GL_RGBA             0x1908
/* Internal formats accepted by glTexImage2D's internalformat parameter -
 * still ignored the same way GL_RGBA/GL_RGBA8 already were (see
 * glTexImage2D's own comment: only GL_RGBA/GL_UNSIGNED_BYTE actual data is
 * supported, regardless of what internal format is requested). */
#define GL_R8       0x8229
#define GL_RG       0x8227
#define GL_RG8      0x822B
#define GL_RGBA8    0x8058
#define GL_RGB16F   0x881B
#define GL_RGBA16F  0x881A
#define GL_RG16F    0x822F

/* Mip level range hints - accepted by glTexParameteri, never applied:
 * ps5gpu.c textures have exactly one mip level (see glGenerateMipmap), so
 * there is no range to narrow. */
#define GL_TEXTURE_BASE_LEVEL 0x813C
#define GL_TEXTURE_MAX_LEVEL  0x813D

/* Cube maps - NOT implemented. ps5gpu.c's Texture/desc_texture only knows
 * Texture2D (see desc_texture's bits() call setting the resource dimension
 * field to a hardcoded Texture2D value) - there is no cubemap resource
 * descriptor or 6-face upload path underneath. glBindTexture/glTexImage2D
 * accept GL_TEXTURE_CUBE_MAP_POSITIVE_X..NEGATIVE_Z as a target (so calling
 * code compiles) but treat it as an ordinary GL_TEXTURE_2D face-by-face,
 * which is wrong for anything that actually samples it as a cube in a
 * shader - real cubemap support needs a new resource descriptor path in
 * ps5gpu.c first. */
#define GL_TEXTURE_CUBE_MAP            0x8513
#define GL_TEXTURE_CUBE_MAP_POSITIVE_X 0x8515
#define GL_TEXTURE_CUBE_MAP_NEGATIVE_X 0x8516
#define GL_TEXTURE_CUBE_MAP_POSITIVE_Y 0x8517
#define GL_TEXTURE_CUBE_MAP_NEGATIVE_Y 0x8518
#define GL_TEXTURE_CUBE_MAP_POSITIVE_Z 0x8519
#define GL_TEXTURE_CUBE_MAP_NEGATIVE_Z 0x851A
#define GL_TEXTURE_WRAP_R              0x8072

/* NOT implemented - no 3D texture resource path in ps5gpu.c either. */
void glTexImage3D(GLenum target, GLint level, GLint internalformat, GLsizei width, GLsizei height,
                   GLsizei depth, GLint border, GLenum format, GLenum type, const void *pixels);

/* State */
#define GL_DEPTH_TEST 0x0B71
#define GL_BLEND      0x0BE2
#define GL_CULL_FACE  0x0B44
#define GL_SCISSOR_TEST 0x0C11

#define GL_LEQUAL 0x0203   /* the only depth mode ps5gpu.c implements */

/* Blend: real GL constants, but ps5gl only recognises the two combinations
 * ps5gpu.c supports - see glBlendFunc below. */
#define GL_ZERO                0
#define GL_ONE                 1
#define GL_SRC_ALPHA           0x0302
#define GL_ONE_MINUS_SRC_ALPHA 0x0303
#define GL_ONE_MINUS_DST_ALPHA 0x0305
#define GL_DST_COLOR           0x0306
/* Real GL value, but glBlendEquation only ever accepts GL_FUNC_ADD - see
 * there. Declared so code that references this constant (even in a branch
 * that never executes on this backend) compiles. */
#define GL_FUNC_SUBTRACT 0x800A

/* Shaders (see the file-level comment: these do not compile GLSL) */
#define GL_VERTEX_SHADER   0x8B31
#define GL_FRAGMENT_SHADER 0x8B30
#define GL_COMPILE_STATUS  0x8B81
#define GL_LINK_STATUS     0x8B82
#define GL_INFO_LOG_LENGTH 0x8B84   /* glGetShaderiv/glGetProgramiv: always 0 - see glGetShaderInfoLog */
/* Tessellation shader stages - NOT implemented, see glPatchParameteri. */
#define GL_TESS_CONTROL_SHADER    0x8E88
#define GL_TESS_EVALUATION_SHADER 0x8E87

/* Errors */
#define GL_NO_ERROR          0
#define GL_INVALID_ENUM      0x0500
#define GL_INVALID_VALUE     0x0501
#define GL_INVALID_OPERATION 0x0502

/* ---- lifecycle ---- */

/* Brings up ps5gpu.c and the library's own object tables. Returns 0 on
 * success; ps5gl_last_error() names the step that failed (forwards
 * ps5gpu_last_error() for anything below this layer). Call once at startup. */
int ps5gl_init(void);
const char *ps5gl_last_error(void);

/* A frame: ties directly to ps5gpu_begin_frame/end_frame. */
void ps5gl_begin_frame(void);
void ps5gl_end_frame(void);

/* ---- textures ---- */
void glGenTextures(GLsizei n, GLuint *textures);
void glDeleteTextures(GLsizei n, const GLuint *textures);
void glBindTexture(GLenum target, GLuint texture);
void glActiveTexture(GLenum texture);   /* GL_TEXTURE0 or GL_TEXTURE0+1 - two units, see below */
/* Only GL_RGBA/GL_UNSIGNED_BYTE, level 0, no border - ps5gpu_texture_upload's
 * own limits. Other formats are accepted and converted to RGBA8 where cheap,
 * refused (a no-op) otherwise. */
void glTexImage2D(GLenum target, GLint level, GLint internalformat, GLsizei width, GLsizei height,
                   GLint border, GLenum format, GLenum type, const void *pixels);
void glTexParameteri(GLenum target, GLenum pname, GLint param);
/* Tracked (GL_TEXTURE_BORDER_COLOR only), never applied - see its own #define. */
void glTexParameterfv(GLenum target, GLenum pname, const GLfloat *params);

/* ---- buffers ---- */
void glGenBuffers(GLsizei n, GLuint *buffers);
void glDeleteBuffers(GLsizei n, const GLuint *buffers);
void glBindBuffer(GLenum target, GLuint buffer);
/* Copies data into the library's own storage now - there is no persistent
 * GPU buffer object underneath (ps5gpu_draw copies vertices into its
 * per-frame arena itself, every draw). usage is accepted and ignored. */
void glBufferData(GLenum target, intptr_t size, const void *data, GLenum usage);
void glBufferSubData(GLenum target, intptr_t offset, intptr_t size, const void *data);

/* ---- vertex arrays ---- */
/* A real VAO abstraction: up to 4 attributes (position, uv, an unused slot,
 * colour - Ps5GpuVertex's own layout), recorded per array object and applied
 * when it is bound. Vertex data is read from whatever buffer glBufferData
 * last filled for the currently bound GL_ARRAY_BUFFER at draw time - matching
 * ps5gpu_draw's own model of "the CPU-side array IS the vertex buffer". */
void glGenVertexArrays(GLsizei n, GLuint *arrays);
void glDeleteVertexArrays(GLsizei n, const GLuint *arrays);
void glBindVertexArray(GLuint array);
void glVertexAttribPointer(GLuint index, GLint size, GLenum type, GLboolean normalized,
                            GLsizei stride, const void *pointer);
void glEnableVertexAttribArray(GLuint index);
void glDisableVertexAttribArray(GLuint index);

/* ---- drawing ---- */
void glDrawArrays(GLenum mode, GLint first, GLsizei count);
void glDrawElements(GLenum mode, GLsizei count, GLenum type, const void *indices);

/* ---- shaders (see the file-level comment) ---- */
GLuint glCreateShader(GLenum type);
void glDeleteShader(GLuint shader);
void glShaderSource(GLuint shader, GLsizei count, const char *const *string, const GLint *length);
void glCompileShader(GLuint shader);
void glGetShaderiv(GLuint shader, GLenum pname, GLint *params);
GLuint glCreateProgram(void);
void glDeleteProgram(GLuint program);
void glAttachShader(GLuint program, GLuint shader);
void glLinkProgram(GLuint program);
void glGetProgramiv(GLuint program, GLenum pname, GLint *params);
void glUseProgram(GLuint program);

/* The real way to make a program do something other than the built-in
 * texture*colour draw: hand it a precompiled AGC container - the .sb bytes
 * agcpack.py produces, embedded as a C array the same way
 * shaders_build/textured_p_sb.h is. Returns 0 on failure (container
 * rejected, or the program had already been given one). */
int ps5gl_program_use_precompiled(GLuint program, const unsigned char *container, unsigned int length);

/* ---- uniforms (only the position matrix is wired to anything real: see
 * comment) ---- */
GLint glGetUniformLocation(GLuint program, const char *name);
/* Only the uniform named "mvp" (a mat4) does anything - it is
 * ps5gpu_set_mvp's matrix, the one real per-draw uniform ps5gpu.c's vertex
 * program reads. Any other uniform location glGetUniformLocation hands out
 * is accepted by these calls and silently discarded, since there is no
 * generic constant-buffer path yet. */
void glUniformMatrix4fv(GLint location, GLsizei count, GLboolean transpose, const GLfloat *value);
void glUniform1i(GLint location, GLint v0);   /* accepted, e.g. for a "tex0" sampler uniform; discarded */
void glUniform1f(GLint location, GLfloat v0);
void glUniform4f(GLint location, GLfloat v0, GLfloat v1, GLfloat v2, GLfloat v3);

/* ---- state ---- */
void glEnable(GLenum cap);
void glDisable(GLenum cap);
GLboolean glIsEnabled(GLenum cap);
void glDepthFunc(GLenum func);     /* only GL_LEQUAL exists underneath; anything else is a no-op */
void glDepthMask(GLboolean flag);
/* Recognises exactly two (sfactor,dfactor) pairs, both already proven on
 * hardware: (GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA) -> PS5GPU_BLEND_ALPHA, and
 * (GL_DST_COLOR, GL_ZERO) -> PS5GPU_BLEND_MULTIPLY (milestone 2's own
 * result). Any other combination is refused: blending stays at whatever it
 * was, not silently wrong. */
void glBlendFunc(GLenum sfactor, GLenum dfactor);
void glViewport(GLint x, GLint y, GLsizei width, GLsizei height);
void glScissor(GLint x, GLint y, GLsizei width, GLsizei height);
void glClearColor(GLfloat r, GLfloat g, GLfloat b, GLfloat a);
void glClear(GLbitfield mask);
#define GL_COLOR_BUFFER_BIT 0x4000
#define GL_DEPTH_BUFFER_BIT 0x0100

/* Real: ps5gpu.c has no async queue to flush ahead of, so this is a no-op
 * that returns immediately - by the time it would return, everything issued
 * so far is already exactly as "finished" as this backend ever makes it
 * (recorded into the current frame's command buffer, submitted at
 * ps5gpu_end_frame - there is no separate GPU completion to wait for here). */
void glFinish(void);

/* Debug callback - NOT implemented: ps5gpu.c has no equivalent mechanism (no
 * driver validation layer to report through). Accepted so calling code that
 * sets one up (typically behind a debug build flag) compiles; the callback
 * is simply never invoked. */
typedef void (APIENTRY *GLDEBUGPROC)(GLenum source, GLenum type, GLuint id, GLenum severity,
                                      GLsizei length, const GLchar *message, const void *userParam);
#define GL_DEBUG_OUTPUT             0x92E0
#define GL_DEBUG_OUTPUT_SYNCHRONOUS 0x8242
#define GL_DEBUG_TYPE_ERROR         0x824C
#define GL_DEBUG_SEVERITY_HIGH      0x9146
void glDebugMessageCallback(GLDEBUGPROC callback, const void *userParam);

GLenum glGetError(void);
const GLubyte *glGetString(GLenum name);
#define GL_VENDOR   0x1F00
#define GL_RENDERER 0x1F01
#define GL_VERSION  0x1F02
/* PS5GL has no extensions of its own beyond what ps5gl.h itself declares, so
 * glGetString(GL_EXTENSIONS) answers "" (empty, not NULL - callers that
 * search it for a substring find nothing, safely) and
 * glGetIntegerv(GL_NUM_EXTENSIONS) answers 0. */
#define GL_EXTENSIONS 0x1F03
#define GL_NUM_EXTENSIONS 0x821D

/* ==========================================================================
 * Everything below was added without a hardware round-trip per function -
 * libmod_3d isn't being ported yet, so the priority right now is breadth
 * (enough of the surface exists to compile against) over per-call proof.
 * Each block says plainly whether it drives something real in ps5gpu.c or is
 * a tracked-but-inert stub, so porting work later knows what to trust.
 * ========================================================================== */

/* ---- more uniforms - same rule as above: only "mvp" is real, these exist so
 * calling code compiles and runs, not so it renders correctly. ---- */
void glUniform2f(GLint location, GLfloat v0, GLfloat v1);
void glUniform3f(GLint location, GLfloat v0, GLfloat v1, GLfloat v2);
void glUniform4fv(GLint location, GLsizei count, const GLfloat *value);
void glUniform4uiv(GLint location, GLsizei count, const GLuint *value);
void glUniformMatrix3fv(GLint location, GLsizei count, GLboolean transpose, const GLfloat *value);

/* ---- shader/program info logs - always empty: glCompileShader/glLinkProgram
 * never fail (see the file-level comment), so there is never anything to
 * report. length is written 0; buf is left untouched if bufSize > 0. */
void glGetShaderInfoLog(GLuint shader, GLsizei bufSize, GLsizei *length, char *infoLog);
void glGetProgramInfoLog(GLuint program, GLsizei bufSize, GLsizei *length, char *infoLog);

/* ---- more pipeline state ----
 * glCullFace/glFrontFace: tracked and readable back, but never applied -
 * ps5gpu.c's frame state always disables hardware culling outright (see its
 * own comment: "the caller's renderer decides visibility itself"). A caller
 * relying on hardware backface culling will see both faces of everything. */
#define GL_FRONT 0x0404
#define GL_BACK  0x0405
#define GL_CCW   0x0901
#define GL_CW    0x0900
void glCullFace(GLenum mode);
void glFrontFace(GLenum mode);

/* Tracked, never applied: ps5gpu.c's fixed-function pixel program pipeline
 * has no wireframe rasterization mode - every draw fills triangles. Code
 * that toggles this for a debug wireframe view will compile and run, but
 * always see filled geometry. */
#define GL_FRONT_AND_BACK 0x0408
#define GL_FILL 0x1B02
#define GL_LINE 0x1B01
void glPolygonMode(GLenum face, GLenum mode);

/* Real: forwards straight to ps5gpu_set_depth_decal - "GL_POLYGON_OFFSET_FILL"
 * is treated as an on/off matching ps5gpu's own decal concept (a fixed
 * offset, not the arbitrary factor/units GL allows). glPolygonOffset's
 * factor/units values are accepted but ignored - only whether the mode is
 * enabled matters. */
#define GL_POLYGON_OFFSET_FILL 0x8037
void glPolygonOffset(GLfloat factor, GLfloat units);

/* Stub: ps5gpu.c always writes all four colour channels every draw - there is
 * no per-channel mask underneath. Tracked and readable back so code that
 * queries it before restoring state doesn't misbehave, but never applied. */
void glColorMask(GLboolean red, GLboolean green, GLboolean blue, GLboolean alpha);

/* GL_FUNC_ADD is the only equation ps5gpu.c's two blend modes ever use;
 * anything else is refused the same way an unrecognised glBlendFunc pair is. */
#define GL_FUNC_ADD 0x8006
void glBlendEquation(GLenum mode);
/* Alpha factors are accepted but not separately wired - ps5gpu.c's two blend
 * modes (see glBlendFunc) do not have an independent alpha path. Colour
 * factors are validated exactly like glBlendFunc. */
void glBlendFuncSeparate(GLenum srcRGB, GLenum dstRGB, GLenum srcAlpha, GLenum dstAlpha);

/* No-op: ps5gpu_texture_upload has no row-alignment concept (it derives pitch
 * from width itself - see its own comment on that). Accepted so calling code
 * ported from GL doesn't need an #ifdef around every glPixelStorei call. */
#define GL_UNPACK_ALIGNMENT 0x0CF5
#define GL_PACK_ALIGNMENT   0x0D05
void glPixelStorei(GLenum pname, GLint param);

/* A handful of queries real enough to answer honestly. Everything else sets
 * GL_INVALID_ENUM and leaves *params untouched. */
#define GL_MAX_TEXTURE_SIZE        0x0D33
#define GL_MAX_VERTEX_ATTRIBS      0x8869
#define GL_MAX_COMBINED_TEXTURE_IMAGE_UNITS 0x8B4D
#define GL_ARRAY_BUFFER_BINDING    0x8894
#define GL_TEXTURE_BINDING_2D      0x8069
#define GL_CURRENT_PROGRAM         0x8B8D
/* [x, y, width, height] of ps5gpu's own current viewport (whatever
 * glViewport last set - see ps5gpu_set_viewport). params must have room for
 * 4 GLint, unlike every other glGetIntegerv pname here which writes one. */
#define GL_VIEWPORT 0x0BA2
/* Real: whatever glDepthMask last set. */
#define GL_DEPTH_WRITEMASK 0x0B72
/* A fixed answer, matching PS5GL's actual GLSL-shaped-but-not-GLSL target -
 * there is no real driver version to report. */
#define GL_MAJOR_VERSION 0x821B
#define GL_MINOR_VERSION 0x821C
void glGetIntegerv(GLenum pname, GLint *params);
const GLubyte *glGetStringi(GLenum name, GLuint index);   /* always returns NULL - no extension list */

/* Sub-region update: only correct when the sub-rectangle is the WHOLE
 * texture (xoffset=yoffset=0, width/height matching the texture's own,
 * which glTexImage2D remembers per texture id) - ps5gpu_texture_upload has no
 * partial-update path, so a true sub-rectangle falls back to re-uploading the
 * entire texture from whatever pixels are given, which is only correct if
 * the caller happens to pass a full-size buffer anyway. A partial buffer for
 * a partial rectangle would corrupt the rest of the texture - refused
 * (GL_INVALID_OPERATION) rather than doing that silently. */
void glTexSubImage2D(GLenum target, GLint level, GLint xoffset, GLint yoffset, GLsizei width, GLsizei height,
                      GLenum format, GLenum type, const void *pixels);

/* Not implemented - ps5gpu_texture_upload only accepts raw RGBA8, and there is
 * no DXT/BCn/ETC decompressor in this codebase. Always sets
 * GL_INVALID_OPERATION and uploads nothing; a caller must decode compressed
 * texture data to RGBA8 itself and call glTexImage2D instead. */
void glCompressedTexImage2D(GLenum target, GLint level, GLenum internalformat, GLsizei width, GLsizei height,
                             GLint border, GLsizei imageSize, const void *data);

/* Sampler objects: a real, separate alternative to glTexParameteri, since
 * ps5gpu.c's one global sampler state is applied fresh before every draw
 * either way (see apply_sampler_state in ps5gl.c) - binding a sampler object
 * to a unit simply takes priority over that unit's texture's own parameters
 * for as long as it stays bound. */
void glGenSamplers(GLsizei n, GLuint *samplers);
void glDeleteSamplers(GLsizei n, const GLuint *samplers);
void glBindSampler(GLuint unit, GLuint sampler);
void glSamplerParameteri(GLuint sampler, GLenum pname, GLint param);

/* ---- instancing ----
 * Real, but implemented entirely on the CPU: ps5gpu.c's backend has no
 * hardware instancing at all, so glDrawElementsInstanced expands the N
 * instances into N ordinary ps5gpu_draw() calls itself, re-gathering
 * attributes each time. Any attribute whose glVertexAttribDivisor is nonzero
 * advances by one element per INSTANCE instead of per vertex - the one piece
 * of real per-instance behaviour this can offer without GPU support. This is
 * draw-call-cost-multiplied-by-instance-count, not free the way real
 * hardware instancing is - fine for tens of instances, a poor fit for
 * thousands (the exact case real instancing exists for). */
void glVertexAttribDivisor(GLuint index, GLuint divisor);
void glDrawElementsInstanced(GLenum mode, GLsizei count, GLenum type, const void *indices, GLsizei instancecount);
void glDrawArraysInstanced(GLenum mode, GLint first, GLsizei count, GLsizei instancecount);

/* ---- occlusion queries ----
 * Stub, not real: ps5gpu.c/AGC's own occlusion-query registers were never
 * investigated. glEndQuery always records "fully visible" (a large sample
 * count), so code that culls draws based on a query result will never
 * incorrectly skip one - the safe direction to be wrong in - but also never
 * actually culls anything. Real GPU occlusion queries are future backend
 * work, not something this wrapper can fake correctly. */
#define GL_SAMPLES_PASSED 0x8914
#define GL_ANY_SAMPLES_PASSED 0x8C2F   /* accepted identically to GL_SAMPLES_PASSED - both are the same "fully visible" stub */
#define GL_QUERY_RESULT   0x8866
#define GL_QUERY_RESULT_AVAILABLE 0x8867
void glGenQueries(GLsizei n, GLuint *ids);
void glDeleteQueries(GLsizei n, const GLuint *ids);
void glBeginQuery(GLenum target, GLuint id);
void glEndQuery(GLenum target);
void glGetQueryObjectuiv(GLuint id, GLenum pname, GLuint *params);

/* ---- framebuffers / renderbuffers ----
 * REAL for the one case that matters: a framebuffer with a single
 * GL_COLOR_ATTACHMENT0 texture, sized via glTexImage2D (data or NULL, the
 * normal way to size a render-target texture - see its own comment).
 * glFramebufferTexture2D then actually calls ps5gpu_target_create() for it
 * (confirmed working on hardware, including reading back through the exact
 * texture id it produces - see ps5gpu.h's own note on
 * PS5GPU_TARGET_USER0/ps5gpu_target_create), and glBindFramebuffer actually
 * calls ps5gpu_set_target() to select it. glCheckFramebufferStatus reports
 * GL_FRAMEBUFFER_COMPLETE only once that real target exists - a caller
 * checking this return value, as correct GL code must, sees the truth.
 * Sampling the attached texture afterward (bind it, draw) transparently
 * reads back what was actually rendered into the target.
 *
 * What's still a stub: a separate depth attachment
 * (glFramebufferRenderbuffer/a depth-texture GL_DEPTH_ATTACHMENT) is tracked
 * but not used - ps5gpu_target_create's own depth buffer, allocated
 * alongside the colour one, is what the target actually uses; there is no
 * support for supplying a different one. GL_TEXTURE_CUBE_MAP_* faces or
 * multiple colour attachments as attachments are not implemented either.
 * ps5gpu.c's PS5GPU_MAX_USER_TARGETS (4) limits how many framebuffers can be
 * simultaneously backed by a real target regardless of MAX_GL_FBOS - beyond
 * that, ps5gpu_target_create() fails and glCheckFramebufferStatus reports it
 * as incomplete, same as any other creation failure. Still exactly like
 * ps5gpu_target_create() itself: setting glViewport/glScissor to match the
 * framebuffer's size is the caller's job, same division of responsibility
 * real GL has - glBindFramebuffer does not do it automatically. */
#define GL_FRAMEBUFFER            0x8D40
#define GL_RENDERBUFFER           0x8D41
#define GL_COLOR_ATTACHMENT0      0x8CE0
#define GL_DEPTH_ATTACHMENT       0x8D00
#define GL_FRAMEBUFFER_COMPLETE      0x8CD5
#define GL_FRAMEBUFFER_UNSUPPORTED  0x8CDD
#define GL_DEPTH_COMPONENT        0x1902
#define GL_DEPTH_COMPONENT24      0x81A6
void glGenFramebuffers(GLsizei n, GLuint *framebuffers);
void glDeleteFramebuffers(GLsizei n, const GLuint *framebuffers);
void glBindFramebuffer(GLenum target, GLuint framebuffer);
void glFramebufferTexture2D(GLenum target, GLenum attachment, GLenum textarget, GLuint texture, GLint level);
GLenum glCheckFramebufferStatus(GLenum target);
void glGenRenderbuffers(GLsizei n, GLuint *renderbuffers);
void glDeleteRenderbuffers(GLsizei n, const GLuint *renderbuffers);
void glBindRenderbuffer(GLenum target, GLuint renderbuffer);
void glRenderbufferStorage(GLenum target, GLenum internalformat, GLsizei width, GLsizei height);
void glFramebufferRenderbuffer(GLenum target, GLenum attachment, GLenum renderbuffertarget, GLuint renderbuffer);
void glGenerateMipmap(GLenum target);   /* no-op - ps5gpu.c textures have exactly one mip level */

/* ==========================================================================
 * Added to cover BennuGD2's actual GL surface, not just libmod_3d's: BennuGD2
 * itself renders through vendor/sdl-gpu, whose GL3/GL4 backend
 * (renderer_GL_common.inl, shared by both) is a second, independent consumer
 * with its own calls beyond what libmod_3d.c uses directly.
 * ========================================================================== */

/* ---- generic attribute locations - REAL, not a stub ----
 * SDL_gpu's shader loader (LinkShaderProgram in renderer_GL_common.inl) only
 * explicitly binds "gpu_Vertex" to location 0 before linking; it discovers
 * "gpu_TexCoord" and "gpu_Color" afterwards via glGetAttribLocation. Since
 * there is no real compiler to assign those, glGetAttribLocation here always
 * answers with PS5GL's own fixed layout - the same one gather_vertex() in
 * ps5gl.c already uses: gpu_Vertex=0, gpu_TexCoord=1, gpu_Color=2, anything
 * else -1. This is why SDL_gpu's default textured/untextured shader blocks
 * happen to line up with this library's vertex model without any special
 * casing - not a coincidence worth removing later. glBindAttribLocation is
 * accepted (SDL_gpu's own location-0 request already matches) but otherwise
 * has no effect, since the three real slots are fixed. */
void glBindAttribLocation(GLuint program, GLuint index, const char *name);
GLint glGetAttribLocation(GLuint program, const char *name);
void glDetachShader(GLuint program, GLuint shader);   /* no-op - nothing is actually attached, see the shader comment above */

/* ---- constant vertex attribute values ----
 * Real GL state (per the spec, NOT part of a VAO - a generic attribute's
 * "current value" is context state, independent of which VAO is bound).
 * Used by an attribute slot in gather_vertex() only when that slot is
 * DISABLED for the current VAO - matching real GL's own "disabled array ->
 * use the constant" behaviour - and only for slots 0/1/2, the ones PS5GL's
 * vertex model understands. */
void glVertexAttrib1f(GLuint index, GLfloat v0);
void glVertexAttrib2f(GLuint index, GLfloat v0, GLfloat v1);
void glVertexAttrib3f(GLuint index, GLfloat v0, GLfloat v1, GLfloat v2);
void glVertexAttrib4f(GLuint index, GLfloat v0, GLfloat v1, GLfloat v2, GLfloat v3);

/* ---- more uniform variants - same rule as glUniform1f etc: accepted,
 * discarded, only "mvp" (via glUniformMatrix4fv) is real. Exist so SDL_gpu's
 * generic uniform-upload code compiles and runs without a special case for
 * this backend, not because these values go anywhere. ---- */
void glUniform1iv(GLint location, GLsizei count, const GLint *value);
void glUniform2iv(GLint location, GLsizei count, const GLint *value);
void glUniform3iv(GLint location, GLsizei count, const GLint *value);
void glUniform4iv(GLint location, GLsizei count, const GLint *value);
void glUniform1ui(GLint location, GLuint v0);
void glUniform2uiv(GLint location, GLsizei count, const GLuint *value);
void glUniform3uiv(GLint location, GLsizei count, const GLuint *value);
void glUniformMatrix2fv(GLint location, GLsizei count, GLboolean transpose, const GLfloat *value);
void glUniformMatrix2x3fv(GLint location, GLsizei count, GLboolean transpose, const GLfloat *value);
void glUniformMatrix2x4fv(GLint location, GLsizei count, GLboolean transpose, const GLfloat *value);
void glUniformMatrix3x2fv(GLint location, GLsizei count, GLboolean transpose, const GLfloat *value);
void glUniformMatrix3x4fv(GLint location, GLsizei count, GLboolean transpose, const GLfloat *value);
void glUniformMatrix4x2fv(GLint location, GLsizei count, GLboolean transpose, const GLfloat *value);
void glUniformMatrix4x3fv(GLint location, GLsizei count, GLboolean transpose, const GLfloat *value);
/* Read-back: there is no generic uniform storage to read from (see above),
 * so these always write zero and set GL_INVALID_OPERATION. */
void glGetUniformfv(GLuint program, GLint location, GLfloat *params);
void glGetUniformiv(GLuint program, GLint location, GLint *params);
void glGetUniformuiv(GLuint program, GLint location, GLuint *params);

/* Real: answers from the same TexParams this library already tracks for
 * glTexParameteri. Any other pname is refused. */
void glGetTexParameteriv(GLenum target, GLenum pname, GLint *params);

/* ---- buffer mapping ----
 * Real: since a "buffer object" here is already a plain CPU-side malloc'd
 * blob (see glBufferData), mapping it is just handing back that same
 * pointer - no separate GPU-side copy exists to synchronize, so unmap is a
 * no-op that always reports success. access is accepted but ignored (every
 * mapping is effectively read-write). */
#define GL_WRITE_ONLY 0x88B9
#define GL_READ_ONLY  0x88B8
#define GL_READ_WRITE 0x88BA
void *glMapBuffer(GLenum target, GLenum access);
GLboolean glUnmapBuffer(GLenum target);

/* ---- NOT implemented - no GPU-to-CPU or GPU-to-GPU readback path exists in
 * ps5gpu.c. Each of these sets GL_INVALID_OPERATION and otherwise does
 * nothing; a caller depending on any of them (screenshot capture,
 * render-to-texture-via-copy, CPU texture readback) will need that backend
 * capability built first - the same gap glReadPixels/glCopyTex* share with
 * the framebuffer functions above. ---- */
void glReadPixels(GLint x, GLint y, GLsizei width, GLsizei height, GLenum format, GLenum type, void *pixels);
void glCopyTexImage2D(GLenum target, GLint level, GLenum internalformat, GLint x, GLint y,
                       GLsizei width, GLsizei height, GLint border);
void glCopyTexSubImage2D(GLenum target, GLint level, GLint xoffset, GLint yoffset, GLint x, GLint y,
                          GLsizei width, GLsizei height);
void glGetTexImage(GLenum target, GLint level, GLenum format, GLenum type, void *pixels);

/* No-op: ps5gpu.c only ever draws triangles, never lines - see ps5gl.h's
 * GL_TRIANGLES-only note on glDrawArrays/glDrawElements. */
void glLineWidth(GLfloat width);

/* GL_FUNC_ADD only, same as glBlendEquation; the separate alpha equation is
 * accepted but ignored, same reason as glBlendFuncSeparate's alpha factors. */
void glBlendEquationSeparate(GLenum modeRGB, GLenum modeAlpha);

/* Real: width/height from the same tracking glTexImage2D already does;
 * anything else queried is refused. */
void glGetTexLevelParameteriv(GLenum target, GLint level, GLenum pname, GLint *params);
#define GL_TEXTURE_WIDTH  0x1000
#define GL_TEXTURE_HEIGHT 0x1001

/* More discarded uniform variants, and the integer constant-attribute
 * setters (glVertexAttribI*) - accepted but not stored anywhere, since
 * PS5GL's fixed vertex model (see gather_vertex in ps5gl.c) has no integer
 * attribute path; a caller relying on an integer vertex attribute will not
 * get one. */
void glUniform1fv(GLint location, GLsizei count, const GLfloat *value);
void glUniform2fv(GLint location, GLsizei count, const GLfloat *value);
void glUniform3fv(GLint location, GLsizei count, const GLfloat *value);
void glUniform1uiv(GLint location, GLsizei count, const GLuint *value);
void glVertexAttribI1i(GLuint index, GLint v0);
void glVertexAttribI1ui(GLuint index, GLuint v0);
void glVertexAttribI2i(GLuint index, GLint v0, GLint v1);
void glVertexAttribI2ui(GLuint index, GLuint v0, GLuint v1);
void glVertexAttribI3i(GLuint index, GLint v0, GLint v1, GLint v2);
void glVertexAttribI3ui(GLuint index, GLuint v0, GLuint v1, GLuint v2);
void glVertexAttribI4i(GLuint index, GLint v0, GLint v1, GLint v2, GLint v3);
void glVertexAttribI4ui(GLuint index, GLuint v0, GLuint v1, GLuint v2, GLuint v3);

/* ---- tessellation / compute - NOT implemented ----
 * ps5gpu.c has no tessellation control/evaluation stage and no compute
 * pipeline at all (see the PS5GL project's own history: milestone 1 barely
 * fit two textures in a PIXEL shader's direct user data; a real
 * indirect-descriptor-table resource path - needed for compute's storage
 * images/buffers even more than for extra textures - was never built).
 * These exist so calling code compiles; every one of them sets
 * GL_INVALID_OPERATION and does nothing. A caller depending on
 * tessellation or compute needs that backend work done first - there is no
 * partial or approximate version of either to offer. */
#define GL_PATCH_VERTICES 0x8E72
void glPatchParameteri(GLenum pname, GLint value);
void glDispatchCompute(GLuint num_groups_x, GLuint num_groups_y, GLuint num_groups_z);
void glMemoryBarrier(GLbitfield barriers);
void glBindImageTexture(GLuint unit, GLuint texture, GLint level, GLboolean layered, GLint layer, GLenum access, GLenum format);

/* GL_FRAMEBUFFER_BINDING answers with whatever glBindFramebuffer last set
 * (real, if not very useful while framebuffers themselves are stubbed - see
 * the long comment above). Everything else glGetIntegerv already covers. */
#define GL_FRAMEBUFFER_BINDING 0x8CA6

#ifdef __cplusplus
}
#endif

#endif
