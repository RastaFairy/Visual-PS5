/* ps5gpu - see ps5gpu.h. Every register value here was established on real
 * hardware during the bring-up in PS5SDK/tools/ps5link; the comments record
 * the ones that were not obvious, because most of them cost a build-and-test
 * cycle to find. */

#include "ps5gpu.h"
/* The vertex program is SharpProspero's; the built-in pixel program is ours,
 * packed into a container made from SharpProspero's (build_shaders.sh). */
#include "shaders_build/mesh_vs_sb.h"
#include "shaders_build/textured_p_sb.h"
/* PS5GL's first multi-texture pixel program: two textures at the same UV,
 * multiplied together and by the vertex colour. Not registered as a program
 * automatically - the caller loads it with ps5gpu_program_new(textured2_p_sb,
 * textured2_p_sb_len) the same way it would load any other. The container's
 * two-texture resource layout is new (agcpack.py texture_container_n) and has
 * not yet been confirmed on hardware - see its docstring. */
#include "shaders_build/textured2_p_sb.h"

/* ---- kernel ---- */
extern int sceKernelSendNotificationRequest(int device, void *request, int size, int flags);
extern unsigned long sceKernelGetDirectMemorySize(void);
extern int sceKernelAllocateDirectMemory(long searchStart, long searchEnd, unsigned long len,
                                          unsigned long alignment, int memoryType, long *physOut);
extern int sceKernelMapDirectMemory(void **addrInOut, unsigned long len, int prot, int mapFlags,
                                     long physAddr, unsigned long alignment);
extern int sceKernelReleaseDirectMemory(long start, unsigned long len);
extern int sceKernelMunmap(void *addr, unsigned long len);

#define MEM_TYPE_CACHED_SHARED 12
#define PROT_ALL 0x33          /* CPU read/write | GPU read/write */

/* ---- VideoOut ---- */
typedef struct { void *data; void *metadata; void *reserved0; void *reserved1; } SceVideoOutBuffers;
extern int sceVideoOutOpen(int userId, int busType, int index, const void *param);
extern int sceVideoOutSetFlipRate(int handle, int rate);
extern void sceVideoOutSetBufferAttribute2(void *attr, unsigned long long pixelFormat, unsigned int tilingMode,
                                            unsigned int width, unsigned int height, unsigned long long option,
                                            unsigned int dccControl, unsigned long long dccClearColor);
extern int sceVideoOutRegisterBuffers2(int handle, int startIndex, int set, const SceVideoOutBuffers *addresses,
                                        int bufferNum, const void *attr, int category, const void *unk);
extern int sceVideoOutWaitVblank(int handle);
extern int sceVideoOutGetFlipStatus(int handle, void *status);

#define SCE_USER_SYSTEM 0xFF
#define VIDEOOUT_TILING_TILED 0
#define PIXELFORMAT_BGRA8_SRGB 0x8000000000000000ULL

/* ---- AGC ---- */
extern int sceAgcInit(void *state, unsigned int defaultsRevision);
extern void *sceAgcGetRegisterDefaults(void);
extern int sceAgcCreateShader(void **outHandle, void *header, void *gpuCode);
extern int sceAgcLinkShaders(void *linkageOut, void *primitiveStateOut, void *unused,
                              void *vsHandle, void *psHandle, unsigned int primitiveType);
extern void sceAgcDcbSetCxRegistersIndirect(void *dcb, void *regs, unsigned int count);
extern void sceAgcDcbSetShRegistersIndirect(void *dcb, void *regs, unsigned int count);
extern void sceAgcDcbSetUcRegistersIndirect(void *dcb, void *regs, unsigned int count);
extern void sceAgcCbSetShRegisterRangeDirect(void *dcb, unsigned int baseOffset, unsigned int *words, unsigned int count);
extern void *sceAgcDcbSetIndexBuffer(void *st, void *indexAddr);
extern void *sceAgcDcbSetIndexCount(void *st, unsigned int indexCount);
extern void *sceAgcDcbSetIndexSize(void *st, unsigned char indexSize, unsigned char cachePolicy);
extern void *sceAgcDcbDrawIndex(void *st, unsigned int indexCount, void *indexAddr, unsigned long long modifier);
extern void *sceAgcDcbSetFlip(void *st, unsigned int videoOutHandle, int bufferIndex, unsigned int flipMode, long long flipArg);
extern int sceAgcDriverSubmitDcb(void *submitDescription);
extern int sceAgcSuspendPoint(void);

typedef struct { unsigned short offset; unsigned short pad; unsigned int value; } CxRegister;

/* The command-buffer allocator state, byte-for-byte as DrawCommandBuffer keeps it. */
typedef struct {
    unsigned int *bottom, *top, *up_cursor, *down_cursor;
    long callback;
    void *user_data;
    unsigned int reserved_dwords, _pad;
} DcbState;

static unsigned char dcb_out_of_space(DcbState *st, unsigned int size, void *ud) {
    (void)st; (void)size; (void)ud;
    static int s_reported;
    if (!s_reported) { s_reported = 1; ps5gpu_notify("ps5gpu: bufer de comandos lleno"); }
    return 0;
}

/* Shader header layout, from AgcShader.cs. */
#define SHDR_USERDATA(h) (*(void**)((unsigned char*)(h) + 8))
#define SHDR_CXREGS(h)   (*(CxRegister**)((unsigned char*)(h) + 24))
#define SHDR_SHREGS(h)   (*(CxRegister**)((unsigned char*)(h) + 32))
#define SHDR_CXCOUNT(h)  (((unsigned char*)(h))[91])
#define SHDR_SHCOUNT(h)  (((unsigned char*)(h))[92])

/* User-data register bases are per shader stage: SPI_SHADER_USER_DATA_<stage>_0
 * minus the 0x2C00 base of the shader register space. Getting these two mixed
 * up is what once drew correct geometry in solid black. */
#define GS_USER_DATA_BASE 0x008C
#define PS_USER_DATA_BASE 0x000C

#define KIND_READONLY 0
#define KIND_SAMPLER 2
#define KIND_CONSTANTBUFFER 3

/* Context register offsets. offset = real GFX10 address - 0xA000. */
#define REG_SCISSOR_TL      0x090
#define REG_SCISSOR_BR      0x091
#define REG_TARGET_MASK     0x08E
#define REG_BLEND0_CONTROL  0x1E0
#define REG_DEPTH_CONTROL   0x200
#define REG_CULL_MODE       0x205
#define REG_ALPHA_TO_MASK   0x2DC

static const unsigned short kRenderTargetOffsets[16] = {
    0x0318,0x031B,0x031C,0x031D,0x031E,0x031F,0x0321,0x0323,
    0x0324,0x0325,0x0390,0x0398,0x03A0,0x03A8,0x03B0,0x03B8,
};

/* The depth block. These were read out of the driver's own defaults table
 * rather than derived: a first attempt placed them at 0x018..0x022 and not one
 * of those addresses exists. See refdata/regdefaults_fw9.txt in the ps5link
 * tools. Note the SW_MODE bits inside Z_INFO already say "depth tiling" in the
 * driver's default, so those must be left alone. */
static const unsigned short kDepthOffsets[16] = {
    0x010, 0x011, 0x012, 0x013, 0x014, 0x015, 0x01A, 0x01B,
    0x01C, 0x01D, 0x01E, 0x002, 0x005, 0x007, 0x00B, 0x00A,
};

#define SCREEN_W 1920
#define SCREEN_H 1080
/* The scene is drawn this many times the display's size in each direction and
 * averaged down - supersampling. The caller still sees SCREEN_W x SCREEN_H. */
#define RENDER_SCALE 2
#define TARGET_W (SCREEN_W * RENDER_SCALE)
#define TARGET_H (SCREEN_H * RENDER_SCALE)
/* The texture id the scene is read back through. The caller's ids start at 1. */
#define SCENE_TEXTURE 0
#define BUF_COUNT 2
#define MAX_TEXTURES 1024
/* Vertices and registers for a whole frame, which with the shadow cascades,
 * the reflection and the scene can be the world drawn four times over. */
#define ARENA_BYTES (32 * 1024 * 1024)
#define MAX_INDICES 65536

typedef struct { void *ptr; long phys; unsigned long size; } DirectMem;

typedef struct {
    DirectMem mem;
    int width, height;
    unsigned int words[8];      /* the T# */
    int valid;
} Texture;

static struct {
    int ready;
    const char *error;
    int video_handle;
    unsigned long frame_bytes;

    DirectMem fb[BUF_COUNT];
    DirectMem fb4k[BUF_COUNT];  /* the second set of display buffers, at 3840x2160 */
    DirectMem depth;
    DirectMem dcb_mem[BUF_COUNT];
    DirectMem arena[BUF_COUNT];
    unsigned long arena_used;
    DirectMem indices;
    DirectMem constants;

    DcbState dcb[BUF_COUNT];
    int slot;
    long long frame_index;

    void *vs, *ps;
    int cb_dwo, vb_dwo;         /* vertex stage: constants, vertex buffer */
    int tex_dwo, smp_dwo;       /* pixel stage: texture, sampler          */
    CxRegister linkage[34], prim_state[3];
    CxRegister *cx_records;
    unsigned int cx_count;

    Texture textures[MAX_TEXTURES];
    unsigned int texture_count;
    unsigned int current_texture;
    unsigned int current_texture2;   /* unit 1, for programs that declare a second texture */
    unsigned int sampler_words[4];

    /* pipeline state, applied lazily on the next draw */
    int vp_x, vp_y, vp_w, vp_h;
    int sc_x, sc_y, sc_w, sc_h;
    int depth_test, depth_mask, depth_decal, blend;
    int state_dirty;
} G;

const char *ps5gpu_last_error(void) { return G.error ? G.error : "sin error"; }

/* A failure names the step AND its return code (and, where it helps, the
 * address involved). A bare step name was not enough: RegisterBuffers2 failed
 * inside SM64 with arguments identical to the bring-up tests where it worked,
 * and without the code there was nothing to tell the possible causes apart. */
