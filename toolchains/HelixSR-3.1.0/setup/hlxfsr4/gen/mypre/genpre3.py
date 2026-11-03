"""genpre3.py OUT.hlsl : own FSR 4.1.2 Lite prepass, thread per pixel, waves uniform in 2x2 position (baked weights), LDS block sum; all modes. Env: INV AE DMV JIT NL (0/1), ROW (H-plane row bytes: 15392 / 30752 / 61472).
Stage 1 = faithful: same math and operation order as AMD's prepass (decoded), written from scratch."""
import os, sys
E = lambda k, d='0': int(os.environ.get(k, d))
INV, AE, DMV, JIT, NL = E('INV', '1'), E('AE'), E('DMV'), E('JIT'), E('NL')
CURVE = E('CURVE') if NL else 0   # with non-linear colour: 0 = as given, 1 = sRGB, 2 = PQ (per-frame dispatch flag)
ROW = E('ROW', '15392'); DIAG = os.environ.get('DIAG', '')  # timing diagnostics only (wrong output)
L = []; e = L.append
e('ByteAddressBuffer W : register(t21);')
e('RWByteAddressBuffer Scratch : register(u13);')
e('cbuffer C : register(b1) { float4 m[7]; };')
H16 = int(os.environ.get('H16', '1'))  # history / recurrent fetched as 16-bit (hardware d16), same rounding as AMD's float->min16 conversion
e('Texture2D<%s> Hist : register(t0); Texture2D<float4> Mv : register(t1); Texture2D<float4> Depth : register(t2);' % ('half4' if H16 else 'float4'))
e('Texture2D<float4> Color : register(t3); Texture2D<%s> Recur : register(t4); Texture2D<float4> Expo : register(t6);' % ('half4' if H16 else 'float4'))
e('Texture2D<float4> AExp : register(t17); RWTexture2D<float4> Reproj : register(u3); SamplerState Lin : register(s0);')
e('float tl(float c, float s) { return %s; }  // tonemap to log' % ('c * s' if DIAG == 'nolog' else 'max(log2(c * s + 1.0f) * 0.08137547969818115234375f, 0.0f)'))
e('float rl(float h, float ip, float s) { return tl(max((exp2(max(h, 0.0f) * 12.28870391845703125f) + (-1.0f)) * 0.006666666828095912933349609375f, 0.0f) / ip, s); }')
e('float lin(float h) { return max((exp2(max(h, 0.0f) * 12.28870391845703125f) + (-1.0f)) * 0.006666666828095912933349609375f, 0.0f); }')
e('float sdec(float c) { return (c < 0.040449999272823333740234375f) ? (c * 0.077399380505084991455078125f) : exp2(log2((c + 0.054999999701976776123046875f) * 0.947867333889007568359375f) * 2.400000095367431640625f); }')
e('float senc(float l) { return (l < 0.003130800090730190277099609375f) ? (l * 12.9200000762939453125f) : ((exp2(log2(l) * 0.4166666567325592041015625f) * 1.05499994754791259765625f) + (-0.054999999701976776123046875f)); }')
e('float pq1(float c) { return exp2(log2(min(max(c, 0.0f), 1.0f)) * 0.0126833133399486541748046875f); }')
e('float pq2(float t) { return max(exp2(log2(max(t + (-0.8359375f), 0.0f) / (18.8515625f - (t * 18.6875f))) * 6.277394771575927734375f) * 33.333332061767578125f, 0.0f); }')
e('float penc(float l) { float y = exp2(log2(max(l * 0.02999999932944774627685546875f, 1.0000000133514319600180897396058e-10f)) * 0.1593017578125f); return max(exp2(log2(((y * 18.8515625f) + 0.8359375f) / ((y * 18.6875f) + 1.0f)) * 78.84375f), 0.0f); }')
e('uint q8(float v) { return uint(min(max(int(round(v * 64.0f)), -128), 127)) & 255u; }')
DTILE = E('DTILE') and not DMV and DIAG != 'nodepth'  # depth 3x3 taps read from a per-group LDS tile (exact: same texels, OOB -> 0)
GDEP = E('GDEP') and not DMV and DIAG != 'nodepth' and not DTILE  # depth taps by 4 gathers (exact)
DT = 22  # tile edge: 16 output pixels at scale <= 1 span <= 17 render texels + rounding + 1-texel margins
def DL(a, b): return ('DTv[clamp(int(%s) - dly, 0, %d) * %d + clamp(int(%s) - dlx, 0, %d)]' % (b, DT - 1, DT, a, DT - 1)) if DTILE else ('Depth.Load(int3(%s, %s, 0)).x' % (a, b))
def pixel(e):
    e(' float fx = float(x), fy = float(y);')
    
    # render-space sample position
    if DMV:
        e(' float px = (m[1].z + (-0.5f)) + (m[1].x * (fx + 0.5f)), py = (m[1].w + (-0.5f)) + (m[1].y * (fy + 0.5f));')
    else:
        e(' float bx = (m[1].x * 0.5f) + (-0.5f), by = (m[1].y * 0.5f) + (-0.5f);')
        e(' float cx = bx + (m[1].x * fx), cy = by + (m[1].y * fy);')
        e(' float px = cx + m[1].z, py = cy + m[1].w;')
    e(' uint ix = uint(int(floor(px))), iy = uint(int(floor(py))); uint ix1 = ix + 1u, iy1 = iy + 1u;')
    e(' uint mxr = iw.w + 4294967295u, myr = asuint(m[5]).x + 4294967295u;')
    e(' uint sx0 = uint(min(int(uint(max(int(ix), 0))), int(mxr))), sy0 = uint(min(int(uint(max(int(iy), 0))), int(myr)));')
    e(' uint sx1 = uint(min(int(uint(max(int(ix1), 0))), int(mxr))), sy1 = uint(min(int(uint(max(int(iy1), 0))), int(myr)));')
    e(' float4 c00 = Color.Load(int3(sx0, sy0, 0)), c10 = Color.Load(int3(sx1, sy0, 0)), c01 = Color.Load(int3(sx0, sy1, 0)), c11 = Color.Load(int3(sx1, sy1, 0));')
    e(' float dx0 = m[0].z * abs(float(int(ix)) - px); float gx0 = exp2((dx0 * dx0) * (-3.2654933929443359375f));')
    e(' float dx1 = abs(float(int(ix1)) - px) * m[0].z; float gx1 = exp2((dx1 * dx1) * (-3.2654933929443359375f));')
    e(' float dy0 = abs(float(int(iy)) - py) * m[0].w; float gy0 = exp2((dy0 * dy0) * (-3.2654933929443359375f));')
    e(' float dy1 = abs(float(int(iy1)) - py) * m[0].w; float gy1 = exp2((dy1 * dy1) * (-3.2654933929443359375f));')
    e(' float w00 = gy0 * gx0, w10 = gy0 * gx1, w01 = gy1 * gx0, w11 = gy1 * gx1;')
    e(' float ws = (w01 + (gy0 * (gx1 + gx0))) + w11;')
    for ch in 'xyz':
        if CURVE: D = {1: 'sdec(%s)', 2: 'pq2(pq1(%s))'}[CURVE]; e(' float k%s = ((((w00 * tl(%s, 150.0f)) + (w10 * tl(%s, 150.0f))) + (w01 * tl(%s, 150.0f))) + (w11 * tl(%s, 150.0f))) / ws;' % (ch, D % ('c00.' + ch), D % ('c10.' + ch), D % ('c01.' + ch), D % ('c11.' + ch)))
        elif NL: e(' float k%s = ((((w00 * c00.%s) + (w10 * c10.%s)) + (w01 * c01.%s)) + (w11 * c11.%s)) / ws;' % ((ch,) * 5))
        else: e(' float k%s = ((((w00 * tl(c00.%s, es)) + (w10 * tl(c10.%s, es))) + (w01 * tl(c01.%s, es))) + (w11 * tl(c11.%s, es))) / ws;' % ((ch,) * 5))
    e(' float wm = max(max(max(w00, w10), w01), w11) * 0.100000001490116119384765625f;')
    # motion vector
    if DMV or DIAG == 'nodepth':
        e(' float4 mv = Mv.Load(int3(uint(px), uint(py), 0));' if DIAG == 'nodepth' else ' float4 mv = Mv.Load(int3(x, y, 0));')
    else:
        gt = '>' if INV else '<'
        e(' uint rx = uint(int(round(cx))), ry = uint(int(round(cy)));')
        e(' uint rxm = uint(int(round(bx + (m[1].x * (fx + (-1.0f)))))), rym = uint(int(round(by + (m[1].y * (fy + (-1.0f))))));')
        e(' uint ryp = uint(int(round(by + (m[1].y * (fy + 1.0f))))), rxp = uint(int(round(bx + (m[1].x * (fx + 1.0f)))));')
        # same order as AMD: centre, (-1,-1), (-1,0), (-1,+1), (0,-1), (0,+1), (+1,-1), (+1,0), (+1,+1)
        seq = [('rxm', 'rym'), ('rxm', 'ry'), ('rxm', 'ryp'), ('rx', 'rym'), ('rx', 'ryp'), ('rxp', 'rym'), ('rxp', 'ry'), ('rxp', 'ryp')]
        if GDEP:
            # the 9 taps lie in the 3x3 texels around (rx, ry) (the render/display ratio is <= 1, so rxm, rxp are rx - 1 or rx,
            # rx or rx + 1): 4 gathers fetch them, each tap picks its texel; texels outside the depth texture read 0 as Load
            # does. Same values in the same compare order: the same result. Any other tap layout takes the 9 loads.
            e(' uint dw_, dh_; Depth.GetDimensions(dw_, dh_); float idw = 1.0f / float(dw_), idh = 1.0f / float(dh_);')
            e(' float d; float dd; bool b1, b2, b3, b4, b5, b6, b7, b8;')
            e(' if ((rx - rxm) <= 1u && (rxp - rx) <= 1u && (ry - rym) <= 1u && (ryp - ry) <= 1u) {')
            e('  float4 ga = Depth.GatherRed(Lin, float2(float(rx) * idw, float(ry) * idh)), gb = Depth.GatherRed(Lin, float2(float(rx + 1u) * idw, float(ry) * idh));')
            e('  float4 gc = Depth.GatherRed(Lin, float2(float(rx) * idw, float(ry + 1u) * idh)), gd = Depth.GatherRed(Lin, float2(float(rx + 1u) * idw, float(ry + 1u) * idh));')
            # T(ox, oy): ga = (-1,0) (0,0) (0,-1) (-1,-1) as x y z w; gb: (1,-1) = z, (1,0) = y; gc: (-1,1) = x, (0,1) = y; gd: (1,1) = y
            T = {(-1, -1): 'ga.w', (0, -1): 'ga.z', (-1, 0): 'ga.x', (0, 0): 'ga.y', (1, -1): 'gb.z', (1, 0): 'gb.y', (-1, 1): 'gc.x',
                 (0, 1): 'gc.y', (1, 1): 'gd.y'}
            e('  bool lx = rxm != rx, hx = rxp != rx, ly = rym != ry, hy = ryp != ry;')
            off = {'rxm': ('lx', -1), 'rx': (None, 0), 'rxp': ('hx', 1), 'rym': ('ly', -1), 'ry': (None, 0), 'ryp': ('hy', 1)}
            def tap(a, b):
                (cx, ox), (cy, oy) = off[a], off[b]
                xs = [(ox, True), (0, False)] if cx else [(0, None)]
                ys = [(oy, True), (0, False)] if cy else [(0, None)]
                def pick_y(xo):
                    if not cy: return T[(xo, 0)]
                    return '(%s ? %s : %s)' % (cy, T[(xo, oy)], T[(xo, 0)])
                v = '(%s ? %s : %s)' % (cx, pick_y(ox), pick_y(0)) if cx else pick_y(0)
                return '((%s < dw_ && %s < dh_) ? %s : 0.0f)' % (a, b, v)
            e('  d = %s;' % tap('rx', 'ry'))
            for i, (a_, b_) in enumerate(seq, 1):
                e('  dd = %s; b%d = dd %s d; d = b%d ? dd : d;' % (tap(a_, b_), i, gt, i))
            e(' } else {')
            e('  d = %s;' % DL('rx', 'ry'))
            for i, (a_, b_) in enumerate(seq, 1):
                e('  dd = %s; b%d = dd %s d; d = b%d ? dd : d;' % (DL(a_, b_), i, gt, i))
            e(' }')
        else:
            e(' float d = %s; float dd; bool b1, b2, b3, b4, b5, b6, b7, b8;' % DL('rx', 'ry'))
            for i, (a, b) in enumerate(seq, 1):
                e(' dd = %s; b%d = dd %s d; d = b%d ? dd : d;' % (DL(a, b), i, gt, i))
        e(' uint mx = (b8 || (b7 || b6)) ? rxp : ((b5 || b4) ? rx : ((b3 || (b2 || b1)) ? rxm : rx));')
        e(' uint my = b8 ? ryp : (b7 ? ry : (b6 ? rym : (b5 ? ryp : (b4 ? rym : (b3 ? ryp : (b2 ? ry : (b1 ? rym : ry)))))));')
        if E('SPECMV'):  # fetch the 9 candidate vectors with the depth taps; the last neighbour that won the depth test picks (same as mx/my)
            e(' float4 mv = Mv.Load(int3(rx, ry, 0));')
            for i, (a, b) in enumerate(seq, 1): e(' float4 mv%d = Mv.Load(int3(%s, %s, 0));' % (i, a, b))
            for i in range(1, 9): e(' mv = b%d ? mv%d : mv;' % (i, i))
        else:
            e(' float4 mv = Mv.Load(int3(mx, my, 0));')
    if JIT: e(' float vx = (m[2].x * mv.x) - m[3].z, vy = (m[2].y * mv.y) - m[3].w;')
    else: e(' float vx = m[2].x * mv.x, vy = m[2].y * mv.y;')
    e(' bool ok = false; float ux = 0.0f, uy = 0.0f;')
    e(' if (!(isnan(vx) || isnan(vy))) { if (!(isinf(vx) || isinf(vy))) { bool big = (vx > 1000000.0f) || (vy > 1000000.0f); ux = big ? 0.0f : vx; uy = big ? 0.0f : vy; ok = !big; } }')
    e(' float hr = (RESET != 0u) ? kx : 0.0f, hg = (RESET != 0u) ? ky : 0.0f, hb = (RESET != 0u) ? kz : 0.0f;')
    e(' float o0 = hr, o1 = hg, o2 = hb, r0 = 0.0f, r1 = 0.0f, r2 = 0.0f, r3 = 0.0f;')
    e(' if (ok && RESET == 0u) {')
    e('  float qx = (((abs(ux) <= (m[0].x * 0.03125f)) ? 0.0f : ux) * float(OW)) + fx;')
    e('  float qy = (((abs(uy) <= (m[0].y * 0.03125f)) ? 0.0f : uy) * float(OH)) + fy;')
    e('  float sx = qx + 0.5f, sy = qy + 0.5f; float h0 = hr, h1 = hg, h2 = hb;')
    e('  bool ins = false; if (qx >= 0.0f) { if ((qx <= float(OW + 4294967295u)) && (qy >= 0.0f)) ins = qy <= float(OH + 4294967295u); }')
    e('  if (ins' + (' && false' if DIAG == 'nohist' else '') + ') {')
    e('   float fbx = floor(sx + (-0.5f)), fby = floor(sy + (-0.5f)); float cbx = fbx + 0.5f, cby = fby + 0.5f;')
    e('   float tx = sx - cbx, ty = sy - cby; float tx2 = tx * 0.5f, ty2 = ty * 0.5f;')
    e('   if (tx == 0.0f && ty == 0.0f) { min16float4 hp = min16float4(Hist.Load(int3(int(fbx), int(fby), 0))); min16float4 rc = min16float4(Recur.SampleLevel(Lin, float2(sx / m[2].z, sy / m[2].w), 0.0f)); h0 = float(hp.x); h1 = float(hp.y); h2 = float(hp.z); r0 = float(rc.x); r1 = float(rc.y); r2 = float(rc.z); r3 = float(rc.w); } else {')
    e('   float wx0 = (((1.0f - tx2) * tx) + (-0.5f)) * tx, wy0 = (((1.0f - ty2) * ty) + (-0.5f)) * ty;')
    e('   float txs = tx * tx, tys = ty * ty, tx3 = tx * 1.5f, ty3 = ty * 1.5f;')
    e('   float wxa = (((2.0f - tx3) * tx) + 0.5f) * tx, wya = (((2.0f - ty3) * ty) + 0.5f) * ty;')
    e('   float wx2 = (tx2 + (-0.5f)) * txs, wy2 = (ty2 + (-0.5f)) * tys;')
    e('   float wx1 = (((tx3 + (-2.5f)) * txs) + 1.0f) + wxa, wy1 = (((ty3 + (-2.5f)) * tys) + 1.0f) + wya;')
    e('   float u0 = (fbx + (-0.5f)) / m[2].z, v0 = (fby + (-0.5f)) / m[2].w, u2 = (fbx + 2.5f) / m[2].z, v2 = (fby + 2.5f) / m[2].w;')
    e('   float u1 = ((wxa / wx1) + cbx) / m[2].z, v1 = ((wya / wy1) + cby) / m[2].w;')
    for nm, (u, v) in [('a', ('u0', 'v0')), ('b', ('u1', 'v0')), ('c', ('u2', 'v0')), ('d', ('u0', 'v1')), ('e', ('u1', 'v1')), ('f', ('u2', 'v1')), ('g', ('u0', 'v2')), ('h', ('u1', 'v2')), ('i', ('u2', 'v2'))]:
        if DIAG == 'hist1': u, v = 'u1', 'v1'
        if DIAG == 'nohs': e('   min16float4 s%s = min16float4(%s, %s, %s, 1.0f);' % (nm, u, v, 'wx1')); continue
        e('   min16float4 s%s = min16float4(Hist.SampleLevel(Lin, float2(%s, %s), 0.0f));' % (nm, u, v))
    e('   min16float4 rc = min16float4(Recur.SampleLevel(Lin, float2(sx / m[2].z, sy / m[2].w), 0.0f));')
    for ch in 'xyz':
        e('   float H%s = (((((float(se.%s) * wx1) + (float(sd.%s) * wx0)) + (float(sf.%s) * wx2)) * wy1) + ((((float(sb.%s) * wx1) + (float(sa.%s) * wx0)) + (float(sc.%s) * wx2)) * wy0)) + ((((float(sh.%s) * wx1) + (float(sg.%s) * wx0)) + (float(si.%s) * wx2)) * wy2);' % ((ch,) * 10))
    e('   h0 = Hx; h1 = Hy; h2 = Hz; r0 = float(rc.x); r1 = float(rc.y); r2 = float(rc.z); r3 = float(rc.w);')
    e('   }')
    e('  }')
    if CURVE:
        R = {1: 'sdec(senc(lin(%s)))', 2: 'pq2(pq1(penc(lin(%s))))'}[CURVE]; e('  float ia = 1.0f - wm;')
        e('  o0 = (tl(%s, 150.0f) * ia) + (wm * kx); o1 = (tl(%s, 150.0f) * ia) + (ky * wm); o2 = (tl(%s, 150.0f) * ia) + (kz * wm);' % (R % 'h0', R % 'h1', R % 'h2'))
    elif NL:
        e('  float ia = 1.0f - wm;')
        e('  o0 = (max(h0, 0.0f) * ia) + (wm * kx); o1 = (max(h1, 0.0f) * ia) + (ky * wm); o2 = (max(h2, 0.0f) * ia) + (kz * wm);')
    else:
        e('  float ip = AExp.Load(int3(1, 0, 0)).x / m[5].z; float ia = 1.0f - wm;')
        e('  o0 = (rl(h0, ip, es) * ia) + (wm * kx); o1 = (rl(h1, ip, es) * ia) + (ky * wm); o2 = (rl(h2, ip, es) * ia) + (kz * wm);')
    e(' }')
    e(' min16float o0h = min16float(o0); Reproj[uint2(x, y)] = float4(min16float4(o0h, min16float(o1), min16float(o2), o0h));')
    e(' float lc = ((ky * 0.715200006961822509765625f) + (kx * 0.2125999927520751953125f)) + (kz * 0.072200000286102294921875f);')
    e(' float lh = ((o1 * 0.715200006961822509765625f) + (o0 * 0.2125999927520751953125f)) + (o2 * 0.072200000286102294921875f);')
    e(' float cb_ = (((kz - lc) - o2) + lh) * 0.538909256458282470703125f, cr_ = (((kx - lc) - o0) + lh) * 0.635001242160797119140625f;')
    e(' min16float f0 = (min16float(lc) * min16float(2.0)) + min16float(-1.0), f1 = (min16float(lh) * min16float(2.0)) + min16float(-1.0);')
    e(' min16float f2 = min16float(sqrt(((cr_ * cr_) + 9.9999999747524270787835121154785e-07f) + (cb_ * cb_)));')
    e(' min16float f3 = (min16float(r0) * min16float(2.0)) + min16float(-1.0), f4 = (min16float(r1) * min16float(2.0)) + min16float(-1.0);')
    e(' min16float f5 = (min16float(r2) * min16float(2.0)) + min16float(-1.0), f6 = (min16float(r3) * min16float(2.0)) + min16float(-1.0);')

