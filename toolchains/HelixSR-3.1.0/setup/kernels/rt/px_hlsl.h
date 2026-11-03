// HLSL target primitives for px_common.h (DXC: -T cs_6_6 -enable-16bit-types -HV 2021 -denorm ftz).
#ifndef PX_HLSL_H
#define PX_HLSL_H
#if defined(PX_FP32) && !defined(HX_FP32)
#define HX_FP32
#endif
#ifdef HX_FP32
// GPUs without native 16-bit shader ops (Pascal: D3D12 Native16BitShaderOpsSupported = false): built without
// -enable-16bit-types. 16-bit values live only in memory (fp16 bits in 32-bit words); arithmetic runs in fp32 (as
// precise or more than the fp16 path). The 16-bit types become their 32-bit counterparts and the bit casts become
// conversions: asfloat16(bits) = the value, asuint16(value) = its fp16 bits.
#define float16_t float
#define float16_t2 float2
#define float16_t3 float3
#define float16_t4 float4
#define uint16_t uint
#define uint16_t2 uint2
#define uint16_t4 uint4
#if defined(HX_UNPACK_BOUND) && HX_UNPACK_BOUND
// Timing diagnostic only (wrong values): a free reinterpretation in place of the fp16 -> fp32 unpack
#define f16tof32(x) asfloat((uint)(x) << 16)
#endif
#define asfloat16(x) f16tof32(x)
#if defined(HX_F2H_TRUNC_BIAS) && HX_F2H_TRUNC_BIAS == 1
// Experimental, for drivers whose f32tof16 truncates (Pascal on Windows): the integer bias turns truncation of the low
// 13 bits into round to nearest even. Valid when |f| <= 2^-25 or 2^-14 <= |f| < 65520 (the normal fp16 range); the rest
// (fp16 subnormals, overflow, inf, NaN) takes the exact integer path in a rarely taken branch.
uint hx_f2h_slow(uint x)
{
    const uint a = x & 0x7fffffffu;
    uint r = min((a + 0xc8000fffu + ((a >> 13) & 1u)) >> 13, 0x7c00u);
    r = a < 0x38800000u ? asuint(asfloat(a) + 0.5f) - 0x3f000000u : r;
    r = a > 0x7f800000u ? 0x7e00u : r;
    return r | ((x >> 16) & 0x8000u);
}
uint hx_f2h(float f)
{
    const uint x = asuint(f), a = x & 0x7fffffffu;
    [branch] if ((a - 0x33000001u) < (0x38800000u - 0x33000001u) || a >= 0x477ff000u) return hx_f2h_slow(x);
    return f32tof16(asfloat(a + 0x0fffu + ((a >> 13) & 1u))) | ((x >> 16) & 0x8000u);
}
#elif defined(HX_F2H_TRUNC_BIAS) && HX_F2H_TRUNC_BIAS == 2
// As 1, without a branch: every path computed, selected.
uint hx_f2h(float f)
{
    const uint x = asuint(f), a = x & 0x7fffffffu;
    uint h = f32tof16(asfloat(a + 0x0fffu + ((a >> 13) & 1u)));
    h = a < 0x38800000u && a > 0x33000000u ? asuint(asfloat(a) + 0.5f) - 0x3f000000u : h;
    h = a >= 0x477ff000u ? (a > 0x7f800000u ? 0x7e00u : 0x7c00u) : h;
    return h | ((x >> 16) & 0x8000u);
}
#elif defined(HX_F2H_TRUNC_BIAS) && HX_F2H_TRUNC_BIAS == 3
// For drivers whose f32tof16 truncates toward zero and saturates at 65504 (Pascal, Windows): every correction is made
// to the INPUT, so the hardware conversion yields the round-to-nearest-even bits directly; only one integer add follows.
//   normal range:     the integer bias makes truncation of the low 13 bits round to nearest even (sign kept)
//   fp16 subnormals:  (f + 0.5) - 0.5 in fp32 rounds to the 2^-24 grid exactly, then the conversion is exact
//   rounds past 65504, inf, NaN: convert +-65504 (0x7bff) and add 1 (-> inf) or 0x201 (-> 0x7e00 | sign)
uint hx_f2h(float f)
{
    const uint u = asuint(f), a = u & 0x7fffffffu, s = u & 0x80000000u;
    const float half_ = asfloat(0x3f000000u | s);
    const float sub = asfloat(asuint(asfloat(asuint(f + half_) | PXGRID.w) - half_) | s);   // opaque zero: no folding
    float g = a < 0x38800000u ? sub : asfloat(u + 0x0fffu + ((u >> 13) & 1u));
    const bool big = a >= 0x477ff000u;
    g = big ? asfloat(s | 0x477fe000u) : g;
    return f32tof16(g) + (big ? (a > 0x7f800000u ? 0x201u : 1u) : 0u);
}
#elif defined(HX_F2H_TRUNC_BIAS) && HX_F2H_TRUNC_BIAS == 4
// NOT exact: the integer bias alone turns the truncating hardware conversion into round to nearest even for the normal
// fp16 range; fp16 subnormal results (|f| < 2^-14) are truncated instead, and overflow saturates at 65504.
uint hx_f2h(float f) { const uint u = asuint(f); return f32tof16(asfloat(u + 0x0fffu + ((u >> 13) & 1u))); }
#elif defined(HX_F2H_TRUNC_BIAS) && HX_F2H_TRUNC_BIAS == 5
// Fast checked conversion (drivers whose f32tof16 truncates, Pascal on Windows): the bias rounds every input to nearest
// even EXCEPT nonzero |f| < 2^-14 (fp16 subnormal range, incl. fp32 denormals) and |f| >= 65520 / inf / NaN. Those
// inputs set hx_rare; the pass then records it so the host re-runs that thread group with the exact conversion.
// On (u << 1): zero stays 0, |f| < 2^-14 is below 0x71000000, |f| >= 65520 is at least 0x8effe000.
static bool hx_rare = false;
#ifdef HX_F2H_TEST_CORRUPT
static bool hx_corrupt = false;   // fix-up test builds only: the raw (wrong) conversion in selected groups
#endif
uint hx_f2h(float f)
{
    const uint u = asuint(f), m = u << 1;
    hx_rare = hx_rare || (m - 1u < 0x71000000u - 1u) || m >= 0x8effe000u;
#ifdef HX_F2H_TEST_CORRUPT
    if (hx_corrupt) return f32tof16(f);
#endif
    return f32tof16(asfloat(u + 0x0fffu + ((u >> 13) & 1u)));
}
#elif defined(HX_F2H_TRUNC_BIAS) && HX_F2H_TRUNC_BIAS == 8
// Probe-only hypothesis test: the raw hardware conversion inside [HX_LO, HX_HI] (magnitude bits), the exact integer
// rounding elsewhere. The exhaustive probe then reports whether the hardware is already exact on that range.
uint hx_f2h(float f)
{
    const uint x = asuint(f), a = x & 0x7fffffffu;
    uint r = min((a + 0xc8000fffu + ((a >> 13) & 1u)) >> 13, 0x7c00u);
    r = a < 0x38800000u ? asuint(asfloat(a) + 0.5f) - 0x3f000000u : r;
    r = a > 0x7f800000u ? 0x7e00u : r;
    r |= (x >> 16) & 0x8000u;
    return a >= HX_LO && a <= HX_HI ? f32tof16(f) : r;
}
#elif defined(HX_F2H_TRUNC_BIAS) && HX_F2H_TRUNC_BIAS == 9
// Timing diagnostic only (inexact): the hardware conversion followed by an opaque runtime zero (PXGRID.w), which keeps
// the compiler from cancelling fp32 -> fp16 -> fp32 round trips.
uint hx_f2h(float f) { return f32tof16(f) | PXGRID.w; }
#elif defined(HX_F2H_HW) && HX_F2H_HW
// _fp32h builds: the GPU's own conversion, selected only after a run-time check found that it rounds to nearest even
// (with fp16 subnormals and overflow to infinity) exactly as the integer rounding below
uint hx_f2h(float f) { return f32tof16(f); }
#elif defined(HX_F2H_FAST) && HX_F2H_FAST
// the integer rounding below without branches (identical results for all 2^32 inputs, with or without flush to zero):
// the normal-range sum saturates at the infinity code, an fp16 subnormal is the low bits of |f| + 0.5 (aligned at 2^-24,
// round to even), NaN -> 0x7e00
#if defined(HX_F2H_CHAIN) && HX_F2H_CHAIN
// Experiment: an opaque zero threaded through every conversion (PXGRID.w, which the host sets to 0) orders them, which
// limits how many the compiler interleaves (register pressure). Values are unchanged.
static uint hx_chain = 0u;
#endif
uint hx_f2h(float f)
{
#if defined(HX_F2H_CHAIN) && HX_F2H_CHAIN
    const uint x = asuint(f) | hx_chain, a = x & 0x7fffffffu;
    uint r = min((a + 0xc8000fffu + ((a >> 13) & 1u)) >> 13, 0x7c00u);
    r = a < 0x38800000u ? asuint(asfloat(a) + 0.5f) - 0x3f000000u : r;
    r = a > 0x7f800000u ? 0x7e00u : r;
    r |= (x >> 16) & 0x8000u;
    hx_chain = r & PXGRID.w;
    return r;
#else
    const uint x = asuint(f), a = x & 0x7fffffffu;
    uint r = min((a + 0xc8000fffu + ((a >> 13) & 1u)) >> 13, 0x7c00u);
    r = a < 0x38800000u ? asuint(asfloat(a) + 0.5f) - 0x3f000000u : r;
    r = a > 0x7f800000u ? 0x7e00u : r;
    return r | ((x >> 16) & 0x8000u);
#endif
}
#else
// fp32 -> fp16 bits, round to nearest even, with integer operations: f32tof16 rounds toward zero on some drivers (RADV:
// v_cvt_pkrtz), which in chains of conversions (the output stage's products) biased the image measurably
uint hx_f2h(float f)
{
    const uint x = asuint(f), sign = (x >> 16) & 0x8000u, a = x & 0x7fffffffu;
    if (a >= 0x7f800000u) return sign | (a > 0x7f800000u ? 0x7e00u : 0x7c00u);   // inf, nan
    if (a >= 0x477ff000u) return sign | 0x7c00u;                                  // rounds past 65504: inf
    if (a < 0x38800000u) return sign | (uint)round(asfloat(a) * 16777216.0f);     // fp16 subnormal (round: to even)
    return sign | ((a + 0x0fffu + ((a >> 13) & 1u) - 0x38000000u) >> 13);
}
#endif
#ifdef HX_R16_NAN
// hx_r16(f) == f16tof32(hx_f2h(f)) bit for bit (fp32 rounded to the fp16 grid, round to nearest even, fp16 overflow to
// inf), in fp32 arithmetic: adding c = 2^(e+13) (e = f's exponent, at least -14) rounds |f| to the fp16 ulp of its
// binade (2^-24 below 2^-14), and the subtraction is exact. Lets shadowed fp16 values skip pack/unpack.
// HX_R16_NAN is the GPU's own unpack of every fp16 NaN (NVIDIA Pascal, Windows 582.78: 0x7fffffff, for both signs;
// source/tests/windows_r16_probe.hlsl checks all 2^32 inputs). The build must state it: it is vendor specific.
// The OR with the host's runtime zero (PXGRID.w) keeps compilers from folding (|f| + c) - c; 'precise' would instead
// propagate backwards into the computation of f.
float hx_r16(float f)
{
#if defined(HX_R16_IDENTITY) && HX_R16_IDENTITY
    // NOT exact (quality-gated builds): fp16 arithmetic chains stay in fp32 (no rounding between operations); only values
    // that are stored keep their fp16 bits
    return f;
#endif
    const uint u = asuint(f), a = u & 0x7fffffffu;
    const float c = asfloat(max(u & 0x7f800000u, 0x38800000u) + 0x06800000u);
    float m = asfloat(asuint(asfloat(a) + c) | PXGRID.w) - c;
    m = a >= 0x477ff000u ? asfloat(0x7f800000u) : m;
    m = asfloat(asuint(m) | (u & 0x80000000u));
    return a > 0x7f800000u ? asfloat(HX_R16_NAN) : m;
}
// f16tof32(px_relu_h(bits)) from the shadow f16tof32(bits): NaN -> fp16 0x7fff, sign set -> +0. The NaN result is
// written as f16tof32(0x7fff) like the original, so it gets the same treatment (DXC folds that constant: 0x7fffe000).
float hx_relu_shadow(float x)
{
    const uint b = asuint(x);
    return (b & 0x7fffffffu) > 0x7f800000u ? f16tof32(0x7fffu) : ((b & 0x80000000u) != 0u ? 0.0f : x);
}
#endif
uint2 hx_f2h(float2 f) { return uint2(hx_f2h(f.x), hx_f2h(f.y)); }
uint3 hx_f2h(float3 f) { return uint3(hx_f2h(f.x), hx_f2h(f.y), hx_f2h(f.z)); }
uint4 hx_f2h(float4 f) { return uint4(hx_f2h(f.x), hx_f2h(f.y), hx_f2h(f.z), hx_f2h(f.w)); }
#define asuint16(x) hx_f2h(x)
#endif
#ifdef HX_FP32
// shared memory keeps the fp16 pairs packed in 32-bit words (an fp32 copy would double it: k4 is at 32 KB already)
#undef PX_LDS_ROW4
#endif
#define INOUT(T) inout T
#define OUTP(T) out T
#ifdef PX_FAST
#define PRECISE
#else
#define PRECISE precise
#endif
#define PX_LOOP [loop]