static char s_err[128];

static int hex_put(char *b, int n, unsigned long long v, int digits) {
    for (int i = digits - 1; i >= 0; i--) {
        unsigned int nib = (unsigned int)((v >> (i * 4)) & 0xF);
        b[n++] = (char)(nib < 10 ? '0' + nib : 'A' + nib - 10);
    }
    return n;
}

static void set_error(const char *what, int rc, const char *extra_name, unsigned long long extra) {
    int n = 0;
    for (int i = 0; what[i] && n < 40; i++) s_err[n++] = what[i];
    const char *t = " rc=0x";
    for (int i = 0; t[i]; i++) s_err[n++] = t[i];
    n = hex_put(s_err, n, (unsigned int)rc, 8);
    if (extra_name) {
        s_err[n++] = ' ';
        for (int i = 0; extra_name[i] && n < 100; i++) s_err[n++] = extra_name[i];
        s_err[n++] = '='; s_err[n++] = '0'; s_err[n++] = 'x';
        n = hex_put(s_err, n, extra, 16);
    }
    s_err[n] = 0;
    G.error = s_err;
}

void ps5gpu_notify(const char *msg) {
    char req[3120];
    for (int i = 0; i < 3120; i++) req[i] = 0;
    for (int i = 0; msg[i] && i < 3074; i++) req[45 + i] = msg[i];
    sceKernelSendNotificationRequest(0, req, sizeof(req), 0);
}

/* Direct memory is granted in whole 16KB pages; asking for less alignment just
 * makes the call fail quietly, which then shows up much later as a null
 * pointer. Clamping here closes that off. */
#define MIN_ALIGN 16384u

static int dm_alloc(DirectMem *out, unsigned long bytes, unsigned long align) {
    out->ptr = 0; out->phys = 0; out->size = 0;
    if (align < MIN_ALIGN) align = MIN_ALIGN;
    unsigned long size = (bytes + align - 1) / align * align;
    long phys = 0;
    unsigned long pool = sceKernelGetDirectMemorySize();
    if (sceKernelAllocateDirectMemory(0, (long)pool, size, align, MEM_TYPE_CACHED_SHARED, &phys) < 0)
        return -1;
    void *addr = 0;
    if (sceKernelMapDirectMemory(&addr, size, PROT_ALL, 0, phys, align) < 0) {
        sceKernelReleaseDirectMemory(phys, size);
        return -1;
    }
    out->ptr = addr; out->phys = phys; out->size = size;
    return 0;
}

static void *arena_take(unsigned long bytes, unsigned long align) {
    unsigned long base = (G.arena_used + align - 1) / align * align;
    if (base + bytes > G.arena[G.slot].size) {              /* frame overflowed */
        static int s_reported;
        if (!s_reported) { s_reported = 1; ps5gpu_notify("ps5gpu: arena del fotograma llena"); }
        return 0;
    }
    G.arena_used = base + bytes;
    return (unsigned char *)G.arena[G.slot].ptr + base;
}

/* The position matrix the next draw binds, and whether it still has to. */
static float s_mvp[16] = { 1, 0, 0, 0,  0, 1, 0, 0,  0, 0, 1, 0,  0, 0, 0, 1 };
static int s_mvp_dirty = 1;

/* The supersampled scene: a linear colour target at TARGET_W x TARGET_H, and
 * the size of it and of the depth buffer that matches it. s_scale is how much
 * the caller's viewport and scissor are multiplied by for the target in use. */
static DirectMem s_scene;
static unsigned long s_scene_bytes, s_depth_bytes;
static int s_scale = RENDER_SCALE;
static void resolve_scene(void);

/* Image quality, from the options: the scene drawn at twice the caller's size
 * each way and averaged down (render scale 2) or at its size (1), and shown on
 * the 1080p display buffers or the 4K ones, where it is drawn at 3840x2160 and
 * shown one to one. Asked for at any time, taken when a frame begins. */
static int s_render_scale = RENDER_SCALE;
static int s_output_4k;
static int s_4k_available;
static int s_want_4k, s_want_supersample = 1;

/* How far right the scene is drawn, in display pixels, and what is drawn over
 * the finished frame. */
static int s_view_offset_x;
static const Ps5GpuVertex *s_overlay;
static int s_overlay_count;
static uint32_t s_overlay_texture;

/* The reflection: the world mirrored in the water, drawn before the scene into
 * a linear target of the display's size with a depth buffer of its own, and
 * read back by the water as a texture. Its id is the last one, which
 * ps5gpu_texture_new() never hands out. */
#define REFLECT_W SCREEN_W
#define REFLECT_H SCREEN_H
#define REFLECT_TEXTURE (MAX_TEXTURES - 1)
static DirectMem s_reflect, s_reflect_depth;
static unsigned long s_reflect_bytes, s_reflect_depth_bytes;

/* The shadow map: depth as the sun sees it, packed into two colour channels of
 * a linear target with a depth buffer of its own. It holds two square
 * cascades side by side - near on the left, far on the right - each drawn in
 * its own half. Its id is the one before the reflection's. */
#define SHADOW_W 4096
#define SHADOW_H 2048
#define SHADOW_CASCADE_SIZE 2048
static int s_shadow_cascade;
#define SHADOW_TEXTURE (MAX_TEXTURES - 2)
static DirectMem s_shadow, s_shadow_depth;
static unsigned long s_shadow_bytes, s_shadow_depth_bytes;

/* Caller-sized render targets, from ps5gpu_target_create() - see its
 * UNTESTED note in ps5gpu.h. Each gets its own depth buffer and a texture id
 * from the same reserved-id space as the reflection/shadow targets, counting
 * down from below them so the three never collide. */
#define USER_TARGET_TEXTURE(i) (MAX_TEXTURES - 3 - (i))
typedef struct {
    DirectMem color, depth;
    unsigned long color_bytes, depth_bytes;
    int width, height;
    int valid;
} UserTarget;
static UserTarget s_user_targets[PS5GPU_MAX_USER_TARGETS];
static int s_active_user_target = -1;

/* What a frame state is for, and which one the command buffer has. */
enum { FRAME_SCENE, FRAME_DISPLAY, FRAME_REFLECTION, FRAME_SHADOW, FRAME_USER };
static int s_frame_target;

/* The pixel programs: each linked with the vertex program, with the linkage
 * and primitive state the library derived for that pair. 0 is the built-in
 * one. s_program_bound is what the command buffer currently has. */
#define MAX_PROGRAMS 16
typedef struct {
    void *ps;
    CxRegister linkage[34], prim_state[3];
    int tex_dwo, smp_dwo;
    int tex1_dwo, smp1_dwo;    /* second texture unit; -1 if this program has only one */
} Program;
static Program s_programs[MAX_PROGRAMS];
static int s_program_count = 1;
static int s_program_current, s_program_bound;

/* Memory that commands already recorded may still read - a texture's old
 * pixels after it is uploaded again - held until those commands have run. */
#define MAX_RETIRED 256
typedef struct { DirectMem mem; unsigned long frame; } Retired;
static Retired s_retired[MAX_RETIRED];
static int s_retired_count;

static void dm_free(DirectMem *m) {
    if (!m->ptr) return;
    sceKernelMunmap(m->ptr, m->size);
    sceKernelReleaseDirectMemory(m->phys, m->size);
    m->ptr = 0; m->phys = 0; m->size = 0;
}

static void retire(DirectMem *m) {
    if (s_retired_count == MAX_RETIRED) {        /* full: the oldest has long since run */
        dm_free(&s_retired[0].mem);
        for (int i = 1; i < MAX_RETIRED; i++) s_retired[i - 1] = s_retired[i];
        s_retired_count--;
    }
    s_retired[s_retired_count].mem = *m;
    s_retired[s_retired_count].frame = (unsigned long)G.frame_index;
    s_retired_count++;
    m->ptr = 0; m->phys = 0; m->size = 0;
}

/* A frame's commands run after it is submitted, and each frame is held for at
 * least one vertical blank, so two frames on they are done. */
static void release_retired(void) {
    int kept = 0;
    for (int i = 0; i < s_retired_count; i++) {
        if ((unsigned long)G.frame_index >= s_retired[i].frame + 2) dm_free(&s_retired[i].mem);
        else s_retired[kept++] = s_retired[i];
    }
    s_retired_count = kept;
}

static unsigned int default_of(unsigned short offset) {
    for (unsigned int i = 0; i < G.cx_count; i++)
        if (G.cx_records[i].offset == offset) return G.cx_records[i].value;
    return 0;
}

/* ---- shader binary container (an ELF holding .shader_header/.shader_text) ---- */
static unsigned int rd32(const unsigned char *p) { return p[0]|(p[1]<<8)|(p[2]<<16)|((unsigned int)p[3]<<24); }
static unsigned long long rd64(const unsigned char *p) { return (unsigned long long)rd32(p) | ((unsigned long long)rd32(p+4) << 32); }
static int str_eq(const char *a, const char *b) { while (*a && *b) { if (*a != *b) return 0; a++; b++; } return *a == *b; }

