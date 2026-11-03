# from tools/pascal_opt.py (runs on the builder's chain)
"""pascal_opt.py IN.dxil OUT.dxil --model 0|1 [--no-unroll] [--no-bake] [--keep DIR]

NVIDIA-friendly rewrite of one compiled shader, output bit-exact to the input on any GPU:
 1. unroll: pin Z ids to 0 and fully unroll loops (tools/unroll_dxil.py), so local arrays become registers
 2. bake:   loads from the weights buffer (t21) at constant addresses become the weight values themselves.
            The runtime always fills t21 with kWeights[model] (fam/w/weights_std.bin / weights_ultra.bin), so a
            baked shader is only valid for that model; configs of the other model need their own copy.
Pascal can issue far fewer loads than math ops, and the stock shaders fetch every weight per thread.
"""
import argparse, os, re, struct, subprocess, tempfile
from pathlib import Path
import unroll_dxil



def bake(text, w):
    """Replace constant-address raw loads from the t21 weights buffer with insertvalue chains of the weight words."""
    # handle(s) bound to SRV register t21: createHandle(i32 57, i8 0 (SRV), i32 rangeId, ...) with rangeId -> !dx.resources
    srv_ids = {}
    for m in re.finditer(r'^!(\d+) = !\{i32 (\d+), %struct\.ByteAddressBuffer\* undef, !"[^"]*", i32 0, i32 21,', text, flags=re.M):
        srv_ids[int(m.group(2))] = True
    handles = set(m.group(1) for m in re.finditer(r'(%\d+) = call %dx\.types\.Handle @dx\.op\.createHandle\(i32 57, i8 0, i32 (\d+),', text) if int(m.group(2)) in srv_ids)
    if not handles: return text, 0
    out, n = [], 0
    for l in text.split('\n'):
        m = re.match(r'(\s+)(%\d+) = call %dx\.types\.ResRet\.i32 @dx\.op\.rawBufferLoad\.i32\(i32 139, %dx\.types\.Handle (%\d+), i32 (\d+), i32 undef, i8 (\d+), i32 4\)', l)
        if m and m.group(3) in handles:
            ind, name, addr = m.group(1), m.group(2), int(m.group(4))
            assert addr % 4 == 0 and addr + 16 <= len(w) + 12, addr
            vals = [struct.unpack_from('<i', w, addr + 4 * k)[0] if addr + 4 * k + 4 <= len(w) else 0 for k in range(4)]
            k = name[1:]; prev = 'undef'
            for c in range(4):
                dst = name if c == 3 else '%%bw%s_%d' % (k, c)
                out.append('%s%s = insertvalue %%dx.types.ResRet.i32 %s, i32 %d, %d' % (ind, dst, prev, vals[c], c)); prev = dst
            n += 1; continue
        out.append(l)
    return '\n'.join(out), n


FOLD = '-instcombine,NoSink=1 -simplifycfg -gvn -dce -dxil-dfe -globaldce'


def run(src, dst, model, weights, ch, do_unroll=True, do_bake=True, keep=None):
    """weights: [weights_std.bin, weights_ultra.bin] paths; ch: the builder's chain"""
    with tempfile.TemporaryDirectory() as t:
        t = Path(keep) if keep else Path(t); t.mkdir(parents=True, exist_ok=True)
        cur = Path(src)
        if do_unroll:
            unroll_dxil.run(cur, t / 'unrolled.dxil', keep=t / 'u', ch=ch); cur = t / 'unrolled.dxil'
        if do_bake:
            ch.disasm(cur, t / 'b.ll')
            raw = (t / 'b.ll').read_text(); mod, n = bake(raw[raw.index('target datalayout'):], Path(weights[model]).read_bytes())
            (t / 'baked.ll').write_text(mod)
            ch.tool('assemble', t / 'baked.ll', t / 'baked.dxil')
            ch.tool('opt', t / 'baked.dxil', t / 'folded.bc', *FOLD.split())
            ch.tool('assemble', t / 'folded.bc', t / 'folded.unsigned')
            cur = t / 'folded.unsigned'
        Path(dst).parent.mkdir(parents=True, exist_ok=True)
        ch.tool('validate', cur, Path(dst))


