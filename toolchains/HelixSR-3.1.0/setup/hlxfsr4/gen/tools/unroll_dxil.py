# from tools/unroll_dxil.py (runs on the builder's chain)
"""unroll_dxil.py IN.dxil OUT.dxil [--passes "..."] [--keep DIR]

Fully unroll a compiled shader's loops and turn its local arrays into registers, using DXC's own optimizer
(IDxcOptimizer via tools/dxc_assemble.exe opt). NVIDIA's compiler keeps arrays that are written with loop-variable
indexes in slow local memory; AMD's compiler keeps them in registers, so AMD's loop-based shaders (e.g. middle 7)
run many times slower on NVIDIA. Unrolled, every index is a constant and SROA removes the arrays.
Output is reassembled and checked by DXC's validator.
"""
import argparse, os, re, shutil, subprocess, tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
DEFAULT = ('-mem2reg -instcombine,NoSink=1 -simplifycfg -loop-simplify -lcssa -dxil-loop-unroll '
           '-sroa -instcombine,NoSink=1 -simplifycfg -sroa -gvn -dce -simplifycfg -dce -dxil-dfe -globaldce')


def pin_z(text):
    """The runtime always dispatches Z = 1, so group/thread Z ids are 0. AMD's middle layers use them in loop bounds
    (count = groupId.z + N), which hides the constant trip count from the compiler; replace them with 0."""
    text, n = re.subn(r'call i32 @dx\.op\.(?:groupId|threadId|threadIdInGroup)\.i32\(i32 9[345], i32 2\)', 'add i32 0, 0', text)
    return text, n


def mark_unroll(text):
    """Tag every loop back edge with llvm.loop.unroll.full (what HLSL [unroll] emits), for dxil-loop-unroll."""
    lines = text.split('\n'); seen = {'%0'}; marked = 0
    ids = [int(x) for x in re.findall(r'^!(\d+) = ', text, flags=re.M)]
    nxt = (max(ids) + 1) if ids else 0
    full = nxt; nxt += 1; meta = ['!%d = !{!"llvm.loop.unroll.full"}' % full]
    for i, l in enumerate(lines):
        m = re.match(r'; <label>:(\d+)', l)
        if m: seen.add('%' + m.group(1)); continue
        b = re.match(r'(\s+br (?:i1 \S+, )?label (%\d+)(?:, label (%\d+))?)(.*)$', l)
        if b and any(x in seen for x in (b.group(2), b.group(3)) if x) and '!llvm.loop' not in l:
            lines[i] = b.group(1) + ', !llvm.loop !%d' % nxt + b.group(4)
            meta.append('!%d = distinct !{!%d, !%d}' % (nxt, nxt, full)); nxt += 1; marked += 1
    return '\n'.join(lines) + '\n' + '\n'.join(meta) + '\n', marked


def run(src, dst, passes=DEFAULT, keep=None, ch=None):
    with tempfile.TemporaryDirectory() as t:
        t = Path(keep) if keep else Path(t); t.mkdir(parents=True, exist_ok=True)
        ch.disasm(Path(src), t / 'in.ll')
        raw = (t / 'in.ll').read_text(); mod, n = pin_z(raw[raw.index('target datalayout'):]); mod, nl = mark_unroll(mod)
        (t / 'pinned.ll').write_text(mod)
        ch.tool('assemble', t / 'pinned.ll', t / 'pinned.dxil')
        ch.tool('opt', t / 'pinned.dxil', t / 'opt.bc', *passes.split())
        ch.tool('assemble', t / 'opt.bc', t / 'opt.unsigned')
        Path(dst).parent.mkdir(parents=True, exist_ok=True)
        ch.tool('validate', t / 'opt.unsigned', Path(dst))