static int make_shader(const unsigned char *elf, unsigned int len, void **out) {
    if (len < 64 || elf[0] != 0x7f || elf[1] != 'E') return -1;
    unsigned long long shoff = rd64(elf + 40);
    unsigned short shentsize = (unsigned short)(elf[58] | (elf[59] << 8));
    unsigned short shnum = (unsigned short)(elf[60] | (elf[61] << 8));
    unsigned short shstrndx = (unsigned short)(elf[62] | (elf[63] << 8));
    unsigned long long stroff = rd64(elf + (unsigned int)shoff + shstrndx * shentsize + 24);

    const unsigned char *hdr = 0, *code = 0;
    unsigned int hdr_len = 0, code_len = 0;
    for (int i = 0; i < shnum; i++) {
        unsigned int rec = (unsigned int)shoff + i * shentsize;
        const char *name = (const char *)(elf + stroff + rd32(elf + rec));
        unsigned long long off = rd64(elf + rec + 24), size = rd64(elf + rec + 32);
        if (str_eq(name, ".shader_header")) { hdr = elf + off; hdr_len = (unsigned int)size; }
        else if (str_eq(name, ".shader_text")) { code = elf + off; code_len = (unsigned int)size; }
    }
    if (!hdr || !code) return -1;

    DirectMem hm, cm;
    if (dm_alloc(&hm, hdr_len, MIN_ALIGN) < 0) return -1;
    if (dm_alloc(&cm, code_len, MIN_ALIGN) < 0) return -1;
    for (unsigned int i = 0; i < hdr_len; i++)  ((unsigned char*)hm.ptr)[i] = hdr[i];
    for (unsigned int i = 0; i < code_len; i++) ((unsigned char*)cm.ptr)[i] = code[i];

    *out = 0;
    return sceAgcCreateShader(out, hm.ptr, cm.ptr);
}

/* index selects which resource of this kind - 0 for the first texture/sampler
 * a shader declares, 1 for a second one (e.g. textured2_p, PS5GL's first
 * multi-texture program). Returns -1 if the shader does not declare that
 * many resources of this kind. */
static int resource_slot_at(void *handle, int kind, int index) {
    void *ud = SHDR_USERDATA(handle);
    if (!ud) return -1;
    unsigned short *counts = (unsigned short*)((unsigned char*)ud + 46);
    if (counts[kind] <= index) return -1;
    unsigned short *sharps = *(unsigned short**)((unsigned char*)ud + 8 + kind * sizeof(void*));
    return sharps[index] & 0x7FFF;
}

static int resource_slot(void *handle, int kind) { return resource_slot_at(handle, kind, 0); }

/* ---- descriptors ---- */
static void bits(unsigned int *w, int word, int off, int width, unsigned int v) {
    unsigned int mask = (width == 32) ? 0xFFFFFFFFu : (((1u << width) - 1u) << off);
    w[word] = (w[word] & ~mask) | ((v << off) & mask);
}

static void desc_structured(unsigned int *w, unsigned long long addr, unsigned int stride, unsigned int count) {
    w[0] = (unsigned int)(addr & 0xFFFFFFFFu);
    w[1] = (unsigned int)((addr >> 32) & 0xFFFFu) | ((stride & 0x3FFFu) << 16);
    w[2] = count;
    w[3] = 0x204u | (5u << 12);
}

static void desc_constant(unsigned int *w, unsigned long long addr, unsigned int size) {
    w[0] = (unsigned int)(addr & 0xFFFFFFFFu);
    w[1] = (unsigned int)((addr >> 32) & 0xFFFFu) | (16u << 16);
    w[2] = (size + 15) / 16;
    w[3] = 0xfacu | (77u << 12);
}

static void desc_texture(unsigned int *w, unsigned long long addr, unsigned int width, unsigned int height) {
    for (int i = 0; i < 8; i++) w[i] = 0;
    unsigned long long units = addr >> 8;
    w[0] = (unsigned int)units;
    bits(w, 1, 0, 8, (unsigned int)(units >> 32) & 0xFFu);
    bits(w, 1, 20, 9, 56);                 /* k8_8_8_8UNorm */
    unsigned int wm1 = width - 1;          /* width-1 straddles words 1 and 2 */
    bits(w, 1, 30, 2, wm1 & 0x3u);
    bits(w, 2, 0, 12, wm1 >> 2);
    bits(w, 2, 14, 14, height - 1);
    bits(w, 3, 0, 3, 4); bits(w, 3, 3, 3, 5);      /* channels R,G,B,A */
    bits(w, 3, 6, 3, 6); bits(w, 3, 9, 3, 7);
    bits(w, 3, 20, 5, 0);                  /* linear: only needs width padded to 64 texels */
    bits(w, 3, 28, 4, 9);                  /* Texture2D */
}

static unsigned int sampler_address(uint32_t mode) {
    /* The caller's modes are the N64 tile modes: bit 0 mirrors, bit 1 clamps. */
    if (mode & PS5GPU_CLAMP)  return 2;    /* clamp to edge */
    if (mode & PS5GPU_MIRROR) return 1;    /* mirror        */
    return 0;                              /* wrap          */
}

