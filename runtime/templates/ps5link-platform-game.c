static int visual_token_at(const char *text,const char *token){while(*token){if(*text++!=*token++)return 0;}return 1;}
static int visual_append(char *out,int length,int capacity,const char *value){while(*value&&length<capacity-1)out[length++]=*value++;return length;}
static int visual_append_uint(char *out,int length,int capacity,unsigned int value){char digits[10];int count=0;do{digits[count++]=(char)('0'+value%10u);value/=10u;}while(value&&count<10);while(count&&length<capacity-1)out[length++]=digits[--count];return length;}
static void format_visual_label(char *out,int capacity,const char *format,unsigned int current,unsigned int total,unsigned int percent,int audioEnabled){
    int length=0;if(!format)format="";
    while(*format&&length<capacity-1){
        if(visual_token_at(format,"{current}")){length=visual_append_uint(out,length,capacity,current);format+=9;}
        else if(visual_token_at(format,"{total}")){length=visual_append_uint(out,length,capacity,total);format+=7;}
        else if(visual_token_at(format,"{percent}")){length=visual_append_uint(out,length,capacity,percent);format+=9;}
        else if(visual_token_at(format,"{state}")){length=visual_append(out,length,capacity,audioEnabled?"ON":"OFF");format+=7;}
        else out[length++]=*format++;
    }
    out[length]=0;
}
/* GPL-3.0-or-later. AGC initialization adapted from ps5link-sdk/examples/gpu_cube/main.c; see LICENSE. */
/* A lit, animated 3D cube drawn by the GPU: video out, a tiled render target,
 * a command buffer, two shaders and a flip, with nothing in between. The
 * register-level details that matter are in the comments as they come up -
 * tiled surface sizing, 16KB direct-memory alignment, the kUNorm channel type,
 * and the user-data register base of each stage.
 *
 * Per-vertex data and matrices are the heart of it. The
 * shaders are SharpProspero's built-in mesh pair, already proven on hardware,
 * whose PSSL source states the contract exactly:
 *   Vertex  { float3 pos@0; float3 normal@12; float2 uv@24; uint color@32; }  stride 36
 *   Constants { row_major float4x4 mvp; row_major float4x4 model; }           128 bytes
 * The vertex program reads the vertex by index from a RegularBuffer (t0) and
 * its matrices from a ConstantBuffer (b0) - both bound to the VERTEX stage.
 * The pixel program takes no resources; it lights the interpolated normal.
 *
 * No SDL, no stdio, no libc math: same minimal-surface philosophy as
 * hw_test.c/pad_test.c, so the trigonometry and matrix maths are here too.
 */
/* Built by shaders/build.sh from SharpProspero's containers. */
#include "mesh_vs_sb.h"
#include "mesh_ps_sb.h"

/* ---- kernel / notify ---- */
extern int sceKernelSendNotificationRequest(int device, void *request, int size, int flags);
extern int sceKernelUsleep(unsigned int microseconds);
extern unsigned long sceKernelGetDirectMemorySize(void);
extern int sceKernelAllocateDirectMemory(long searchStart, long searchEnd, unsigned long len,
                                          unsigned long alignment, int memoryType, long *physOut);
extern int sceKernelMapDirectMemory(void **addrInOut, unsigned long len, int prot, int mapFlags,
                                     long physAddr, unsigned long alignment);
extern int sceKernelReleaseDirectMemory(long start, unsigned long len);

#define MEM_TYPE_CACHED_SHARED 12
#define PROT_CPU_RW   0x03
#define PROT_GPU_ALL  0x30
#define PROT_ALL      (PROT_CPU_RW | PROT_GPU_ALL)

/* ---- VideoOut ---- */
/* SceVideoOutBuffers: {void* Data; void* Metadata; void* Reserved0; void* Reserved1;} - 4 pointers. */
typedef struct { void *data; void *metadata; void *reserved0; void *reserved1; } SceVideoOutBuffers;
#define SCE_USER_SYSTEM 0xFF
#define VIDEOOUT_BUS_MAIN 0
#define VIDEOOUT_TILING_TILED 0   /* VideoOutTilingMode.Tiled = 0 */
#define VIDEOOUT_TILING_LINEAR 1
#define VIDEOOUT_PIXELFORMAT_BGRA8_SRGB 0x8000000000000000ULL
extern int sceSystemServiceHideSplashScreen(void);
extern int sceVideoOutOpen(int userId, int busType, int index, const void *param);
extern int sceVideoOutClose(int handle);
extern int sceVideoOutSetFlipRate(int handle, int rate);
extern void sceVideoOutSetBufferAttribute2(void *attr, unsigned long long pixelFormat, unsigned int tilingMode,
                                            unsigned int width, unsigned int height, unsigned long long option,
                                            unsigned int dccControl, unsigned long long dccCbRegisterClearColor);
extern int sceVideoOutRegisterBuffers2(int handle, int startIndex, int set, const SceVideoOutBuffers *addresses,
                                        int bufferNum, const void *attr, int category, const void *unk);
extern int sceVideoOutSubmitFlip(int handle, int bufferIndex, unsigned int flipMode, long long flipArg);
extern int sceVideoOutWaitVblank(int handle);

/* ---- AGC ---- */
extern int sceAgcInit(void *state, unsigned int defaultsRevision);
extern void *sceAgcGetRegisterDefaults(void);
extern int sceAgcCreateShader(void **outHandle, void *header, void *gpuCode);
extern int sceAgcLinkShaders(void *linkageOut, void *primitiveStateOut, void *unused,
                              void *vsHandle, void *psHandle, unsigned int primitiveType);
extern void *sceAgcDcbSetCxRegisterDirect(void *st, unsigned long long packed);
extern void *sceAgcDcbSetShRegisterDirect(void *st, unsigned long long packed);
extern void sceAgcDcbSetCxRegistersIndirect(void *dcb, void *regs, unsigned int count);
extern void sceAgcDcbSetShRegistersIndirect(void *dcb, void *regs, unsigned int count);
extern void sceAgcDcbSetUcRegistersIndirect(void *dcb, void *regs, unsigned int count);
extern void sceAgcCbSetShRegisterRangeDirect(void *dcb, unsigned int baseOffset, unsigned int *words, unsigned int count);
extern void *sceAgcDcbDrawIndexAuto(void *st, unsigned int indexCount, unsigned long long modifier);
extern void *sceAgcDcbSetIndexBuffer(void *st, void *indexAddr);
extern void *sceAgcDcbSetIndexCount(void *st, unsigned int indexCount);
extern void *sceAgcDcbSetIndexSize(void *st, unsigned char indexSize, unsigned char cachePolicy);
extern void *sceAgcDcbDrawIndex(void *st, unsigned int indexCount, void *indexAddr, unsigned long long modifier);
extern void *sceAgcDcbSetFlip(void *st, unsigned int videoOutHandle, int bufferIndex, unsigned int flipMode, long long flipArg);
extern int sceAgcDriverSubmitDcb(void *submitDescription);
extern int sceVideoOutGetFlipStatus(int handle, void *status);
extern int sceAgcSuspendPoint(void);

/* SharpProspero's CxRegister is {ushort Offset; uint Value;} sequential, which C#
 * lays out as offset(2) + pad(2) + value(4) = 8 bytes (uint needs 4-byte alignment).
 * Mirrored exactly here so the shader's embedded register arrays (read straight out
 * of GPU-visible memory the driver wrote) can be indexed as this same struct. */
typedef struct { unsigned short offset; unsigned short pad; unsigned int value; } CxRegister;

/* ---- command buffer state (matches DrawCommandBuffer's private State struct byte-for-byte) ---- */
typedef struct {
    unsigned int *bottom;
    unsigned int *top;
    unsigned int *up_cursor;
    unsigned int *down_cursor;
    long callback; /* out-of-space callback; must be a real function pointer, not null */
    void *user_data;
    unsigned int reserved_dwords;
    unsigned int _pad;
} DcbState;

static unsigned char out_of_space(DcbState *st, unsigned int size, void *userData) {
    (void)st; (void)size; (void)userData;
    return 0;
}

static void dcb_reset(DcbState *st, unsigned int *buffer, unsigned int capacity_dwords) {
    st->bottom = buffer;
    st->top = buffer + capacity_dwords;
    st->up_cursor = buffer;
    st->down_cursor = buffer + capacity_dwords;
    st->callback = (long)(void *)&out_of_space;
    st->user_data = 0;
    st->reserved_dwords = 0;
    st->_pad = 0;
}

/* ---- tiny direct-memory allocator ---- */
typedef struct { void *ptr; long phys; unsigned long size; } DirectMem;

/* Direct memory is only ever granted in whole pages: KernelMemory.PageSize
 * (16384) is "the alignment a direct mapping is made on" per SharpProspero's
 * own KernelMemory.cs. A caller asking for a smaller alignment (8, 256...)
 * isn't rejected loudly - it just makes sceKernelAllocateDirectMemory or
 * sceKernelMapDirectMemory fail, and this function used to return -1 in that
 * case *without every caller checking it*, leaving the DirectMem's .ptr as
 * uninitialized stack garbage (often 0 on a fresh frame) - a silent NULL that
 * only crashed later, on the first real write through it. Clamping here
 * closes off that whole class of mistake at the source. */
#define DIRECT_MEM_MIN_ALIGN 16384u

static int direct_alloc(DirectMem *out, unsigned long bytes, unsigned long align) {
    out->ptr = 0; out->phys = 0; out->size = 0;
    if (align < DIRECT_MEM_MIN_ALIGN) align = DIRECT_MEM_MIN_ALIGN;
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
    out->ptr = addr;
    out->phys = phys;
    out->size = size;
    return 0;
}

/* Direct-memory framebuffers are cached on the CPU, but display scan-out reads
 * them from DRAM outside the CPU cache-coherency domain. Publish CPU-written
 * pixels before the GPU's flip packet can hand the buffer to scan-out. The
 * allocation is 2 MiB aligned and sized, so this walks complete 64-byte lines. */
static void framebuffer_writeback(const void *address, unsigned long bytes) {
    const unsigned char *line = (const unsigned char *)address;
    for (unsigned long offset = 0; offset < bytes; offset += 64)
        __asm__ volatile("clflushopt (%0)" : : "r"(line + offset) : "memory");
    __asm__ volatile("sfence" : : : "memory");
}

static void notify(const char *msg) {
    char req[3120];
    for (int i = 0; i < 3120; i++) req[i] = 0;
    for (int i = 0; msg[i] && i < 3074; i++) req[45 + i] = msg[i];
    sceKernelSendNotificationRequest(0, req, sizeof(req), 0);
}

/* Writes msg followed by " rc=" and rc in hex (e.g. "80290005") into a small
 * stack buffer and notifies it - so a failure says which error, not just where. */
static void notify_rc(const char *msg, int rc) {
    char buf[96];
    int len = 0;
    for (; msg[len] && len < 64; len++) buf[len] = msg[len];
    const char *tag = " rc=0x";
    for (int i = 0; tag[i]; i++) buf[len++] = tag[i];
    unsigned int u = (unsigned int)rc;
    char hex[8];
    for (int i = 7; i >= 0; i--) { unsigned int nib = u & 0xF; hex[i] = (char)(nib < 10 ? ('0'+nib) : ('A'+nib-10)); u >>= 4; }
    for (int i = 0; i < 8; i++) buf[len++] = hex[i];
    buf[len] = 0;
    notify(buf);
}

/* ---- shader-binary ELF container parsing (mirrors ShaderBinary.cs Load()) ---- */
typedef struct { const unsigned char *header; unsigned int header_len; const unsigned char *code; unsigned int code_len; } ShaderParts;

static unsigned int rd32(const unsigned char *p) { return p[0] | (p[1]<<8) | (p[2]<<16) | ((unsigned int)p[3]<<24); }
static unsigned long long rdu64(const unsigned char *p) {
    unsigned long long lo = rd32(p);
    unsigned long long hi = rd32(p+4);
    return lo | (hi << 32);
}

static int str_eq(const char *a, const char *b) {
    while (*a && *b) { if (*a != *b) return 0; a++; b++; }
    return *a == *b;
}