# model weights (prepass part of the 27392-byte weight buffer), baked in: W[k][pos][f] at 512*yb + 16*xb + 32*k
import numpy as np
WB = np.fromfile(os.environ['WEIGHTS'], np.uint8)
def wh(k, xb, yb, f): o = 512 * yb + 16 * xb + 32 * k + 2 * f; return float(np.frombuffer(WB[o:o + 2].tobytes(), np.float16)[0])
BIAS = np.frombuffer(WB[1024:1088].tobytes(), np.float32)
hf = lambda v: repr(float(np.float16(v)))
W64S0 = E('W64SAFE')
G128 = E('G128'); assert not (G128 and (W64S0 or E('RED3') or E('DTILE') or E('FEAT')))
NT = 128 if G128 else 256   # threads per group: G128 = 16x8 pixels (runtime pass kind pre8), else 16x16
FEAT = E('FEAT') and not E('RED3') and not W64S0 and DIAG not in ('noproj', 'nored')
if FEAT: e('groupshared half Fs[1792];')   # 7 features x 4 positions x 64 blocks
else: e('groupshared float R[%d];' % (3072 if E('RED3') else 16 * NT))
if DTILE: e('groupshared float DTv[%d];' % (DT * DT))
# W64SAFE=1: any wave size (wave64-only GPUs: Vega, Radeon VII, Polaris). The wave index comes from WaveGetLaneCount(); with
# 64 lanes each of the 4 waves holds one 2x2 position for all 64 blocks. No [WaveSize] attribute (the driver picks; RDNA
# picks wave32). Same additions in the same order: in wave32 the output is identical to the default kernel.
W64S = E('W64SAFE'); assert not (W64S and E('RED3'))
e('%s[numthreads(%d,1,1)] void main(uint3 g : SV_GroupID, uint3 t : SV_GroupThreadID) {' % ('' if W64S else '[WaveSize(32)] ', NT))
e(' uint4 iw = asuint(m[4]); uint OW = iw.x, OH = iw.y, RESET = iw.z;')
if W64S: e(' uint ws = firstbitlow(WaveGetLaneCount()), wv = WaveReadLaneFirst(t.x >> ws), pos = wv & 3u, lane = t.x & ((1u << ws) - 1u), b = ((wv >> 2) << ws) | lane;')
else: e(' uint wv = WaveReadLaneFirst(t.x >> 5), pos = wv & 3u, lane = t.x & 31u, b = ((wv >> 2) << 5) | lane;')
e(' uint bx = (g.x << 3) | (b & 7u), by = (g.y << %d) | (b >> 3);' % (2 if G128 else 3))
e(' uint x = 2u * bx + (pos & 1u), y = 2u * by + (pos >> 1);')
if NL: pass
elif AE: e(' float es = (AExp.Load(int3(0, 0, 0)).x / m[5].y) * 150.0f;')
else: e(' float e0 = Expo.Load(int3(0, 0, 0)).x; float es = (((e0 == 0.0f) ? 1.0f : e0) / m[5].y) * 150.0f;')
e(' float acc[16]; [unroll] for (uint c = 0; c < 16u; c++) acc[c] = 0.0f;')
if DTILE:
    e(' int dlx = int(round(((m[1].x * 0.5f) + (-0.5f)) + (m[1].x * (float(g.x * 16u) + (-1.0f))))) - 1, dly = int(round(((m[1].y * 0.5f) + (-0.5f)) + (m[1].y * (float(g.y * 16u) + (-1.0f))))) - 1;')
    e(' for (uint k = t.x; k < %du; k += 256u) { uint j = k / %du, i = k - j * %du; DTv[k] = Depth.Load(int3(uint(dlx + int(i)), uint(dly + int(j)), 0)).x; }' % (DT * DT, DT, DT))
    e(' GroupMemoryBarrierWithGroupSync();')
