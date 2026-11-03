#!/usr/bin/env python3
"""Shadow packed fp16 values with their fp32 values in generated HX_FP32 output passes (no arithmetic change).

On GPUs without native 16-bit ops the generated code keeps fp16 pairs packed in uints: every f16x2 operation unpacks
its operands (f16tof32), computes in fp32, and repacks with the exact software rounding hx_f2h; split halves are
unpacked again with px_h2f. This pass keeps, next to each packed variable R, two floats R_l / R_h that always equal
f16tof32(R) / f16tof32(R >> 16), and lets consumers read them directly:

  - f16x2 add/sub/mul/fma (and relu of an fma) compute from the shadows, the new shadows are hx_r16(result) and the
    packed bits are still produced by the original expression from the same fp32 results;
  - (hx_f2h(a) | hx_f2h(b) << 16) packs set the shadows to hx_r16(a), hx_r16(b);
  - any other assignment to R refreshes its shadows from its bits;
  - split halves RS = R & 0xffff / R >> 16 take the matching shadow, and px_h2f(RS) reads it.

hx_r16(f) == f16tof32(hx_f2h(f)) for all 2^32 inputs is checked on the target GPU (source/tests/windows_r16_probe.hlsl),
so every value the program computes is unchanged; unused packing and unpacking is left to dead-code elimination.
Variables passed to any function that could modify them are not shadowed.
"""
import re
from pathlib import Path

R = r'x_r\d+'
RS = r'x_rs\d+'
OPS = {'add': '{0} + {1}', 'sub': '{0} - {1}', 'mul': '{0} * {1}', 'fma': 'mad({0}, {1}, {2})'}
F16X2 = re.compile(r'^(\s*)(' + R + r') = (px_relu_f16x2\()?px_(add|sub|mul|fma)_f16x2\(([^()]*)\)(\))?;\s*$')
PACK = re.compile(r'^(\s*)(' + R + r') = \(px_f2h\(asfloat\((x_f\d+)\)\) \| \(px_f2h\(asfloat\((x_f\d+)\)\) << 16\)\);\s*$')
SPLIT = re.compile(r'^(\s*)(' + RS + r') = \(\((' + R + r') (& 0xffffU|>> 16)\)\) & 0xffffU;\s*$')
UNPACK = re.compile(r'px_h2f\((' + RS + r')\)')
# functions taking INOUT / out parameters in the generated code and runtime (a variable passed to them may change)
MUTATORS = re.compile(r'\b(compact_\d+|pxr_\w+|px_ldmatrix\w*|px_mma\w*|px_mmar\w*|px_shfl\w*|Interlocked\w*)\s*\(')


def lanes(var, shadowed):
    if var in shadowed:
        return var + '_l', var + '_h'
    if re.fullmatch(R, var):
        return f'f16tof32({var})', f'f16tof32({var} >> 16)'
    m = re.fullmatch(r'0x([0-9A-Fa-f]+)U', var)
    if m:
        v = int(m[1], 16)
        return f'f16tof32({v & 0xffff}u)', f'f16tof32({v >> 16}u)'
    raise ValueError('Unexpected f16x2 operand ' + var)


def relu(expr):
    # px_relu_h on the bits: NaN -> 0x7fff, sign set (incl. -0) -> +0; f16tof32 of any fp16 NaN is HX_R16_NAN
    return f'hx_relu_shadow({expr})'