static int shader_parts_from_elf(const unsigned char *elf, unsigned int len, ShaderParts *out) {
    if (len < 64 || elf[0] != 0x7f || elf[1] != 'E' || elf[2] != 'L' || elf[3] != 'F') return -1;
    unsigned long long shoff = rdu64(elf + 40);
    unsigned short shentsize = (unsigned short)(elf[58] | (elf[59] << 8));
    unsigned short shnum = (unsigned short)(elf[60] | (elf[61] << 8));
    unsigned short shstrndx = (unsigned short)(elf[62] | (elf[63] << 8));
    if (shoff == 0 || shnum == 0 || shstrndx >= shnum) return -1;

    unsigned int strrec = (unsigned int)shoff + shstrndx * shentsize;
    unsigned long long stroff = rdu64(elf + strrec + 24);

    out->header = 0; out->code = 0;
    for (int i = 0; i < shnum; i++) {
        unsigned int rec = (unsigned int)shoff + i * shentsize;
        unsigned int nameIndex = rd32(elf + rec);
        unsigned long long off = rdu64(elf + rec + 24);
        unsigned long long size = rdu64(elf + rec + 32);
        const char *name = (const char *)(elf + stroff + nameIndex);
        if (str_eq(name, ".shader_header")) { out->header = elf + off; out->header_len = (unsigned int)size; }
        else if (str_eq(name, ".shader_text")) { out->code = elf + off; out->code_len = (unsigned int)size; }
    }
    if (!out->header || !out->code) return -1;
    return 0;
}

/* ---- shader user-data layout (AgcShader.cs TryGetResourceSlot, byte-exact) ---- */
#define SHDR_USERDATA(h)   (*(void**)((unsigned char*)(h) + 8))
#define SHDR_CXREGS(h)     (*(CxRegister**)((unsigned char*)(h) + 24))
#define SHDR_SHREGS(h)     (*(CxRegister**)((unsigned char*)(h) + 32))
#define SHDR_CXCOUNT(h)    (((unsigned char*)(h))[91])
#define SHDR_SHCOUNT(h)    (((unsigned char*)(h))[92])

/* ShaderResourceKind */
#define KIND_READONLY       0
#define KIND_READWRITE      1
#define KIND_SAMPLER        2
#define KIND_CONSTANTBUFFER 3

/* User-data register bases, per shader stage: SPI_SHADER_USER_DATA_<stage>_0
 * minus the 0x2C00 base of the SH register space. */
#define GS_USER_DATA_BASE 0x008C
#define PS_USER_DATA_BASE 0x000C

static int resource_dword_offset(void *handle, unsigned short kind, int slot) {
    void *ud = SHDR_USERDATA(handle);
    if (!ud) return -1;
    unsigned short *counts = (unsigned short*)((unsigned char*)ud + 46);
    if ((unsigned int)slot >= counts[kind]) return -1;
    unsigned short *sharps = *(unsigned short**)((unsigned char*)ud + 8 + kind * sizeof(void*));
    return sharps[slot] & 0x7FFF;
}

/* ---- buffer descriptors (AgcBufferDescriptor.cs) ---- */
static void desc_structured(unsigned int *w, unsigned long long addr, unsigned int stride, unsigned int count) {
    w[0] = (unsigned int)(addr & 0xFFFFFFFFu);
    w[1] = (unsigned int)((addr >> 32) & 0xFFFFu) | ((stride & 0x3FFFu) << 16);
    w[2] = count;
    w[3] = 0x204u | (5u << 12);       /* RegularSwizzle | RegularFormat<<12 */
}
static void desc_constant(unsigned int *w, unsigned long long addr, unsigned int size_bytes) {
    unsigned int record = 16;
    w[0] = (unsigned int)(addr & 0xFFFFFFFFu);
    w[1] = (unsigned int)((addr >> 32) & 0xFFFFu) | (record << 16);
    w[2] = (size_bytes + record - 1) / record;
    w[3] = 0xfacu | (77u << 12);      /* ConstantSwizzle | ConstantFormat<<12 */
}

/* ---- minimal maths: no libc, so sine comes from a 7th-order Taylor series
 * after wrapping into [-PI, PI], which is accurate to about 1e-4 there - far
 * finer than a 1080p pixel. Matrices are row-major and act on row vectors
 * (v' = v * M), matching the PSSL's row_major float4x4 and its mul(v, M). ---- */
#define M_PI_F 3.14159265358979f
#define M_TAU_F 6.28318530717959f

static float m_sin(float x) {
    while (x >  M_PI_F) x -= M_TAU_F;
    while (x < -M_PI_F) x += M_TAU_F;
    float x2 = x * x;
    return x * (1.0f - x2 * (1.0f/6.0f - x2 * (1.0f/120.0f - x2 * (1.0f/5040.0f))));
}
static float m_cos(float x) { return m_sin(x + M_PI_F * 0.5f); }

static void mat_identity(float *m) {
    for (int i = 0; i < 16; i++) m[i] = 0.0f;
    m[0] = m[5] = m[10] = m[15] = 1.0f;
}
static void mat_mul(float *out, const float *a, const float *b) {
    float t[16];
    for (int r = 0; r < 4; r++)
        for (int c = 0; c < 4; c++) {
            float s = 0.0f;
            for (int k = 0; k < 4; k++) s += a[r*4+k] * b[k*4+c];
            t[r*4+c] = s;
        }
    for (int i = 0; i < 16; i++) out[i] = t[i];
}
/* Left-handed perspective with depth in [0,1], for row vectors. */
static void mat_perspective(float *m, float fov_y, float aspect, float zn, float zf) {
    float f = m_cos(fov_y * 0.5f) / m_sin(fov_y * 0.5f);   /* cot(fov/2) */
    for (int i = 0; i < 16; i++) m[i] = 0.0f;
    m[0]  = f / aspect;
    m[5]  = f;
    m[10] = zf / (zf - zn);
    m[11] = 1.0f;
    m[14] = -zn * zf / (zf - zn);
}

/* ---- the cube: 6 faces x 4 corners, so every face carries its own flat
 * normal and colour rather than sharing averaged ones at the corners. ---- */
#define VERTEX_STRIDE 36
#define CUBE_VERTS 24
#define CUBE_INDICES 36

static void put_vertex(unsigned char *p, int i,
                       float px, float py, float pz,
                       float nx, float ny, float nz,
                       unsigned int color) {
    float *f = (float*)(p + (unsigned int)i * VERTEX_STRIDE);
    f[0] = px; f[1] = py; f[2] = pz;
    f[3] = nx; f[4] = ny; f[5] = nz;
    f[6] = 0.0f; f[7] = 0.0f;                    /* uv, unused by these shaders */
    *(unsigned int*)(p + (unsigned int)i * VERTEX_STRIDE + 32) = color;
}

/* Motor visual reutilizable para juegos 3D de plataformas PS5, AGC directo.
 * La interfaz y sus flujos C se integran desde los bloques del IDE.
 * Textura de superficie muestreada offline y horneada en colores de vértice AGC.
 */
#include "ps5hs_visual.h"
#include "ps5hs_game_scene.h"
#include <stdint.h>

extern int sceUserServiceInitialize(const void *);
extern int sceUserServiceGetInitialUser(int *);
extern int scePadInit(void);
extern int scePadOpen(int,int,int,const void *);
extern int scePadReadState(int,void *);
extern int scePadClose(int);
extern int scePadSetVibrationMode(int,int);
extern int scePadSetVibration(int,const void *);
extern int scePadSetLightBar(int,const void *);
extern int sceAudioOutInit(void);
extern int sceAudioOutOpen(int,int,int,unsigned,unsigned,unsigned);
extern int sceAudioOutOutput(int,const void *);
extern int sceAudioOutClose(int);

#define BTN_OPTIONS 0x00000008u
#define BTN_UP 0x00000010u
#define BTN_DOWN 0x00000040u
#define BTN_TRIANGLE 0x00001000u
#define BTN_CROSS 0x00004000u
#define BTN_CIRCLE 0x00002000u
#define BTN_SQUARE 0x00008000u
#define BTN_INTERCEPTED 0x80000000u
#define PLAYER_HALF_H PS5HS_GAME_PLAYER_HALF_HEIGHT
#define PLATFORM_COUNT PS5HS_GAME_PLATFORM_COUNT
#define GAME_OBJECT_COUNT PS5HS_GAME_OBJECT_COUNT
#define SHARD_COUNT PS5HS_GAME_SHARD_COUNT
#define SCENE_MAX_VERTS 24000
#define SCENE_MAX_INDICES 40000
#define UI_MAX_VERTS 12000
#define UI_MAX_INDICES 18000
#define AUDIO_RATE 48000u
#define AUDIO_GRAIN 256u
#define SCREEN_W 1920.0f
#define SCREEN_H 1080.0f
#define PI_F 3.14159265358979f
#define TAU_F 6.28318530717959f

typedef struct { float x,y,z; } Vec3;
typedef struct { unsigned char large_motor,small_motor; } PadVibration;
typedef struct { unsigned char r,g,b,reserved; } PadColor;
typedef struct {
    unsigned char *vertices; unsigned int *indices;
    unsigned int vertex_count,index_count,max_vertices,max_indices;
} MeshBatch;
typedef struct {
    float x,z,top,half_x,half_z;
    float collision_half_x,collision_half_y,collision_half_z,collision_offset_y;
    int collision_enabled,shard_id,checkpoint,goal;
    unsigned int top_color;
} Platform;
typedef struct { float x,y,z,vx,vy,vz; int on_ground,support; } Player;

static Platform level[PLATFORM_COUNT];
static unsigned char shard_taken[SHARD_COUNT];
static Player hero;
static int checkpoint_platform,current_screen,game_started,game_won,menu_choice;
static int audio_enabled=1,audio_port=-1,pad_handle=-1,rumble_frames,respawn_flash,shard_total;
static int audio_sfx_samples;
static float audio_sfx_frequency,audio_sfx_phase,music_phase,world_time;
static unsigned int music_sample;
void game_start(void); void game_pause(void); void game_resume(void);
void game_restart(void); void game_toggle_audio(void);
static void play_note(float hz,int samples);