/* ---- init ---- */
int ps5gpu_init(void) {
    static unsigned long long agc_state;
    { int rc = sceAgcInit(&agc_state, 8);
      if (rc < 0) { set_error("sceAgcInit", rc, 0, 0); return -1; } }

    G.video_handle = sceVideoOutOpen(SCE_USER_SYSTEM, 0, 0, 0);
    if (G.video_handle < 0) { set_error("sceVideoOutOpen", G.video_handle, 0, 0); return -1; }
    sceVideoOutSetFlipRate(G.video_handle, 0);

    /* A tiled 32bpp surface is addressed in 128x128 blocks, so both extents
     * pad up to a multiple of 128 before the byte size is worked out. */
    unsigned int pw = (SCREEN_W + 127u) & ~127u, ph = (SCREEN_H + 127u) & ~127u;
    G.frame_bytes = (unsigned long)pw * ph * 4;
    G.frame_bytes = (G.frame_bytes + (2*1024*1024 - 1)) & ~(unsigned long)(2*1024*1024 - 1);

    for (int i = 0; i < BUF_COUNT; i++)
        if (dm_alloc(&G.fb[i], G.frame_bytes, 2*1024*1024) < 0) { G.error = "framebuffer"; return -1; }
    /* The scene target is linear - rows one after another, each padded to 64
     * texels, which 3840 already is - so the pixel program can read it back as
     * an ordinary texture, the way SharpProspero's renderer allows a linear
     * target. The depth buffer matches it in size and keeps the driver's depth
     * tiling, whose blocks are 128 elements; it is never read back. */
    s_scene_bytes = (unsigned long)TARGET_W * TARGET_H * 4;
    s_scene_bytes = (s_scene_bytes + (2*1024*1024 - 1)) & ~(unsigned long)(2*1024*1024 - 1);
    if (dm_alloc(&s_scene, s_scene_bytes, 2*1024*1024) < 0) { G.error = "scene"; return -1; }
    { unsigned int dw = (TARGET_W + 127u) & ~127u, dh = (TARGET_H + 127u) & ~127u;
      s_depth_bytes = (unsigned long)dw * dh * 4;
      s_depth_bytes = (s_depth_bytes + (2*1024*1024 - 1)) & ~(unsigned long)(2*1024*1024 - 1); }
    if (dm_alloc(&G.depth, s_depth_bytes, 2*1024*1024) < 0) { G.error = "depth"; return -1; }
    desc_texture(G.textures[SCENE_TEXTURE].words, (unsigned long long)(unsigned long)s_scene.ptr, TARGET_W, TARGET_H);
    G.textures[SCENE_TEXTURE].width = TARGET_W;
    G.textures[SCENE_TEXTURE].height = TARGET_H;
    G.textures[SCENE_TEXTURE].valid = 1;

    s_reflect_bytes = (unsigned long)REFLECT_W * REFLECT_H * 4;
    s_reflect_bytes = (s_reflect_bytes + (2*1024*1024 - 1)) & ~(unsigned long)(2*1024*1024 - 1);
    if (dm_alloc(&s_reflect, s_reflect_bytes, 2*1024*1024) < 0) { G.error = "reflection"; return -1; }
    { unsigned int dw = (REFLECT_W + 127u) & ~127u, dh = (REFLECT_H + 127u) & ~127u;
      s_reflect_depth_bytes = (unsigned long)dw * dh * 4;
      s_reflect_depth_bytes = (s_reflect_depth_bytes + (2*1024*1024 - 1)) & ~(unsigned long)(2*1024*1024 - 1); }
    if (dm_alloc(&s_reflect_depth, s_reflect_depth_bytes, 2*1024*1024) < 0) { G.error = "reflection depth"; return -1; }
    desc_texture(G.textures[REFLECT_TEXTURE].words, (unsigned long long)(unsigned long)s_reflect.ptr, REFLECT_W, REFLECT_H);
    G.textures[REFLECT_TEXTURE].width = REFLECT_W;
    G.textures[REFLECT_TEXTURE].height = REFLECT_H;
    G.textures[REFLECT_TEXTURE].valid = 1;

    s_shadow_bytes = (unsigned long)SHADOW_W * SHADOW_H * 4;
    s_shadow_bytes = (s_shadow_bytes + (2*1024*1024 - 1)) & ~(unsigned long)(2*1024*1024 - 1);
    if (dm_alloc(&s_shadow, s_shadow_bytes, 2*1024*1024) < 0) { G.error = "shadow map"; return -1; }
    { unsigned int dw = (SHADOW_W + 127u) & ~127u, dh = (SHADOW_H + 127u) & ~127u;
      s_shadow_depth_bytes = (unsigned long)dw * dh * 4;
      s_shadow_depth_bytes = (s_shadow_depth_bytes + (2*1024*1024 - 1)) & ~(unsigned long)(2*1024*1024 - 1); }
    if (dm_alloc(&s_shadow_depth, s_shadow_depth_bytes, 2*1024*1024) < 0) { G.error = "shadow depth"; return -1; }
    desc_texture(G.textures[SHADOW_TEXTURE].words, (unsigned long long)(unsigned long)s_shadow.ptr, SHADOW_W, SHADOW_H);
    G.textures[SHADOW_TEXTURE].width = SHADOW_W;
    G.textures[SHADOW_TEXTURE].height = SHADOW_H;
    G.textures[SHADOW_TEXTURE].valid = 1;

    SceVideoOutBuffers addr[BUF_COUNT];
    for (int i = 0; i < BUF_COUNT; i++) {
        addr[i].data = G.fb[i].ptr;
        addr[i].metadata = 0; addr[i].reserved0 = 0; addr[i].reserved1 = 0;
    }
    /* SceVideoOutBufferAttribute2 is 80 bytes and SetBufferAttribute2 writes all
     * of it. A 64-byte buffer let it zero addr[0].data sitting right after it on
     * the stack, and RegisterBuffers2 then failed with 0x80290013. */
    unsigned char attr[256];
    for (int i = 0; i < (int)sizeof attr; i++) attr[i] = 0;
    sceVideoOutSetBufferAttribute2(attr, PIXELFORMAT_BGRA8_SRGB, VIDEOOUT_TILING_TILED,
                                   SCREEN_W, SCREEN_H, 0ULL, 0u, 0ULL);
    { int rc = sceVideoOutRegisterBuffers2(G.video_handle, 0, 0, addr, BUF_COUNT, attr, 0, 0);
      if (rc < 0) {
          set_error("RegisterBuffers2", rc, "fb0", (unsigned long long)(unsigned long)G.fb[0].ptr);
          return -1;
      } }

    /* A second set of display buffers at 3840x2160, for the 4K output the
     * options offer: registered as set 1, at buffer indices from BUF_COUNT.
     * If the output will not take it, 4K is simply not offered. */
    { unsigned int pw4 = (3840u + 127u) & ~127u, ph4 = (2160u + 127u) & ~127u;
      unsigned long bytes4 = (unsigned long)pw4 * ph4 * 4;
      bytes4 = (bytes4 + (2*1024*1024 - 1)) & ~(unsigned long)(2*1024*1024 - 1);
      int ok = 1;
      for (int i = 0; i < BUF_COUNT && ok; i++)
          if (dm_alloc(&G.fb4k[i], bytes4, 2*1024*1024) < 0) ok = 0;
      if (ok) {
          SceVideoOutBuffers addr4k[BUF_COUNT];
          for (int i = 0; i < BUF_COUNT; i++) {
              addr4k[i].data = G.fb4k[i].ptr;
              addr4k[i].metadata = 0; addr4k[i].reserved0 = 0; addr4k[i].reserved1 = 0;
          }
          unsigned char attr4k[256];
          for (int i = 0; i < (int)sizeof attr4k; i++) attr4k[i] = 0;
          sceVideoOutSetBufferAttribute2(attr4k, PIXELFORMAT_BGRA8_SRGB, VIDEOOUT_TILING_TILED,
                                         3840, 2160, 0ULL, 0u, 0ULL);
          ok = sceVideoOutRegisterBuffers2(G.video_handle, 1, BUF_COUNT, addr4k, BUF_COUNT, attr4k, 0, 0) >= 0;
      }
      if (!ok)
          for (int i = 0; i < BUF_COUNT; i++) dm_free(&G.fb4k[i]);
      s_4k_available = ok; }

    for (int i = 0; i < BUF_COUNT; i++) {
        if (dm_alloc(&G.dcb_mem[i], 16*1024*1024, MIN_ALIGN) < 0) { G.error = "dcb"; return -1; }
        if (dm_alloc(&G.arena[i], ARENA_BYTES, MIN_ALIGN) < 0)    { G.error = "arena"; return -1; }
    }

    if (make_shader(mesh_vs_sb, mesh_vs_sb_len, &G.vs) < 0) { G.error = "vertex shader"; return -1; }
    if (make_shader(textured_p_sb, textured_p_sb_len, &G.ps) < 0) { G.error = "pixel shader"; return -1; }

    G.cb_dwo  = resource_slot(G.vs, KIND_CONSTANTBUFFER);
    G.vb_dwo  = resource_slot(G.vs, KIND_READONLY);
    G.tex_dwo = resource_slot(G.ps, KIND_READONLY);
    G.smp_dwo = resource_slot(G.ps, KIND_SAMPLER);
    if (G.cb_dwo < 0 || G.vb_dwo < 0) { G.error = "recursos del vertex shader"; return -1; }
    if (G.tex_dwo < 0 || G.smp_dwo < 0) { G.error = "recursos del pixel shader"; return -1; }

    if (sceAgcLinkShaders(G.linkage, G.prim_state, 0, G.vs, G.ps, 4 /* triangle list */) < 0) {
        G.error = "sceAgcLinkShaders"; return -1;
    }
    s_programs[0].ps = G.ps;
    for (int i = 0; i < 34; i++) s_programs[0].linkage[i] = G.linkage[i];
    for (int i = 0; i < 3; i++) s_programs[0].prim_state[i] = G.prim_state[i];
    s_programs[0].tex_dwo = G.tex_dwo;
    s_programs[0].smp_dwo = G.smp_dwo;
    s_programs[0].tex1_dwo = -1;
    s_programs[0].smp1_dwo = -1;

    /* The vertex program multiplies by two matrices from a constant buffer.
     * Both are identity here: the caller hands in positions that are already
     * transformed, and the second matrix is the one the "normal" - which is
     * really the texture coordinate - passes through, so it must not rotate
     * anything. Written once; it never changes. */
    if (dm_alloc(&G.constants, 128, MIN_ALIGN) < 0) { G.error = "constants"; return -1; }
    { float *m = (float*)G.constants.ptr;
      for (int i = 0; i < 32; i++) m[i] = 0.0f;
      m[0] = m[5] = m[10] = m[15] = 1.0f;
      m[16] = m[21] = m[26] = m[31] = 1.0f; }

    /* A plain ascending index buffer: the vertex program indexes the vertex
     * buffer by vertex id, so index i simply means vertex i. */
    if (dm_alloc(&G.indices, MAX_INDICES * 4, MIN_ALIGN) < 0) { G.error = "indices"; return -1; }
    { unsigned int *ix = (unsigned int*)G.indices.ptr;
      for (unsigned int i = 0; i < MAX_INDICES; i++) ix[i] = i; }

    void *defaults = sceAgcGetRegisterDefaults();
    CxRegister **blocks = *(CxRegister***)((unsigned char*)defaults + 0x00);
    G.cx_count = *(unsigned int*)((unsigned char*)defaults + 0x20);
    G.cx_records = blocks ? blocks[0] : 0;

    ps5gpu_sampler_set(1, PS5GPU_CLAMP, PS5GPU_CLAMP);
    G.vp_x = G.sc_x = 0; G.vp_y = G.sc_y = 0;
    G.vp_w = G.sc_w = SCREEN_W; G.vp_h = G.sc_h = SCREEN_H;
    G.depth_test = 0; G.depth_mask = 1; G.blend = 0;
    G.state_dirty = 1;
    G.ready = 1;
    return 0;
}

void ps5gpu_get_dimensions(uint32_t *w, uint32_t *h) { if (w) *w = SCREEN_W; if (h) *h = SCREEN_H; }

/* ---- per-frame ---- */

/* The state that does not change between draws: where to draw, the depth
 * surface, how the two programs are wired together, and the programs' own
 * registers. Emitted once per frame. */
/* The state every frame starts from, for one of two targets: the supersampled
 * scene, or - resolve - the display buffer the scene is averaged onto. */
