#!/usr/bin/env python3
"""Native fp32 version of the output kernel's two 1x1 layers in split pass 0 (k5x_s0_body.h, dfn_mid_3x3_128_032_032_048).

The translated pass emulates NVIDIA's m16n8k16 tensor-core MMAs: every lane gathers fp16 A rows / B columns from
shared memory through lane exchanges and converts them for every product. Per warp the two layers are only
   layer A: 16 rows x 32 -> 32 (bias, relu),  layer B: 16 rows x 32 -> 48 (no bias here; pass 1 adds it),
so this rewrite converts the weights to an fp32 table once per thread group and computes each lane's fragment
outputs with plain FMAs, writing the same checkpoint words (the m16n8k16 D fragments) for passes 1 and 2.

Data layout (from the generated address arithmetic and the PTX ldmatrix / mma.m16n8k16.row.col semantics):
  * an ldmatrix.x4 group at per-lane address X: lane L holds the row address of matrix L >> 3, row L & 7;
  * B groups (weights): matrix j row r = output column nb + 8 * (j >> 1) + r, words w = k pairs kb + 8 * (j & 1) + 2w;
      layer A: x_r678 (nb 0, kb 0), x_r683 (16, 0), x_r693 (0, 16), x_r698 (16, 16)
      layer B: x_r916 (0, 0), x_r921 (16, 0), x_r926 (32, 0), x_r931 (0, 16), x_r936 (16, 16), x_r941 (32, 16)
  * A rows (layer A input): blocks x_r673 (k 0..15) and x_r688 (k 16..31); matrices 0..3 = rows 0-7 / 8-15 of
    k 0-7, then rows 0-7 / 8-15 of k 8-15;
  * layer A bias: fp16 pairs at shared byte 0x2840 + 16 * tile + 4 * t (loaded as x_r833 / 835 / 837 / 839);
  * D fragment: lane (g, t) = (lane >> 2, lane & 3) holds rows g and g + 8, columns 2t and 2t + 1 of each n tile.
The register names above are k5x's; other output kernels with the same layers (k5fx, dfn_fastpath: renumbered
registers, `output_relu`) are matched by pattern and the names mapped (_resolve).
Numerics differ from the original (fp32 accumulation, no fp16 rounding between products): quality-gated builds only.
"""
import re
from pathlib import Path

