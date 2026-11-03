#!/usr/bin/env python3
# Copyright 2026 lonewolf0622. All rights reserved (HelixSR Freeware License).
"""k5_xform.py <kernel> <source dir> <out dir>: faster builds of the translated output kernels: the same operations on the
same values (identical results in the CPU emulator); only where values are kept and which code exists.

k5n -> k5nx and k5nxf (dfn_3x3_256: below a 1.49 scale ratio, incl. native / DLAA), files <name>.hlsl, _body.h, _cfg.h.
  The shaders are built with relaxed floating point (PX_FAST): the GPU compiler contracts and fuses operations by the
  shape of the code around them, so the same source operations give the same GPU results only where the arithmetic
  code stays as it was.
  k5nx   stash (raw), size, order, fp32: offline compiler output has the same arithmetic instructions as the original
         (RDNA 1/2 wave32 and wave64, RDNA 3 wave64, GCN, both 32-bit builds with the GPU's conversion)
  k5nxf  fold, stash (bias added early), size, order, fp32: half the code; the compiler contracts and fuses some
         operations differently (GPU: about half the output values differ in the last bits, PSNR vs the original
         about 60 dB; a gated variant)
  fold   (k5nxf) the optional-path switches at argument words 616 and 620 become 0: HelixSR's launches always pass 0
         there (the host uses k5nxf only for such launches), so the path they select is removed;
  stash  the second 1x1 convolution's results for the last two row groups wait in shared memory instead of registers
         (k5nx: as they are, the bias reloaded from its read-only buffer and added where the original adds it; k5nxf:
         with the bias added early, read back where the original adds it): 10 words per thread at bytes
         [10320, 20560). After its seventh barrier the kernel reads and writes only bytes [0, 10320) of its shared
         memory, and it never uses bytes past 20544;
  size   the shared memory is declared as the 20560 bytes used (was 24576);
  order  the four MMA groups of each 1x1 convolution run row tile by row tile (see _mma_order);
  fp32   32-bit builds use the branch-free fp32 -> fp16 rounding (kernels/rt/px_hlsl.h, HX_F2H_FAST: identical
         results for all inputs).
k5 -> k5x (dfn_mid), k5f -> k5fx (dfn_fastpath): the kernel unchanged with the branch-free rounding; only its 32-bit
  builds are made (HX_FP32_ONLY; the native ones would be the original shader).

Every step checks the shape it expects and stops otherwise (a different kernel source is not transformed)."""
import re
import sys
from pathlib import Path

STASH_BASE = 10320           # first byte of the stash (16-byte aligned)
STASH_WORDS = 10             # per thread
THREADS = 256
SMEM_BYTES = STASH_BASE + STASH_WORDS * THREADS * 4   # 20560
LAST_USED_BYTE = 20544       # the original kernel's highest shared-memory byte + 1 (checked by the CPU tests)


def _one(pattern, repl, text):
    n = len(re.findall(pattern, text))
    if n != 1:
        raise SystemExit(f'k5_xform: {pattern!r}: {n} matches, expected 1')
    return re.sub(pattern, repl, text)


def _mma_order(lines):
    """order: each 1x1 convolution runs as four MMA groups (row tile 0 / 1 x input half 0 / 1, each a 5-line
    '#ifdef PX_FAST' alternative) in the order (0, lo) (1, lo) (0, hi) (1, hi); run them as (0, lo) (0, hi) (1, lo)
    (1, hi). Every accumulator gets the same operations in the same order (the groups of different row tiles share
    no register they write), and row tile 1's accumulators are not live while row tile 0 is computed."""
    def group(i):
        g = lines[i:i + 5]
        if g[0].strip() != '#ifdef PX_FAST' or g[2].strip() != '#else' or g[4].strip() != '#endif':
            return None
        m = re.match(r'\s*compact_(\d+)\((.*)\);$', g[3])
        if not m:
            return None
        args = [a.strip() for a in m.group(2).split(',')]
        n = int(m.group(1))
        return set(args[:2 * n]), set(args[2 * n:]), set(re.findall(r'x_r\d+', g[1]))
    done, i = 0, 0
    while i + 20 <= len(lines):
        gs = [group(i + 5 * k) for k in range(4)]
        if all(gs):
            (d0, r0, f0), (d1, r1, f1), (d2, r2, f2), (d3, r3, f3) = gs
            if d0 != d2 or d1 != d3 or d0 & d1:
                raise SystemExit('k5_xform: unexpected MMA group accumulators')
            # groups 1 and 2 swap: neither may read or write what the other writes
            if (d1 & (r2 | f2)) or (d2 & (r1 | f1)):
                raise SystemExit('k5_xform: MMA groups 1 and 2 depend on each other')
            blk = lines[i:i + 20]
            lines[i:i + 20] = blk[0:5] + blk[10:15] + blk[5:10] + blk[15:20]
            done += 1
            i += 20
        else:
            i += 1
    if done != 2:
        raise SystemExit(f'k5_xform: expected 2 convolutions of 4 MMA groups, found {done}')
    return lines