static void emit_frame_state(int target) {
    DcbState *dcb = &G.dcb[G.slot];
    int resolve = target == FRAME_DISPLAY;
    int reflection = target == FRAME_REFLECTION;
    int shadow = target == FRAME_SHADOW;
    int user = target == FRAME_USER;
    UserTarget *ut = user ? &s_user_targets[s_active_user_target] : NULL;
    s_frame_target = target;

    CxRegister *rt = arena_take(16 * sizeof(CxRegister), 8);
    if (!rt) return;
    for (int i = 0; i < 16; i++) {
        rt[i].offset = kRenderTargetOffsets[i]; rt[i].pad = 0;
        rt[i].value = default_of(kRenderTargetOffsets[i]);
    }
    #define RT(idx, mask, val) rt[idx].value = (rt[idx].value & ~(unsigned int)(mask)) | (unsigned int)(val)
    RT(1, 0x03ffe000u, 0u);
    RT(2, 0x0000007cu, 0x28u);           /* k8_8_8_8                                  */
    RT(2, 0x00000700u, 0x00u);           /* kUNorm - NOT kSrgb, that is the display's */
    /* kAlt for the display buffer, which carries blue first; the ordinary
     * order for the scene, so that it reads back as the RGBA a texture is. */
    RT(2, 0x00001800u, resolve ? 0x800u : 0u);
    RT(2, 0x00008000u, 0x8000u);         /* blend clamp                               */
    RT(2, 0x10000000u, 0u);              /* DCC off - bit 0x10000000, not 0x4000      */
    RT(2, 0x00004000u, 0u);              /* fmask compression off                     */
    RT(3, 0x00007000u, 0u); RT(3, 0x00018000u, 0u);
    RT(4, 0x00000008u, 0x8u); RT(4, 0x00000040u, 0x40u);
    RT(4, 0x00100200u, 0u);   RT(4, 0x00080000u, 0u);
    { unsigned int dispw = s_output_4k ? 3840u : SCREEN_W, disph = s_output_4k ? 2160u : SCREEN_H;
      unsigned int tw = resolve ? dispw : shadow ? SHADOW_W : reflection ? REFLECT_W : user ? (unsigned int)ut->width : TARGET_W;
      unsigned int th = resolve ? disph : shadow ? SHADOW_H : reflection ? REFLECT_H : user ? (unsigned int)ut->height : TARGET_H;
      rt[14].value = (rt[14].value & 0xffffc000u) | ((th - 1) & 0x3fffu);
      rt[14].value = (rt[14].value & 0xf0003fffu) | (((tw - 1) << 14) & 0x0fffc000u); }
    rt[14].value &= 0x0fffffffu;
    rt[15].value &= 0xffffe000u;
    RT(15, 0x0007c000u, resolve ? 0x6c000u : 0u);   /* render-target tiling, or linear */
    RT(15, 0x03000000u, 0x1000000u);     /* 2D                   */
    RT(15, 0x44000000u, 0x44000000u);
    { unsigned long long a = (unsigned long long)(unsigned long)(resolve ? (s_output_4k ? G.fb4k[G.slot].ptr : G.fb[G.slot].ptr)
                                                                         : shadow ? s_shadow.ptr
                                                                         : reflection ? s_reflect.ptr
                                                                         : user ? ut->color.ptr : s_scene.ptr);
      rt[0].value = (unsigned int)((a >> 8) & 0xffffffffu);
      rt[10].value = (rt[10].value & 0xffffff00u) | (unsigned int)((a >> 40) & 0xffu);
      rt[5].value = 0; rt[11].value &= 0xffffff00u;
      rt[6].value = 0; rt[12].value &= 0xffffff00u;
      rt[9].value = 0; rt[13].value &= 0xffffff00u; }

    CxRegister *zr = arena_take(16 * sizeof(CxRegister), 8);
    if (!zr) return;
    for (int i = 0; i < 16; i++) {
        zr[i].offset = kDepthOffsets[i]; zr[i].pad = 0;
        zr[i].value = default_of(kDepthOffsets[i]);
    }
    #define ZR(idx, mask, val) zr[idx].value = (zr[idx].value & ~(unsigned int)(mask)) | (unsigned int)(val)
    ZR(0, 0x00000003u, 0x3u);            /* Z32_FLOAT. SW_MODE is left alone: the   */
    ZR(0, 0x000f0000u, 0u);              /* driver default already says depth tiling */
    ZR(0, 0x20000000u, 0u);              /* HTILE off - no metadata surface to keep  */
    ZR(0, 0x08000000u, 0u);
    ZR(1, 0x00000003u, 0u);              /* no stencil */
    ZR(11, 0x01000000u, 0u);             /* depth writes allowed by the surface */
    ZR(11, 0x02000000u, 0x02000000u);    /* stencil writes off */
    /* The reflection has a depth buffer of its own. The resolve uses the
     * scene's: it draws with depth off, and a depth buffer larger than the
     * target is allowed. */
    { unsigned int dw = shadow ? SHADOW_W : reflection ? REFLECT_W : user ? (unsigned int)ut->width : TARGET_W;
      unsigned int dh = shadow ? SHADOW_H : reflection ? REFLECT_H : user ? (unsigned int)ut->height : TARGET_H;
      zr[13].value = (zr[13].value & 0xffffc000u) | ((dw - 1) & 0x3fffu);
      zr[13].value = (zr[13].value & 0xc000ffffu) | (((dh - 1) << 16) & 0x3fff0000u); }
    { union { float f; unsigned int u; } cv; cv.f = 1.0f; zr[14].value = cv.u; }
    zr[15].value &= 0xffffff00u;
    { unsigned long long a = (unsigned long long)(unsigned long)(shadow ? s_shadow_depth.ptr
                                                                 : reflection ? s_reflect_depth.ptr
                                                                 : user ? ut->depth.ptr : G.depth.ptr);
      unsigned int lo = (unsigned int)((a >> 8) & 0xffffffffu), hi = (unsigned int)((a >> 40) & 0xffu);
      zr[2].value = lo; zr[6].value = (zr[6].value & 0xffffff00u) | hi;
      zr[4].value = lo; zr[8].value = (zr[8].value & 0xffffff00u) | hi;
      zr[3].value = 0; zr[7].value &= 0xffffff00u;
      zr[5].value = 0; zr[9].value &= 0xffffff00u;
      zr[12].value = 0; zr[10].value &= 0xffffff00u; }

    int n = 16 + 16 + 1 + 1 + 34 + SHDR_CXCOUNT(G.vs) + SHDR_CXCOUNT(G.ps);
    CxRegister *cx = arena_take((unsigned long)n * sizeof(CxRegister), 8);
    if (!cx) return;
    int k = 0;
    for (int i = 0; i < 16; i++) cx[k++] = rt[i];
    for (int i = 0; i < 16; i++) cx[k++] = zr[i];
    cx[k].offset = REG_TARGET_MASK; cx[k].pad = 0; cx[k].value = 0xF; k++;
    /* No culling: the caller's renderer decides visibility itself, exactly as
     * its OpenGL backend does by never enabling face culling. */
    cx[k].offset = REG_CULL_MODE; cx[k].pad = 0; cx[k].value = default_of(REG_CULL_MODE) & ~0x7u; k++;
    for (int i = 0; i < 34; i++) cx[k++] = G.linkage[i];
    for (int i = 0; i < SHDR_CXCOUNT(G.vs); i++) cx[k++] = SHDR_CXREGS(G.vs)[i];
    for (int i = 0; i < SHDR_CXCOUNT(G.ps); i++) cx[k++] = SHDR_CXREGS(G.ps)[i];
    sceAgcDcbSetCxRegistersIndirect(dcb, cx, (unsigned int)k);

    int sn = SHDR_SHCOUNT(G.vs) + SHDR_SHCOUNT(G.ps);
    CxRegister *sh = arena_take((unsigned long)sn * sizeof(CxRegister), 8);
    if (!sh) return;
    int s = 0;
    for (int i = 0; i < SHDR_SHCOUNT(G.vs); i++) sh[s++] = SHDR_SHREGS(G.vs)[i];
    for (int i = 0; i < SHDR_SHCOUNT(G.ps); i++) sh[s++] = SHDR_SHREGS(G.ps)[i];
    sceAgcDcbSetShRegistersIndirect(dcb, sh, (unsigned int)s);

    CxRegister *uc = arena_take(3 * sizeof(CxRegister), 8);
    if (!uc) return;
    for (int i = 0; i < 3; i++) uc[i] = G.prim_state[i];
    sceAgcDcbSetUcRegistersIndirect(dcb, uc, 3);

    /* Identity to begin with; the first draw rebinds whatever matrix is
     * current, since a new command buffer has forgotten the last one. */
    unsigned int cbw[4];
    desc_constant(cbw, (unsigned long long)(unsigned long)G.constants.ptr, 128);
    sceAgcCbSetShRegisterRangeDirect(dcb, GS_USER_DATA_BASE + (unsigned int)G.cb_dwo, cbw, 4);
    s_mvp_dirty = 1;
    s_program_bound = 0;                   /* the frame state carries the built-in program */

    sceAgcDcbSetIndexSize(dcb, 1 /* 32-bit */, 0);
    sceAgcDcbSetIndexBuffer(dcb, G.indices.ptr);
}

void ps5gpu_begin_frame(void) {
    if (!G.ready) return;
    G.arena_used = 0;
    release_retired();

    /* Colour and depth are cleared by the processor. Both are uniform fills,
     * so the tiling arrangement does not matter - which is what makes it
     * possible to skip tiling maths entirely. */
    { unsigned int *p = (unsigned int*)s_scene.ptr;
      unsigned long n = s_scene_bytes / 4;
      for (unsigned long i = 0; i < n; i++) p[i] = 0xFF000000u; }
    { unsigned int *p = (unsigned int*)G.depth.ptr;
      unsigned long n = s_depth_bytes / 4;
      for (unsigned long i = 0; i < n; i++) p[i] = 0x3F800000u; }   /* 1.0f, the far plane */
    /* The display buffer is not cleared: the resolve covers every pixel of it. */

    DcbState *st = &G.dcb[G.slot];
    unsigned int cap = (unsigned int)(G.dcb_mem[G.slot].size / 4);
    st->bottom = (unsigned int*)G.dcb_mem[G.slot].ptr;
    st->top = st->bottom + cap;
    st->up_cursor = st->bottom;
    st->down_cursor = st->bottom + cap;
    st->callback = (long)(void*)&dcb_out_of_space;
    st->user_data = 0; st->reserved_dwords = 0; st->_pad = 0;

    s_output_4k = s_want_4k && s_4k_available;
    s_render_scale = (s_output_4k || s_want_supersample) ? 2 : 1;
    s_scale = s_render_scale;
    emit_frame_state(FRAME_SCENE);
    G.state_dirty = 1;
}

void ps5gpu_set_quality(int output_4k, int supersample) {
    s_want_4k = output_4k != 0;
    s_want_supersample = supersample != 0;
}

int ps5gpu_4k_available(void) { return s_4k_available; }
int ps5gpu_render_scale(void) { return s_render_scale; }

void ps5gpu_set_target(int target) {
    if (!G.ready) return;
    if (target == PS5GPU_TARGET_REFLECTION) {
        /* Cleared the first time it is selected in a frame rather than when
         * the frame begins, so a frame without a reflection costs nothing, and
         * one that selects it twice - sky, then world - keeps the first part.
         * Transparent black: where nothing is reflected, the water keeps its
         * own colour. */
        static long long s_cleared_frame = -1;
        if (s_cleared_frame != G.frame_index) {
            s_cleared_frame = G.frame_index;
            { unsigned int *p = (unsigned int*)s_reflect.ptr;
              unsigned long n = s_reflect_bytes / 4;
              for (unsigned long i = 0; i < n; i++) p[i] = 0u; }
            { unsigned int *p = (unsigned int*)s_reflect_depth.ptr;
              unsigned long n = s_reflect_depth_bytes / 4;
              for (unsigned long i = 0; i < n; i++) p[i] = 0x3F800000u; }
        }
        s_scale = 1;
        emit_frame_state(FRAME_REFLECTION);
    } else if (target == PS5GPU_TARGET_SHADOW) {
        /* Cleared once a frame too, to the farthest depth: red full, green
         * empty, which unpacks to one. */
        static long long s_cleared_frame = -1;
        if (s_cleared_frame != G.frame_index) {
            s_cleared_frame = G.frame_index;
            { unsigned int *p = (unsigned int*)s_shadow.ptr;
              unsigned long n = s_shadow_bytes / 4;
              for (unsigned long i = 0; i < n; i++) p[i] = 0xFF0000FFu; }
            { unsigned int *p = (unsigned int*)s_shadow_depth.ptr;
              unsigned long n = s_shadow_depth_bytes / 4;
              for (unsigned long i = 0; i < n; i++) p[i] = 0x3F800000u; }
        }
        s_scale = 1;
        emit_frame_state(FRAME_SHADOW);
    } else if (target >= PS5GPU_TARGET_USER0 && target < PS5GPU_TARGET_USER0 + PS5GPU_MAX_USER_TARGETS) {
        int idx = target - PS5GPU_TARGET_USER0;
        if (!s_user_targets[idx].valid) { s_scale = s_render_scale; emit_frame_state(FRAME_SCENE); G.state_dirty = 1; return; }
        /* No auto-clear, unlike reflection/shadow above - see ps5gpu_target_create's own comment in ps5gpu.h. */
        s_active_user_target = idx;
        s_scale = 1;
        emit_frame_state(FRAME_USER);
    } else {
        s_scale = s_render_scale;
        emit_frame_state(FRAME_SCENE);
    }
    G.state_dirty = 1;
}