HELPERS = r'''
// ---- native fp32 1x1 layers (source/tools/native_mlp.py) ----
groupshared float4 HX_WA4[32 * 9];  // layer A weights [n][k / 4], row stride 9 float4 (conflict-free column reads)
groupshared float4 HX_WB4[40 * 9];  // layer B weights [n][k / 4], the 40 columns passes 1/2 use
void hx_wset(bool layerA, uint n, uint k, float v)
{
    if (layerA) { if ((k & 3u) == 0u) HX_WA4[n * 9u + (k >> 2)].x = v; else if ((k & 3u) == 1u) HX_WA4[n * 9u + (k >> 2)].y = v;
                  else if ((k & 3u) == 2u) HX_WA4[n * 9u + (k >> 2)].z = v; else HX_WA4[n * 9u + (k >> 2)].w = v; }
    else        { if ((k & 3u) == 0u) HX_WB4[n * 9u + (k >> 2)].x = v; else if ((k & 3u) == 1u) HX_WB4[n * 9u + (k >> 2)].y = v;
                  else if ((k & 3u) == 2u) HX_WB4[n * 9u + (k >> 2)].z = v; else HX_WB4[n * 9u + (k >> 2)].w = v; }
}
static float hx_ra[32], hx_rb[32];  // this lane's A rows g and g + 8 (fp32)
static float hx_acc[16];            // layer A sums: [tile * 4 + c * 2 + row]
void hx_tbl(uint addr, uint nb, uint kb, bool layerA)
{
    const uint lane = WaveGetLaneIndex() & 31u, j = lane >> 3, n = nb + 8u * (j >> 1) + (lane & 7u), k = kb + 8u * (j & 1u);
    const uint base = addr >> 2;
    [unroll] for (uint w = 0u; w < 4u; ++w) {
        const uint v = SMW[base + w];
        if (layerA || n < 40u) { hx_wset(layerA, n, k + 2u * w, f16tof32(v)); hx_wset(layerA, n, k + 2u * w + 1u, f16tof32(v >> 16)); }
    }
}
void hx_rows(uint addr, uint kb)
{
    const uint g = (WaveGetLaneIndex() & 31u) >> 2;
    const uint r0 = px_rd(addr, g) >> 2, r1 = px_rd(addr, 8u + g) >> 2, r2 = px_rd(addr, 16u + g) >> 2, r3 = px_rd(addr, 24u + g) >> 2;
    [unroll] for (uint w = 0u; w < 4u; ++w) {
        uint v = SMW[r0 + w]; hx_ra[kb + 2u * w] = f16tof32(v); hx_ra[kb + 2u * w + 1u] = f16tof32(v >> 16);
        v = SMW[r1 + w]; hx_rb[kb + 2u * w] = f16tof32(v); hx_rb[kb + 2u * w + 1u] = f16tof32(v >> 16);
        v = SMW[r2 + w]; hx_ra[kb + 8u + 2u * w] = f16tof32(v); hx_ra[kb + 8u + 2u * w + 1u] = f16tof32(v >> 16);
        v = SMW[r3 + w]; hx_rb[kb + 8u + 2u * w] = f16tof32(v); hx_rb[kb + 8u + 2u * w + 1u] = f16tof32(v >> 16);
    }
}
void hx_layer_a(uint a678, uint a673, uint a688, uint warp)
{
    if (warp == 0u) hx_tbl(a678, 0u, 0u, true);
    if (warp == 1u) hx_tbl(a678 + 0x100u, 16u, 0u, true);
    if (warp == 2u) hx_tbl(a678 + 0x400u, 0u, 16u, true);
    if (warp == 3u) hx_tbl(a678 + 0x500u, 16u, 16u, true);
    hx_rows(a673, 0u);
    hx_rows(a688, 16u);
    GroupMemoryBarrierWithGroupSync();
    const uint t = WaveGetLaneIndex() & 3u;
    [unroll] for (uint i = 0u; i < 4u; ++i) {
        [unroll] for (uint c = 0u; c < 2u; ++c) {
            const uint n = 8u * i + 2u * t + c;
            float sa = 0.0f, sb = 0.0f;
            [unroll] for (uint q = 0u; q < 8u; ++q) {
                const float4 wv = HX_WA4[n * 9u + q];
                sa = mad(hx_ra[4u * q], wv.x, sa); sb = mad(hx_rb[4u * q], wv.x, sb);
                sa = mad(hx_ra[4u * q + 1u], wv.y, sa); sb = mad(hx_rb[4u * q + 1u], wv.y, sb);
                sa = mad(hx_ra[4u * q + 2u], wv.z, sa); sb = mad(hx_rb[4u * q + 2u], wv.z, sb);
                sa = mad(hx_ra[4u * q + 3u], wv.w, sa); sb = mad(hx_rb[4u * q + 3u], wv.w, sb);
            }
            hx_acc[i * 4u + c * 2u] = sa; hx_acc[i * 4u + c * 2u + 1u] = sb;
        }
    }
}
void hx_bias_relu(uint b0, uint b1, uint b2, uint b3)
{
    const uint bw[4] = {b0, b1, b2, b3};
    [unroll] for (uint i = 0u; i < 4u; ++i) {
        [unroll] for (uint c = 0u; c < 2u; ++c) {
            const float b = f16tof32(bw[i] >> (16u * c));
            hx_acc[i * 4u + c * 2u] = max(hx_acc[i * 4u + c * 2u] + b, 0.0f);
            hx_acc[i * 4u + c * 2u + 1u] = max(hx_acc[i * 4u + c * 2u + 1u] + b, 0.0f);
        }
    }
}
void hx_layer_b(uint a916, uint a931, uint warp, out uint d[10])
{
    if (warp == 0u) hx_tbl(a916, 0u, 0u, false);
    if (warp == 1u) hx_tbl(a916 + 0x400u, 16u, 0u, false);
    if (warp == 2u) hx_tbl(a916 + 0x800u, 32u, 0u, false);
    if (warp == 3u) hx_tbl(a931, 0u, 16u, false);
    if (warp == 4u) hx_tbl(a931 + 0x400u, 16u, 16u, false);
    if (warp == 5u) hx_tbl(a931 + 0x800u, 32u, 16u, false);
    // full layer-A rows g and g + 8: column 8i + 2t' + c lives in quad lane t'
    float ag[32], ah[32];
    [unroll] for (uint k = 0u; k < 32u; ++k) {
        const uint i = k >> 3, tq = (k >> 1) & 3u, c = k & 1u;
        ag[k] = QuadReadLaneAt(hx_acc[i * 4u + c * 2u], tq);
        ah[k] = QuadReadLaneAt(hx_acc[i * 4u + c * 2u + 1u], tq);
    }
    GroupMemoryBarrierWithGroupSync();
    const uint t = WaveGetLaneIndex() & 3u;
    [unroll] for (uint i = 0u; i < 5u; ++i) {
        float s[4];
        [unroll] for (uint c = 0u; c < 2u; ++c) {
            const uint n = 8u * i + 2u * t + c;
            float sa = 0.0f, sb = 0.0f;
            [unroll] for (uint q = 0u; q < 8u; ++q) {
                const float4 wv = HX_WB4[n * 9u + q];
                sa = mad(ag[4u * q], wv.x, sa); sb = mad(ah[4u * q], wv.x, sb);
                sa = mad(ag[4u * q + 1u], wv.y, sa); sb = mad(ah[4u * q + 1u], wv.y, sb);
                sa = mad(ag[4u * q + 2u], wv.z, sa); sb = mad(ah[4u * q + 2u], wv.z, sb);
                sa = mad(ag[4u * q + 3u], wv.w, sa); sb = mad(ah[4u * q + 3u], wv.w, sb);
            }
            s[c] = sa; s[2u + c] = sb;
        }
        d[2u * i] = px_h2v(float2(s[0], s[1]));
        d[2u * i + 1u] = px_h2v(float2(s[2], s[3]));
    }
}
'''