#ifndef PX_SMEM_WORDS
#define PX_SMEM_WORDS 1
#endif
// Shared memory is typed as fp16 pairs so that rows read from it stay 2 x 16-bit vectors through DXIL -> SPIR-V -> NIR,
// which is what lets RADV form packed v_pk_fma_f16 (32-bit words read through integer casts do not vectorize).
#ifdef PX_LDS_ROW8
groupshared uint4 SMR[(PX_SMEM_WORDS + 3) / 4];
#elif defined(HX_FP32) || defined(PX_LDS_W32)
// PX_LDS_W32 (16-bit builds for the Windows AMD driver): fp16 pairs as plain 32-bit words, read and written as whole
// words and bit-cast to typed pairs; typed float16_t2 shared memory becomes two 16-bit LDS operations per access there.
groupshared uint SMW[PX_SMEM_WORDS];
#elif defined(PX_LDS_ROW4)
groupshared float16_t4 SM4[(PX_SMEM_WORDS + 1) / 2];
#else
groupshared float16_t2 SM[PX_SMEM_WORDS];
#endif
typedef float16_t2 PXH2;
#ifdef PX_HALF_UNPACK
float16_t2 px_v2h(uint w) { return float16_t2((float16_t)f16tof32(w), (float16_t)f16tof32(w >> 16)); }
#else
float16_t2 px_v2h(uint w) { return asfloat16(uint16_t2((uint16_t)(w & 0xffffu), (uint16_t)(w >> 16))); }
#endif
#if defined(HX_BOUND_SITE) && HX_BOUND_SITE == 2
// Timing diagnostic only (inexact): hardware conversion in packed-half ops
uint px_h2v(float16_t2 v) { return f32tof16(v.x) | (f32tof16(v.y) << 16); }
#else
uint px_h2v(float16_t2 v) { return (uint)asuint16(v.x) | ((uint)asuint16(v.y) << 16); }
#endif
#if defined(HX_FP32) && !defined(PX_LDS_ROW8)
#define PX_SMH2(i) px_v2h(SMW[i])   // fp16 pair at word index i, as a typed pair
#define LDS32(a) SMW[(a) >> 2]
#define PX_STS32(a, v) SMW[(a) >> 2] = (v)
#define PX_LDSH2(a) px_v2h(SMW[(a) >> 2])
#elif defined(PX_LDS_W32)
float16_t2 px_w2h(uint w) { return asfloat16(uint16_t2((uint16_t)(w & 0xffffu), (uint16_t)(w >> 16))); }   // bit cast
#define PX_SMH2(i) px_w2h(SMW[i])
#define LDS32(a) SMW[(a) >> 2]
#define PX_STS32(a, v) SMW[(a) >> 2] = (v)
#define PX_LDSH2(a) px_w2h(SMW[(a) >> 2])
#elif defined(PX_LDS_ROW8)
#define LDS32(a) SMR[(a) >> 4][((a) >> 2) & 3u]
void px_sts_word(uint a, uint v) {
    switch ((a >> 2) & 3u) {
    case 0u: SMR[a >> 4].x = v; break;
    case 1u: SMR[a >> 4].y = v; break;
    case 2u: SMR[a >> 4].z = v; break;
    default: SMR[a >> 4].w = v; break;
    }
}
#define PX_STS32(a, v) px_sts_word(a, v)
#define PX_LDSH2(a) px_v2h(LDS32(a))
#elif defined(PX_LDS_ROW4)
PXH2 px_lds_pair(uint a) { float16_t4 v = SM4[a >> 3]; return (a & 4u) ? v.zw : v.xy; }
void px_sts_pair(uint a, uint v) {
    if (a & 4u) SM4[a >> 3].zw = px_v2h(v);
    else SM4[a >> 3].xy = px_v2h(v);
}
#define LDS32(a) px_h2v(px_lds_pair(a))
#define PX_STS32(a, v) px_sts_pair(a, v)
#define PX_LDSH2(a) px_lds_pair(a)
#else
#define PX_SMH2(i) SM[i]
#define LDS32(a) px_h2v(SM[(a) >> 2])
#define PX_STS32(a, v) SM[(a) >> 2] = px_v2h(v)
#define PX_LDSH2(a) SM[(a) >> 2]
#endif