def transform(text: str, entry: str):
    start = text.index(entry)
    head, body = text[:start], text[start:]
    lines = body.split('\n')
    # Candidates: packed variables that are split or used as f16x2 operands, and the split halves.
    packed, halves = set(), set()
    for line in lines:
        m = SPLIT.match(line)
        if m:
            packed.add(m[3]); halves.add(m[2])
        m = F16X2.match(line)
        if m:
            packed.add(m[2])
            packed.update(a.strip() for a in m[5].split(',') if re.fullmatch(R, a.strip()))
        m = PACK.match(line)
        if m:
            packed.add(m[2])
    unsafe = set()
    for line in lines:
        if MUTATORS.search(line):
            unsafe.update(re.findall(r'\b(?:' + R + '|' + RS + r')\b', line))
    packed -= unsafe
    halves -= unsafe
    out, declared, stats = [], False, {'f16x2': 0, 'pack': 0, 'refresh': 0, 'split': 0, 'unpack': 0}
    assign_any = re.compile(r'\b(' + R + '|' + RS + r')\s*=(?!=)')
    for index, line in enumerate(lines):
        if index == 0:
            out.append(line)
            continue
        if not declared and re.match(r'\s*(uint|int|float|bool|uint64_t|int64_t)\b', line):
            out.append(line)   # declaration block: zero initializers match the zero shadows
            continue
        if not declared:
            # end of the declaration block: shadows start at +0, the value of zero bits
            decl = sorted(packed, key=lambda v: int(v[3:]))
            for i in range(0, len(decl), 8):
                out.append('    float ' + ', '.join(f'{v}_l = 0.0f, {v}_h = 0.0f' for v in decl[i:i + 8]) + ';')
            hs = sorted(halves, key=lambda v: int(v[4:]))
            for i in range(0, len(hs), 16):
                out.append('    float ' + ', '.join(f'{v}_f = 0.0f' for v in hs[i:i + 16]) + ';')
            declared = True
        m = F16X2.match(line)
        if m and m[2] in packed:
            ind, dst, has_relu, op, args, _ = m.groups()
            args = [a.strip() for a in args.split(',')]
            lo = OPS[op].format(*[lanes(a, packed)[0] for a in args])
            hi = OPS[op].format(*[lanes(a, packed)[1] for a in args])
            fma = op == 'fma'
            # original semantics: bits = px_h2v(result pair) (relu applied to the bits afterwards)
            bits = 'px_h2v(float2(_sl, _sh))'
            if has_relu:
                bits = f'px_relu_f16x2({bits})'
            shl, shh = 'hx_r16(_sl)', 'hx_r16(_sh)'
            if has_relu:
                shl, shh = relu(shl), relu(shh)
            out.append(f'{ind}{{ float _sl = {lo}, _sh = {hi}; {dst} = {bits}; {dst}_l = {shl}; {dst}_h = {shh}; }}')
            stats['f16x2'] += 1
            continue
        m = PACK.match(line)
        if m and m[2] in packed:
            out.append(line)
            out.append(f'{m[1]}{m[2]}_l = hx_r16(asfloat({m[3]})); {m[2]}_h = hx_r16(asfloat({m[4]}));')
            stats['pack'] += 1
            continue
        m = SPLIT.match(line)
        if m and m[2] in halves:
            out.append(line)
            src = m[3]
            if src in packed:
                out.append(f'{m[1]}{m[2]}_f = {src}_l;' if m[4].startswith('&') else f'{m[1]}{m[2]}_f = {src}_h;')
            else:
                out.append(f'{m[1]}{m[2]}_f = f16tof32({m[2]});')
            stats['split'] += 1
            continue
        if any(v in halves for v in UNPACK.findall(line)):
            n = 0
            def repl(mm):
                nonlocal n
                if mm[1] in halves:
                    n += 1
                    return '(' + mm[1] + '_f)'
                return mm[0]
            line = UNPACK.sub(repl, line)
            stats['unpack'] += n
        targets = [v for v in assign_any.findall(line) if v in packed or v in halves]
        out.append(line)
        if targets:
            if not line.rstrip().endswith((';', '}')):
                raise ValueError('Multi-line assignment: ' + line)
            ind = re.match(r'\s*', line)[0]
            for v in dict.fromkeys(targets):
                if v in packed:
                    out.append(f'{ind}{v}_l = f16tof32({v}); {v}_h = f16tof32({v} >> 16);')
                else:
                    out.append(f'{ind}{v}_f = f16tof32({v});')
                stats['refresh'] += 1
    stats.update(packed=len(packed), halves=len(halves), excluded=len(unsafe))
    return head + '\n'.join(out), stats


def apply(path: Path):
    text = path.read_text()
    m = re.search(r'void (k5f?x_s\d+_body)\(uint3 tid, uint3 ctaid\) \{', text)
    if not m:
        raise ValueError('Pass entry absent: ' + str(path))
    new, stats = transform(text, m[0])
    path.write_text(new)
    return stats