uint32_t ps5gpu_reflection_texture(void) { return REFLECT_TEXTURE; }
uint32_t ps5gpu_shadow_texture(void) { return SHADOW_TEXTURE; }

int ps5gpu_target_create(int width, int height) {
    if (!G.ready || width <= 0 || height <= 0) return -1;
    int idx = -1;
    for (int i = 0; i < PS5GPU_MAX_USER_TARGETS; i++) if (!s_user_targets[i].valid) { idx = i; break; }
    if (idx < 0) return -1;

    UserTarget *t = &s_user_targets[idx];
    unsigned long color_bytes = (unsigned long)width * (unsigned long)height * 4;
    color_bytes = (color_bytes + (2*1024*1024 - 1)) & ~(unsigned long)(2*1024*1024 - 1);
    if (dm_alloc(&t->color, color_bytes, 2*1024*1024) < 0) return -1;

    unsigned int dw = ((unsigned int)width + 127u) & ~127u, dh = ((unsigned int)height + 127u) & ~127u;
    unsigned long depth_bytes = (unsigned long)dw * dh * 4;
    depth_bytes = (depth_bytes + (2*1024*1024 - 1)) & ~(unsigned long)(2*1024*1024 - 1);
    if (dm_alloc(&t->depth, depth_bytes, 2*1024*1024) < 0) { dm_free(&t->color); return -1; }

    t->color_bytes = color_bytes; t->depth_bytes = depth_bytes;
    t->width = width; t->height = height;

    int tex_id = USER_TARGET_TEXTURE(idx);
    desc_texture(G.textures[tex_id].words, (unsigned long long)(unsigned long)t->color.ptr, (unsigned int)width, (unsigned int)height);
    G.textures[tex_id].width = width;
    G.textures[tex_id].height = height;
    G.textures[tex_id].valid = 1;

    t->valid = 1;
    return idx;
}

int ps5gpu_target_texture(int index) {
    if (index < 0 || index >= PS5GPU_MAX_USER_TARGETS || !s_user_targets[index].valid) return -1;
    return USER_TARGET_TEXTURE(index);
}

int ps5gpu_debug_read_target_pixel(int index, int x, int y, unsigned char rgba[4]) {
    rgba[0] = rgba[1] = rgba[2] = rgba[3] = 0;
    if (index < 0 || index >= PS5GPU_MAX_USER_TARGETS || !s_user_targets[index].valid) return 0;
    UserTarget *t = &s_user_targets[index];
    if (x < 0 || y < 0 || x >= t->width || y >= t->height) return 0;
    unsigned int pitch = ((unsigned int)t->width + 63u) & ~63u;   /* linear surface: width padded to 64 texels */
    unsigned char *p = (unsigned char *)t->color.ptr + (unsigned long)y * pitch * 4 + (unsigned long)x * 4;
    rgba[0] = p[0]; rgba[1] = p[1]; rgba[2] = p[2]; rgba[3] = p[3];
    return 1;
}

void ps5gpu_set_shadow_cascade(int cascade) {
    s_shadow_cascade = cascade == 1 ? 1 : 0;
    G.state_dirty = 1;
}

static int s_frame_interval = 1;
static int s_measured_fps;

extern unsigned long long sceKernelGetProcessTimeCounter(void);
extern unsigned long long sceKernelGetProcessTimeCounterFrequency(void);

void ps5gpu_set_frame_interval(int vblanks) {
    s_frame_interval = vblanks < 1 ? 1 : vblanks;
}

void ps5gpu_end_frame(void) {
    if (!G.ready) return;
    resolve_scene();
    DcbState *dcb = &G.dcb[G.slot];
    sceAgcDcbSetFlip(dcb, (unsigned int)G.video_handle, (s_output_4k ? BUF_COUNT : 0) + G.slot,
                     1 /* on vertical blank */, G.frame_index);

    struct { void *words; unsigned int count; unsigned char flag; } submit;
    submit.words = dcb->bottom;
    submit.count = (unsigned int)(dcb->up_cursor - dcb->bottom);
    submit.flag = 0;
    sceAgcDriverSubmitDcb(&submit);
    sceAgcSuspendPoint();
    for (int i = 0; i < s_frame_interval; i++)
        sceVideoOutWaitVblank(G.video_handle);
    /* A vertical blank comes whether or not the processor has finished the
     * frame, and the next frame clears the scene, the reflection and the
     * shadow map from the processor side and reuses the command buffer and
     * arena of the frame before last. So this waits until the output reports
     * the flip carrying this frame's number - which the processor reaches only
     * at the end of the frame's commands - as done. Without it, a frame that
     * took the graphics processor longer than a blank had its surfaces cleared
     * under it, row by row: the screen flickered with black stripes. The
     * status is 128 bytes, the flip argument at offset 24, as SharpProspero's
     * SceVideoOutFlipStatus has it. */
    for (int guard = 0; guard < 120; guard++) {
        unsigned char status[128];
        long long shown;
        if (sceVideoOutGetFlipStatus(G.video_handle, status) < 0) break;
        shown = (long long)rd64(status + 24);
        if (shown >= G.frame_index) break;
        sceVideoOutWaitVblank(G.video_handle);
    }

    G.frame_index++;
    G.slot = (G.slot + 1) % BUF_COUNT;

    /* Presented frames a second, counted over whole seconds. */
    static unsigned long long s_frequency, s_window_start;
    static int s_window_frames;
    if (!s_frequency) s_frequency = sceKernelGetProcessTimeCounterFrequency();
    unsigned long long now = sceKernelGetProcessTimeCounter();
    if (!s_window_start) s_window_start = now;
    s_window_frames++;
    if (s_frequency && now - s_window_start >= s_frequency) {
        s_measured_fps = (int)((s_window_frames * s_frequency + (now - s_window_start) / 2) / (now - s_window_start));
        s_window_frames = 0;
        s_window_start = now;
    }
}

int ps5gpu_measured_fps(void) { return s_measured_fps; }

/* ---- textures ---- */
uint32_t ps5gpu_texture_new(void) {
    if (G.texture_count + 1 >= USER_TARGET_TEXTURE(PS5GPU_MAX_USER_TARGETS - 1)) return 1;
    return ++G.texture_count;                 /* ids start at 1 */
}

void ps5gpu_texture_upload(uint32_t id, const uint8_t *rgba32, int width, int height) {
    if (id == 0 || id >= MAX_TEXTURES || width <= 0 || height <= 0) return;
    Texture *t = &G.textures[id];

    /* A linear surface stores each row padded to a 256-byte block - 64 texels
     * here - and no tiling arrangement is needed. The padding is implied: the
     * processor derives the row pitch from the width the descriptor declares,
     * as SharpProspero's LinearSurface.Compute does. So the descriptor must
     * carry the real width. Declaring the padded one made a 32-texel texture
     * read as 64 with a transparent right half, and every repeat of it showed a
     * black stripe. */
    unsigned int pitch = ((unsigned int)width + 63u) & ~63u;
    unsigned long need = (unsigned long)pitch * (unsigned long)height * 4;

    /* A texture uploaded again - the caller recycles ids once its cache fills -
     * always takes fresh memory. Draws are recorded as the frame is built and
     * run only when it is submitted, so writing over the old pixels would
     * change what the draws recorded earlier in this frame sample. The old
     * block is released once they have run. */
    if (t->valid) {
        retire(&t->mem);
        t->valid = 0;
    }
    if (dm_alloc(&t->mem, need, MIN_ALIGN) < 0) return;
    t->width = width; t->height = height; t->valid = 1;

    unsigned int *dst = (unsigned int*)t->mem.ptr;
    const unsigned int *src = (const unsigned int*)rgba32;
    for (int y = 0; y < height; y++) {
        for (int x = 0; x < width; x++) dst[(unsigned int)y * pitch + x] = src[y * width + x];
        for (unsigned int x = (unsigned int)width; x < pitch; x++) dst[(unsigned int)y * pitch + x] = 0;
    }
    desc_texture(t->words, (unsigned long long)(unsigned long)t->mem.ptr, (unsigned int)width, (unsigned int)height);
}

void ps5gpu_texture_select(uint32_t id) {
    if (id < MAX_TEXTURES) { G.current_texture = id; G.state_dirty = 1; }
}

void ps5gpu_texture_select2(uint32_t id) {
    if (id < MAX_TEXTURES) { G.current_texture2 = id; G.state_dirty = 1; }
}

void ps5gpu_sampler_set(int linear_filter, uint32_t address_s, uint32_t address_t) {
    unsigned int *w = G.sampler_words;
    for (int i = 0; i < 4; i++) w[i] = 0;
    bits(w, 0, 0, 3, sampler_address(address_s));
    bits(w, 0, 3, 3, sampler_address(address_t));
    bits(w, 0, 6, 3, 2);
    unsigned int filter = linear_filter ? 1u : 0u;      /* bilinear or point */
    bits(w, 2, 20, 2, filter);
    bits(w, 2, 22, 2, filter);
    bits(w, 2, 26, 2, 0);                                /* one mip level, no mip filter */
    G.state_dirty = 1;
}