static int equal(const char *a,const char *b) {
    if(!a||!b)return 0;
    while(*a&&*b&&*a==*b){a++;b++;}
    return *a==*b;
}
static void dispatch_game_action(const char *component_id,const char *event_name,void (*fallback)(void)){
    if(component_id&&component_id[0])ps5hs_dispatch_action(component_id,event_name);
    else if(fallback)fallback();
}
static float clampf(float v,float lo,float hi){if(v<lo)return lo;if(v>hi)return hi;return v;}
static float absf(float v){return v<0?-v:v;}
static Vec3 vec3(float x,float y,float z){Vec3 v={x,y,z};return v;}
static Vec3 sub3(Vec3 a,Vec3 b){return vec3(a.x-b.x,a.y-b.y,a.z-b.z);}
static Vec3 cross3(Vec3 a,Vec3 b){return vec3(a.y*b.z-a.z*b.y,a.z*b.x-a.x*b.z,a.x*b.y-a.y*b.x);}
static float dot3(Vec3 a,Vec3 b){return a.x*b.x+a.y*b.y+a.z*b.z;}
static float sqrt_approx(float x){
    if(x<=0)return 0;
    float r=x>1?x:1;
    for(int i=0;i<8;i++)r=0.5f*(r+x/r);
    return r;
}
static Vec3 normalize3(Vec3 a){
    float n=sqrt_approx(dot3(a,a));
    if(n<0.0001f)return vec3(0,0,1);
    return vec3(a.x/n,a.y/n,a.z/n);
}
static void look_at(float *m,Vec3 eye,Vec3 target){
    Vec3 z=normalize3(sub3(target,eye)),x=normalize3(cross3(vec3(0,1,0),z)),y=cross3(z,x);
    for(int i=0;i<16;i++)m[i]=0;
    m[0]=x.x;m[1]=y.x;m[2]=z.x;m[4]=x.y;m[5]=y.y;m[6]=z.y;
    m[8]=x.z;m[9]=y.z;m[10]=z.z;m[12]=-dot3(x,eye);m[13]=-dot3(y,eye);
    m[14]=-dot3(z,eye);m[15]=1;
}
static void view_projection(float *out,Vec3 eye,Vec3 target){
    float view[16],projection[16];
    look_at(view,eye,target);
    mat_perspective(projection,56.0f*(PI_F/180.0f),16.0f/9.0f,0.1f,120.0f);
    mat_mul(out,view,projection);
}
static float light_channel(unsigned int color,unsigned int shift){return (float)((color>>shift)&255u)/255.0f;}
static unsigned int shade_color_at(unsigned int color,float face,Vec3 normal,Vec3 position){
    normal=normalize3(normal);
    float lr=light_channel(PS5HS_GAME_AMBIENT_COLOR,16)*PS5HS_GAME_AMBIENT_INTENSITY;
    float lg=light_channel(PS5HS_GAME_AMBIENT_COLOR,8)*PS5HS_GAME_AMBIENT_INTENSITY;
    float lb=light_channel(PS5HS_GAME_AMBIENT_COLOR,0)*PS5HS_GAME_AMBIENT_INTENSITY;
    if(lr<0.12f)lr=0.12f;if(lg<0.12f)lg=0.12f;if(lb<0.12f)lb=0.12f;
    if(PS5HS_GAME_SUN_ENABLED){
        Vec3 ray=normalize3(vec3(PS5HS_GAME_SUN_X,PS5HS_GAME_SUN_Y,PS5HS_GAME_SUN_Z));
        float diffuse=dot3(normal,vec3(-ray.x,-ray.y,-ray.z));if(diffuse<0)diffuse=0;
        float energy=diffuse*PS5HS_GAME_SUN_INTENSITY;
        lr+=light_channel(PS5HS_GAME_SUN_COLOR,16)*energy;
        lg+=light_channel(PS5HS_GAME_SUN_COLOR,8)*energy;
        lb+=light_channel(PS5HS_GAME_SUN_COLOR,0)*energy;
    }
    for(unsigned int i=0;i<PS5HS_GAME_POINT_LIGHT_COUNT;i++){
        const Ps5HSGamePointLight *light=&ps5hs_game_point_lights[i];
        Vec3 toLight=vec3(light->x-position.x,light->y-position.y,light->z-position.z);
        float distance=sqrt_approx(dot3(toLight,toLight));if(distance<0.001f||distance>=light->range)continue;
        float ndl=dot3(normal,vec3(toLight.x/distance,toLight.y/distance,toLight.z/distance));if(ndl<=0)continue;
        float attenuation=1.0f-distance/light->range;float energy=light->intensity*ndl*attenuation*attenuation;
        lr+=light_channel(light->color,16)*energy;lg+=light_channel(light->color,8)*energy;lb+=light_channel(light->color,0)*energy;
    }
    /* The built-in AGC pixel shader also applies a fixed 25% + directional term.
       Divide that out here so the visual lighting controls remain authoritative. */
    Vec3 fixed=normalize3(vec3(0.4f,-1.0f,-0.6f));float fixedDiffuse=dot3(normal,vec3(-fixed.x,-fixed.y,-fixed.z));if(fixedDiffuse<0)fixedDiffuse=0;
    float shaderLight=0.25f+0.75f*fixedDiffuse;
    float r=light_channel(color,16)*face*lr/shaderLight*255.0f;
    float g=light_channel(color,8)*face*lg/shaderLight*255.0f;
    float b=light_channel(color,0)*face*lb/shaderLight*255.0f;
    unsigned int ri=(unsigned int)clampf(r,0.0f,255.0f),gi=(unsigned int)clampf(g,0.0f,255.0f),bi=(unsigned int)clampf(b,0.0f,255.0f);
    return 0xFF000000u|(ri<<16)|(gi<<8)|bi;
}
static void batch_init(MeshBatch *b,DirectMem *v,DirectMem *i,unsigned int mv,unsigned int mi){
    b->vertices=(unsigned char*)v->ptr;b->indices=(unsigned int*)i->ptr;
    b->vertex_count=b->index_count=0;b->max_vertices=mv;b->max_indices=mi;
}
static void add_cube(MeshBatch *b,float x,float y,float z,float hx,float hy,float hz,float angle,unsigned int color){
    static const float N[6][3]={{0,0,-1},{0,0,1},{-1,0,0},{1,0,0},{0,1,0},{0,-1,0}};
    static const float C[6][4][3]={
        {{-1,-1,-1},{-1,1,-1},{1,1,-1},{1,-1,-1}},{{1,-1,1},{1,1,1},{-1,1,1},{-1,-1,1}},
        {{-1,-1,1},{-1,1,1},{-1,1,-1},{-1,-1,-1}},{{1,-1,-1},{1,1,-1},{1,1,1},{1,-1,1}},
        {{-1,1,-1},{-1,1,1},{1,1,1},{1,1,-1}},{{-1,-1,1},{-1,-1,-1},{1,-1,-1},{1,-1,1}}
    };
    static const float S[6]={0.72f,0.94f,0.58f,0.82f,1.20f,0.44f};
    if(b->vertex_count+24>b->max_vertices||b->index_count+36>b->max_indices)return;
    float c=m_cos(angle),s=m_sin(angle);unsigned int base=b->vertex_count;
    for(int f=0;f<6;f++){
        for(int k=0;k<4;k++){
            float lx=C[f][k][0]*hx,ly=C[f][k][1]*hy,lz=C[f][k][2]*hz;
            Vec3 worldPosition=vec3(x+lx*c+lz*s,y+ly,z-lx*s+lz*c);
            Vec3 worldNormal=vec3(N[f][0]*c+N[f][2]*s,N[f][1],-N[f][0]*s+N[f][2]*c);
            put_vertex(b->vertices,(int)(base+f*4+k),worldPosition.x,worldPosition.y,worldPosition.z,
                worldNormal.x,worldNormal.y,worldNormal.z,shade_color_at(color,S[f],worldNormal,worldPosition));
        }
        unsigned int *q=b->indices+b->index_count,v=base+(unsigned int)f*4;
        q[0]=v;q[1]=v+1;q[2]=v+2;q[3]=v;q[4]=v+2;q[5]=v+3;b->index_count+=6;
    }
    b->vertex_count+=24;
}
static void add_octahedron(MeshBatch *b,float x,float y,float z,float hx,float hy,float hz,float angle,unsigned int color){
    static const float V[6][3]={{0,1,0},{0,-1,0},{1,0,0},{0,0,1},{-1,0,0},{0,0,-1}};
    static const unsigned char F[8][3]={{0,2,3},{0,3,4},{0,4,5},{0,5,2},{1,3,2},{1,4,3},{1,5,4},{1,2,5}};
    if(b->vertex_count+24>b->max_vertices||b->index_count+24>b->max_indices)return;
    float c=m_cos(angle),s=m_sin(angle);unsigned int base=b->vertex_count;
    for(int face=0;face<8;face++){
        Vec3 local[3];
        for(int k=0;k<3;k++){const float *v=V[F[face][k]];local[k]=vec3(v[0]*hx,v[1]*hy,v[2]*hz);}
        Vec3 normal=normalize3(cross3(sub3(local[1],local[0]),sub3(local[2],local[0])));
        Vec3 centroid=vec3((local[0].x+local[1].x+local[2].x)/3.0f,(local[0].y+local[1].y+local[2].y)/3.0f,(local[0].z+local[1].z+local[2].z)/3.0f);
        if(dot3(normal,centroid)<0){Vec3 swap=local[1];local[1]=local[2];local[2]=swap;normal=vec3(-normal.x,-normal.y,-normal.z);}
        Vec3 worldNormal=normalize3(vec3(normal.x*c+normal.z*s,normal.y,-normal.x*s+normal.z*c));
        for(int k=0;k<3;k++){
            Vec3 p=local[k],worldPosition=vec3(x+p.x*c+p.z*s,y+p.y,z-p.x*s+p.z*c);
            put_vertex(b->vertices,(int)(base+(unsigned int)(face*3+k)),worldPosition.x,worldPosition.y,worldPosition.z,
                worldNormal.x,worldNormal.y,worldNormal.z,shade_color_at(color,1.0f,worldNormal,worldPosition));
        }
        unsigned int *q=b->indices+b->index_count,v=base+(unsigned int)(face*3);q[0]=v;q[1]=v+1;q[2]=v+2;b->index_count+=3;
    }
    b->vertex_count+=24;
}
static Vec3 rotate_y_vector(Vec3 p,float c,float s){return vec3(p.x*c+p.z*s,p.y,-p.x*s+p.z*c);}
static void add_surface_triangle(MeshBatch *b,Vec3 a,Vec3 c,Vec3 d,Vec3 center,float angle,unsigned int color,float face){
    if(b->vertex_count+3>b->max_vertices||b->index_count+3>b->max_indices)return;
    Vec3 normal=normalize3(cross3(sub3(c,a),sub3(d,a)));
    Vec3 centroid=vec3((a.x+c.x+d.x)/3.0f,(a.y+c.y+d.y)/3.0f,(a.z+c.z+d.z)/3.0f);
    if(dot3(normal,sub3(centroid,center))<0){Vec3 swap=c;c=d;d=swap;normal=vec3(-normal.x,-normal.y,-normal.z);}
    float cs=m_cos(angle),sn=m_sin(angle);Vec3 local[3]={a,c,d};unsigned int base=b->vertex_count;
    for(int i=0;i<3;i++){
        Vec3 p=local[i],world=vec3(center.x+p.x*cs+p.z*sn,center.y+p.y,center.z-p.x*sn+p.z*cs);
        Vec3 n=rotate_y_vector(normal,cs,sn);
        put_vertex(b->vertices,(int)(base+(unsigned int)i),world.x,world.y,world.z,n.x,n.y,n.z,shade_color_at(color,face,n,world));
    }
    unsigned int *q=b->indices+b->index_count;q[0]=base;q[1]=base+1;q[2]=base+2;b->vertex_count+=3;b->index_count+=3;
}
static void add_uv_sphere(MeshBatch *b,float x,float y,float z,float hx,float hy,float hz,float angle,unsigned int color){
    enum { SEGMENTS=10, STACKS=5 };
    if(b->vertex_count+SEGMENTS*STACKS*4>b->max_vertices||b->index_count+SEGMENTS*STACKS*6>b->max_indices)return;
    float cs=m_cos(angle),sn=m_sin(angle);unsigned int base=b->vertex_count;
    for(int stack=0;stack<STACKS;stack++)for(int segment=0;segment<SEGMENTS;segment++){
        float lat0=-PI_F*0.5f+PI_F*(float)stack/(float)STACKS,lat1=-PI_F*0.5f+PI_F*(float)(stack+1)/(float)STACKS;
        float a0=TAU_F*(float)segment/(float)SEGMENTS,a1=TAU_F*(float)(segment+1)/(float)SEGMENTS;
        float cy0=m_cos(lat0),cy1=m_cos(lat1),sy0=m_sin(lat0),sy1=m_sin(lat1);
        Vec3 local[4]={vec3(hx*cy0*m_cos(a0),hy*sy0,hz*cy0*m_sin(a0)),vec3(hx*cy1*m_cos(a0),hy*sy1,hz*cy1*m_sin(a0)),vec3(hx*cy1*m_cos(a1),hy*sy1,hz*cy1*m_sin(a1)),vec3(hx*cy0*m_cos(a1),hy*sy0,hz*cy0*m_sin(a1))};
        unsigned int v=base+(unsigned int)((stack*SEGMENTS+segment)*4);
        for(int k=0;k<4;k++){
            Vec3 p=local[k],normal=normalize3(vec3(p.x/(hx*hx),p.y/(hy*hy),p.z/(hz*hz)));
            Vec3 world=vec3(x+p.x*cs+p.z*sn,y+p.y,z-p.x*sn+p.z*cs),worldNormal=rotate_y_vector(normal,cs,sn);
            put_vertex(b->vertices,(int)(v+(unsigned int)k),world.x,world.y,world.z,worldNormal.x,worldNormal.y,worldNormal.z,shade_color_at(color,1.0f,worldNormal,world));
        }
        unsigned int *q=b->indices+b->index_count;q[0]=v;q[1]=v+1;q[2]=v+2;q[3]=v;q[4]=v+2;q[5]=v+3;b->index_count+=6;
    }
    b->vertex_count+=(unsigned int)(SEGMENTS*STACKS*4);
}
static void add_tapered_cylinder(MeshBatch *b,float x,float y,float z,float hx,float hy,float hz,float angle,float top_radius,unsigned int color){
    enum { SEGMENTS=12 };
    if(b->vertex_count+SEGMENTS*4+SEGMENTS*6>b->max_vertices||b->index_count+SEGMENTS*6+SEGMENTS*6>b->max_indices)return;
    float cs=m_cos(angle),sn=m_sin(angle);unsigned int base=b->vertex_count;
    for(int segment=0;segment<SEGMENTS;segment++){
        float a0=TAU_F*(float)segment/(float)SEGMENTS,a1=TAU_F*(float)(segment+1)/(float)SEGMENTS;
        Vec3 local[4]={vec3(hx*m_cos(a0),-hy,hz*m_sin(a0)),vec3(hx*top_radius*m_cos(a0),hy,hz*top_radius*m_sin(a0)),vec3(hx*top_radius*m_cos(a1),hy,hz*top_radius*m_sin(a1)),vec3(hx*m_cos(a1),-hy,hz*m_sin(a1))};
        Vec3 localNormal=normalize3(vec3(2.0f*hy*(m_cos(a0)+m_cos(a1))*0.5f,hx*(1.0f-top_radius),2.0f*hy*(m_sin(a0)+m_sin(a1))*0.5f)),worldNormal=rotate_y_vector(localNormal,cs,sn);
        unsigned int v=base+(unsigned int)(segment*4);
        for(int k=0;k<4;k++){Vec3 p=local[k],world=vec3(x+p.x*cs+p.z*sn,y+p.y,z-p.x*sn+p.z*cs);put_vertex(b->vertices,(int)(v+(unsigned int)k),world.x,world.y,world.z,worldNormal.x,worldNormal.y,worldNormal.z,shade_color_at(color,1.0f,worldNormal,world));}
        unsigned int *q=b->indices+b->index_count;q[0]=v;q[1]=v+1;q[2]=v+2;q[3]=v;q[4]=v+2;q[5]=v+3;b->index_count+=6;
    }
    b->vertex_count+=(unsigned int)(SEGMENTS*4);
    for(int cap=0;cap<2;cap++){
        float yy=cap?hy:-hy;Vec3 normal=vec3(0,cap?1.0f:-1.0f,0),worldNormal=rotate_y_vector(normal,cs,sn);float radius=cap?top_radius:1.0f;
        for(int segment=0;segment<SEGMENTS;segment++){
            float a0=TAU_F*(float)segment/(float)SEGMENTS,a1=TAU_F*(float)(segment+1)/(float)SEGMENTS;
            Vec3 p0=vec3(0,yy,0),p1=vec3(hx*radius*m_cos(a0),yy,hz*radius*m_sin(a0)),p2=vec3(hx*radius*m_cos(a1),yy,hz*radius*m_sin(a1));
            if(cap){Vec3 swap=p1;p1=p2;p2=swap;}
            Vec3 local[3]={p0,p1,p2};unsigned int v=b->vertex_count;
            for(int k=0;k<3;k++){Vec3 p=local[k],world=vec3(x+p.x*cs+p.z*sn,y+p.y,z-p.x*sn+p.z*cs);put_vertex(b->vertices,(int)(v+(unsigned int)k),world.x,world.y,world.z,worldNormal.x,worldNormal.y,worldNormal.z,shade_color_at(color,1.15f,worldNormal,world));}
            unsigned int *q=b->indices+b->index_count;q[0]=v;q[1]=v+1;q[2]=v+2;b->vertex_count+=3;b->index_count+=3;
        }
    }
}
static void add_square_pyramid(MeshBatch *b,float x,float y,float z,float hx,float hy,float hz,float angle,unsigned int color){
    Vec3 center=vec3(x,y,z),apex=vec3(0,hy,0),base[4]={vec3(-hx,-hy,-hz),vec3(hx,-hy,-hz),vec3(hx,-hy,hz),vec3(-hx,-hy,hz)};
    for(int i=0;i<4;i++)add_surface_triangle(b,base[i],base[(i+1)%4],apex,center,angle,color,1.0f);
    add_surface_triangle(b,base[0],base[2],base[1],center,angle,color,0.72f);
    add_surface_triangle(b,base[0],base[3],base[2],center,angle,color,0.72f);
}
static void add_surface_tile(MeshBatch *b,float x0,float x1,float z0,float z1,float y,unsigned int color){
    if(b->vertex_count+4>b->max_vertices||b->index_count+6>b->max_indices)return;
    unsigned int v=b->vertex_count;
    Vec3 p[4]={vec3(x0,y,z0),vec3(x0,y,z1),vec3(x1,y,z1),vec3(x1,y,z0)};
    for(int i=0;i<4;i++)put_vertex(b->vertices,(int)(v+(unsigned int)i),p[i].x,p[i].y,p[i].z,0,1,0,
        shade_color_at(color,1.20f,vec3(0,1,0),p[i]));
    unsigned int *q=b->indices+b->index_count;
    q[0]=v;q[1]=v+1;q[2]=v+2;q[3]=v;q[4]=v+2;q[5]=v+3;
    b->vertex_count+=4;b->index_count+=6;
}
static void ui_rect(MeshBatch *b,float x,float y,float w,float h,unsigned int color){
    if(w<=0||h<=0||b->vertex_count+4>b->max_vertices||b->index_count+6>b->max_indices)return;
    unsigned int v=b->vertex_count;
    float x0=2*x/SCREEN_W-1,x1=2*(x+w)/SCREEN_W-1,y0=1-2*y/SCREEN_H,y1=1-2*(y+h)/SCREEN_H;
    put_vertex(b->vertices,(int)v,x0,y0,0,0,0,1,color);
    put_vertex(b->vertices,(int)v+1,x0,y1,0,0,0,1,color);
    put_vertex(b->vertices,(int)v+2,x1,y1,0,0,0,1,color);
    put_vertex(b->vertices,(int)v+3,x1,y0,0,0,0,1,color);
    unsigned int *q=b->indices+b->index_count;q[0]=v;q[1]=v+1;q[2]=v+2;q[3]=v;q[4]=v+2;q[5]=v+3;
    b->vertex_count+=4;b->index_count+=6;
}
static const unsigned char *glyph(char ch){
    static const unsigned char g[36][7]={
        {14,17,17,31,17,17,17},{30,17,17,30,17,17,30},{14,17,16,16,16,17,14},{30,17,17,17,17,17,30},
        {31,16,16,30,16,16,31},{31,16,16,30,16,16,16},{14,17,16,23,17,17,15},{17,17,17,31,17,17,17},
        {14,4,4,4,4,4,14},{7,2,2,2,18,18,12},{17,18,20,24,20,18,17},{16,16,16,16,16,16,31},
        {17,27,21,21,17,17,17},{17,25,21,19,17,17,17},{14,17,17,17,17,17,14},{30,17,17,30,16,16,16},
        {14,17,17,17,21,18,13},{30,17,17,30,20,18,17},{15,16,16,14,1,1,30},{31,4,4,4,4,4,4},
        {17,17,17,17,17,17,14},{17,17,17,17,17,10,4},{17,17,17,21,21,21,10},{17,17,10,4,10,17,17},
        {17,17,10,4,4,4,4},{31,1,2,4,8,16,31},{14,17,19,21,25,17,14},{4,12,4,4,4,4,14},
        {14,17,1,2,4,8,31},{30,1,1,14,1,1,30},{2,6,10,18,31,2,2},{31,16,16,30,1,1,30},
        {14,16,16,30,17,17,14},{31,1,2,4,8,8,8},{14,17,17,14,17,17,14},{14,17,17,15,1,1,14}
    };
    if(ch>='a'&&ch<='z')ch=(char)(ch-'a'+'A');
    if(ch>='A'&&ch<='Z')return g[ch-'A'];
    if(ch>='0'&&ch<='9')return g[26+ch-'0'];
    return 0;
}
static int utf8_width(const unsigned char *s){
    if(s[0]<0x80)return 1;if((s[0]&0xE0)==0xC0)return 2;
    if((s[0]&0xF0)==0xE0)return 3;if((s[0]&0xF8)==0xF0)return 4;return 1;
}
static void draw_line(MeshBatch *ui,const unsigned char *s,int bytes,float x,float y,float scale,unsigned int color){
    float cx=x;
    for(int i=0;i<bytes;i++){
        unsigned char ch=s[i];
        if(ch>=0x80){
            int n=utf8_width(s+i);if(n>bytes-i)n=bytes-i;
            ui_rect(ui,cx+2*scale,y+scale,2*scale,2*scale,color);
            ui_rect(ui,cx+scale,y+3*scale,4*scale,scale,color);
            ui_rect(ui,cx+2*scale,y+4*scale,2*scale,2*scale,color);
            cx+=6*scale;i+=n-1;continue;
        }
        if(ch==' '){cx+=4*scale;continue;}
        const unsigned char *rows=glyph((char)ch);
        if(rows){for(int yy=0;yy<7;yy++)for(int xx=0;xx<5;xx++)
            if((rows[yy]>>(4-xx))&1)ui_rect(ui,cx+xx*scale,y+yy*scale,scale,scale,color);}
        else if(ch=='.')ui_rect(ui,cx+2*scale,y+6*scale,scale,scale,color);
        else if(ch==':'){ui_rect(ui,cx+2*scale,y+2*scale,scale,scale,color);ui_rect(ui,cx+2*scale,y+5*scale,scale,scale,color);}
        else if(ch=='-')ui_rect(ui,cx+scale,y+3*scale,3*scale,scale,color);
        else if(ch=='!'){ui_rect(ui,cx+2*scale,y,scale,5*scale,color);ui_rect(ui,cx+2*scale,y+6*scale,scale,scale,color);}
        else if(ch=='/')for(int k=0;k<5;k++)ui_rect(ui,cx+(4-k)*scale,y+k*scale,scale,scale,color);
        else if(ch=='+'){ui_rect(ui,cx+2*scale,y+scale,scale,5*scale,color);ui_rect(ui,cx,y+3*scale,5*scale,scale,color);}
        else if(ch=='='){ui_rect(ui,cx,y+2*scale,5*scale,scale,color);ui_rect(ui,cx,y+5*scale,5*scale,scale,color);}
        cx+=6*scale;
    }
}
static void draw_text(MeshBatch *ui,const char *s,float x,float y,float w,float h,float font,unsigned int color){
    if(!s||!s[0]||font<4)return;int len=0;while(s[len]&&len<160)len++;
    float scale=font/7.0f;int cap=(int)(w/(6*scale));if(cap<1)cap=1;if(cap>len)cap=len;
    int starts[12],counts[12],lines=0,start=0;
    while(start<len&&lines<12){
        int end=start+cap;if(end>=len)end=len;
        else{int split=end;while(split>start&&s[split]!=' ')split--;if(split>start)end=split;}
        if(end<=start)end=start+1;starts[lines]=start;counts[lines]=end-start;lines++;start=end;
        while(start<len&&s[start]==' ')start++;
    }
    float lh=8*scale;if(lines*lh>h&&lines>1){scale=h/(8.0f*lines);if(scale<1)scale=1;lh=8*scale;}
    float y0=y;if(lines*lh<h)y0+=(h-lines*lh)*0.5f;
    for(int i=0;i<lines;i++){float tw=counts[i]*6*scale;draw_line(ui,(const unsigned char*)s+starts[i],counts[i],x+(w-tw)*0.5f,y0+i*lh,scale,color);}
}
static void create_level(void){
    for(int i=0;i<PLATFORM_COUNT;i++){
        const Ps5HSGamePlatform *source=&ps5hs_game_platforms[i];
        level[i].x=source->x;level[i].z=source->z;level[i].top=source->height;
        level[i].half_x=source->half_width;level[i].half_z=source->half_depth;
        level[i].collision_half_x=source->collision_half_width;
        level[i].collision_half_y=source->collision_half_height;
        level[i].collision_half_z=source->collision_half_depth;
        level[i].collision_offset_y=source->collision_offset_y;
        level[i].collision_enabled=source->collision_enabled;
        level[i].shard_id=source->shard_id;level[i].checkpoint=source->checkpoint;
        level[i].goal=source->goal;level[i].top_color=source->top_color;
    }
}
static void reset_run(void){
    create_level();for(int i=0;i<SHARD_COUNT;i++)shard_taken[i]=0;
    shard_total=0;checkpoint_platform=PS5HS_GAME_SPAWN_INDEX;
    if(checkpoint_platform<0||checkpoint_platform>=PLATFORM_COUNT)checkpoint_platform=0;
    if(!level[checkpoint_platform].collision_enabled){
        int safe_platform=-1;
        for(int i=0;i<PLATFORM_COUNT;i++)if(level[i].collision_enabled&&level[i].checkpoint){safe_platform=i;break;}
        if(safe_platform<0)for(int i=0;i<PLATFORM_COUNT;i++)if(level[i].collision_enabled){safe_platform=i;break;}
        if(safe_platform<0){game_started=0;current_screen=0;game_won=0;notify(PS5HS_GAME_TITLE ": la escena no tiene ninguna superficie solida");return;}
        checkpoint_platform=safe_platform;
    }
    Platform *start=&level[checkpoint_platform];hero.x=start->x;hero.y=start->top+start->collision_offset_y+PLAYER_HALF_H;hero.z=start->z;
    hero.vx=hero.vy=hero.vz=0;hero.on_ground=1;hero.support=checkpoint_platform;
    game_won=0;respawn_flash=0;menu_choice=0;game_started=1;world_time=0;
    if(pad_handle>=0){PadColor c={112,131,255,0};(void)scePadSetLightBar(pad_handle,&c);}
}
void game_start(void){if(!game_started)reset_run();if(!game_started)return;current_screen=2;}
void game_pause(void){if(game_started&&!game_won&&current_screen==2){current_screen=1;menu_choice=0;}}
void game_resume(void){if(current_screen==1)current_screen=2;}
void game_restart(void){reset_run();if(game_started)current_screen=2;}