if FEAT:
    # FEAT: the 7 features of each pixel go to LDS (half, zero outside the image: the same zero sums as the 16-sum
    # exchange); thread t then makes word t >> 6 (channels 4w .. 4w + 3) of block t & 63 from the 4 positions' features with
    # the same multiply-add chains, adds the positions in the same order (precise: kept as written) and stores the word
    e(' min16float F0 = 0, F1 = 0, F2 = 0, F3 = 0, F4 = 0, F5 = 0, F6 = 0;')
    e(' if (x < OW && y < OH) {')
    pixel(e)
    e('  F0 = f0; F1 = f1; F2 = f2; F3 = f3; F4 = f4; F5 = f5; F6 = f6;')
    e(' }')
    for f in range(7): e(' Fs[(%du + pos) * 64u + b] = half(F%d);' % (4 * f, f))
    e(' GroupMemoryBarrierWithGroupSync();')
    e(' uint ob = t.x & 63u, ow = t.x >> 6, obx = (g.x << 3) | (ob & 7u), oby = (g.y << 3) | (ob >> 3);')
    e(' if (2u * obx >= OW || 2u * oby >= OH) return;')
    for w in range(4):
        e(' %sif (ow == %du) {' % ('' if w == 0 else 'else ', w))
        for p in range(4):
            e('  min16float g%d_0 = min16float(Fs[%du + ob])' % (p, (0 * 4 + p) * 64) + ''.join(', g%d_%d = min16float(Fs[%du + ob])' % (p, f, (f * 4 + p) * 64) for f in range(1, 7)) + ';')
        for c in range(4 * w, 4 * w + 4):
            for p in range(4):
                xb, yb = p & 1, p >> 1
                e('  float a%d_%d = 0.0f; ' % (p, c) + ''.join('a%d_%d = mad(float(g%d_%d), %s, a%d_%d); ' % (p, c, p, f, hf(wh(c, xb, yb, f)), p, c) for f in range(7)))
            e('  precise float v%d = ((a0_%d + a1_%d) + a2_%d) + a3_%d;' % (c, c, c, c, c))
        e('  Scratch.Store(%du * (oby + 1u) + 16u * (obx + 1u) + %du, q8(v%d + %sf) | (q8(v%d + %sf) << 8u) | (q8(v%d + %sf) << 16u) | (q8(v%d + %sf) << 24u));' % (ROW, 4 * w, 4*w, repr(float(BIAS[4*w])), 4*w+1, repr(float(BIAS[4*w+1])), 4*w+2, repr(float(BIAS[4*w+2])), 4*w+3, repr(float(BIAS[4*w+3]))))
        e(' }')
    e('}')
    open(sys.argv[1], 'w').write('\n'.join(L) + '\n'); sys.exit(0)
