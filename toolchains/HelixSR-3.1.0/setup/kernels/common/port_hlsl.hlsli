// HLSL side of the portable kernel sources (DXC, cs_6_6, -HV 2021).
#ifndef PORT_HLSL_HLSLI
#define PORT_HLSL_HLSLI
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
#define asfloat16(x) f16tof32(x)
#if defined(HX_F2H_HW) && HX_F2H_HW
// _fp32h builds: the GPU's own conversion, selected only after a run-time check found that it rounds to nearest even
// (with fp16 subnormals and overflow to infinity) exactly as the integer rounding below
uint hx_f2h(float f) { return f32tof16(f); }
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
uint2 hx_f2h(float2 f) { return uint2(hx_f2h(f.x), hx_f2h(f.y)); }
uint3 hx_f2h(float3 f) { return uint3(hx_f2h(f.x), hx_f2h(f.y), hx_f2h(f.z)); }
uint4 hx_f2h(float4 f) { return uint4(hx_f2h(f.x), hx_f2h(f.y), hx_f2h(f.z), hx_f2h(f.w)); }
#define asuint16(x) hx_f2h(x)
#endif
// Constant-buffer tables of fp16 weights, one 16-byte register per entry: HX_CB_H4 is the entry type and hx_h4 gives
// its first four values (FP32 builds read the register as words and unpack it: an fp32 view would read garbage).
#ifdef HX_FP32
#define HX_CB_H4 uint4
float4 hx_h4(uint4 r) { return float4(f16tof32(r.x), f16tof32(r.x >> 16), f16tof32(r.y), f16tof32(r.y >> 16)); }
float4 hx_h4hi(uint4 r) { return float4(f16tof32(r.z), f16tof32(r.z >> 16), f16tof32(r.w), f16tof32(r.w >> 16)); }
#else
#define HX_CB_H4 float16_t4
#define hx_h4(r) (r)
#endif
#define ASUINT asuint
#define ASFLOAT asfloat
#define PRECISE precise
#define GS groupshared
#define UNROLL [unroll]
#define LOOP [loop]
#define BARRIER() GroupMemoryBarrierWithGroupSync()
#define F4(a, b, c, d) float4(a, b, c, d)
#define U2(a, b) uint2(a, b)
#define U4(a, b, c, d) uint4(a, b, c, d)
#define MAXU(a, b) max(a, b)
// mad -> DXIL FMad -> SPIR-V Fma; stock RADV lowers it to an unfused multiply + add on gfx1013 (the reference model).
#define MAD(a, b, c) mad(a, b, c)
// Wave size: 32 by default. HX_W64 (wave64 builds, for GPUs that cannot run wave32 such as GCN/Vega) keeps the
// arithmetic identical but drops the wave-uniform broadcast of the cout group (each 32-lane half has its own) and marks
// the descriptor index non-uniform.
#ifndef HX_WAVE
#define HX_WAVE 32
#endif
#ifdef HX_W64
#define WAVE_FIRST(x) (x)
#define NU(x) NonUniformResourceIndex(x)
// A quantity that is wave-uniform in wave32 (the cout group) takes two values in a wave64, one per 32-lane half, and
// those are the consecutive values the two halves of wave32 pairs would have had. WAVE_DECL(T, name, expr): this lane's
// value, plus name_lo / name_hi (the value of the first / second half: wave-uniform, so weight loads stay scalar). The
// loads read both and pick by half (HI_HALF) with one select, instead of a per-lane (or waterfall) load.
#define WAVE_DECL(T, name, expr) T name = (expr); T name##_lo = WaveReadLaneFirst(name); T name##_hi = WaveReadLaneAt(name, 32u)
#define HI_HALF(tid) (((tid) & 32u) != 0u)
#else
#define WAVE_FIRST(x) WaveReadLaneFirst(x)
#define NU(x) (x)
#define WAVE_DECL(T, name, expr) T name = WaveReadLaneFirst(expr); T name##_lo = name; T name##_hi = name
#define HI_HALF(tid) false
#endif
// int8 dot product (4 unsigned bytes, accumulated). I8_PROXY (timing tests only, wrong results): one xor-add instead, the
// cost of the real instruction on GPUs that have it (this GPU emulates dot4add_u8packed)
#ifdef I8_PROXY
#define DOT4U8(a, b, c) ((c) + ((a) ^ (b)))
#define DOT4I8(a, b, c) ((c) + int((a) ^ (b)))
#else
#define DOT4U8(a, b, c) dot4add_u8packed(a, b, c)
#define DOT4I8(a, b, c) dot4add_i8packed(a, b, c)   // 4 signed bytes x 4 signed bytes, int accumulator
#endif
#define LANE_XOR(tid, v, m) WaveReadLaneAt(v, WaveGetLaneIndex() ^ (m))
#include "fp16.h"
// Shader-level fp16 primitives (needs -enable-16bit-types). ACO lowering on gfx1013 (checked in the offline ISA):
//   H2F    f16tof32            -> v_cvt_f32_f16 or an fp16 operand (lo/hi op_sel) of a v_fma_mix (exact)
//   CVT16  (half) conversion   -> v_or_b32 + v_cvt_f16_f32 (RNE; NOT f32tof16, which RADV lowers to v_cvt_pkrtz = round to zero)
//   FMIX   mad of fp16 values  -> v_fma_mix_f32 (product exact: fused == unfused)
//   MIXLO  (half)mad(...)      -> v_fma_mixlo_f16 (one rounding). PORT_MIXLO_RTO=1: TwoSum + round-to-odd + CVT16,
//          exact under any lowering (about 14 VALU instead of 1).
// fp16 sums through fp32 then CVT16 are exact either way (double rounding is innocuous for 24 >= 2*11+2).
// OPAQUE_F(x): x unchanged, but the compiler cannot fuse across it (OR with P_ZERO, a constant-buffer zero): stops
// v_fma_mixlo formation where two roundings are wanted, and stops HLSL 'precise' from propagating backwards.
#define OPAQUE_F(x) asfloat(asuint(x) | P_ZERO)
#define H2F(h) f16tof32(h)
// CVT16 rounds the fp32 VALUE (barrier first: ACO fuses an add feeding a conversion into v_fma_mixlo_f16, one rounding,
// even when the add is precise). CVT16_SUM16 is for fp32 sums of two fp16 values, where fusing is harmless.
#define CVT16_RAW(f) ((uint)asuint16((half)(f)))
#define CVT16(f) CVT16_RAW(OPAQUE_F(f))
#define CVT16_SUM16(f) CVT16_RAW(f)
#define FMIX(a, b, c) mad(f16tof32(a), f16tof32(b), (c))
#if defined(PORT_MIXLO_RTO) && PORT_MIXLO_RTO
uint port_mixlo(uint a, uint b, float c)
{
    precise float p = f16tof32(a) * f16tof32(b);
    precise float s = p + c;
    precise float bb = s - p;
    precise float e0 = p - (s - bb);
    precise float e1 = c - bb;
    precise float err = e0 + e1;
    return CVT16_RAW(fp_rto(s, err));
}
#define MIXLO(a, b, c) port_mixlo(a, b, c)
#else
#define MIXLO(a, b, c) CVT16_RAW(mad(f16tof32(a), f16tof32(b), (c)))
#endif
#endif