#if defined(HX_OCC_PAD_WORDS) && HX_OCC_PAD_WORDS
// Occupancy diagnostic: extra shared memory per group caps groups per SM (96 KB on Pascal). The store runs only when
// the host's runtime zero is nonzero (never), but keeps the allocation. Values unchanged.
groupshared uint HX_OCC_PAD[HX_OCC_PAD_WORDS];
void hx_occ_touch(uint t) { if (PXGRID.w != 0u) HX_OCC_PAD[t % HX_OCC_PAD_WORDS] = t; }
#else
void hx_occ_touch(uint t) {}
#endif
uint px_lane() { return WaveGetLaneIndex() & 31u; }
#if defined(PX_LDS_SHUFFLE) && (PX_SMEM_WORDS * 4 + PX_BLOCK_X * PX_BLOCK_Y * PX_BLOCK_Z * 4 <= 32768)
// wave64 builds: these reads stay inside one 32-lane warp (px_rd) or quad (px_qrd), which the compiler cannot prove for
// WaveReadLaneAt in a 64-lane wave (it emits a slow cross-half sequence). They go through a per-thread LDS slot instead:
// a wave's LDS operations execute in order, so each read sees the value its lane just wrote. Same results.
groupshared uint PX_SHF[PX_BLOCK_X * PX_BLOCK_Y * PX_BLOCK_Z];
static uint px_gi;
uint px_rd(uint v, uint l) { PX_SHF[px_gi] = v; return PX_SHF[(px_gi & ~31u) | l]; }
uint px_qrd(uint v, uint l) { PX_SHF[px_gi] = v; return PX_SHF[(px_gi & ~3u) | l]; }
#define PX_SET_GI(t) px_gi = (t)
#elif defined(HX_SHUFFLE_BOUND) && HX_SHUFFLE_BOUND
// Timing diagnostic only (wrong values): lane reads replaced by a cheap lane-dependent integer op
uint px_rd(uint v, uint l) { return v ^ l; }
uint px_qrd(uint v, uint l) { return v ^ l; }
#define PX_SET_GI(t)
#else
uint px_rd(uint v, uint l) { return WaveReadLaneAt(v, (WaveGetLaneIndex() & ~31u) | l); }
uint px_qrd(uint v, uint l) { return QuadReadLaneAt(v, l); }
#define PX_SET_GI(t)
#endif