def body(text, name='k5nx', fold=False, raw=False):
    text = '\n'.join(_mma_order(text.split('\n')))
    if fold:
        text = _one(r'(x_r\d+) = PX_PARAM32\(616u\);', r'\1 = 0u;', text)
        text = _one(r'(x_r\d+) = PX_PARAM32\(620u\);', r'\1 = 0u;', text)
    # stash: the two groups of 10 bias additions of the second convolution's results
    lines = text.split('\n')
    add = re.compile(r'^\s*(x_r\d+) = px_add_f16x2\((x_r\d+), (x_r\d+)\);$')
    groups, i = [], 0
    while i < len(lines):
        if add.match(lines[i]):
            j = i
            while j < len(lines) and add.match(lines[j]):
                j += 1
            if j - i == STASH_WORDS:
                groups.append((i, j))
            i = j
        else:
            i += 1
    if len(groups) != 2:
        raise SystemExit(f'k5_xform: expected 2 groups of {STASH_WORDS} bias additions, found {len(groups)}')
    (a0, a1), (b0, b1) = groups
    first = [add.match(lines[k]).groups() for k in range(a0, a1)]
    later = [add.match(lines[k]).groups() for k in range(b0, b1)]
    if [g[2] for g in later] != [g[2] for g in first]:
        raise SystemExit('k5_xform: the two groups add different bias registers')
    # the later group's inputs and bias must not be written between the two groups (they are read early instead)
    between = '\n'.join(lines[a1:b0])
    for d, c, b in later:
        if re.search(r'\b%s\s*=(?!=)' % c, between) or re.search(r'\b%s\s*=(?!=)' % b, between):
            raise SystemExit(f'k5_xform: {c} or {b} changes between the groups')
        if re.search(r'\b%s\b' % d, between):
            raise SystemExit(f'k5_xform: {d} is used between the groups')
    if between.count('PX_BARRIER()') < 1:
        raise SystemExit('k5_xform: no barrier between the groups')
    if raw:
        # the convolution's results wait in shared memory as they are; the bias words are loaded again from their
        # read-only buffer; the additions stay where they were (the same instructions on the same operands there)
        bias = sorted({b for _, _, b in later}, key=lambda r: int(r[3:]))
        loads = []
        for b in bias:
            k = next((k for k in range(a0) if re.match(r'^\s*%s = PX_GLD32\(5, _a\);$' % b, lines[k])), None)
            if k is None or not lines[k - 1].strip().startswith('{ uint64_t _a = ') or lines[k + 1].strip() != '}':
                raise SystemExit(f'k5_xform: load of bias {b} not found')
            addr = re.findall(r'x_rd\d+', lines[k - 1])
            for r in addr:
                if re.search(r'\b%s\s*=(?!=)' % r, '\n'.join(lines[k + 1:b0])):
                    raise SystemExit(f'k5_xform: {r} changes before the bias is loaded again')
            loads += lines[k - 1:k + 2]
        raws = sorted({c for _, c, _ in later}, key=lambda r: int(r[3:]))
        ins = ['        // row groups 3 and 4: results of the second convolution kept in shared memory until used']
        ins += [f'        k5s_st({n}u, tid.x, {c});' for n, c in enumerate(raws)]
        back = [f'        {c} = k5s_ld({n}u, tid.x);' for n, c in enumerate(raws)] + loads
        lines[b0:b0] = back
        lines[a1:a1] = ins
    else:
        ins = ['        // row groups 3 and 4: bias added here (the same additions), kept in shared memory until used']
        for n, (d, c, b) in enumerate(later):
            ins.append(f'        {d} = px_add_f16x2({c}, {b});')
            ins.append(f'        k5s_st({n}u, tid.x, {d});')
        for n, (d, c, b) in enumerate(later):
            lines[b0 + n] = f'        {d} = k5s_ld({n}u, tid.x);'
        lines[a1:a1] = ins
    text = '\n'.join(lines)
    if text.count('void k5n_body(uint3 tid, uint3 ctaid) {') != 1:
        raise SystemExit('k5_xform: entry point not found')
    text = text.replace('void k5n_body(uint3 tid, uint3 ctaid) {', f'void {name}_body(uint3 tid, uint3 ctaid) {{')
    pre = f'''// shared-memory slots of the stashed results: raw 32-bit words, bytes [{STASH_BASE}, {SMEM_BYTES}), slot k of thread t at
// {STASH_BASE} + k * {THREADS * 4} + t * 4 (unused by the kernel after its seventh barrier)
#if defined(PX_CPP_H) || defined(HX_FP32)
void k5s_st(uint k, uint tx, uint v) {{ PX_STS32({STASH_BASE}u + k * {THREADS * 4}u + tx * 4u, v); }}
uint k5s_ld(uint k, uint tx) {{ return LDS32({STASH_BASE}u + k * {THREADS * 4}u + tx * 4u); }}
#else
// shared memory is typed as fp16 pairs here: bit casts only, so every 32-bit pattern comes back unchanged
void k5s_st(uint k, uint tx, uint v) {{ SM[({STASH_BASE}u + k * {THREADS * 4}u + tx * 4u) >> 2] = asfloat16(uint16_t2((uint16_t)(v & 0xffffu), (uint16_t)(v >> 16))); }}
uint k5s_ld(uint k, uint tx) {{ uint16_t2 h = asuint16(SM[({STASH_BASE}u + k * {THREADS * 4}u + tx * 4u) >> 2]); return (uint)h.x | ((uint)h.y << 16); }}
#endif
'''
    return pre + text


