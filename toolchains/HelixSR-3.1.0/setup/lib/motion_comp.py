#!/usr/bin/env python3
"""Motion-compensated filter parameters for the split output kernel's reconstruction passes (k5x / k5fx _s1 / _s2).

With the network spread over frames (NetworkInterval / NetworkStagger) the reconstruction uses filter parameters
computed from an input `age` frames old. Without correction they are applied where the content WAS; in motion that
blurs edges. This rewrite fetches each 2x2 output block's parameters from the block the content came from.

Layout (from the generated code): reconstruction lane tid of thread group (cx, cy) owns the 2x2 output block
    bx = 32 cx + 2 ((tid >> 2) & 15) + (tid & 1),   by = 16 cy + ((tid >> 1) & 1) + 2 (tid >> 6) + 8 half
(half 0: pass 1's rows, slots 0,2,..,8; half 1: pass 2's rows, slots 1,3,..,9); its 10 parameters are the lean
checkpoint words (slot 2i + half) of that lane, plus the bias of channel group t = (bx & 1) | (by & 1) << 1.
Inputs: t9 = this frame's MV_HIST_WRITE (the input kernel's motion, output pixels, one texel per render pixel) and
argument word 648 = the age in frames (0: unchanged, the original addresses).
"""
import re
from pathlib import Path

HELPERS = r'''
// ---- motion-compensated filter parameters (source/tools/motion_comp.py) ----
Texture2D<float4> HX_MV : register(t9);
#if defined(HX_MC_NEG) && HX_MC_NEG
#define HX_MC_SIGN (-1.0f)
#else
#define HX_MC_SIGN 1.0f
#endif
// word index of the source block's slot-0 word of its half (loads add 2i x 256); tp = its channel group
uint hx_mc_src(uint3 ctaid, uint tid, uint half, uint hx_base, out uint tp)
{
    const uint age = PX_PARAM32(648u);
    tp = tid & 3u;
    if (age == 0u) return hx_base + tid + half * 256u;
    const uint bx = 32u * ctaid.x + 2u * ((tid >> 2) & 15u) + (tid & 1u);
    const uint by = 16u * ctaid.y + ((tid >> 1) & 1u) + 2u * (tid >> 6) + 8u * half;
    // render pixel under the block centre (args 536 / 528: render / output size, 572 / 564: render size - 1)
    const uint rx = min((uint)((2.0f * bx + 1.0f) * asfloat(PX_PARAM32(536u))), PX_PARAM32(572u));
    const uint ry = min((uint)((2.0f * by + 1.0f) * asfloat(PX_PARAM32(528u))), PX_PARAM32(564u));
    const float2 mv = HX_MV.Load(int3(rx, ry, 0)).xy * (HX_MC_SIGN * 0.5f * (float)age);   // blocks
    const int bw = (int)((PX_PARAM32(508u) + 1u) >> 1), bh = (int)((PX_PARAM32(504u) + 1u) >> 1);
#if defined(HX_MC_CELL) && HX_MC_CELL
    // whole network cells (2x2 blocks): every block keeps its own sub-position's parameters
    const int cx = 2 * (int)floor(mv.x * 0.5f + 0.5f), cy = 2 * (int)floor(mv.y * 0.5f + 0.5f);
    const uint sx = (uint)clamp((int)bx + cx, 0, bw - 1);
    const uint sy = (uint)clamp((int)by + cy, 0, bh - 1);
#else
    const uint sx = (uint)clamp((int)floor((float)bx + mv.x + 0.5f), 0, bw - 1);
    const uint sy = (uint)clamp((int)floor((float)by + mv.y + 0.5f), 0, bh - 1);
#endif
    tp = (sx & 1u) | ((sy & 1u) << 1);
    const uint lx = sx & 31u, ly = sy & 15u, l = ly & 7u;
    const uint st = (lx & 1u) | ((l & 1u) << 1) | ((lx >> 1) << 2) | ((l >> 1) << 6);
    return ((ctaid.z * PXGRID.y + (sy >> 4)) * PXGRID.x + (sx >> 5)) * HX_MC_STRIDE + (ly >> 3) * 256u + st;
}
uint hx_mc_bias(uint tile, uint tp) { return PX_GLD32(5, PX_PARAM64(248u) + (uint64_t)(4u * tp + 16u * tile)); }
'''

