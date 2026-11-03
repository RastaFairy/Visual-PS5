# from tools/lower_sm69.py (convert runs on the builder's chain)
"""lower_sm69.py IN.ll OUT.ll: rewrite SM 6.9 native-vector DXIL ops as their SM 6.8 scalar forms.

- dx.op.{unary,binary,tertiary}.vN<t>  -> N scalar calls + insertelement (same opcode, per component)
- rawBufferVectorLoad.vN<t>            -> rawBufferLoad.<t> with mask (1<<N)-1; extractvalue users rebuilt
- rawBufferVectorStore.vN<t>           -> rawBufferStore.<t> with mask (1<<N)-1
- shader model metadata 6.9 -> 6.8
Every value keeps its name/number, so the rest of the module is untouched. Same math per component.
"""
import re, sys

TY = {'f16': 'half', 'f32': 'float', 'i32': 'i32', 'i16': 'i16', 'f64': 'double', 'i64': 'i64'}
ARITY = {'unary': 1, 'binary': 2, 'tertiary': 3}

def split_args(s):
    out, depth, cur = [], 0, ''
    for ch in s:
        if ch in '<({[': depth += 1
        elif ch in '>)}]': depth -= 1
        if ch == ',' and depth == 0: out.append(cur.strip()); cur = ''
        else: cur += ch
    if cur.strip(): out.append(cur.strip())
    return out