void game_toggle_audio(void){audio_enabled=!audio_enabled;audio_sfx_frequency=audio_enabled?660:330;audio_sfx_samples=3600;audio_sfx_phase=0;}
static void play_note(float hz,int samples){audio_sfx_frequency=hz;audio_sfx_samples=samples;audio_sfx_phase=0;}
static void rumble(unsigned char large,unsigned char small,int frames){
    if(pad_handle<0)return;PadVibration v={large,small};(void)scePadSetVibration(pad_handle,&v);rumble_frames=frames;
}
static unsigned int read_buttons(const unsigned char *p){
    return (unsigned int)p[0]|((unsigned int)p[1]<<8)|((unsigned int)p[2]<<16)|((unsigned int)p[3]<<24);
}
static float stick(unsigned char v){int d=(int)v-128;if(d>-16&&d<16)return 0;return clampf((float)d/112,-1,1);}
static void respawn(void){
    Platform *p=&level[checkpoint_platform];hero.x=p->x;hero.y=p->top+p->collision_offset_y+PLAYER_HALF_H;hero.z=p->z;
    hero.vx=hero.vy=hero.vz=0;hero.on_ground=1;hero.support=checkpoint_platform;respawn_flash=100;
    play_note(190,9000);rumble(225,90,14);PadColor c={180,105,255,0};if(pad_handle>=0)(void)scePadSetLightBar(pad_handle,&c);
}
static void collect_shards(void){
    for(int i=0;i<PLATFORM_COUNT;i++){
        int id=level[i].shard_id;if(id<0||shard_taken[id])continue;
        if(absf(hero.x-level[i].x)<0.82f&&absf(hero.y-level[i].top-level[i].collision_offset_y-1.05f)<1.12f&&absf(hero.z-level[i].z)<0.95f){
            shard_taken[id]=1;shard_total++;play_note(880+(id%3)*110,7200);rumble(150,220,9);
            PadColor c={255,201,102,0};if(pad_handle>=0)(void)scePadSetLightBar(pad_handle,&c);
        }
    }
}
/* Resolve the player against an axis-aligned solid box. The authored top is
 * the walkable surface; half-height controls the box thickness below it. */