e(' if (x < OW && y < OH) {')
pixel(e)
for p in range(0 if DIAG == 'noproj' else 4):
    xb, yb = p & 1, p >> 1
    e('  %sif (pos == %du) {' % ('' if p == 0 else 'else ', p))
    for k in range(16):
        e('   ' + ''.join('acc[%d] = mad(float(f%d), %s, acc[%d]); ' % (k, f, hf(wh(k, xb, yb, f)), k) for f in range(7)))
    e('  }')
if DIAG == 'noproj': e('  acc[0] = float(f0 + f1 + f2 + f3 + f4 + f5 + f6);')
e(' }')
if DIAG == 'nored':  # timing only: each thread stores its own sums, no LDS exchange
    e(' uint a = %du * (by + 1u) + 16u * (bx + 1u) + 4u * pos;' % ROW)
    e(' Scratch.Store(a, q8(acc[0]) | (q8(acc[5]) << 8u) | (q8(acc[10]) << 16u) | (q8(acc[15]) << 24u));')
    e('}')
    open(sys.argv[1], 'w').write('\n'.join(L) + '\n'); sys.exit(0)
if E('RED3'):  # 12 KB: waves at positions 1-3 hand their sums to the position-0 wave (same addition order)
    e(' if (pos != 0u) { [unroll] for (uint c = 0; c < 16u; c++) R[((pos - 1u) * 16u + c) * 64u + b] = acc[c]; }')
    e(' GroupMemoryBarrierWithGroupSync();')
    e(' if (pos != 0u) return;')
    e(' uint ob = b, obx = bx, oby = by;')
    e(' if (2u * obx >= OW || 2u * oby >= OH) return;')
    e(' float v[16]; [unroll] for (uint c = 0; c < 16u; c++) v[c] = ((acc[c] + R[c * 64u + b]) + R[(16u + c) * 64u + b]) + R[(32u + c) * 64u + b];')