def cfg(text):
    if '#define PX_BLOCK_X 256' not in text or '#define PX_BLOCK_Y 1\n' not in text or '#define PX_BLOCK_Z 1\n' not in text:
        raise SystemExit('k5_xform: unexpected block shape')
    for flag in ('PX_LDS_ROW4', 'PX_LDS_ROW8'):
        if flag in text:
            raise SystemExit(f'k5_xform: {flag} layout not supported')
    return _one(r'#define PX_SMEM_WORDS 6144\b', f'#define PX_SMEM_WORDS {SMEM_BYTES // 4}', text)


def hlsl(text, name='k5nx'):
    text = _one(r'#include "k5n_cfg\.h"', f'#include "{name}_cfg.h"', text)
    text = _one(r'#include "k5n_body\.h"', f'#include "{name}_body.h"', text)
    text = _one(r'\{ k5n_body\(tid, gid\); \}', f'{{ {name}_body(tid, gid); }}', text)
    return '// k5n after tools/k5_xform.py (same results); 32-bit builds: branch-free fp32 -> fp16 rounding\n' \
           '#define HX_F2H_FAST 1\n' + text


def fp32_variant(name, new, src):
    """the unchanged kernel `name` as `new`, built only for 32-bit arithmetic, with the branch-free rounding"""
    b = (src / f'{name}_body.h').read_text()
    if b.count(f'void {name}_body(uint3 tid, uint3 ctaid) {{') != 1:
        raise SystemExit(f'k5_xform: {name} entry point not found')
    b = b.replace(f'void {name}_body(uint3 tid, uint3 ctaid) {{', f'void {new}_body(uint3 tid, uint3 ctaid) {{')
    h = (src / f'{name}.hlsl').read_text()
    h = _one(r'#include "%s_cfg\.h"' % name, f'#include "{new}_cfg.h"', h)
    h = _one(r'#include "%s_body\.h"' % name, f'#include "{new}_body.h"', h)
    h = _one(r'\{ %s_body\(tid, gid\); \}' % name, f'{{ {new}_body(tid, gid); }}', h)
    h = (f'// {name} for 32-bit arithmetic only, with the branch-free fp32 -> fp16 rounding (tools/k5_xform.py)\n'
         '#define HX_FP32_ONLY 1\n#define HX_F2H_FAST 1\n') + h
    return {f'{new}_body.h': b, f'{new}_cfg.h': (src / f'{name}_cfg.h').read_text(), f'{new}.hlsl': h}


def main():
    if len(sys.argv) != 4 or sys.argv[1] not in ('k5n', 'k5', 'k5f'):
        raise SystemExit(__doc__)
    kernel, src, out = sys.argv[1], Path(sys.argv[2]), Path(sys.argv[3])
    out.mkdir(parents=True, exist_ok=True)
    if kernel == 'k5n':
        files = {}
        for name, fold, raw in (('k5nx', False, True), ('k5nxf', True, False)):
            files.update({f'{name}_body.h': body((src / 'k5n_body.h').read_text(), name, fold, raw),
                          f'{name}_cfg.h': cfg((src / 'k5n_cfg.h').read_text()), f'{name}.hlsl': hlsl((src / 'k5n.hlsl').read_text(), name)})
    else:
        files = fp32_variant(kernel, kernel + 'x', src)
    for name, text in files.items():
        (out / name).write_text(text)


if __name__ == '__main__':
    main()