def lower(ll):
    lines = ll.split('\n'); out = []; n = [0]; loads = {}; need = {}  # need: scalar fn name -> (decl text, vector fn attr)
    attr_of = dict(re.findall(r'^declare [^@]*@(dx\.op\.[\w.]+)\(.*\) (#\d+)$', ll, re.M))
    def tmp():
        n[0] += 1; return '%%lw%d' % n[0]
    def build(ind, dst, vty, n_, elems):  # insertelement chain ending in dst
        cur = 'undef'
        for i, e in enumerate(elems):
            name = dst if i == n_ - 1 else tmp()
            out.append('%s%s = insertelement %s %s, %s %s, i32 %d' % (ind, name, vty, cur, vty.split(' x ')[1][:-1], e, i)); cur = name
    for full in lines:
        line = full.split(';', 1)[0].rstrip() if '@dx.op.' in full or 'extractvalue' in full else full  # drop "; Op(args)" comments
        m = re.match(r'^(\s*)(%[\w.]+) = call <(\d+) x (\w+)> @dx\.op\.(unary|binary|tertiary)\.v\d+(\w+)\((.*)\)(\s*;.*)?$', line)
        if m:
            ind, dst, N, st, kind, suf, args = m.group(1), m.group(2), int(m.group(3)), m.group(4), m.group(5), m.group(6), split_args(m.group(7))
            vty = '<%d x %s>' % (N, st); op = args[0]; vals = [a[len(vty):].strip() for a in args[1:]]
            assert all(a.startswith(vty) for a in args[1:]), line
            fn = 'dx.op.%s.%s' % (kind, suf)
            need[fn] = ('declare %s @%s(i32%s)' % (st, fn, ', %s' % st * ARITY[kind]), attr_of['dx.op.%s.v%d%s' % (kind, N, suf)])
            res = []
            for i in range(N):
                ex = []
                for v in vals:
                    t = tmp(); out.append('%s%s = extractelement %s %s, i32 %d' % (ind, t, vty, v, i)); ex.append(t)
                r = tmp(); out.append('%s%s = call %s @%s(%s%s)' % (ind, r, st, fn, op, ''.join(', %s %s' % (st, e) for e in ex))); res.append(r)
            build(ind, dst, vty, N, res); continue
        m = re.match(r'^(\s*)(%[\w.]+) = call %dx\.types\.ResRet\.v(\d+)(\w+) @dx\.op\.rawBufferVectorLoad\.v\d+\w+\((.*)\)(\s*;.*)?$', line)
        if m:
            ind, dst, N, suf, args = m.group(1), m.group(2), int(m.group(3)), m.group(4), split_args(m.group(5))
            assert len(args) == 5, line  # opcode, handle, index, offset, alignment
            fn = 'dx.op.rawBufferLoad.%s' % suf
            need[fn] = ('declare %%dx.types.ResRet.%s @%s(i32, %%dx.types.Handle, i32, i32, i8, i32)' % (suf, fn), attr_of['dx.op.rawBufferVectorLoad.v%d%s' % (N, suf)])
            need['type:' + suf] = None
            out.append('%s%s = call %%dx.types.ResRet.%s @%s(i32 139, %s, %s, %s, i8 %d, %s)' % (ind, dst, suf, fn, args[1], args[2], args[3], (1 << N) - 1, args[4]))
            loads[dst] = (N, suf); continue
        m = re.match(r'^(\s*)(%[\w.]+) = extractvalue %dx\.types\.ResRet\.v(\d+)(\w+) (%[\w.]+), (\d)(\s*;.*)?$', line)
        if m and m.group(5) in loads:
            ind, dst, src, idx = m.group(1), m.group(2), m.group(5), int(m.group(6)); N, suf = loads[src]; st = TY[suf]
            if idx == 1: out.append('%s%s = extractvalue %%dx.types.ResRet.%s %s, 4' % (ind, dst, suf, src)); continue
            ex = []
            for i in range(N):
                t = tmp(); out.append('%s%s = extractvalue %%dx.types.ResRet.%s %s, %d' % (ind, t, suf, src, i)); ex.append(t)
            build(ind, dst, '<%d x %s>' % (N, st), N, ex); continue
        m = re.match(r'^(\s*)call void @dx\.op\.rawBufferVectorStore\.v(\d+)(\w+)\((.*)\)(\s*;.*)?$', line)
        if m:
            ind, N, suf, args = m.group(1), int(m.group(2)), m.group(3), split_args(m.group(4)); st = TY[suf]
            assert len(args) == 6, line  # opcode, handle, index, offset, value, alignment
            vty = '<%d x %s>' % (N, st); v = args[4][len(vty):].strip()
            fn = 'dx.op.rawBufferStore.%s' % suf
            need[fn] = ('declare void @%s(i32, %%dx.types.Handle, i32, i32, %s, %s, %s, %s, i8, i32)' % (fn, st, st, st, st), attr_of['dx.op.rawBufferVectorStore.v%d%s' % (N, suf)])
            ex = []
            for i in range(N):
                t = tmp(); out.append('%s%s = extractelement %s %s, i32 %d' % (ind, t, vty, v, i)); ex.append(t)
            ex += ['undef'] * (4 - N)
            out.append('%scall void @%s(i32 140, %s, %s, %s, %s, i8 %d, %s)' % (ind, fn, args[1], args[2], args[3], ', '.join('%s %s' % (st, e) for e in ex), (1 << N) - 1, args[5]))
            continue
        out.append(full)
    text = '\n'.join(out)
    # drop the vector declarations (now unused) and add the scalar ones that are missing
    text = re.sub(r'^declare [^\n]*@dx\.op\.(?:\w+\.v\d+\w+|rawBufferVector\w+\.\w+)\([^\n]*\n', '', text, flags=re.M)
    decls = ''
    for fn, d in need.items():
        if fn.startswith('type:'):
            suf = fn[5:]
            if '%%dx.types.ResRet.%s = type' % suf not in text:
                text = text.replace('%dx.types.Handle = type { i8* }\n', '%%dx.types.Handle = type { i8* }\n%%dx.types.ResRet.%s = type { %s, %s, %s, %s, i32 }\n' % (suf, *[TY[suf]] * 4), 1)
        elif not re.search(r'^declare [^\n]*@%s\(' % re.escape(fn), text, re.M):
            decls += '%s %s\n\n' % d
    i = text.index('\nattributes #'); text = text[:i + 1] + decls + text[i + 1:]
    assert not re.search(r'@dx\.op\.(?:\w+\.v\d+\w+|rawBufferVector)', text), 'unlowered vector op left'
    ver = re.search(r'^!dx\.version = !\{(![0-9]+)\}', text, re.M).group(1)
    text = re.sub(r'^%s = !\{i32 1, i32 9\}' % ver, '%s = !{i32 1, i32 8}' % ver, text, flags=re.M)
    return text.replace('!{!"cs", i32 6, i32 9}', '!{!"cs", i32 6, i32 8}')