elif E('RED4') and not W64S:
    # the final sums on all 256 threads: thread t finishes word t >> 6 (channels 4w .. 4w + 3) of block t & 63, with the same
    # additions in the same order, and stores that word (the same bytes as the block's 16-byte store)
    e(' [unroll] for (uint c = 0; c < 16u; c++) R[c * %du + t.x] = acc[c];' % NT)
    e(' GroupMemoryBarrierWithGroupSync();')
    if G128: e(' uint ob = t.x & 31u, ow = t.x >> 5, obx = (g.x << 3) | (ob & 7u), oby = (g.y << 2) | (ob >> 3);')
    else: e(' uint ob = t.x & 63u, ow = t.x >> 6, obx = (g.x << 3) | (ob & 7u), oby = (g.y << 3) | (ob >> 3);')
    e(' if (2u * obx >= OW || 2u * oby >= OH) return;')
    e(' uint s0 = %s;' % ('ob' if G128 else '((ob >> 5) << 7) | (ob & 31u)'))
    # word ow per wave (t.x >> 6 is the same in a wave): a uniform branch per word keeps each channel's expression as in the
    # 64-thread reduction (immediate bias), so the compiler makes the same arithmetic of it
    for w in range(4):
        e(' %sif (ow == %du) {' % ('' if w == 0 else 'else ', w))
        for j in range(4):
            c = 4 * w + j
            e('  float v%d = ((R[%d * %du + s0] + R[%d * %du + s0 + 32u]) + R[%d * %du + s0 + 64u]) + R[%d * %du + s0 + 96u];' % (j, c, NT, c, NT, c, NT, c, NT))
        e('  Scratch.Store(%du * (oby + 1u) + 16u * (obx + 1u) + %du, q8(v0 + %sf) | (q8(v1 + %sf) << 8u) | (q8(v2 + %sf) << 16u) | (q8(v3 + %sf) << 24u));' % (ROW, 4*w, repr(float(BIAS[4*w])), repr(float(BIAS[4*w+1])), repr(float(BIAS[4*w+2])), repr(float(BIAS[4*w+3]))))
        e(' }')
    e('}')
    open(sys.argv[1], 'w').write('\n'.join(L) + '\n'); sys.exit(0)
