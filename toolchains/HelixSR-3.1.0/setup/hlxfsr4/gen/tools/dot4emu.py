# from tools/dot4emu.py (convert runs on the builder's chain)
"""dot4emu.py IN.dxil OUT.dxil int|f32 : replace every dot4AddPacked(acc, a, b) (signed int8 x4 dot product) by exact
arithmetic, for GPUs without INT8 dot instructions (Polaris, Vega 56/64), where the driver has to emulate it anyway.
  int: acc + sum sext(a_i) * sext(b_i)      (32-bit integer multiply-adds)
  f32: the same in fp32 (fmul/fadd), the accumulator chain kept in float until an integer use. Exact while every partial
       sum stays below 2^24 in magnitude (int8 x int8 products, the network's sums) - check the output hash.
Byte extracts of shared activation words and constant weights are folded/shared by the DXC passes run afterwards.
Needs DXC_DIR.
"""
import os, re, subprocess, sys, tempfile
from pathlib import Path

OPT = ['-instcombine,NoSink=1', '-gvn', '-dce']


def rewrite(ll, mode):
    out = []; n = [0]; twin = {}
    def t():
        n[0] += 1; return '%%e4_%d' % n[0]
    for line in ll.split('\n'):
        code = line.split(';', 1)[0].rstrip()
        m = re.match(r'^(\s*)(%[\w.]+) = call i32 @dx\.op\.dot4AddPacked\.i32\(i32 \d+, i32 ([%\w.-]+), i32 ([%\w.-]+), i32 ([%\w.-]+)\)$', code)
        if not m: out.append(line); continue
        ind, dst, acc, a, b = m.groups()
        def byte(v, i):
            s, r = t(), t(); out.append('%s%s = shl i32 %s, %d' % (ind, s, v, 24 - 8 * i)); out.append('%s%s = ashr i32 %s, 24' % (ind, r, s)); return r
        if mode == 'int':
            cur = acc
            for i in range(4):
                p, q = t(), t()
                out.append('%s%s = mul i32 %s, %s' % (ind, p, byte(a, i), byte(b, i))); out.append('%s%s = add i32 %s, %s' % (ind, q, cur, p)); cur = q
            out.append('%s%s = add i32 %s, 0' % (ind, dst, cur))
        else:
            if acc in twin: cf = twin[acc]
            else: cf = t(); out.append('%s%s = sitofp i32 %s to float' % (ind, cf, acc))
            for i in range(4):
                fa, fb, p, q = t(), t(), t(), t()
                out.append('%s%s = sitofp i32 %s to float' % (ind, fa, byte(a, i))); out.append('%s%s = sitofp i32 %s to float' % (ind, fb, byte(b, i)))
                # fast: products and sums are exact integers below 2^24, so fusing (v_fmac) or reordering changes nothing
                if mode == 'fma':   # one FMad per product: the chain stays a chain (no reassociated product trees)
                    out.append('%s%s = call float @dx.op.tertiary.f32(i32 46, float %s, float %s, float %s)' % (ind, q, fa, fb, cf)); cf = q; continue
                out.append('%s%s = fmul fast float %s, %s' % (ind, p, fa, fb)); out.append('%s%s = fadd fast float %s, %s' % (ind, q, cf, p)); cf = q
            twin[dst] = cf
            out.append('%s%s = fptosi float %s to i32' % (ind, dst, cf))
    text = '\n'.join(out)
    if mode == 'fma' and 'declare float @dx.op.tertiary.f32(' not in text:
        text = text.replace('declare i32 @dx.op.dot4AddPacked.i32(', 'declare float @dx.op.tertiary.f32(i32, float, float, float) #0\ndeclare i32 @dx.op.dot4AddPacked.i32(', 1)
    return re.sub(r'^declare i32 @dx\.op\.dot4AddPacked\.i32\([^\n]*\n', '', text, flags=re.M)


def convert(src, dst, mode, ch):
    """ch: the HLX FSR 4 builder's chain"""
    with tempfile.TemporaryDirectory() as tdir:
        tdir = Path(tdir)
        s = ch.disasm(Path(src), tdir/'in.ll'); s = s[s.index('target datalayout'):]
        if '@dx.op.dot4AddPacked' not in s: Path(dst).write_bytes(Path(src).read_bytes()); return False
        (tdir/'o.ll').write_text(rewrite(s, mode))
        ch.tool('assemble', tdir/'o.ll', tdir/'o.u')
        ch.tool('opt', tdir/'o.u', tdir/'o.bc', *OPT)
        ch.tool('assemble', tdir/'o.bc', tdir/'o2.u')
        Path(dst).parent.mkdir(parents=True, exist_ok=True)
        ch.tool('validate', tdir/'o2.u', Path(dst))
    return True