static int resolve_player_box(float center_x,float top,float center_z,float half_x,float half_y,float half_z,
                              float old_x,float old_y,float old_z,float *next_x,float *next_y,float *next_z,
                              float *velocity_x,float *velocity_y,float *velocity_z){
    const float player_half_x=0.34f,player_half_z=0.32f,epsilon=0.001f;
    float left=center_x-half_x,right=center_x+half_x,front=center_z-half_z,back=center_z+half_z;
    float bottom=top-2.0f*half_y,old_feet=old_y-PLAYER_HALF_H,new_feet=*next_y-PLAYER_HALF_H;
    float old_head=old_y+PLAYER_HALF_H,new_head=*next_y+PLAYER_HALF_H;
    int overlaps_x=(*next_x+player_half_x>left&&*next_x-player_half_x<right);
    int overlaps_z=(*next_z+player_half_z>front&&*next_z-player_half_z<back);
    if(*velocity_y<=0.0f&&old_feet>=top-0.06f&&new_feet<=top+0.08f&&overlaps_x&&overlaps_z){
        *next_y=top+PLAYER_HALF_H;*velocity_y=0.0f;return 1;
    }
    if(*velocity_y>0.0f&&old_head<=bottom+0.06f&&new_head>=bottom-0.08f&&overlaps_x&&overlaps_z){
        *next_y=bottom-PLAYER_HALF_H-epsilon;*velocity_y=0.0f;new_head=*next_y+PLAYER_HALF_H;
    }
    if(new_feet<top-0.01f&&new_head>bottom+0.01f){
        int overlaps_z_for_x=(*next_z+player_half_z>front&&*next_z-player_half_z<back);
        float old_left=old_x-player_half_x,old_right=old_x+player_half_x;
        float new_left=*next_x-player_half_x,new_right=*next_x+player_half_x;
        if(overlaps_z_for_x&&old_right<=left&&new_right>left){*next_x=left-player_half_x-epsilon;*velocity_x=0.0f;}
        else if(overlaps_z_for_x&&old_left>=right&&new_left<right){*next_x=right+player_half_x+epsilon;*velocity_x=0.0f;}
        int overlaps_x_for_z=(*next_x+player_half_x>left&&*next_x-player_half_x<right);
        float old_front=old_z-player_half_z,old_back=old_z+player_half_z;
        float new_front=*next_z-player_half_z,new_back=*next_z+player_half_z;
        if(overlaps_x_for_z&&old_back<=front&&new_back>front){*next_z=front-player_half_z-epsilon;*velocity_z=0.0f;}
        else if(overlaps_x_for_z&&old_front>=back&&new_front<back){*next_z=back+player_half_z+epsilon;*velocity_z=0.0f;}
    }
    return 0;
}
static void update_game(float ax,float forward,int jump){
    if(current_screen!=2||game_won)return;
    const float dt=1.0f/60.0f,speed=PS5HS_GAME_MOVE_SPEED;
    int was_grounded=hero.on_ground;
    float smooth=clampf(dt*PS5HS_GAME_ACCELERATION,0,1);
    hero.vx+=(ax*speed-hero.vx)*smooth;hero.vz+=(forward*speed-hero.vz)*smooth;
    if(jump&&hero.on_ground){hero.vy=PS5HS_GAME_JUMP_SPEED;hero.on_ground=0;hero.support=-1;play_note(430,5400);rumble(45,135,5);}
    float old_x=hero.x,old_y=hero.y,old_z=hero.z;
    hero.x+=hero.vx*dt;hero.z+=hero.vz*dt;hero.vy-=PS5HS_GAME_GRAVITY*dt;hero.y+=hero.vy*dt;
    hero.on_ground=0;hero.support=-1;
    for(int i=0;i<PLATFORM_COUNT;i++){
        Platform *p=&level[i];if(!p->collision_enabled)continue;
        float collision_top=p->top+p->collision_offset_y;
        if(resolve_player_box(p->x,collision_top,p->z,p->collision_half_x,p->collision_half_y,p->collision_half_z,
                              old_x,old_y,old_z,&hero.x,&hero.y,&hero.z,&hero.vx,&hero.vy,&hero.vz)){
            hero.on_ground=1;hero.support=i;
            if(p->checkpoint&&i>checkpoint_platform){checkpoint_platform=i;play_note(620,9600);rumble(100,175,8);}
            else if(!was_grounded){play_note(245,2400);rumble(30,100,4);}break;
        }
    }
    if(!hero.on_ground)for(int i=0;i<GAME_OBJECT_COUNT;i++){
        const Ps5HSGameObject *object=&ps5hs_game_objects[i];if(!object->collision_enabled)continue;
        float collision_top=object->y+object->collision_offset_y+object->collision_half_height;
        if(resolve_player_box(object->x,collision_top,object->z,object->collision_half_width,object->collision_half_height,object->collision_half_depth,
                              old_x,old_y,old_z,&hero.x,&hero.y,&hero.z,&hero.vx,&hero.vy,&hero.vz)){
            hero.on_ground=1;hero.support=PLATFORM_COUNT+i;
            if(!was_grounded){play_note(245,2400);rumble(30,100,4);}break;
        }
    }
    if(hero.on_ground&&hero.support>=0){
        if(hero.support<PLATFORM_COUNT){Platform *support=&level[hero.support];hero.y=support->top+support->collision_offset_y+PLAYER_HALF_H;}
        else{int object_index=hero.support-PLATFORM_COUNT;if(object_index>=0&&object_index<GAME_OBJECT_COUNT){const Ps5HSGameObject *support=&ps5hs_game_objects[object_index];hero.y=support->y+support->collision_offset_y+support->collision_half_height+PLAYER_HALF_H;}else{hero.on_ground=0;hero.support=-1;}}
    }
    collect_shards();
    if((!PS5HS_GAME_REQUIRE_COLLECTIBLES||shard_total>=SHARD_COUNT)&&hero.on_ground&&hero.support==PS5HS_GAME_GOAL_INDEX){
        game_won=1;play_note(784,18000);rumble(210,255,18);
    }
    if(hero.y<PS5HS_GAME_FALL_LIMIT)respawn();
    if(respawn_flash>0)respawn_flash--;
}

static void menu_input(int up,int down,int cross,int circle){
    if(current_screen==0&&cross){dispatch_game_action(PS5HS_GAME_START_COMPONENT_ID,PS5HS_GAME_START_EVENT,game_start);return;}
    if(current_screen==1){
        if(up)menu_choice=(menu_choice+2)%3;if(down)menu_choice=(menu_choice+1)%3;
        if(cross){if(menu_choice==0)dispatch_game_action(PS5HS_GAME_RESUME_COMPONENT_ID,PS5HS_GAME_RESUME_EVENT,game_resume);
            else if(menu_choice==1)dispatch_game_action(PS5HS_GAME_RESTART_COMPONENT_ID,PS5HS_GAME_RESTART_EVENT,game_restart);
            else dispatch_game_action(PS5HS_GAME_AUDIO_COMPONENT_ID,PS5HS_GAME_AUDIO_EVENT,game_toggle_audio);}
        if(circle)dispatch_game_action(PS5HS_GAME_RESUME_COMPONENT_ID,PS5HS_GAME_RESUME_EVENT,game_resume);
    }else if(current_screen==2&&game_won&&cross)dispatch_game_action(PS5HS_GAME_RESTART_COMPONENT_ID,PS5HS_GAME_RESTART_EVENT,game_restart);
}
static void audio_frame(void){
    if(audio_port<0)return;static int16_t pcm[AUDIO_GRAIN*2];const float step=TAU_F/(float)AUDIO_RATE;
    static const unsigned short notes[8]={392,440,523,659,587,523,440,349};
    for(unsigned int i=0;i<AUDIO_GRAIN;i++){
        float sample=0;
        if(audio_enabled){
            unsigned int beat=(music_sample/12000u)&7u;music_phase+=step*notes[beat];if(music_phase>TAU_F)music_phase-=TAU_F;
            sample=m_sin(music_phase)*0.055f+m_sin(music_phase*0.5f)*0.018f;
            if(current_screen==2&&!game_won)sample*=0.58f;
            if(audio_sfx_samples>0){audio_sfx_phase+=step*audio_sfx_frequency;if(audio_sfx_phase>TAU_F)audio_sfx_phase-=TAU_F;
                sample+=m_sin(audio_sfx_phase)*0.20f;audio_sfx_samples--;}
        }
        sample=clampf(sample,-0.90f,0.90f);int16_t v=(int16_t)(sample*32767);pcm[i*2]=v;pcm[i*2+1]=v;music_sample++;
    }(void)sceAudioOutOutput(audio_port,pcm);
}
static void add_platform(MeshBatch *b,int i){
    Platform *p=&level[i];unsigned int stone=(i/4)%3==0?0xFF514D78u:((i/4)%3==1?0xFF59495Fu:0xFF424F7Cu);
    float surface_y=p->top+p->collision_offset_y;
    add_cube(b,p->x,p->top-0.47f,p->z,p->half_x,0.45f,p->half_z,i*0.11f,stone);
    add_cube(b,p->x,surface_y-0.06f,p->z,p->half_x,0.10f,p->half_z,0,p->top_color);
    if(PS5HS_GAME_SURFACE_TEXTURE_ENABLED){
        float tile_width=(p->half_x*2.0f)/(float)PS5HS_GAME_SURFACE_TEXTURE_SIZE;
        float tile_depth=(p->half_z*2.0f)/(float)PS5HS_GAME_SURFACE_TEXTURE_SIZE;
        for(int row=0;row<PS5HS_GAME_SURFACE_TEXTURE_SIZE;row++)for(int col=0;col<PS5HS_GAME_SURFACE_TEXTURE_SIZE;col++){
            float x0=p->x-p->half_x+(float)col*tile_width,x1=x0+tile_width;
            float z0=p->z-p->half_z+(float)row*tile_depth,z1=z0+tile_depth;
            unsigned int texel=ps5hs_game_surface_texture[row*PS5HS_GAME_SURFACE_TEXTURE_SIZE+col];
            add_surface_tile(b,x0,x1,z0,z1,surface_y+0.055f,texel);
        }
    }
    add_cube(b,p->x+p->half_x*0.60f,surface_y+0.045f,p->z+p->half_z*0.60f,0.10f,0.05f,0.10f,world_time,0xFFFFD894u);
    int sid=p->shard_id;if(sid>=0&&!shard_taken[sid]){
        float bob=m_sin(world_time*1.6f+sid)*0.10f;
        add_octahedron(b,p->x+0.10f,surface_y+1.04f+bob,p->z,0.32f,0.48f,0.32f,world_time+sid*0.5f,PS5HS_GAME_COLLECTIBLE_COLOR);
        add_octahedron(b,p->x+0.10f,surface_y+1.04f+bob,p->z,0.105f,0.58f,0.105f,-world_time,0xFFD6FFF5u);
    }
}