float px_h2f(uint h) { return (float)asfloat16((uint16_t)(h & 0xffffu)); }
// fp32 -> fp16, round to nearest even. The OR with the host's runtime zero stops ACO from merging a preceding fp32
// add/FMA and this conversion into one rounding (v_fma_mix_lo), which it does even for precise code.
#if defined(HX_BOUND_SITE) && HX_BOUND_SITE == 1
// Timing diagnostic only (inexact): hardware conversion at explicit fp32 -> fp16 conversions
uint px_f2h(float f) { return f32tof16(f); }
#else
uint px_f2h(float f) { return (uint)asuint16((float16_t)asfloat(asuint(f) | px_rtzero())); }
#endif
uint px_fma16(uint a, uint b, uint c) {
    return (uint)asuint16(mad(asfloat16((uint16_t)a), asfloat16((uint16_t)b), asfloat16((uint16_t)c)));
}
uint px_half_boundary(uint w) {
#ifdef PX_HALF_ROUND_BARRIER
    return w | px_rtzero();
#else
    return w;
#endif
}
uint px_half_add_boundary(uint w) {
#ifdef PX_HALF_ADD_NO_BARRIER
    return w;
#else
    return px_half_boundary(w);
#endif
}
uint px_add_f16x2(uint a, uint b) { return px_half_add_boundary(px_h2v(px_v2h(a) + px_v2h(b))); }
uint px_sub_f16x2(uint a, uint b) { return px_half_add_boundary(px_h2v(px_v2h(a) - px_v2h(b))); }
uint px_mul_f16x2(uint a, uint b) { return px_half_boundary(px_h2v(px_v2h(a) * px_v2h(b))); }
uint px_fma_f16x2(uint a, uint b, uint c) {
    uint w = px_h2v(mad(px_v2h(a), px_v2h(b), px_v2h(c)));
#ifdef PX_HALF_FMA_NO_BARRIER
    return w;
#else
    return px_half_boundary(w);
#endif
}
// typed pairs for the MMA rows
PXH2 px_h2fma(PXH2 a, PXH2 b, PXH2 c) { return mad(a, b, c); }
float px_h2lo(PXH2 a) { return (float)a.x; }
float px_h2hi(PXH2 a) { return (float)a.y; }
PXH2 px_u2h2(uint w) { return px_v2h(w); }
// +0 pair that the compiler cannot see as a constant (an FMA with a literal 0 becomes a multiply: wrong sign for -0)
PXH2 px_h2z(PXH2 a) { return asfloat16(asuint16(a) & (uint16_t)px_rtzero()); }
uint px_h22u(PXH2 a) { return px_h2v(a); }
uint px_max_f16x2(uint a, uint b) { return px_h2v(max(px_v2h(a), px_v2h(b))); }
uint px_min_f16x2(uint a, uint b) { return px_h2v(min(px_v2h(a), px_v2h(b))); }
uint px_abs_f16x2(uint a) { return a & 0x7fff7fffu; }
// fp32 math (ACO: v_rcp_f32 / v_exp_f32 / v_log_f32 / v_sqrt_f32)
float px_fmax(float a, float b) { return max(a, b); }
float px_fmin(float a, float b) { return min(a, b); }
float px_div_approx(float a, float b) { return a / b; }
#if defined(HX_BOUND_MUFU) && HX_BOUND_MUFU
// Timing diagnostic only (wrong values): reciprocal and exp2 as one multiply
float px_rcp(float a) { return a * 0.5f; }
float px_ex2(float a) { return a * 0.5f; }
#else
float px_rcp(float a) { return 1.0f / a; }
float px_ex2(float a) { return exp2(a); }
#endif
float px_lg2(float a) { return log2(a); }
float px_sqrt(float a) { return sqrt(a); }
float px_sqrt_rn(float a) { return sqrt(a); }
float px_sat(float a) { return saturate(a); }
float px_floor(float a) { return floor(a); }
float px_trunc(float a) { return trunc(a); }
uint px_ballot(bool p) { uint4 mask = WaveActiveBallot(p); return WaveGetLaneIndex() < 32u ? mask.x : mask.y; }
#define PX_BARRIER() GroupMemoryBarrierWithGroupSync()