LAYER_A = ('        { PXH2 _pu[8], _pl[8]; pxr_arows_lds(x_r673, _pu, _pl); pxr_tile(x_r739, x_r740, _pu, _pl, x_r678, 0u); '
           'pxr_tile(x_r749, x_r750, _pu, _pl, x_r678, 2u); pxr_tile(x_r759, x_r760, _pu, _pl, x_r683, 0u); '
           'pxr_tile(x_r769, x_r770, _pu, _pl, x_r683, 2u); }')
LAYER_A2 = ('        { PXH2 _pu[8], _pl[8]; pxr_arows_lds(x_r688, _pu, _pl); pxr_tile(x_r739, x_r740, _pu, _pl, x_r693, 0u); '
            'pxr_tile(x_r749, x_r750, _pu, _pl, x_r693, 2u); pxr_tile(x_r759, x_r760, _pu, _pl, x_r698, 0u); '
            'pxr_tile(x_r769, x_r770, _pu, _pl, x_r698, 2u); }')
RELU = ['        x_r841 = px_relu_f16x2(px_fma_f16x2(x_r739, x_r871, x_r833));',
        '        x_r845 = px_relu_f16x2(px_fma_f16x2(x_r740, x_r871, x_r833));',
        '        x_r849 = px_relu_f16x2(px_fma_f16x2(x_r749, x_r871, x_r835));',
        '        x_r853 = px_relu_f16x2(px_fma_f16x2(x_r750, x_r871, x_r835));',
        '        x_r857 = px_relu_f16x2(px_fma_f16x2(x_r759, x_r871, x_r837));',
        '        x_r861 = px_relu_f16x2(px_fma_f16x2(x_r760, x_r871, x_r837));',
        '        x_r865 = px_relu_f16x2(px_fma_f16x2(x_r769, x_r871, x_r839));',
        '        x_r869 = px_relu_f16x2(px_fma_f16x2(x_r770, x_r871, x_r839));']
LAYER_B = ('        { PXH2 _pu[8], _pl[8]; pxr_arows_reg(x_r841, x_r845, x_r849, x_r853, _pu, _pl); pxr_tile(x_r1002, x_r1003, _pu, _pl, x_r916, 0u); '
           'pxr_tile(x_r1012, x_r1013, _pu, _pl, x_r916, 2u); pxr_tile(x_r1022, x_r1023, _pu, _pl, x_r921, 0u); '
           'pxr_tile(x_r1032, x_r1033, _pu, _pl, x_r921, 2u); pxr_tile(x_r1042, x_r1043, _pu, _pl, x_r926, 0u); '
           'pxr_tile(x_r1052, x_r1053, _pu, _pl, x_r926, 2u); }')
LAYER_B2 = ('        { PXH2 _pu[8], _pl[8]; pxr_arows_reg(x_r857, x_r861, x_r865, x_r869, _pu, _pl); pxr_tile(x_r1002, x_r1003, _pu, _pl, x_r931, 0u); '
            'pxr_tile(x_r1012, x_r1013, _pu, _pl, x_r931, 2u); pxr_tile(x_r1022, x_r1023, _pu, _pl, x_r936, 0u); '
            'pxr_tile(x_r1032, x_r1033, _pu, _pl, x_r936, 2u); pxr_tile(x_r1042, x_r1043, _pu, _pl, x_r941, 0u); '
            'pxr_tile(x_r1052, x_r1053, _pu, _pl, x_r941, 2u); }')