static void add_nebula_explorer(MeshBatch *b){
    float moving=clampf(absf(hero.vx)+absf(hero.vz),0.0f,1.0f);
    float stride=m_sin(world_time*11.0f)*0.13f*moving;
    float arm_swing=m_sin(world_time*11.0f+PI_F)*0.15f*moving;
    float yaw=hero.vx*0.10f;
    unsigned int suit=PS5HS_GAME_PLAYER_COLOR,trim=PS5HS_GAME_PLAYER_ACCENT_COLOR;
    unsigned int dark=0xFF252849u,glass=0xFF79F4E6u;

    /* A small low-poly explorer built from the same editable palette as the scene. */
    add_uv_sphere(b,hero.x,hero.y+0.01f,hero.z,0.27f,0.34f,0.22f,yaw,suit);
    add_tapered_cylinder(b,hero.x,hero.y+0.28f,hero.z,0.19f,0.07f,0.17f,yaw,0.92f,trim);
    add_cube(b,hero.x,hero.y+0.02f,hero.z-0.235f,0.17f,0.23f,0.12f,yaw,dark);
    add_cube(b,hero.x,hero.y+0.02f,hero.z-0.32f,0.12f,0.14f,0.055f,yaw,0xFF68A8D8u);
    add_uv_sphere(b,hero.x,hero.y+0.49f,hero.z,0.195f,0.19f,0.19f,yaw,trim);
    add_cube(b,hero.x,hero.y+0.49f,hero.z+0.171f,0.142f,0.075f,0.035f,yaw,dark);
    add_cube(b,hero.x-0.065f,hero.y+0.49f,hero.z+0.204f,0.025f,0.025f,0.014f,yaw,glass);
    add_cube(b,hero.x+0.065f,hero.y+0.49f,hero.z+0.204f,0.025f,0.025f,0.014f,yaw,glass);
    add_octahedron(b,hero.x,hero.y+0.66f,hero.z,0.055f,0.065f,0.055f,world_time*0.8f,glass);

    add_uv_sphere(b,hero.x-0.30f,hero.y+0.17f+arm_swing,hero.z,0.105f,0.21f,0.115f,yaw,suit);
    add_uv_sphere(b,hero.x+0.30f,hero.y+0.17f-arm_swing,hero.z,0.105f,0.21f,0.115f,yaw,suit);
    add_uv_sphere(b,hero.x-0.34f,hero.y-0.06f+arm_swing,hero.z+0.015f,0.09f,0.105f,0.095f,yaw,trim);
    add_uv_sphere(b,hero.x+0.34f,hero.y-0.06f-arm_swing,hero.z+0.015f,0.09f,0.105f,0.095f,yaw,trim);
    add_uv_sphere(b,hero.x-0.12f,hero.y-0.36f+stride,hero.z,0.105f,0.24f,0.115f,yaw,suit);
    add_uv_sphere(b,hero.x+0.12f,hero.y-0.36f-stride,hero.z,0.105f,0.24f,0.115f,yaw,suit);
    add_cube(b,hero.x-0.12f,hero.y-0.61f+stride,hero.z+0.045f,0.13f,0.09f,0.17f,yaw,dark);
    add_cube(b,hero.x+0.12f,hero.y-0.61f-stride,hero.z+0.045f,0.13f,0.09f,0.17f,yaw,dark);
    add_cube(b,hero.x,hero.y+0.02f,hero.z+0.232f,0.075f,0.075f,0.035f,0,glass);
}