// sub-word shared memory: a 16-bit store writes one half of the pair (a separate ds_write_b16, so lanes writing the
// two halves of one word do not race). 8-bit stores are read-modify-write of the half (only used for single-value
// flags written identically by every thread).
uint PX_LDS16(uint a) { float16_t2 h = PX_LDSH2(a & ~3u); return (uint)asuint16((a & 2u) != 0u ? h.y : h.x); }
#define PX_LDS8(a) ((LDS32(a) >> (((a) & 3u) * 8u)) & 0xffu)
void PX_STS16(uint a, uint v) {
#if (defined(HX_FP32) || defined(PX_LDS_W32)) && !defined(PX_LDS_ROW8)
    // one half of a packed word: and/or keep the other half, which another lane may be writing
    const uint shift = (a & 2u) * 8u;
    InterlockedAnd(SMW[a >> 2], ~(0xffffu << shift));
    InterlockedOr(SMW[a >> 2], (v & 0xffffu) << shift);
#elif defined(PX_LDS_ROW8)
    uint shift = (a & 2u) * 8u;
    uint expected = LDS32(a), observed;
    do {
        uint replacement = (expected & ~(0xffffu << shift)) | ((v & 0xffffu) << shift);
        InterlockedCompareExchange(SMR[a >> 4][(a >> 2) & 3u], expected, replacement, observed);
        if (observed == expected) break;
        expected = observed;
    } while (true);
#elif defined(PX_LDS_ROW4)
    SM4[a >> 3][(a >> 1) & 3u] = asfloat16((uint16_t)(v & 0xffffu));
#else
    if ((a & 2u) != 0u) SM[a >> 2].y = asfloat16((uint16_t)(v & 0xffffu));
    else SM[a >> 2].x = asfloat16((uint16_t)(v & 0xffffu));
#endif
}
void PX_STS8(uint a, uint v) {
    uint h = PX_LDS16(a & ~1u);
    uint sh = (a & 1u) * 8u;
    PX_STS16(a & ~1u, (h & ~(0xffu << sh)) | ((v & 0xffu) << sh));
}