# address relations the helpers rely on (checked in the generated text)
RELATIONS = ['x_r683 = (x_r678 + 0x100U);', 'x_r693 = (x_r678 + 0x400U);', 'x_r698 = (x_r678 + 0x500U);',
             'x_r688 = (x_r673 + 0x800U);', 'x_r921 = (x_r916 + 0x400U);', 'x_r926 = (x_r916 + 0x800U);',
             'x_r936 = (x_r931 + 0x400U);', 'x_r941 = (x_r931 + 0x800U);', 'x_r871 = 0x3c003c00U;',
             'x_r834 = (x_r879 + 0x2840U);', 'x_r836 = (x_r879 + 0x2850U);', 'x_r838 = (x_r879 + 0x2860U);',
             'x_r840 = (x_r879 + 0x2870U);', 'x_r879 = (x_r877 + x_r395);', 'x_r877 = px_shl32(x_r74, 0x2U);',
             'x_r74 = (x_r1 & 0x3U);']


# the bias words are loaded from the checked addresses
LOADS = ['{ uint _a = x_r834;\n        x_r833 = LDS32(_a);', '{ uint _a = x_r836;\n        x_r835 = LDS32(_a);',
         '{ uint _a = x_r838;\n        x_r837 = LDS32(_a);', '{ uint _a = x_r840;\n        x_r839 = LDS32(_a);']
RELU_NAMES = '(?:px_relu_f16x2|output_relu)'   # k5x / k5fx spelling of the same packed ReLU


def _pattern(template):
    """Regex for a k5x template: every register is a capture (named after its k5x register), the ReLU either name."""
    seen = set()
    def reg(m):
        name = 'r' + m[0][3:]
        if name in seen: return f'(?P={name})'
        seen.add(name); return f'(?P<{name}>x_r\\d+)'
    escaped = re.escape(template).replace('px_relu_f16x2', '\0')
    return re.sub(r'x_r\d+', reg, escaped).replace('\0', RELU_NAMES)


def _resolve(text):
    """Map the k5x register names in the templates to this kernel's registers (k5x: the identity)."""
    mapping = {}
    pending = [LAYER_A, LAYER_A2, LAYER_B, LAYER_B2, *RELU, *LOADS, *RELATIONS]
    while pending:
        progress = []
        for template in pending:
            hits = []
            for m in re.finditer(_pattern(template), text):
                found = {'x_' + k: v for k, v in m.groupdict().items()}
                if all(mapping.get(k, v) == v for k, v in found.items()): hits.append((m, found))
            if not hits: raise ValueError('native_mlp: generated code absent near ' + template[:60])
            if len(hits) == 1:
                mapping.update(hits[0][1]); progress.append(template)
        if not progress: raise ValueError('native_mlp: ambiguous generated code near ' + pending[0][:60])
        pending = [t for t in pending if t not in progress]
    if len(set(mapping.values())) != len(mapping): raise ValueError('native_mlp: register mapping not one-to-one')
    return mapping


def apply(path: Path):
    text = path.read_text()
    mapping = _resolve(text)
    def mapped(s):
        return re.sub(r'x_r\d+', lambda m: mapping[m[0]], s)
    def found(template):
        for relu in ('px_relu_f16x2', 'output_relu'):
            t = mapped(template).replace('px_relu_f16x2', relu)
            if text.count(t) == 1: return t
        raise ValueError('native_mlp: unexpected generated code near ' + template[:60])
    warp = '(tid.x >> 5)'
    edits = [(LAYER_A, f'        hx_layer_a(x_r678, x_r673, x_r688, {warp});'), (LAYER_A2, ''),
             (RELU[0], '        hx_bias_relu(x_r833, x_r835, x_r837, x_r839);'), *[(line, '') for line in RELU[1:]],
             (LAYER_B, (f'        {{ uint _d[10]; hx_layer_b(x_r916, x_r931, {warp}, _d); '
                        'x_r1002 = _d[0]; x_r1003 = _d[1]; x_r1012 = _d[2]; x_r1013 = _d[3]; x_r1022 = _d[4]; '
                        'x_r1023 = _d[5]; x_r1032 = _d[6]; x_r1033 = _d[7]; x_r1042 = _d[8]; x_r1043 = _d[9]; }')),
             (LAYER_B2, '')]
    targets = [(found(t), mapped(r)) for t, r in edits]
    for t in [*LOADS, *RELATIONS]: found(t)
    for t, r in targets: text = text.replace(t, r)
    entry = re.search(r'void k5\w*_s0_body\(', text).start()
    text = text[:entry] + HELPERS + text[entry:]
    path.write_text(text)
    return {'native_mlp': True, 'smem_extra_bytes': (32 + 40) * 36 * 4,
            'registers_renamed': sum(k != v for k, v in mapping.items())}
