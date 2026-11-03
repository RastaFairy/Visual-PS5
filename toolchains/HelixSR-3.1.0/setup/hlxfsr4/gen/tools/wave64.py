# from tools/wave64.py (convert runs on the builder's chain)
"""wave64.py IN.dxil OUT.dxil : force wave64 on a compute shader (emulates wave64-only GPUs - Vega, Radeon VII,
Polaris - on an RDNA card, which otherwise picks wave32 or follows [WaveSize(32)]). Needs DXC_DIR.

Sets the entry point's wave size to 64: SM 6.8 tag 23 (WaveSizeRange) -> {64, 0, 0}; SM 6.6/6.7 tag 11 -> {64};
no tag -> adds tag 11, raising the shader model (and DXIL version) to 6.6 if lower. Same instructions otherwise;
DXC's validator checks the result.
"""
import os, re, subprocess, sys, tempfile
from pathlib import Path


KIND = {'Texture1D': 1, 'Texture2D': 2, 'Texture2DMS': 3, 'Texture3D': 4, 'TextureCube': 5, 'Texture1DArray': 6,
        'Texture2DArray': 7, 'TypedBuffer': 10, 'RawBuffer': 11, 'StructuredBuffer': 12}
SHAPE = {1: 'Texture1D', 2: 'Texture2D', 3: 'Texture2DMS', 4: 'Texture3D', 5: 'TextureCube', 6: 'Texture1DArray',
         7: 'Texture2DArray', 10: 'TypedBuffer', 11: 'RawBuffer', 12: 'StructuredBuffer'}


def modern_handles(ll):
    """SM <= 6.5 createHandle (op 57) -> SM 6.6 createHandleFromBinding (217) + annotateHandle (216), resource
    properties built from the !dx.resources metadata (needed before raising a shader to 6.6)."""
    rn = re.search(r'^!dx\.resources = !\{!(\d+)\}', ll, re.M).group(1)
    lists = [x.strip() for x in re.search(r'^!%s = !\{(.*)\}$' % rn, ll, re.M).group(1).split(',')]
    node = lambda n: re.search(r'^!%s = !\{(.*)\}$' % n, ll, re.M).group(1)
    res = {}
    for cls, ln in enumerate(lists):
        if ln == 'null': continue
        for en in [x.strip()[1:] for x in node(ln[1:]).split(',')]:
            f = [x.strip() for x in re.split(r',(?![^<]*>)', node(en))]
            rid, ty, space, lb, size = int(f[0].split()[1]), f[1], int(f[3].split()[1]), int(f[4].split()[1]), int(f[5].split()[1])
            if cls == 2: props = (13, int(f[6].split()[1]))
            elif cls == 3: props = (14 | ((1 << 15) if int(f[6].split()[1]) == 1 else 0), 0)
            else:
                shape = int(f[6].split()[1]); kind = shape; p1 = 0
                extra = f[-1]
                if extra != 'null':
                    tags = [x.strip() for x in node(extra[1:]).split(',')]
                    tv = dict(zip(tags[0::2], tags[1::2]))
                    if 'i32 0' in tv:  # element type
                        cnt = re.search(r'vector<\w+, (\d)>', ty); p1 = int(tv['i32 0'].split()[1]) | ((int(cnt.group(1)) if cnt else 1) << 8)
                    if 'i32 1' in tv: p1 = int(tv['i32 1'].split()[1])  # structured stride
                p0 = kind | ((1 << 12) if cls == 1 else 0)
                if cls == 1 and f[7] == 'i1 true': p0 |= 1 << 14  # globally coherent
                props = (p0, p1)
            res[(cls, rid)] = (lb, lb + size - 1 if size >= 0 else -1, space, props)
    n = [0]
    def rep(m):
        ind, dst, cls, rid, idx, nu = m.groups(); lb, ub, sp, (p0, p1) = res[(int(cls), int(rid))]; n[0] += 1
        return ('%s%%hb%d = call %%dx.types.Handle @dx.op.createHandleFromBinding(i32 217, %%dx.types.ResBind { i32 %d, i32 %d, i32 %d, i8 %s }, i32 %s, i1 %s)\n'
                '%s%s = call %%dx.types.Handle @dx.op.annotateHandle(i32 216, %%dx.types.Handle %%hb%d, %%dx.types.ResourceProperties { i32 %d, i32 %d })'
                % (ind, n[0], lb, ub, sp, cls, idx, nu, ind, dst, n[0], p0, p1))
    ll = re.sub(r'^(\s*)(%[\w.]+) = call %dx\.types\.Handle @dx\.op\.createHandle\(i32 57, i8 (\d), i32 (\d+), i32 ([%\w.]+), i1 (\w+)\)', rep, ll, flags=re.M)
    ll = re.sub(r'^declare %dx\.types\.Handle @dx\.op\.createHandle\(i32, i8, i32, i32, i1\)( #\d+)?\n', '', ll, flags=re.M)
    attr = re.search(r'attributes #(\d+) = \{ nounwind readnone \}', ll).group(1)
    if '%dx.types.ResBind = type' not in ll:
        ll = ll.replace('%dx.types.Handle = type { i8* }\n', '%dx.types.Handle = type { i8* }\n%dx.types.ResBind = type { i32, i32, i32, i8 }\n%dx.types.ResourceProperties = type { i32, i32 }\n', 1)
    i = ll.index('\nattributes #')
    return ll[:i + 1] + ('declare %%dx.types.Handle @dx.op.createHandleFromBinding(i32, %%dx.types.ResBind, i32, i1) #%s\n'
                         'declare %%dx.types.Handle @dx.op.annotateHandle(i32, %%dx.types.Handle, %%dx.types.ResourceProperties) #%s\n' % (attr, attr)) + ll[i + 1:]