// global memory: one buffer per pointer argument (PXBUF_<slot>, defined by the kernel), byte offset = low 32 bits of
// the 64-bit "address" (the host writes (slot + 1) << 40 | byte offset into each pointer argument)
#define PX_GLD32(S, a) PXBUF_##S.Load((uint)(a))
#define PX_GLD64(S, a) ((uint64_t)PXBUF_##S.Load((uint)(a)) | ((uint64_t)PXBUF_##S.Load((uint)(a) + 4u) << 32))
#ifdef HX_FP32
#define PX_GLD16(S, a) ((PXBUF_##S.Load((uint)(a) & ~3u) >> (((uint)(a) & 2u) * 8u)) & 0xffffu)
#else
#define PX_GLD16(S, a) ((uint)PXBUF_##S.Load<uint16_t>((uint)(a)))
#endif
#define PX_GLD8(S, a) ((PXBUF_##S.Load((uint)(a) & ~3u) >> (((uint)(a) & 3u) * 8u)) & 0xffu)
#define PX_GLD2(S, a) PXBUF_##S.Load2((uint)(a))
#define PX_GLD4(S, a) PXBUF_##S.Load4((uint)(a))
#define PX_GST32(S, a, v) PXBUF_##S.Store((uint)(a), (v))
#ifdef HX_FP32
// one half of a 32-bit word in memory (no 16-bit stores without 16-bit types): and/or keep the other half
void px_gst16(RWByteAddressBuffer b, uint a, uint v)
{
    const uint sh = (a & 2u) * 8u;
    b.InterlockedAnd(a & ~3u, ~(0xffffu << sh));
    b.InterlockedOr(a & ~3u, (v & 0xffffu) << sh);
}
#if defined(HX_NO_NETIN) && HX_NO_NETIN
// input-kernel variant for frames whose network input is unused (staggered decoder frames): no network-input stores
#define PX_GST16(S, a, v) ((void)0)
#define HX_GST_FLUSH()
#elif defined(HX_GST16_COMBINE) && HX_GST16_COMBINE
// Write combining for kernels that write fp16 halves in ascending order and never read that buffer back (the input
// kernels): a half waits one store; when the next store is the upper half of the same aligned word, both are written
// as one plain 32-bit store (this thread owns the whole word), otherwise the waiting half takes the atomic path.
// HX_GST_FLUSH() (after the kernel body) writes the last waiting half. Same memory contents as px_gst16.
static uint hx_gpa = 0xffffffffu, hx_gpv = 0u;
void hx_gst16c(RWByteAddressBuffer b, uint a, uint v)
{
    v &= 0xffffu;
    if (hx_gpa != 0xffffffffu && (hx_gpa & 3u) == 0u && a == hx_gpa + 2u)
    {
        b.Store(hx_gpa, hx_gpv | (v << 16));
        hx_gpa = 0xffffffffu;
        return;
    }
    if (hx_gpa != 0xffffffffu) px_gst16(b, hx_gpa, hx_gpv);
    hx_gpa = a;
    hx_gpv = v;
}
#define PX_GST16(S, a, v) hx_gst16c(PXBUF_##S, (uint)(a), (v))
#define HX_GST_FLUSH() if (hx_gpa != 0xffffffffu) px_gst16(PXBUF_0, hx_gpa, hx_gpv)
#else
#define HX_GST_FLUSH()
#define PX_GST16(S, a, v) px_gst16(PXBUF_##S, (uint)(a), (v))
#endif
#else
#define PX_GST16(S, a, v) PXBUF_##S.Store<uint16_t>((uint)(a), (uint16_t)(v))
#define HX_GST_FLUSH()
#endif
#define PX_GST8(S, a, v) px_gst8_##S((uint)(a), (v))
#define PX_GST2(S, a, v) PXBUF_##S.Store2((uint)(a), (v))
#define PX_GST4(S, a, v) PXBUF_##S.Store4((uint)(a), (v))
#ifdef PX_U5_COMPACT
uint u5_load32(uint a);
void u5_store32(uint a, uint v);
PXH2 u5_loadh2(uint a);
#undef LDS32
#undef PX_STS32
#undef PX_LDSH2
#define LDS32(a) u5_load32(a)
#define PX_STS32(a, v) u5_store32(a, v)
#define PX_LDSH2(a) u5_loadh2(a)
#endif
#include "px_common.h"
#endif