/* ---- pipeline state ---- */
void ps5gpu_set_viewport(int x, int y, int w, int h) {
    G.vp_x = x; G.vp_y = y; G.vp_w = w; G.vp_h = h; G.state_dirty = 1;
}
void ps5gpu_set_scissor(int x, int y, int w, int h) {
    G.sc_x = x; G.sc_y = y; G.sc_w = w; G.sc_h = h; G.state_dirty = 1;
}
void ps5gpu_set_depth_test(int e)  { G.depth_test = e; G.state_dirty = 1; }
void ps5gpu_set_depth_mask(int e)  { G.depth_mask = e; G.state_dirty = 1; }
void ps5gpu_set_depth_decal(int e) { G.depth_decal = e; G.state_dirty = 1; }
void ps5gpu_set_blend(int e)       { G.blend = e; G.state_dirty = 1; }

static int s_alpha_test;
void ps5gpu_set_alpha_test(int e) {
    if (s_alpha_test != e) { s_alpha_test = e; G.state_dirty = 1; }
}

/* Everything that can change between draws. */
static void emit_draw_state(void) {
    DcbState *dcb = &G.dcb[G.slot];
    CxRegister *cx = arena_take(32 * sizeof(CxRegister), 8);
    if (!cx) return;
    int k = 0;
    union { float f; unsigned int u; } cv;
    #define PUT(off, val) do { cx[k].offset = (off); cx[k].pad = 0; cx[k].value = (val); k++; } while (0)
    #define PUTF(off, fv) do { cv.f = (fv); PUT((off), cv.u); } while (0)

    /* The caller measures the viewport from the bottom of the screen, as
     * OpenGL does, so it is flipped here. The vertical scale is negative for
     * the same reason: clip space counts +Y upwards and the target's rows
     * count downwards. */
    float sc = (float)s_scale;             /* the caller's units are display pixels */
    float w2 = (float)G.vp_w * 0.5f * sc, h2 = (float)G.vp_h * 0.5f * sc;
    float top = (float)(SCREEN_H - (G.vp_y + G.vp_h)) * sc;
    float left = (float)(G.vp_x + s_view_offset_x) * sc;
    /* A shadow cascade is always drawn whole into its half of the map,
     * whatever the caller's viewport. */
    if (s_frame_target == FRAME_SHADOW) {
        w2 = SHADOW_CASCADE_SIZE * 0.5f; h2 = SHADOW_CASCADE_SIZE * 0.5f;
        top = 0.0f; left = (float)(s_shadow_cascade * SHADOW_CASCADE_SIZE);
    } else if (s_frame_target == FRAME_USER) {
        /* Unlike scene/reflection/resolve, a user target has no relationship
         * to the 1920x1080 display - the caller's viewport is in the
         * target's OWN pixel space directly (s_scale is already 1 for this
         * target, set by ps5gpu_set_target), so the flip uses the target's
         * own height instead of SCREEN_H. UNTESTED on hardware along with
         * the rest of ps5gpu_target_create() - see its note in ps5gpu.h. */
        top = (float)(s_user_targets[s_active_user_target].height - (G.vp_y + G.vp_h));
        left = (float)G.vp_x;
    }
    PUTF(0x10F, w2);                       /* x scale  */
    PUTF(0x110, left + w2);                /* x offset */
    PUTF(0x111, -h2);                      /* y scale  */
    PUTF(0x112, top + h2);                 /* y offset */
    PUTF(0x113, 1.0f);                     /* z scale  */
    PUTF(0x114, 0.0f);                     /* z offset */
    PUTF(0x0B4, 0.0f); PUTF(0x0B5, 1.0f);  /* depth range */
    PUTF(0x2FA, 8.0f); PUTF(0x2FB, 8.0f);  /* a generous guardband, so a triangle */
    PUTF(0x2FC, 8.0f); PUTF(0x2FD, 8.0f);  /* reaching well past the edge is clipped, not dropped */

    int scr_w = SCREEN_W, scr_h = SCREEN_H;
    if (s_frame_target == FRAME_USER) {
        /* Same reasoning as the viewport override above - see its comment. */
        scr_w = s_user_targets[s_active_user_target].width;
        scr_h = s_user_targets[s_active_user_target].height;
    }
    int sx0 = (G.sc_x + s_view_offset_x) * s_scale, sy0 = (scr_h - (G.sc_y + G.sc_h)) * s_scale;
    int sx1 = sx0 + G.sc_w * s_scale, sy1 = sy0 + G.sc_h * s_scale;
    if (sx0 < 0) sx0 = 0; if (sy0 < 0) sy0 = 0;
    if (sx1 > scr_w * s_scale) sx1 = scr_w * s_scale;
    if (sy1 > scr_h * s_scale) sy1 = scr_h * s_scale;
    /* A texel of border stays at the cleared depth, so a lookup past the map's
     * edge, clamped onto it, finds nothing in the sun's way. */
    if (s_frame_target == FRAME_SHADOW) {
        int base = s_shadow_cascade * SHADOW_CASCADE_SIZE;   /* and nothing spills into the other half */
        sx0 = base + 1; sy0 = 1; sx1 = base + SHADOW_CASCADE_SIZE - 1; sy1 = SHADOW_CASCADE_SIZE - 1;
    }
    PUT(REG_SCISSOR_TL, ((unsigned int)sx0 & 0x7fffu) | (((unsigned int)sy0 & 0x7fffu) << 16) | 0x80000000u);
    PUT(REG_SCISSOR_BR, ((unsigned int)sx1 & 0x7fffu) | (((unsigned int)sy1 & 0x7fffu) << 16));

    unsigned int zc = default_of(REG_DEPTH_CONTROL) & ~0x8000007Fu;
    /* Less-or-equal, as the OpenGL backend sets: the game draws some geometry
     * twice over the same vertices, and plain less would reject the second. */
    if (G.depth_test) zc |= 0x2u | 0x30u;              /* test, keeping the nearer or equal */
    if (G.depth_test && G.depth_mask) zc |= 0x4u;      /* and write it through     */
    PUT(REG_DEPTH_CONTROL, zc);

    unsigned int bl = default_of(REG_BLEND0_CONTROL) & ~0x60000000u;
    if (G.blend == PS5GPU_BLEND_ALPHA) bl = 0x40000000u | 0x4u | 0x500u;      /* src alpha, one minus src alpha, add */
    else if (G.blend == PS5GPU_BLEND_MULTIPLY) bl = 0x40000000u | 0x8u;       /* dst colour, zero, add: dst = src*dst */
    else bl &= ~0x40000000u;
    PUT(REG_BLEND0_CONTROL, bl);

    /* The pixel program cannot discard, so a cut-out would still write depth
     * over its transparent texels and hide whatever is drawn behind it later.
     * With one sample, alpha to coverage is the test instead: below one half a
     * pixel has no coverage, and neither colour nor depth is written. The
     * default already holds the undithered offsets. */
    PUT(REG_ALPHA_TO_MASK, default_of(REG_ALPHA_TO_MASK) | (s_alpha_test ? 1u : 0u));

    /* A decal is pulled towards the camera by its depth slope as well as a
     * constant, as the OpenGL backend's glPolygonOffset(-2, -2) does. The
     * values follow the register convention for a float depth buffer, which
     * the driver's default for the offset format register (0x2DE) already
     * selects: scale is the factor times 12, offset the units as they are.
     * Culling stays off, as the frame state set it. */
    unsigned int su = default_of(REG_CULL_MODE) & ~0x3807u;
    if (G.depth_decal) su |= 0x1800u;                  /* offset front and back faces */
    PUT(REG_CULL_MODE, su);
    PUTF(0x2E0, G.depth_decal ? -24.0f : 0.0f);        /* front scale  */
    PUTF(0x2E1, G.depth_decal ? -2.0f : 0.0f);         /* front offset */
    PUTF(0x2E2, G.depth_decal ? -24.0f : 0.0f);        /* back scale   */
    PUTF(0x2E3, G.depth_decal ? -2.0f : 0.0f);         /* back offset  */

    sceAgcDcbSetCxRegistersIndirect(dcb, cx, (unsigned int)k);

    Program *bound = &s_programs[s_program_bound];
    Texture *t = &G.textures[G.current_texture];
    if (t->valid)
        sceAgcCbSetShRegisterRangeDirect(dcb, PS_USER_DATA_BASE + (unsigned int)bound->tex_dwo, t->words, 8);
    sceAgcCbSetShRegisterRangeDirect(dcb, PS_USER_DATA_BASE + (unsigned int)bound->smp_dwo, G.sampler_words, 4);

    /* A program with a second texture (textured2_p and beyond) gets it bound
     * here too. Same sampler settings as unit 0 - PS5GL does not yet expose
     * per-unit filtering/wrap, and neither texture unit needs it to differ for
     * the multitexture case this was built for (base times lightmap, same UVs). */
    if (bound->tex1_dwo >= 0) {
        Texture *t2 = &G.textures[G.current_texture2];
        if (t2->valid)
            sceAgcCbSetShRegisterRangeDirect(dcb, PS_USER_DATA_BASE + (unsigned int)bound->tex1_dwo, t2->words, 8);
        if (bound->smp1_dwo >= 0)
            sceAgcCbSetShRegisterRangeDirect(dcb, PS_USER_DATA_BASE + (unsigned int)bound->smp1_dwo, G.sampler_words, 4);
    }

    G.state_dirty = 0;
}

int ps5gpu_program_new(const unsigned char *container, unsigned int length) {
    if (!G.ready || s_program_count >= MAX_PROGRAMS) return 0;
    Program *p = &s_programs[s_program_count];
    if (make_shader(container, length, &p->ps) < 0) return 0;
    p->tex_dwo = resource_slot_at(p->ps, KIND_READONLY, 0);
    p->smp_dwo = resource_slot_at(p->ps, KIND_SAMPLER, 0);
    if (p->tex_dwo < 0 || p->smp_dwo < 0) return 0;
    /* A second texture unit (PS5GL's textured2_p and beyond) is optional: a
     * program with only one texture simply does not declare a second one, and
     * resource_slot_at returns -1, which emit_draw_state takes as "skip". */
    p->tex1_dwo = resource_slot_at(p->ps, KIND_READONLY, 1);
    p->smp1_dwo = resource_slot_at(p->ps, KIND_SAMPLER, 1);
    if (sceAgcLinkShaders(p->linkage, p->prim_state, 0, G.vs, p->ps, 4 /* triangle list */) < 0) return 0;
    return s_program_count++;
}