# bilinear: the biased parameters of the four blocks around the source position, weighted in fp32
BILINEAR = r'''
// ---- motion-compensated filter parameters, bilinear (source/tools/motion_comp.py) ----
Texture2D<float4> HX_MV : register(t9);
uint hx_mc_addr(uint3 ctaid, int x, int y)   // word index of block (x, y)'s slot-0 word of its half
{
    const uint sx = (uint)x, sy = (uint)y, lx = sx & 31u, ly = sy & 15u, l = ly & 7u;
    const uint st = (lx & 1u) | ((l & 1u) << 1) | ((lx >> 1) << 2) | ((l >> 1) << 6);
    return ((ctaid.z * PXGRID.y + (sy >> 4)) * PXGRID.x + (sx >> 5)) * HX_MC_STRIDE + (ly >> 3) * 256u + st;
}
uint hx_mc_bias(uint tile, uint tp) { return PX_GLD32(5, PX_PARAM64(248u) + (uint64_t)(4u * tp + 16u * tile)); }
// this block's five parameter words (bias added), from where its content was `age` frames ago
void hx_mc_words(uint3 ctaid, uint tid, uint half, uint hx_base, out uint w[5])
{
    const uint age = PX_PARAM32(648u);
    if (age == 0u) {   // unchanged: the original words and fp16 bias add
        [unroll] for (uint i = 0u; i < 5u; ++i)
            w[i] = px_add_f16x2(HX_SPLIT.Load((hx_base + tid + half * 256u + 2u * i * 256u) * 4u), hx_mc_bias(i, tid & 3u));
        return;
    }
    const uint bx = 32u * ctaid.x + 2u * ((tid >> 2) & 15u) + (tid & 1u);
    const uint by = 16u * ctaid.y + ((tid >> 1) & 1u) + 2u * (tid >> 6) + 8u * half;
    const uint rx = min((uint)((2.0f * bx + 1.0f) * asfloat(PX_PARAM32(536u))), PX_PARAM32(572u));
    const uint ry = min((uint)((2.0f * by + 1.0f) * asfloat(PX_PARAM32(528u))), PX_PARAM32(564u));
    const int bw = (int)((PX_PARAM32(508u) + 1u) >> 1), bh = (int)((PX_PARAM32(504u) + 1u) >> 1);
#if defined(HX_MC_CELL) && HX_MC_CELL
    // between the four blocks of this block's own sub-position (whole network cells: steps of 2 blocks)
    const float2 o = HX_MV.Load(int3(rx, ry, 0)).xy * (0.25f * (float)age);   // cells
    const float2 f0 = floor(o), fr = o - f0;
    const int x0 = clamp((int)bx + 2 * (int)f0.x, 0, bw - 1), x1 = clamp((int)bx + 2 * (int)f0.x + 2, 0, bw - 1);
    const int y0 = clamp((int)by + 2 * (int)f0.y, 0, bh - 1), y1 = clamp((int)by + 2 * (int)f0.y + 2, 0, bh - 1);
#else
    const float2 p = float2(bx, by) + HX_MV.Load(int3(rx, ry, 0)).xy * (0.5f * (float)age);
    const float2 f0 = floor(p), fr = p - f0;
    const int x0 = clamp((int)f0.x, 0, bw - 1), x1 = clamp((int)f0.x + 1, 0, bw - 1);
    const int y0 = clamp((int)f0.y, 0, bh - 1), y1 = clamp((int)f0.y + 1, 0, bh - 1);
#endif
    const uint a[4] = {hx_mc_addr(ctaid, x0, y0), hx_mc_addr(ctaid, x1, y0), hx_mc_addr(ctaid, x0, y1), hx_mc_addr(ctaid, x1, y1)};
    const uint t[4] = {(x0 & 1) | ((y0 & 1) << 1), (x1 & 1) | ((y0 & 1) << 1), (x0 & 1) | ((y1 & 1) << 1), (x1 & 1) | ((y1 & 1) << 1)};
    const float k[4] = {(1.0f - fr.x) * (1.0f - fr.y), fr.x * (1.0f - fr.y), (1.0f - fr.x) * fr.y, fr.x * fr.y};
    [unroll] for (uint i = 0u; i < 5u; ++i) {
        float2 s = 0.0f;
        [unroll] for (uint q = 0u; q < 4u; ++q) {
            const uint v = HX_SPLIT.Load((a[q] + 2u * i * 256u) * 4u), b = hx_mc_bias(i, t[q]);
            s += k[q] * (float2(f16tof32(v), f16tof32(v >> 16)) + float2(f16tof32(b), f16tof32(b >> 16)));
        }
        w[i] = px_h2v(s);
    }
}
'''