def force(ll):
    sm = re.search(r'!\{!"cs", i32 6, i32 (\d)\}', ll); minor = int(sm.group(1))
    ep = re.search(r'^!dx\.entryPoints = !\{!(\d+)\}', ll, re.M).group(1)
    epl = re.search(r'^!%s = !\{(.*)\}$' % ep, ll, re.M)
    props = epl.group(1).rsplit(',', 1)[1].strip()
    nid = max(int(x) for x in re.findall(r'^!(\d+) = ', ll, re.M)) + 1
    if props == 'null':  # no properties node: make one
        ll = ll.replace(epl.group(0), '!%s = !{%s, !%d}' % (ep, epl.group(1).rsplit(',', 1)[0], nid))
        ll += '\n!%d = !{}' % nid; props = '!%d' % nid; nid += 1
    pn = props[1:]
    pl = re.search(r'^!%s = !\{(.*)\}$' % pn, ll, re.M)
    items = [x.strip() for x in pl.group(1).split(',')] if pl.group(1).strip() else []
    pairs = list(zip(items[0::2], items[1::2]))
    tags = {k: v for k, v in pairs}
    if 'i32 23' in tags:
        ll = re.sub(r'^%s = !\{i32 \d+, i32 \d+, i32 \d+\}$' % re.escape(tags['i32 23']), '%s = !{i32 64, i32 0, i32 0}' % tags['i32 23'], ll, flags=re.M)
        return ll
    if 'i32 11' in tags:
        return re.sub(r'^%s = !\{i32 \d+\}$' % re.escape(tags['i32 11']), '%s = !{i32 64}' % tags['i32 11'], ll, flags=re.M)
    pairs.append(('i32 23' if minor >= 8 else 'i32 11', '!%d' % nid))  # SM 6.8+: WaveSizeRange tag
    ll = ll.replace(pl.group(0), '!%s = !{%s}' % (pn, ', '.join('%s, %s' % p for p in pairs)))
    ll += '\n!%d = !{i32 64%s}\n' % (nid, ', i32 0, i32 0' if minor >= 8 else '')
    if minor < 6:
        if '@dx.op.createHandle(' in ll: ll = modern_handles(ll)
        ll = ll.replace(sm.group(0), '!{!"cs", i32 6, i32 6}')
        ver = re.search(r'^!dx\.version = !\{!(\d+)\}', ll, re.M).group(1)
        ll = re.sub(r'^!%s = !\{i32 1, i32 \d\}' % ver, '!%s = !{i32 1, i32 6}' % ver, ll, flags=re.M)
    return ll