void ps5gpu_set_program(int id) {
    if (id >= 0 && id < s_program_count) s_program_current = id;
}

void ps5gpu_debug_program_slots(int id, int *tex_dwo, int *smp_dwo, int *tex1_dwo, int *smp1_dwo) {
    Program *p = (id >= 0 && id < s_program_count) ? &s_programs[id] : &s_programs[0];
    if (tex_dwo) *tex_dwo = p->tex_dwo;
    if (smp_dwo) *smp_dwo = p->smp_dwo;
    if (tex1_dwo) *tex1_dwo = p->tex1_dwo;
    if (smp1_dwo) *smp1_dwo = p->smp1_dwo;
}

/* Switches the command buffer to the current pixel program: the linkage the
 * library derived for it with the vertex program, then its own context and
 * shader registers, then the primitive state. The texture and sampler are
 * bound again afterwards, since the program may read them from other slots. */
static void bind_program(void) {
    Program *p = &s_programs[s_program_current];
    DcbState *dcb = &G.dcb[G.slot];
    int n = 34 + SHDR_CXCOUNT(p->ps), sn = SHDR_SHCOUNT(p->ps);
    CxRegister *cx = arena_take((unsigned long)n * sizeof(CxRegister), 8);
    CxRegister *sh = arena_take((unsigned long)(sn ? sn : 1) * sizeof(CxRegister), 8);
    CxRegister *uc = arena_take(3 * sizeof(CxRegister), 8);
    if (!cx || !sh || !uc) return;

    int k = 0;
    for (int i = 0; i < 34; i++) cx[k++] = p->linkage[i];
    for (int i = 0; i < SHDR_CXCOUNT(p->ps); i++) cx[k++] = SHDR_CXREGS(p->ps)[i];
    sceAgcDcbSetCxRegistersIndirect(dcb, cx, (unsigned int)k);
    for (int i = 0; i < sn; i++) sh[i] = SHDR_SHREGS(p->ps)[i];
    if (sn) sceAgcDcbSetShRegistersIndirect(dcb, sh, (unsigned int)sn);
    for (int i = 0; i < 3; i++) uc[i] = p->prim_state[i];
    sceAgcDcbSetUcRegistersIndirect(dcb, uc, 3);

    s_program_bound = s_program_current;
    G.state_dirty = 1;
}

void ps5gpu_set_mvp(const float m[16]) {
    for (int i = 0; i < 16; i++) {
        if (s_mvp[i] != m[i]) {
            for (int j = 0; j < 16; j++) s_mvp[j] = m[j];
            s_mvp_dirty = 1;
            return;
        }
    }
}

/* Copies the current matrix into this frame's arena and points the vertex
 * program at it. The model matrix beside it stays identity: it is the one the
 * texture coordinates, travelling as the normal, pass through. */
static int bind_mvp(void) {
    float *c = arena_take(128, 16);
    if (!c) return -1;
    for (int i = 0; i < 16; i++) c[i] = s_mvp[i];
    for (int i = 16; i < 32; i++) c[i] = 0.0f;
    c[16] = c[21] = c[26] = c[31] = 1.0f;
    unsigned int cbw[4];
    desc_constant(cbw, (unsigned long long)(unsigned long)c, 128);
    sceAgcCbSetShRegisterRangeDirect(&G.dcb[G.slot], GS_USER_DATA_BASE + (unsigned int)G.cb_dwo, cbw, 4);
    s_mvp_dirty = 0;
    return 0;
}

void ps5gpu_draw(const Ps5GpuVertex *vertices, int vertex_count) {
    if (!G.ready || vertex_count <= 0) return;
    if (vertex_count > MAX_INDICES) vertex_count = MAX_INDICES;

    Ps5GpuVertex *dst = arena_take((unsigned long)vertex_count * sizeof(Ps5GpuVertex), 64);
    if (!dst) return;                     /* the frame's arena is full; drop the draw */
    for (int i = 0; i < vertex_count; i++) dst[i] = vertices[i];

    if (s_program_current != s_program_bound) bind_program();
    if (G.state_dirty) emit_draw_state();
    if (s_mvp_dirty && bind_mvp() < 0) return;   /* arena full: a stale matrix would misplace it */

    DcbState *dcb = &G.dcb[G.slot];
    unsigned int vb[4];
    desc_structured(vb, (unsigned long long)(unsigned long)dst,
                    (unsigned int)sizeof(Ps5GpuVertex), (unsigned int)vertex_count);
    sceAgcCbSetShRegisterRangeDirect(dcb, GS_USER_DATA_BASE + (unsigned int)G.vb_dwo, vb, 4);

    sceAgcDcbSetIndexCount(dcb, (unsigned int)vertex_count);
    sceAgcDcbDrawIndex(dcb, (unsigned int)vertex_count, G.indices.ptr, 0);
}

/* Draws the scene onto the display buffer. The scene is twice the display's
 * size in each direction, so the centre of every display pixel falls exactly
 * between four texels, and one bilinear sample there is their average: four
 * samples a pixel with the one pixel program there is.
 *
 * The caller believes the state it set lasts from one frame to the next and
 * only reports changes, so everything this touches is put back afterwards. */
static void resolve_scene(void) {
    int depth_test = G.depth_test, depth_mask = G.depth_mask, depth_decal = G.depth_decal;
    int blend = G.blend, alpha_test = s_alpha_test;
    int vx = G.vp_x, vy = G.vp_y, vw = G.vp_w, vh = G.vp_h;
    int cx = G.sc_x, cy = G.sc_y, cw = G.sc_w, ch = G.sc_h;
    uint32_t texture = G.current_texture;
    unsigned int sampler[4];
    for (int i = 0; i < 4; i++) sampler[i] = G.sampler_words[i];
    float mvp[16];
    for (int i = 0; i < 16; i++) mvp[i] = s_mvp[i];

    int program = s_program_current;
    int view_offset = s_view_offset_x;
    s_view_offset_x = 0;
    s_scale = s_output_4k ? 2 : 1;         /* the display's pixels, in the caller's units */
    /* The part of the scene target this frame drew into: all of it when
     * supersampled or for 4K, the top left quarter otherwise, shown one to one. */
    float extent = s_render_scale == 2 ? 1.0f : 0.5f;
    emit_frame_state(FRAME_DISPLAY);
    s_program_current = 0;                /* averaging is the built-in program's job */
    G.depth_test = 0; G.depth_mask = 0; G.depth_decal = 0; G.blend = 0; s_alpha_test = 0;
    G.vp_x = 0; G.vp_y = 0; G.vp_w = SCREEN_W; G.vp_h = SCREEN_H;
    G.sc_x = 0; G.sc_y = 0; G.sc_w = SCREEN_W; G.sc_h = SCREEN_H;
    ps5gpu_texture_select(SCENE_TEXTURE);
    ps5gpu_sampler_set(1, PS5GPU_CLAMP, PS5GPU_CLAMP);
    static const float identity[16] = { 1, 0, 0, 0,  0, 1, 0, 0,  0, 0, 1, 0,  0, 0, 0, 1 };
    ps5gpu_set_mvp(identity);
    s_mvp_dirty = 1;                       /* the new frame state forgot the last binding */
    G.state_dirty = 1;

    /* Clip +y is the top of the screen, and the scene's first row is its top. */
    static const float corners[6][4] = {
        { -1.0f,  1.0f, 0.0f, 0.0f }, {  1.0f,  1.0f, 1.0f, 0.0f }, { -1.0f, -1.0f, 0.0f, 1.0f },
        {  1.0f,  1.0f, 1.0f, 0.0f }, {  1.0f, -1.0f, 1.0f, 1.0f }, { -1.0f, -1.0f, 0.0f, 1.0f },
    };
    Ps5GpuVertex quad[6];
    for (int i = 0; i < 6; i++) {
        quad[i].x = corners[i][0]; quad[i].y = corners[i][1]; quad[i].z = 0.0f;
        quad[i].u = corners[i][2] * extent; quad[i].v = corners[i][3] * extent; quad[i].n_pad = 0.0f;
        quad[i].uv_unused[0] = 0.0f; quad[i].uv_unused[1] = 0.0f;
        quad[i].color = 0xFFFFFFFFu;
    }
    ps5gpu_draw(quad, 6);

    if (s_overlay && s_overlay_count > 0 && s_overlay_texture < MAX_TEXTURES && G.textures[s_overlay_texture].valid) {
        G.blend = 1;
        ps5gpu_texture_select(s_overlay_texture);
        G.state_dirty = 1;
        ps5gpu_draw(s_overlay, s_overlay_count);
    }

    G.depth_test = depth_test; G.depth_mask = depth_mask; G.depth_decal = depth_decal;
    G.blend = blend; s_alpha_test = alpha_test;
    G.vp_x = vx; G.vp_y = vy; G.vp_w = vw; G.vp_h = vh;
    G.sc_x = cx; G.sc_y = cy; G.sc_w = cw; G.sc_h = ch;
    G.current_texture = texture;
    for (int i = 0; i < 4; i++) G.sampler_words[i] = sampler[i];
    ps5gpu_set_mvp(mvp);
    s_mvp_dirty = 1;
    G.state_dirty = 1;
    s_program_current = program;
    s_view_offset_x = view_offset;
    s_scale = s_render_scale;
}

void ps5gpu_set_view_offset_x(int display_pixels) {
    s_view_offset_x = display_pixels < 0 ? 0 : display_pixels;
    G.state_dirty = 1;
}

void ps5gpu_set_overlay(const Ps5GpuVertex *vertices, int vertex_count, uint32_t texture) {
    s_overlay = vertices;
    s_overlay_count = vertex_count;
    s_overlay_texture = texture;
}