def apply_bilinear(path: Path):
    text = path.read_text()
    m = re.search(r'void (k5f?x_s[12]_body)\(uint3 tid, uint3 ctaid\) \{', text)
    if not m: raise ValueError('motion_comp: pass entry absent in ' + str(path))
    base = re.search(r'uint _hx_base=\(\(ctaid\.z\*PXGRID\.y\+ctaid\.y\)\*PXGRID\.x\+ctaid\.x\)\*(\d+)u;\n', text)
    if not base or base[1] != '2560': raise ValueError('motion_comp: needs the lean checkpoint (stride 2560)')
    loads = re.findall(r'(x_r\d+)=HX_SPLIT\.Load\(\(_hx_base\+(\d+)u\*256u\+tid\.x\)\*4u\);', text)
    regs = {int(s): r for r, s in loads}
    if sorted(regs) != list(range(10)) or len(loads) != 10: raise ValueError('motion_comp: needs slots 0..9')
    for slot, reg in regs.items():
        text = text.replace(f'{reg}=HX_SPLIT.Load((_hx_base+{slot}u*256u+tid.x)*4u);', f'{reg}=hx_mc_w{slot & 1}[{slot >> 1}];')
        pat = re.compile(rf'(x_r\d+) = px_add_f16x2\({reg}, (x_r\d+)\);')
        if len(pat.findall(text)) != 1: raise ValueError(f'motion_comp: bias add of {reg} not unique')
        text = pat.sub(lambda mm: f'{mm[1]} = {reg};', text)   # the words already carry their bias
    text = text.replace(base[0], base[0] + 'uint hx_mc_w0[5], hx_mc_w1[5];\nhx_mc_words(ctaid,tid.x,0u,_hx_base,hx_mc_w0);\n'
                        'hx_mc_words(ctaid,tid.x,1u,_hx_base,hx_mc_w1);\n')
    text = text[:m.start()] + BILINEAR.replace('HX_MC_STRIDE', '2560u') + text[m.start():]
    path.write_text(text)
    return {'motion_comp': 'bilinear', 'loads': len(regs)}


def apply(path: Path):
    text = path.read_text()
    m = re.search(r'void (k5f?x_s[12]_body)\(uint3 tid, uint3 ctaid\) \{', text)
    if not m: raise ValueError('motion_comp: pass entry absent in ' + str(path))
    base = re.search(r'uint _hx_base=\(\(ctaid\.z\*PXGRID\.y\+ctaid\.y\)\*PXGRID\.x\+ctaid\.x\)\*(\d+)u;\n', text)
    if not base: raise ValueError('motion_comp: checkpoint base absent')
    stride = int(base[1])
    loads = list(re.finditer(r'(x_r\d+)=HX_SPLIT\.Load\(\(_hx_base\+(\d+)u\*256u\+tid\.x\)\*4u\);', text))
    regs = {int(s): r for _, r, s in [(x[0], x[1], x[2]) for x in loads] if int(s) < 10}
    if sorted(regs) != list(range(10)) or len(loads) != 10 or stride != 2560:
        raise ValueError('motion_comp: needs the lean checkpoint (slots 0..9, stride 2560)')
    for slot, reg in regs.items():
        old = f'{reg}=HX_SPLIT.Load((_hx_base+{slot}u*256u+tid.x)*4u);'
        new = f'{reg}=HX_SPLIT.Load((hx_mc_b{slot & 1}+{slot & ~1}u*256u)*4u);'
        text = text.replace(old, new)
    text = text.replace(base[0], base[0] + 'uint hx_mc_t0, hx_mc_t1;\nconst uint hx_mc_b0=hx_mc_src(ctaid,tid.x,0u,_hx_base,hx_mc_t0);\n'
                        'const uint hx_mc_b1=hx_mc_src(ctaid,tid.x,1u,_hx_base,hx_mc_t1);\n')
    # the bias add of each parameter word: the source block's channel group
    biased = 0
    for slot, reg in regs.items():
        pat = re.compile(rf'(x_r\d+) = px_add_f16x2\({reg}, (x_r\d+)\);')
        hits = pat.findall(text)
        if len(hits) != 1: raise ValueError(f'motion_comp: bias add of {reg} not unique ({len(hits)})')
        text = pat.sub(lambda mm: f'{mm[1]} = px_add_f16x2({reg}, hx_mc_bias({slot >> 1}u, hx_mc_t{slot & 1}));', text)
        biased += 1
    text = text[:m.start()] + HELPERS.replace('HX_MC_STRIDE', f'{stride}u') + text[m.start():]
    path.write_text(text)
    return {'motion_comp': True, 'loads': len(regs), 'bias_adds': biased}


def root_signature(hlsl: Path):
    """All passes get t9 (identical root signatures); root parameter 4."""
    text = hlsl.read_text()
    sig = 'UAV(u0, numDescriptors = 2)), UAV(u2)'
    if text.count(sig) != 1: raise ValueError('motion_comp: split root signature absent in ' + str(hlsl))
    hlsl.write_text(text.replace(sig, sig + ', DescriptorTable(SRV(t9))'))