# DXC passes that finish the job: split the remaining vector instructions (fadd <2 x half>, shufflevector, ...)
# into scalars and fold the extract/insert chains this file and the scalarizer leave behind.
OPT = ['-scalarizer', '-instcombine,NoSink=1', '-dce', '-dxil-dfe']
import os as _os
F16CB = _os.environ.get('LOWER_F16CB', '1') == '1'  # weight pairs read as 16-bit CB values (see lower_post)


def lower_post(ll):
    """Second stage, on the scalarizer's output: what it leaves as vectors.
    - bitcast i32 -> <2 x half> (packed fp16 weights): trunc / lshr 16 + bitcast i16 -> half per lane
    - constant tables [N x <4 x i32>] (static const uint4 arrays) move into one weight constant buffer
      (the runtime's per-pass "wcb", bound as a root CBV at b0 or b1): each load <4 x i32> becomes one
      cbufferLoadLegacy of the same 16-byte row. AMD's Windows compiler copies dynamically indexed constant
      arrays into scratch memory (10 KB per thread in the first layer); a CBV row read needs no copy.
    Returns (text, wcb bytes or None, wcb register). Run OPT again afterwards to fold the insert/extract chains."""
    n = [0]
    def tmp():
        n[0] += 1; return '%%lp%d' % n[0]
    tables = {}; rows = []
    def take(m):
        name, N, body = m.group(1), int(m.group(2)), m.group(3)
        vals = [int(v) & 0xffffffff for v in re.findall(r'i32 (-?\d+)', body)] if body.strip() != 'zeroinitializer' else [0] * (4 * N)
        assert len(vals) == 4 * N, name
        tables[name] = len(rows); rows.extend(vals[i:i + 4] for i in range(0, 4 * N, 4))
        return ''
    ll = re.sub(r'^(@\w+) = internal unnamed_addr constant \[(\d+) x <4 x i32>\] (\[.*\]|zeroinitializer)(?:, align \d+)?\n', take, ll, flags=re.M)
    assert len(rows) <= 4096, 'tables exceed 64 KB'
    used = [int(r) for r in re.findall(r'^!\d+ = !\{i32 \d+, %[^*]+\* undef, !"[^"]*", i32 0, i32 (\d+), i32 1, i32 \d+, null\}$', ll, re.M)]
    reg = 0 if 0 not in used else 1
    assert not rows or reg not in used, 'b0 and b1 both in use'
    size = 16 * len(rows)
    out = []; geps = {}; loads16 = {}; ext = {}
    for line in ll.split('\n'):
        if rows and line.startswith('define void @main'):
            out += [line, '  %%wcb0 = call %%dx.types.Handle @dx.op.createHandleFromBinding(i32 217, %%dx.types.ResBind { i32 %d, i32 %d, i32 0, i8 2 }, i32 %d, i1 false)' % (reg, reg, reg),
                    '  %%wcbh = call %%dx.types.Handle @dx.op.annotateHandle(i32 216, %%dx.types.Handle %%wcb0, %%dx.types.ResourceProperties { i32 13, i32 %d })' % size]
            continue
        code = line.split(';', 1)[0].rstrip()
        m = re.match(r'^\s*(%[\w.]+) = extractelement <4 x i32> (%[\w.]+), i32 (\d)$', code)
        if m and m.group(2) in loads16: ext[m.group(1)] = (loads16[m.group(2)], int(m.group(3)))
        m = re.match(r'^(\s*)(%[\w.]+) = bitcast i32 (%[\w.]+) to <2 x half>$', code)
        if m and m.group(3) in ext and F16CB:  # weight pair straight from the CB as two halves of one dword
            ind, dst, src = m.groups(); r16, k = ext[src]; lo, h, a = tmp(), tmp(), tmp()
            out += ['%s%s = extractvalue %%dx.types.CBufRet.f16.8 %s, %d' % (ind, lo, r16, 2 * k),
                    '%s%s = extractvalue %%dx.types.CBufRet.f16.8 %s, %d' % (ind, h, r16, 2 * k + 1),
                    '%s%s = insertelement <2 x half> undef, half %s, i32 0' % (ind, a, lo),
                    '%s%s = insertelement <2 x half> %s, half %s, i32 1' % (ind, dst, a, h)]
            continue
        if m:
            ind, dst, src = m.groups(); lo16, hi, hi16, lo, h = tmp(), tmp(), tmp(), tmp(), tmp()
            a, b = tmp(), tmp()
            out += ['%s%s = trunc i32 %s to i16' % (ind, lo16, src), '%s%s = bitcast i16 %s to half' % (ind, lo, lo16),
                    '%s%s = lshr i32 %s, 16' % (ind, hi, src), '%s%s = trunc i32 %s to i16' % (ind, hi16, hi),
                    '%s%s = bitcast i16 %s to half' % (ind, h, hi16),
                    '%s%s = insertelement <2 x half> undef, half %s, i32 0' % (ind, a, lo),
                    '%s%s = insertelement <2 x half> %s, half %s, i32 1' % (ind, dst, a, h)]
            continue
        m = re.match(r'^(\s*)(%[\w.]+) = getelementptr inbounds \[(\d+) x <4 x i32>\], \[\d+ x <4 x i32>\]\* (@\w+), i32 0, i32 (%[\w.]+|\d+)$', code)
        if m and m.group(4) in tables:
            ind, dst, N, g, idx = m.groups()
            out.append('%s%s = add i32 %s, %d' % (ind, dst, idx, tables[g]))  # row in the weight CB; same name, now an i32
            geps[dst] = 1; continue
        m = re.match(r'^(\s*)(%[\w.]+) = load <4 x i32>, <4 x i32>\* (%[\w.]+), align (\d+)', code)
        if m:
            ind, dst, p, al = m.groups(); assert p in geps, line
            r = tmp(); cur = 'undef'
            out.append('%s%s = call %%dx.types.CBufRet.i32 @dx.op.cbufferLoadLegacy.i32(i32 59, %%dx.types.Handle %%wcbh, i32 %s)' % (ind, r, p))
            if F16CB:
                r16 = tmp(); loads16[dst] = r16
                out.append('%s%s = call %%dx.types.CBufRet.f16.8 @dx.op.cbufferLoadLegacy.f16(i32 59, %%dx.types.Handle %%wcbh, i32 %s)' % (ind, r16, p))
            for k in range(4):
                v = tmp(); out.append('%s%s = extractvalue %%dx.types.CBufRet.i32 %s, %d' % (ind, v, r, k))
                nm = dst if k == 3 else tmp()
                out.append('%s%s = insertelement <4 x i32> %s, i32 %s, i32 %d' % (ind, nm, cur, v, k)); cur = nm
            continue
        assert not re.search(r'<\d+ x i32>\]\*', code), 'unhandled table use: ' + line
        out.append(line)
    text = '\n'.join(out)
    if not rows: return text, None, reg
    if '%dx.types.CBufRet.i32 = type' not in text:
        text = text.replace('%dx.types.Handle = type { i8* }\n', '%dx.types.Handle = type { i8* }\n%dx.types.CBufRet.i32 = type { i32, i32, i32, i32 }\n', 1)
    text = text.replace('%dx.types.Handle = type { i8* }\n', '%%hlsl.WCB = type { [%d x i32] }\n%%dx.types.Handle = type { i8* }\n' % (4 * len(rows)), 1)
    ro = re.search(r'attributes #(\d+) = \{ nounwind readonly \}', text).group(1)
    if not re.search(r'^declare %dx\.types\.CBufRet\.i32 @dx\.op\.cbufferLoadLegacy\.i32', text, re.M):
        i = text.index('\nattributes #'); text = text[:i + 1] + 'declare %%dx.types.CBufRet.i32 @dx.op.cbufferLoadLegacy.i32(i32, %%dx.types.Handle, i32) #%s\n' % ro + text[i + 1:]
    if F16CB:
        if '%dx.types.CBufRet.f16.8 = type' not in text:
            text = text.replace('%dx.types.Handle = type { i8* }\n', '%dx.types.Handle = type { i8* }\n%dx.types.CBufRet.f16.8 = type { half, half, half, half, half, half, half, half }\n', 1)
        if not re.search(r'^declare %dx\.types\.CBufRet\.f16\.8 @dx\.op\.cbufferLoadLegacy\.f16', text, re.M):
            i = text.index('\nattributes #'); text = text[:i + 1] + 'declare %%dx.types.CBufRet.f16.8 @dx.op.cbufferLoadLegacy.f16(i32, %%dx.types.Handle, i32) #%s\n' % ro + text[i + 1:]
    # resources: !dx.resources = !{!R}; !R = !{srv, uav, cbv, sampler}
    rnode = re.search(r'^!dx\.resources = !\{!(\d+)\}', text, flags=re.M).group(1)
    m = re.search(r'^!%s = !\{(.*)\}$' % rnode, text, flags=re.M)
    parts = [p.strip() for p in m.group(1).split(',')]
    nid = max(int(x) for x in re.findall(r'^!(\d+) = ', text, flags=re.M)) + 1
    if parts[2] == 'null':
        new = ['!%d = !{i32 0, %%hlsl.WCB* undef, !"", i32 0, i32 %d, i32 1, i32 %d, null}' % (nid, reg, size), '!%d = !{!%d}' % (nid + 1, nid)]
        parts[2] = '!%d' % (nid + 1)
        text = text.replace(m.group(0), '!%s = !{%s}' % (rnode, ', '.join(parts)))
    else:
        lm = re.search(r'^!%s = !\{(.*)\}$' % parts[2][1:], text, flags=re.M)
        items = [x.strip() for x in lm.group(1).split(',')]
        new = ['!%d = !{i32 %d, %%hlsl.WCB* undef, !"", i32 0, i32 %d, i32 1, i32 %d, null}' % (nid, len(items), reg, size)]
        text = text.replace(lm.group(0), '!%s = !{%s}' % (parts[2][1:], ', '.join(items + ['!%d' % nid])))
    data = b''.join(v.to_bytes(4, 'little') for row in rows for v in row)
    return text + '\n' + '\n'.join(new) + '\n', data, reg