else:
    e(' [unroll] for (uint c = 0; c < 16u; c++) R[c * %du + t.x] = acc[c];' % NT)
    e(' GroupMemoryBarrierWithGroupSync();')
    e(' if (t.x >= %du) return;' % (NT // 4))
    e(' uint ob = t.x, obx = (g.x << 3) | (ob & 7u), oby = (g.y << %d) | (ob >> 3);' % (2 if G128 else 3))
    e(' if (2u * obx >= OW || 2u * oby >= OH) return;')
    if W64S:
        e(' uint W = 1u << ws, s0 = ((ob >> ws) << (ws + 2u)) | (ob & (W - 1u));')
        e(' float v[16]; [unroll] for (uint c = 0; c < 16u; c++) v[c] = ((R[c * 256u + s0] + R[c * 256u + s0 + W]) + R[c * 256u + s0 + 2u * W]) + R[c * 256u + s0 + 3u * W];')
    else:
        e(' uint s0 = %s;' % ('ob' if G128 else '((ob >> 5) << 7) | (ob & 31u)'))
        e(' float v[16]; [unroll] for (uint c = 0; c < 16u; c++) v[c] = ((R[c * %du + s0] + R[c * %du + s0 + 32u]) + R[c * %du + s0 + 64u]) + R[c * %du + s0 + 96u];' % (NT, NT, NT, NT))
e(' uint a = %du * (oby + 1u) + 16u * (obx + 1u);' % ROW)
e(' Scratch.Store4(a, uint4(%s));' % ', '.join('q8(v[%d] + %s) | (q8(v[%d] + %s) << 8u) | (q8(v[%d] + %s) << 16u) | (q8(v[%d] + %s) << 24u)' % (4*w, repr(float(BIAS[4*w])) + 'f', 4*w+1, repr(float(BIAS[4*w+1])) + 'f', 4*w+2, repr(float(BIAS[4*w+2])) + 'f', 4*w+3, repr(float(BIAS[4*w+3])) + 'f') for w in range(4)))
e('}')
open(sys.argv[1], 'w').write('\n'.join(L) + '\n'); print(sys.argv[1], len(L), 'lines', dict(INV=INV, AE=AE, DMV=DMV, JIT=JIT, NL=NL, ROW=ROW))