def generic66(ll):
    """Shader model 6.7/6.8 -> 6.6 (older drivers, e.g. GCN) and no wave-size tag (11/23): the driver picks the wave size."""
    sm = re.search(r'!\{!"cs", i32 6, i32 (\d)\}', ll)
    if int(sm.group(1)) > 6:
        ll = ll.replace(sm.group(0), '!{!"cs", i32 6, i32 6}')
        ver = re.search(r'^!dx\.version = !\{!(\d+)\}', ll, re.M).group(1)
        ll = re.sub(r'^!%s = !\{i32 1, i32 \d\}' % ver, '!%s = !{i32 1, i32 6}' % ver, ll, flags=re.M)
    ep = re.search(r'^!dx\.entryPoints = !\{!(\d+)\}', ll, re.M).group(1)
    props = re.search(r'^!%s = !\{(.*)\}$' % ep, ll, re.M).group(1).rsplit(',', 1)[1].strip()
    if props != 'null':
        pl = re.search(r'^!%s = !\{(.*)\}$' % props[1:], ll, re.M)
        items = [x.strip() for x in pl.group(1).split(',')]
        pairs = [p for p in zip(items[0::2], items[1::2]) if p[0] not in ('i32 11', 'i32 23')]
        ll = ll.replace(pl.group(0), '!%s = !{%s}' % (props[1:], ', '.join('%s, %s' % p for p in pairs)))
    return ll


def keep66(ll):
    """Shader model 6.7/6.8 -> 6.6, keeping the wave size: SM 6.8 WaveSizeRange (tag 23, {min, max, pref}) becomes the
    SM 6.6 WaveSize tag 11 {min}. HelixSR's Windows shaders all target cs_6_6 (older drivers stop there)."""
    m = re.search(r'i32 23, (!\d+)', ll)
    ws = re.search(r'^%s = !\{i32 (\d+), i32 \d+, i32 \d+\}$' % m.group(1), ll, re.M).group(1) if m else None
    ll = generic66(ll)
    if ws:
        ep = re.search(r'^!dx\.entryPoints = !\{!(\d+)\}', ll, re.M).group(1)
        pn = re.search(r'^!%s = !\{(.*)\}$' % ep, ll, re.M).group(1).rsplit(',', 1)[1].strip()[1:]
        pl = re.search(r'^!%s = !\{(.*)\}$' % pn, ll, re.M)
        nid = max(int(x) for x in re.findall(r'^!(\d+) = ', ll, re.M)) + 1
        ll = ll.replace(pl.group(0), '!%s = !{%s, i32 11, !%d}' % (pn, pl.group(1), nid)) + '\n!%d = !{i32 %s}\n' % (nid, ws)
    return ll


def convert(src, dst, fn=None, ch=None):
    """ch: the HLX FSR 4 builder's chain (DXC + dxc_assemble)"""
    with tempfile.TemporaryDirectory() as t:
        t = Path(t)
        s = ch.disasm(Path(src), t/'in.ll'); ll = (fn or force)(s[s.index('target datalayout'):])
        Path(dst).parent.mkdir(parents=True, exist_ok=True)
        for _ in range(2):
            (t/'o.ll').write_text(ll)
            ch.tool('assemble', t/'o.ll', t/'o.u')
            rc, err = ch.tool('validate', t/'o.u', Path(dst), check=False)
            if rc == 0: return
            m = re.search(r'Flags declared=(\d+), actual=(\d+)', err)
            if not m: break
            # shader feature flags of the new shader model (entry properties tag 0)
            # clear only the bits that differ (the validator masks e.g. UseNativeLowPrecision out of "declared")
            diff = int(m.group(1)) ^ int(m.group(2))
            ll = re.sub(r'^(!\d+ = !\{i32 0, i64 )(\d+)', lambda q: q.group(1) + str(int(q.group(2)) & ~diff), ll, count=1, flags=re.M)
        raise RuntimeError('validation failed for %s:\n%s' % (src, err[-2000:]))