def convert(src, dst, ch, root):
    """cs_6_9 DXIL file -> validated cs_6_8 DXIL file. Returns None if src is already <= 6.8 (nothing written),
    else the config keys for the pass ({} or {'wcb': ..., 'wcb_reg': ...}; the weight CB goes next to dst).
    ch: the HLX FSR 4 builder's chain (DXC + dxc_assemble); root: what the config paths are relative to."""
    import tempfile
    from pathlib import Path
    dst = Path(dst)
    def build(ll, t, name):  # assemble -> OPT -> assemble; returns the unsigned container
        (t/(name + '.ll')).write_text(ll)
        ch.tool('assemble', t/(name + '.ll'), t/(name + '.u'))
        ch.tool('opt', t/(name + '.u'), t/(name + '.bc'), *OPT)
        ch.tool('assemble', t/(name + '.bc'), t/(name + '2.u'))
        return t/(name + '2.u')
    def dis(p, t):
        s = ch.disasm(p, t/'dis.ll'); return s[s.index('target datalayout'):]
    with tempfile.TemporaryDirectory() as t:
        t = Path(t); ll = dis(src, t)
        if '!{!"cs", i32 6, i32 9}' not in ll: return None
        text, wcb, reg = lower_post(dis(build(lower(ll), t, 'a'), t))
        dst.parent.mkdir(parents=True, exist_ok=True)
        ch.tool('validate', build(text, t, 'b'), dst)
    if not wcb: return {}
    wp = dst.with_suffix('.wcb.bin'); wp.write_bytes(wcb)
    return {'wcb': wp.resolve().relative_to(Path(root).resolve()).as_posix(), 'wcb_reg': reg}