static void build_scene(MeshBatch *b){
    b->vertex_count=b->index_count=0;
    for(unsigned int i=0;i<GAME_OBJECT_COUNT;i++){
        const Ps5HSGameObject *object=&ps5hs_game_objects[i];
        float angle=object->rotation_y_degrees*(PI_F/180.0f);
        if(object->shape==1)add_octahedron(b,object->x,object->y,object->z,object->half_width,object->half_height,object->half_depth,angle,object->color);
        else if(object->shape==2)add_uv_sphere(b,object->x,object->y,object->z,object->half_width,object->half_height,object->half_depth,angle,object->color);
        else if(object->shape==3)add_tapered_cylinder(b,object->x,object->y,object->z,object->half_width,object->half_height,object->half_depth,angle,1.0f,object->color);
        else if(object->shape==4)add_tapered_cylinder(b,object->x,object->y,object->z,object->half_width,object->half_height,object->half_depth,angle,0.035f,object->color);
        else if(object->shape==5)add_square_pyramid(b,object->x,object->y,object->z,object->half_width,object->half_height,object->half_depth,angle,object->color);
        else add_cube(b,object->x,object->y,object->z,object->half_width,object->half_height,object->half_depth,angle,object->color);
    }
    for(int i=0;i<30;i++){
        float x=(float)((i*37)%31-15)*1.9f,y=3+(float)((i*19)%17)*0.53f,z=18+(float)((i*23)%25)*3.2f;
        float size=i%5==0?0.075f:0.045f;
        add_octahedron(b,x,y,z,size,size*1.4f,size,world_time*0.15f,i%4==0?0xFF77D9FFu:0xFFEEE7FFu);
    }
    add_uv_sphere(b,-8,8,35,1.8f,1.0f,1.2f,0.18f,0xFF7569A8u);
    add_uv_sphere(b,9,10,62,2.2f,1.25f,1.8f,-0.24f,0xFF424E81u);
    add_octahedron(b,6,5,20,0.55f,0.8f,0.55f,world_time*0.18f,0xFFFFC58Cu);
    for(int i=PLATFORM_COUNT-1;i>=0;i--){
        add_platform(b,i);
        if(i==PS5HS_GAME_GOAL_INDEX){Platform *p=&level[i];float surface_y=p->top+p->collision_offset_y;
            add_tapered_cylinder(b,p->x-0.66f,surface_y+0.88f,p->z,0.13f,0.88f,0.13f,0,0.78f,PS5HS_GAME_GOAL_COLOR);
            add_tapered_cylinder(b,p->x+0.66f,surface_y+0.88f,p->z,0.13f,0.88f,0.13f,0,0.78f,PS5HS_GAME_GOAL_COLOR);
            add_uv_sphere(b,p->x,surface_y+1.76f,p->z,0.77f,0.16f,0.16f,0,0xFFFFC56Du);
            add_octahedron(b,p->x,surface_y+1.00f,p->z+0.08f,0.43f,0.72f,0.075f,world_time*0.45f,0xFF70E6D7u);
            add_octahedron(b,p->x,surface_y+1.00f,p->z+0.14f,0.18f,0.44f,0.055f,-world_time*0.8f,0xFFFFE48Au);
        }
    }
    for(unsigned int i=0;i<PS5HS_GAME_POINT_LIGHT_COUNT;i++){
        const Ps5HSGamePointLight *light=&ps5hs_game_point_lights[i];
        if(light->intensity<=0.01f)continue;
        add_tapered_cylinder(b,light->x,light->y-0.16f,light->z,0.075f,0.18f,0.075f,0,0.72f,0xFF8995B8u);
        add_tapered_cylinder(b,light->x,light->y-0.38f,light->z,0.28f,0.08f,0.28f,0,0.82f,0xFF292D50u);
        add_uv_sphere(b,light->x,light->y+0.06f,light->z,0.18f,0.19f,0.18f,world_time*0.28f,light->color);
        add_octahedron(b,light->x,light->y+0.06f,light->z,0.09f,0.13f,0.09f,-world_time*0.32f,0xFFF4FCFFu);
    }
    add_nebula_explorer(b);
}
static void ui_component(MeshBatch *ui,const Ps5HSVisualComponent *c,float progress){
    if(!c->visible)return;if(equal(c->id,PS5HS_GAME_PAUSE_COMPONENT_ID)&&(current_screen!=2||game_won))return;if(equal(c->id,PS5HS_GAME_START_COMPONENT_ID)&&game_won)return;
    int selected=(current_screen==0&&equal(c->id,PS5HS_GAME_START_COMPONENT_ID));
    if(current_screen==1)selected=(menu_choice==0&&equal(c->id,PS5HS_GAME_RESUME_COMPONENT_ID))||
        (menu_choice==1&&equal(c->id,PS5HS_GAME_RESTART_COMPONENT_ID))||(menu_choice==2&&equal(c->id,PS5HS_GAME_AUDIO_COMPONENT_ID));
    unsigned int bg=c->background,fg=c->foreground;if(equal(c->id,PS5HS_GAME_AUDIO_COMPONENT_ID))fg=audio_enabled?0xFFB8FFF0u:0xFFFFB89Au;
    if(c->type==1||c->type==2||c->type==5||c->type==6||c->type==13){
        if(bg>>24)ui_rect(ui,c->x,c->y,c->w,c->h,bg);
        if(c->type==5){unsigned int edge=selected?0xFFFFE98Au:0xFF9B8BFFu;
            ui_rect(ui,c->x,c->y,c->w,selected?4:2,edge);ui_rect(ui,c->x,c->y+c->h-2,c->w,2,edge);
            if(selected){ui_rect(ui,c->x,c->y,3,c->h,edge);ui_rect(ui,c->x+c->w-3,c->y,3,c->h,edge);}}
        if(c->type==6){ui_rect(ui,c->x+c->w-62,c->y+16,46,26,audio_enabled?0xFF43C9AAu:0xFF594C68u);
            ui_rect(ui,c->x+c->w-(audio_enabled?38:60),c->y+18,22,22,0xFFFFFFFFu);}
    }
    if(c->type==14){ui_rect(ui,c->x,c->y+26,c->w,c->h-26,0xFF252744u);
        float fill=(c->w-6)*progress;if(fill>0)ui_rect(ui,c->x+3,c->y+29,fill,c->h-32,0xFF63D6C5u);}
    char dynamic[128];unsigned int progressPercent=(unsigned int)(clampf(progress,0.0f,1.0f)*100.0f+0.5f);
    format_visual_label(dynamic,sizeof(dynamic),c->label,(unsigned int)shard_total,(unsigned int)SHARD_COUNT,progressPercent,audio_enabled);
    const char *label=dynamic;
    if(c->type==3)ui_rect(ui,c->x+16,c->y+c->h-5,c->w-32,2,0xFF67D8CEu);
    float tx=c->x+8,ty=c->y+4,tw=c->w-16,th=c->h-8;if(c->type==14){ty=c->y;th=22;}if(c->type==6)tw=c->w-72;
    draw_text(ui,label,tx,ty,tw,th,c->font,fg);
}
static void build_ui(MeshBatch *ui){
    ui->vertex_count=ui->index_count=0;float start_z=level[PS5HS_GAME_SPAWN_INDEX].z;float goal_z=level[PS5HS_GAME_GOAL_INDEX].z;float route_length=goal_z-start_z;float progress=absf(route_length)>0.001f?clampf((hero.z-start_z)/route_length,0,1):0;
    if(current_screen==0){ui_rect(ui,470,76,980,500,0xF2111830u);ui_rect(ui,470,76,980,4,0xFF5EE6D0u);
        ui_rect(ui,490,545,940,2,0xFF6F87C9u);ui_rect(ui,500,88,6,470,0xFF7C66FFu);
        ui_rect(ui,300,170,8,8,0xFF63D6C8u);ui_rect(ui,1580,225,6,6,0xFFFFD780u);ui_rect(ui,1515,465,10,10,0xFF7888FFu);
    }else if(current_screen==1){ui_rect(ui,500,80,920,620,0xF20C1024u);ui_rect(ui,500,80,920,5,0xFFFFD880u);}
    else if(game_won){ui_rect(ui,470,300,980,430,0xF20B1026u);ui_rect(ui,470,300,980,5,0xFFFFD875u);}
    else ui_rect(ui,0,0,SCREEN_W,58,0xB910142Au);
    unsigned short activeScreen=(unsigned short)(current_screen==0?PS5HS_GAME_MENU_SCREEN_INDEX:current_screen==1?PS5HS_GAME_PAUSE_SCREEN_INDEX:PS5HS_GAME_PLAY_SCREEN_INDEX);
    for(unsigned int i=0;i<ps5hs_visual_component_count;i++){
        const Ps5HSVisualComponent *c=&ps5hs_visual_components[i];int pauseButton=equal(c->id,PS5HS_GAME_PAUSE_COMPONENT_ID);
        if(c->screen_index==activeScreen||(pauseButton&&current_screen==2))ui_component(ui,c,progress);
    }
    if(game_won){
        draw_text(ui,"META ALCANZADA",600,365,720,60,45,0xFFFFE7A6u);
        if(PS5HS_GAME_REQUIRE_COLLECTIBLES)draw_text(ui,"HAS REUNIDO TODOS LOS CRISTALES",570,445,780,42,25,0xFF9EEFE1u);
        draw_text(ui,"X PARA VOLVER A JUGAR",600,560,720,40,19,0xFFB8C8E8u);
    }else if(current_screen==2){
        if(respawn_flash>0)draw_text(ui,"HAS VUELTO AL CHECKPOINT",680,132,560,30,16,0xFFFFD184u);
        if(PS5HS_GAME_REQUIRE_COLLECTIBLES&&shard_total>=SHARD_COUNT&&hero.z<level[PS5HS_GAME_GOAL_INDEX].z-1)
            draw_text(ui,"REUNISTE TODOS LOS CRISTALES: VE A LA META",500,85,920,30,16,0xFF72F1D6u);
    }
}
static void error_notice(const char *what,int rc){
    char msg[96];int n=0;const char *p=PS5HS_GAME_TITLE ": ";while(*p&&n<60)msg[n++]=*p++;while(*what&&n<78)msg[n++]=*what++;
    msg[n++]=' ';msg[n++]='0';msg[n++]='x';const char hex[]="0123456789ABCDEF";unsigned int u=(unsigned int)rc;
    for(int i=7;i>=0;i--)msg[n++]=hex[(u>>(i*4))&15u];msg[n]=0;notify(msg);
}
static int open_pad(void){
    int init=sceUserServiceInitialize(0);if(init<0&&(unsigned int)init!=0x80960003u){error_notice("UserService fallo",init);return -1;}
    int user=0;if(sceUserServiceGetInitialUser(&user)<0){notify(PS5HS_GAME_TITLE ": no hay usuario activo");return -1;}
    int rc=scePadInit();if(rc<0){error_notice("PadInit fallo",rc);return -1;}
    for(int i=0;i<20;i++){int h=scePadOpen(user,0,0,0);if(h>=0){(void)scePadSetVibrationMode(h,2);return h;}sceKernelUsleep(50000);}
    notify(PS5HS_GAME_TITLE ": conecta DualSense y reinicia");return -1;
}
static int wait_until_flip_visible(int video,long long target_frame){
    for(int blank=0;blank<120;blank++){
        unsigned long long status[16]={0};
        int rc=sceVideoOutGetFlipStatus(video,status);
        if(rc<0){notify_rc(PS5HS_GAME_TITLE ": FlipStatus fallo",rc);return rc;}
        if((long long)status[3]>=target_frame)return 0;
        rc=sceVideoOutWaitVblank(video);
        if(rc<0){notify_rc(PS5HS_GAME_TITLE ": WaitVblank de FlipStatus fallo",rc);return rc;}
    }
    notify(PS5HS_GAME_TITLE ": timeout esperando flip de VideoOut");
    return -1;
}
static int render_frame(int frame,DirectMem *fb,DirectMem *dcbMem,DirectMem *ctxMem,DirectMem *shMem,
    DirectMem *primMem,DirectMem *consMem,DcbState *dcb,void *vs,void *ps,CxRegister *cxRecords,
    unsigned int cxCount,int video,unsigned int W,unsigned int H,int slot,DirectMem *sceneV,
    DirectMem *sceneI,DirectMem *uiV,DirectMem *uiI,int cbOff,int vbOff){
    if(frame>=2&&wait_until_flip_visible(video,(long long)frame-1)<0)return -1;
    MeshBatch scene,ui;batch_init(&scene,sceneV,sceneI,SCENE_MAX_VERTS,SCENE_MAX_INDICES);build_scene(&scene);
    batch_init(&ui,uiV,uiI,UI_MAX_VERTS,UI_MAX_INDICES);build_ui(&ui);
    float ex=hero.x*0.72f,ey=hero.y+PS5HS_GAME_CAMERA_FOLLOW_HEIGHT,ez=hero.z-PS5HS_GAME_CAMERA_FOLLOW_DISTANCE;
    if(current_screen==0){ex=0;ey=hero.y+PS5HS_GAME_CAMERA_FOLLOW_HEIGHT+0.7f;ez=hero.z-PS5HS_GAME_CAMERA_FOLLOW_DISTANCE;}if(current_screen==1){ey=hero.y+PS5HS_GAME_CAMERA_FOLLOW_HEIGHT;ez=hero.z-PS5HS_GAME_CAMERA_FOLLOW_DISTANCE-1.1f;}
    float mvp[16],identity[16];view_projection(mvp,vec3(ex,ey,ez),vec3(hero.x,hero.y+0.20f,hero.z+PS5HS_GAME_CAMERA_LOOK_AHEAD));mat_identity(identity);
    float *cons=(float*)consMem->ptr;for(int i=0;i<16;i++){cons[i]=mvp[i];cons[16+i]=identity[i];cons[32+i]=identity[i];cons[48+i]=identity[i];}
    unsigned int cbScene[4],vbScene[4],cbUi[4],vbUi[4];
    desc_constant(cbScene,(unsigned long long)(unsigned long)consMem->ptr,128);
    desc_structured(vbScene,(unsigned long long)(unsigned long)sceneV->ptr,VERTEX_STRIDE,scene.vertex_count);
    desc_constant(cbUi,(unsigned long long)(unsigned long)((unsigned char*)consMem->ptr+128),128);
    desc_structured(vbUi,(unsigned long long)(unsigned long)uiV->ptr,VERTEX_STRIDE,ui.vertex_count);
    unsigned int *pixels=(unsigned int*)fb->ptr;for(unsigned long i=0;i<fb->size/4;i++)pixels[i]=PS5HS_GAME_SKY_COLOR;
    framebuffer_writeback(fb->ptr,fb->size);
    dcb_reset(dcb,(unsigned int*)dcbMem->ptr,(unsigned int)(dcbMem->size/4));
    /* Submit the DCB directly. The flip-status gate above prevents CPU reuse
     * of this scan-out buffer until its previous flip has completed. */
    static const unsigned short offsets[16]={0x0318,0x031B,0x031C,0x031D,0x031E,0x031F,0x0321,0x0323,0x0324,0x0325,0x0390,0x0398,0x03A0,0x03A8,0x03B0,0x03B8};
    CxRegister rt[16];for(int i=0;i<16;i++){rt[i].offset=offsets[i];rt[i].pad=0;rt[i].value=0;
        for(unsigned int r=0;r<cxCount;r++)if(cxRecords[r].offset==offsets[i]){rt[i].value=cxRecords[r].value;break;}}
    #define RT_SET(i,m,v) rt[i].value=(rt[i].value&~(unsigned int)(m))|(unsigned int)(v)
    RT_SET(1,0x03ffe000u,0u);RT_SET(2,0x0000007cu,0x00000028u);RT_SET(2,0x00000700u,0u);
    RT_SET(2,0x00001800u,0x00000800u);RT_SET(2,0x00010000u,0u);RT_SET(2,0x00008000u,0x00008000u);
    RT_SET(2,0x00040000u,0u);RT_SET(2,0x10000000u,0u);RT_SET(2,0x00004000u,0u);
    RT_SET(3,0x00007000u,0u);RT_SET(3,0x00018000u,0u);RT_SET(4,0x00000008u,0x00000008u);
    RT_SET(4,0x00000040u,0x00000040u);RT_SET(4,0x00100200u,0u);RT_SET(4,0x00080000u,0u);
    rt[14].value=(rt[14].value&0xffffc000u)|((H-1)&0x3fffu);rt[14].value=(rt[14].value&0xf0003fffu)|(((W-1)<<14)&0x0fffc000u);
    rt[14].value&=0x0fffffffu;rt[15].value&=0xffffe000u;RT_SET(15,0x0007c000u,0x0006c000u);
    RT_SET(15,0x03000000u,0x01000000u);RT_SET(15,0x44000000u,0x44000000u);
    unsigned long long a=(unsigned long long)(unsigned long)fb->ptr;rt[0].value=(unsigned int)((a>>8)&0xffffffffu);
    rt[10].value=(rt[10].value&0xffffff00u)|(unsigned int)((a>>40)&0xffu);
    rt[5].value=0;rt[11].value&=0xffffff00u;rt[6].value=0;rt[12].value&=0xffffff00u;rt[9].value=0;rt[13].value&=0xffffff00u;
    CxRegister vp[14];{float xs=W*0.5f,xo=xs,ys=-(float)H*0.5f,yo=H*0.5f;union{float f;unsigned int u;}cv;int i=0;
        #define VPF(o,v) {cv.f=(v);vp[i].offset=(o);vp[i].pad=0;vp[i].value=cv.u;i++;}
        VPF(0x10F,xs);VPF(0x110,xo);VPF(0x111,ys);VPF(0x112,yo);VPF(0x113,1.0f);VPF(0x114,0.0f);
        VPF(0x0B4,0.0f);VPF(0x0B5,1.0f);VPF(0x2FA,8.0f);VPF(0x2FB,8.0f);VPF(0x2FC,8.0f);VPF(0x2FD,8.0f);
        #undef VPF
        vp[i].offset=0x090;vp[i].pad=0;vp[i].value=0x80000000u;i++;
        vp[i].offset=0x091;vp[i].pad=0;vp[i].value=0x4000u|(0x4000u<<16);}
    CxRegister linkage[34],primitive[3];int rc=sceAgcLinkShaders(linkage,primitive,0,vs,ps,4);
    if(rc<0){notify_rc(PS5HS_GAME_TITLE ": LinkShaders fallo",rc);return -1;}
    CxRegister context[16+14+2+34+255+255];int cx=0;
    for(int i=0;i<16;i++)context[cx++]=rt[i];for(int i=0;i<14;i++)context[cx++]=vp[i];
    context[cx].offset=0x008E;context[cx].pad=0;context[cx].value=0xF;cx++;
    /* A fresh AGC context disables color-buffer writes. Explicitly enable
     * normal color output (ROP3 copy) for the BGRA8 render target. */
    context[cx].offset=0x0202;context[cx].pad=0;context[cx].value=0x00CC0011u;cx++;
    unsigned int cull=0;for(unsigned int i=0;i<cxCount;i++)if(cxRecords[i].offset==0x205){cull=cxRecords[i].value;break;}
    context[cx].offset=0x205;context[cx].pad=0;context[cx].value=(cull&~7u)|2u|4u;cx++;
    for(int i=0;i<34;i++)context[cx++]=linkage[i];
    for(int i=0;i<SHDR_CXCOUNT(vs);i++)context[cx++]=SHDR_CXREGS(vs)[i];
    for(int i=0;i<SHDR_CXCOUNT(ps);i++)context[cx++]=SHDR_CXREGS(ps)[i];
    CxRegister shRegs[510];int sh=0;for(int i=0;i<SHDR_SHCOUNT(vs);i++)shRegs[sh++]=SHDR_SHREGS(vs)[i];
    for(int i=0;i<SHDR_SHCOUNT(ps);i++)shRegs[sh++]=SHDR_SHREGS(ps)[i];
    for(int i=0;i<cx;i++)((CxRegister*)ctxMem->ptr)[i]=context[i];for(int i=0;i<sh;i++)((CxRegister*)shMem->ptr)[i]=shRegs[i];
    for(int i=0;i<3;i++)((CxRegister*)primMem->ptr)[i]=primitive[i];
    sceAgcDcbSetCxRegistersIndirect(dcb,ctxMem->ptr,cx);sceAgcDcbSetShRegistersIndirect(dcb,shMem->ptr,sh);
    sceAgcDcbSetUcRegistersIndirect(dcb,primMem->ptr,3);
    sceAgcCbSetShRegisterRangeDirect(dcb,GS_USER_DATA_BASE+(unsigned int)cbOff,cbScene,4);
    sceAgcCbSetShRegisterRangeDirect(dcb,GS_USER_DATA_BASE+(unsigned int)vbOff,vbScene,4);
    sceAgcDcbSetIndexSize(dcb,1,0);sceAgcDcbSetIndexBuffer(dcb,sceneI->ptr);sceAgcDcbSetIndexCount(dcb,scene.index_count);
    sceAgcDcbDrawIndex(dcb,scene.index_count,sceneI->ptr,0);
    sceAgcCbSetShRegisterRangeDirect(dcb,GS_USER_DATA_BASE+(unsigned int)cbOff,cbUi,4);
    sceAgcCbSetShRegisterRangeDirect(dcb,GS_USER_DATA_BASE+(unsigned int)vbOff,vbUi,4);
    sceAgcDcbSetIndexBuffer(dcb,uiI->ptr);sceAgcDcbSetIndexCount(dcb,ui.index_count);sceAgcDcbDrawIndex(dcb,ui.index_count,uiI->ptr,0);
    sceAgcDcbSetFlip(dcb,(unsigned int)video,slot,1,(long long)frame);
    struct{void *words;unsigned int wordCount;unsigned char flag;}submit;
    submit.words=dcb->bottom;submit.wordCount=(unsigned int)(dcb->up_cursor-dcb->bottom);submit.flag=0;
    rc=sceAgcDriverSubmitDcb(&submit);
    if(rc<0){notify_rc(PS5HS_GAME_TITLE ": Submit fallo",rc);return -1;}
    if(frame==0)notify(PS5HS_GAME_TITLE ": primer DCB AGC enviado");
    rc=sceAgcSuspendPoint();
    if(rc<0){notify_rc(PS5HS_GAME_TITLE ": SuspendPoint fallo",rc);return -1;}
    rc=sceVideoOutWaitVblank(video);
    if(rc<0){notify_rc(PS5HS_GAME_TITLE ": WaitVblank fallo",rc);return -1;}
    if(frame==0)notify(PS5HS_GAME_TITLE ": primer vblank completado");
    return 0;
}
int main(void){
    /* Release the launch splash/compositor before taking VideoOut for AGC. */
    (void)sceSystemServiceHideSplashScreen();
    notify(PS5HS_GAME_TITLE ": AGC directo y DualSense");
    static unsigned long long agcState;int rc=sceAgcInit(&agcState,8);
    if(rc<0){notify_rc(PS5HS_GAME_TITLE ": AGC fallo",rc);return 1;}
    int video=sceVideoOutOpen(SCE_USER_SYSTEM,VIDEOOUT_BUS_MAIN,0,0);
    if(video<0){notify_rc(PS5HS_GAME_TITLE ": VideoOut fallo",video);return 1;}sceVideoOutSetFlipRate(video,0);
    const unsigned int W=1920,H=1080;const int BUFFERS=2;
    unsigned int pw=(W+127u)&~127u,ph=(H+127u)&~127u;
    unsigned long fbBytes=(unsigned long)pw*ph*4u;fbBytes=(fbBytes+2097151u)&~(unsigned long)2097151u;
    #define ALLOC_OR_FAIL(r,n,a,label) do{if(direct_alloc(&(r),(n),(a))<0){notify(PS5HS_GAME_TITLE ": alloc " label " fallo");return 1;}}while(0)
    DirectMem fb[2];for(int i=0;i<BUFFERS;i++)ALLOC_OR_FAIL(fb[i],fbBytes,2u*1024u*1024u,"framebuffer");
    SceVideoOutBuffers addresses[2];for(int i=0;i<BUFFERS;i++){
        addresses[i].data=fb[i].ptr;addresses[i].metadata=0;addresses[i].reserved0=0;addresses[i].reserved1=0;}
    /* SceVideoOutBufferAttribute2 is 80 bytes. SetBufferAttribute2 writes the
     * whole structure; 64 bytes corrupts the neighboring stack and can make
     * RegisterBuffers2 reject the scan-out buffers before the first AGC flip. */
    unsigned char attr[256];for(unsigned int i=0;i<sizeof attr;i++)attr[i]=0;
    sceVideoOutSetBufferAttribute2(attr,VIDEOOUT_PIXELFORMAT_BGRA8_SRGB,VIDEOOUT_TILING_TILED,W,H,0,0,0);
    rc=sceVideoOutRegisterBuffers2(video,0,0,addresses,BUFFERS,attr,0,0);
    if(rc<0){notify_rc(PS5HS_GAME_TITLE ": RegisterBuffers fallo",rc);return 1;}
    ShaderParts vsp,psp;
    if(shader_parts_from_elf(mesh_vs_sb,mesh_vs_sb_len,&vsp)<0||shader_parts_from_elf(mesh_ps_sb,mesh_ps_sb_len,&psp)<0){
        notify(PS5HS_GAME_TITLE ": shader invalido");return 1;}
    DirectMem vh,vc,phdr,pc;ALLOC_OR_FAIL(vh,vsp.header_len,DIRECT_MEM_MIN_ALIGN,"VS header");
    ALLOC_OR_FAIL(vc,vsp.code_len,DIRECT_MEM_MIN_ALIGN,"VS code");ALLOC_OR_FAIL(phdr,psp.header_len,DIRECT_MEM_MIN_ALIGN,"PS header");
    ALLOC_OR_FAIL(pc,psp.code_len,DIRECT_MEM_MIN_ALIGN,"PS code");
    for(unsigned int i=0;i<vsp.header_len;i++)((unsigned char*)vh.ptr)[i]=vsp.header[i];
    for(unsigned int i=0;i<vsp.code_len;i++)((unsigned char*)vc.ptr)[i]=vsp.code[i];
    for(unsigned int i=0;i<psp.header_len;i++)((unsigned char*)phdr.ptr)[i]=psp.header[i];
    for(unsigned int i=0;i<psp.code_len;i++)((unsigned char*)pc.ptr)[i]=psp.code[i];
    void *vs=0,*ps=0;rc=sceAgcCreateShader(&vs,vh.ptr,vc.ptr);
    if(rc<0){notify_rc(PS5HS_GAME_TITLE ": create VS fallo",rc);return 1;}
    rc=sceAgcCreateShader(&ps,phdr.ptr,pc.ptr);if(rc<0){notify_rc(PS5HS_GAME_TITLE ": create PS fallo",rc);return 1;}
    int cbOff=resource_dword_offset(vs,KIND_CONSTANTBUFFER,0),vbOff=resource_dword_offset(vs,KIND_READONLY,0);
    if(cbOff<0||vbOff<0){notify(PS5HS_GAME_TITLE ": faltan recursos shader");return 1;}
    DirectMem dcb[2],ctx[2],sh[2],prim[2],cons[2],sceneV[2],sceneI[2],uiV[2],uiI[2];DcbState dcbState[2];
    for(int i=0;i<BUFFERS;i++){
        ALLOC_OR_FAIL(dcb[i],64*1024,DIRECT_MEM_MIN_ALIGN,"DCB");ALLOC_OR_FAIL(ctx[i],8192,DIRECT_MEM_MIN_ALIGN,"context");
        ALLOC_OR_FAIL(sh[i],4096,DIRECT_MEM_MIN_ALIGN,"shader state");ALLOC_OR_FAIL(prim[i],4096,DIRECT_MEM_MIN_ALIGN,"primitive state");
        ALLOC_OR_FAIL(cons[i],512,DIRECT_MEM_MIN_ALIGN,"constants");ALLOC_OR_FAIL(sceneV[i],SCENE_MAX_VERTS*VERTEX_STRIDE,DIRECT_MEM_MIN_ALIGN,"scene vertices");
        ALLOC_OR_FAIL(sceneI[i],SCENE_MAX_INDICES*4,DIRECT_MEM_MIN_ALIGN,"scene indices");
        ALLOC_OR_FAIL(uiV[i],UI_MAX_VERTS*VERTEX_STRIDE,DIRECT_MEM_MIN_ALIGN,"UI vertices");
        ALLOC_OR_FAIL(uiI[i],UI_MAX_INDICES*4,DIRECT_MEM_MIN_ALIGN,"UI indices");
    }
    void *defaults=sceAgcGetRegisterDefaults();CxRegister **blocks=*(CxRegister***)((unsigned char*)defaults+0);
    unsigned int cxCount=*(unsigned int*)((unsigned char*)defaults+0x20);CxRegister *cxRecords=blocks?blocks[0]:0;
    pad_handle=open_pad();if(pad_handle<0)notify(PS5HS_GAME_TITLE ": no se pudo abrir DualSense");
    int audioInit=sceAudioOutInit();
    if(audioInit>=0||(unsigned int)audioInit==0x8026000Eu){
        audio_port=sceAudioOutOpen(0xFF,0,0,AUDIO_GRAIN,AUDIO_RATE,1);
        if(audio_port<0){error_notice("AudioOutOpen fallo",audio_port);audio_enabled=0;}
    }else{error_notice("AudioOutInit fallo",audioInit);audio_enabled=0;}
    reset_run();current_screen=0;unsigned int previous=0;int frame=0;
    for(;;frame++){
        world_time+=1.0f/60.0f;unsigned char data[1024];for(int i=0;i<1024;i++)data[i]=0;
        unsigned int buttons=0;float ax=0,forward=0;
        if(pad_handle>=0&&scePadReadState(pad_handle,data)>=0){
            buttons=read_buttons(data);
            if(!(buttons&BTN_INTERCEPTED)){ax=stick(data[4]);forward=-stick(data[5]);}else buttons=0;
        }
        unsigned int pressed=buttons&~previous;int cross=(pressed&BTN_CROSS)!=0;
        if(pressed&BTN_OPTIONS){if(current_screen==2)dispatch_game_action(PS5HS_GAME_PAUSE_COMPONENT_ID,PS5HS_GAME_PAUSE_EVENT,game_pause);}
        if(pressed&BTN_SQUARE){if(current_screen==2)dispatch_game_action(PS5HS_GAME_RESTART_COMPONENT_ID,PS5HS_GAME_RESTART_EVENT,game_restart);}
        if(pressed&BTN_TRIANGLE){if(current_screen==2)dispatch_game_action(PS5HS_GAME_AUDIO_COMPONENT_ID,PS5HS_GAME_AUDIO_EVENT,game_toggle_audio);}
        int menuState=current_screen!=2||game_won;
        if(menuState)menu_input((pressed&BTN_UP)!=0,(pressed&BTN_DOWN)!=0,cross,(pressed&BTN_CIRCLE)!=0);
        else update_game(ax,forward,cross);
        previous=buttons;
        if(rumble_frames>0&&--rumble_frames==0&&pad_handle>=0){PadVibration stop={0,0};(void)scePadSetVibration(pad_handle,&stop);}
        audio_frame();int slot=frame&1;
        if(render_frame(frame,&fb[slot],&dcb[slot],&ctx[slot],&sh[slot],&prim[slot],&cons[slot],&dcbState[slot],
            vs,ps,cxRecords,cxCount,video,W,H,slot,&sceneV[slot],&sceneI[slot],&uiV[slot],&uiI[slot],cbOff,vbOff)<0){
            notify(PS5HS_GAME_TITLE ": renderer detenido por un error AGC");return 1;
        }
    }
    if(audio_port>=0)(void)sceAudioOutClose(audio_port);
    if(pad_handle>=0)(void)scePadClose(pad_handle);
    return 0;
}
