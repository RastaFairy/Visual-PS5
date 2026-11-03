# Copyright 2026 lonewolf0622. All rights reserved (HelixSR Freeware License).
"""build.py OUT [--amd amdxcffx64.dll] [--dxc DXC_DIR --assemble dxc_assemble(.exe) [--wine WINE --prefix PFX]]
          [--groups a,b,..] [--jobs N] [--yes]

HLX FSR 4's data built from AMD's FSR 4 driver file: AMD's weights and stock shaders cut out of it, the weight tables
our generators read extracted from them, then every kernel generated and compiled as the tested build did. Each blob is
checked against the tested build's SHA-256 (data/blobs.json); OUT holds them at the paths the shader-set configs use.
Development: --linux-dxc DIR (a Linux DXC of the same commit) and --linux-assemble TOOL instead of the Windows DXC."""
import argparse, json, os, re, subprocess, sys, threading
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
GEN = ROOT / 'gen'
DATA = ROOT / 'data'
sys.path.insert(0, str(ROOT))
from hlx import amd, chain as ch, lf  # noqa: E402
lf.install()   # (Windows: LF text files, as the checked build wrote them)

FAMS = {'s': dict(row=15392, sh=15392, wh=960, hh=540, hp=16684928),
        'm': dict(row=30752, sh=30752, wh=1920, hh=1080, hp=66547328),
        'l': dict(row=61472, sh=61472, wh=3840, hh=2160, hp=265804928)}


HERE_PKG = Path(__file__).resolve().parents[1]   # (the folder holding hlx/)


def py(script):
    """Command line running a generator script with its own folder importable: Windows' embeddable Python (the
    setup's, with a ._pth file) does not put the script's folder on sys.path as python3 does"""
    d = str(Path(script).parent)
    return [sys.executable, '-c', 'import runpy, sys; sys.path.insert(0, sys.argv[1]); sys.path.insert(0, sys.argv[2]); '
            'import hlx.lf; hlx.lf.install(); sys.argv = sys.argv[3:]; runpy.run_path(sys.argv[0], run_name="__main__")',
            d, str(HERE_PKG), str(script)]


class Ctx:
    """chain: DXC 1.9.2607 (most of the tested build); chain2609: DXC 1.9.2609 (the kernels built on the Windows PC)"""
    def __init__(s, out, chain, jobs, chain2609=None, chainw=None):
        s.out, s.chain, s.jobs, s.chain2609 = Path(out), chain, jobs, chain2609
        s.chainw = chainw or chain   # the official Windows v1.9.2607 (direct compiles of the kernels built on Windows)
        s.man = json.loads((DATA / 'blobs.json').read_text())
        s.lock = threading.Lock(); s.bad = []; s.done = 0; s.seen = set()

    def p(s, rel):
        f = s.out / rel; f.parent.mkdir(parents=True, exist_ok=True); return f

    def gen(s, script, out, env, args=()):
        e = dict(os.environ); e.update({k: str(v) for k, v in env.items()})
        r = subprocess.run(py(GEN / script) + [str(out)] + [str(a) for a in args], env=e,
                           stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        if r.returncode:
            raise RuntimeError(f'{script} {env}: {r.stderr.decode(errors="replace")[-400:]}')

    progress = None   # callable(fraction): the setup's progress bar
    CHECKS = 2366     # blobs checked in a whole build (each config path, the intermediate ones too)

    def check(s, rel, b):
        want = s.man['blobs'].get(rel)
        with s.lock:
            s.done += 1; s.seen.add(rel)
            if s.progress:
                s.progress(min(s.done / s.CHECKS, 1.0))
            if want is not None and amd.sha256(b) != want:
                s.bad.append(rel)

    def many(s, items, fn):
        try:
            with ThreadPoolExecutor(max_workers=s.jobs) as pool:
                for f in [pool.submit(fn, *it) for it in items]:
                    f.result()
        finally:
            # the pool's threads have ended: their DXC batch processes too (else every step leaves its own set running,
            # hundreds by the end of a build, until the memory runs out)
            for ch in {id(c): c for c in (s.chain, s.chain2609, s.chainw) if c is not None}.values():
                ch.close()


def step_amd(c, dll):
    """AMD's weights and stock shaders, at the paths the configs use; the extractors' stock shaders disassembled"""
    pieces = json.loads((DATA / 'amd_pieces.json').read_text())['pieces']
    got = amd.cut(dll, pieces)
    for n in ('weights_std.bin', 'weights_ultra.bin'):
        c.p('optimize/own_runtime/fam/w/' + n).write_bytes(got[n])
    by_sha = {Path(n).stem: b for n, b in got.items() if n.startswith('stock/')}
    for rel in c.man['stock']:
        b = by_sha[c.man['blobs'][rel]]; c.p(rel).write_bytes(b); c.check(rel, b)
    for n, b in got.items():
        if n.startswith('stock/'):
            c.p(n).write_bytes(b)
    for h in ('de740c6c', '1b112778', '306af382', 'a743ef83', 'fdd1e686', '0f3ba82a'):
        f = next((c.out / 'stock').glob(h + '*.dxil'))
        c.chain.disasm(f, f.with_suffix('.ll'))


def stock_ll(c, h):
    return next((c.out / 'stock').glob(h + '*.ll'))


def step_npz(c):
    """the weight tables our generators read, extracted from AMD's stock shaders / weights"""
    w = c.out / 'weights'; w.mkdir(parents=True, exist_ok=True)
    fw = c.out / 'optimize/own_runtime/fam/w'
    std, ultra = fw / 'weights_std.bin', fw / 'weights_ultra.bin'
    # the middle-5 layer's constants (resolutions of the 1080p layout's planes), as AMD's runtime sets them
    cb = w / 'cb-p5.bin'
    cb.write_bytes(b''.join(int(v).to_bytes(4, 'little') for v in
                            [960, 540, 0, 0, 1920, 1080, 0, 0, 960, 540, 0, 0, 480, 270, 0, 0, 480, 270, 0, 0, 960, 540, 0, 0,
                             1920, 1080, 0, 0, 1920, 1080, 0, 0, 1920, 1080, 0, 0] + [0] * 28))
    jobs = [('m9/ext9.py', [stock_ll(c, 'fdd1e686'), w / 'w9.npz'], {}),
            ('m9/ext9u.py', [stock_ll(c, '0f3ba82a'), w / 'w9u.npz'], {}),
            ('own/ext1.py', [stock_ll(c, 'de740c6c'), std, w / 'first_w.npz'], {}),
            ('own/ext1u.py', [stock_ll(c, '1b112778'), ultra, w / 'first_wu.npz'], {}),
            ('m7/ext7.py', [std, w / 'w7.npz'], {}),
            ('m7/ext7u.py', [ultra, w / 'w7u.npz'], {}),
            ('pe/run5p.py', [], dict(INIT=std, SHADER=stock_ll(c, '306af382'), OUT=w / 'w5.npz', CB=cb)),
            ('pe/run5p.py', [], dict(INIT=ultra, SHADER=stock_ll(c, 'a743ef83'), OUT=w / 'w5u.npz', CB=cb))]

    def one(script, args, env):
        e = dict(os.environ); e.update({k: str(v) for k, v in env.items()})
        r = subprocess.run(py(GEN / script) + [str(x) for x in args], env=e, cwd=str(w),
                           stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        if r.returncode:
            raise RuntimeError(f'{script}: {r.stderr.decode(errors="replace")[-400:]}')
    c.many(jobs, one)


def step_mypre(c):
    """kernels/mypre/out: the prepass, 3 families x 2 models x 32 flag keys (inv, ae, dmv, jit, nl); kernels/mypre/out8: the
    same with 128-thread groups and the final sums on every thread (G128 RED4: AMD's tiers 7-9, pass kind pre8)"""
    def one(f, mo, k, g8):
        rel = 'kernels/mypre/%s/pre-%s-%s-k%02d.dxil' % ('out8' if g8 else 'out', f, mo, k)
        dx = c.p(rel); hl = dx.with_suffix('.hlsl')
        env = dict(ROW=FAMS[f]['row'], INV=k & 1, AE=k >> 1 & 1, DMV=k >> 2 & 1, JIT=k >> 3 & 1, NL=k >> 4 & 1,
                   WEIGHTS=c.out / 'optimize/own_runtime/fam/w' / f'weights_{mo}.bin')
        if g8: env.update(G128=1, RED4=1)
        c.gen('mypre/genpre3.py', hl, env)
        c.check(rel, c.chain.compile(hl, dx))
    c.many([(f, mo, k, g8) for g8 in (0, 1) for f in 'sml' for mo in ('std', 'ultra') for k in range(32)], one)


def step_m9(c):
    """kernels/m9/out: the post pass, 3 families x 2 models x auto exposure x non-linear colour; kernels/m9/out8: the same
    with 16-pixel row stores and the output colour after the store shuffle (ROW16 OCR: AMD's tiers 7, 8)"""
    def one(f, mo, ae, nl, o8):
        rel = 'kernels/m9/%s/post-%s-%s-a%dn%d.dxil' % ('out8' if o8 else 'out', f, mo, ae, nl)
        dx = c.p(rel); hl = dx.with_suffix('.hlsl'); F = FAMS[f]
        env = dict(OSPLIT=2, SH=F['sh'], WH=F['wh'], HH=F['hh'], HP=F['hp'], MODEL=mo, AE=ae, NL=nl,
                   W9=c.out / 'weights' / ('w9u.npz' if mo == 'ultra' else 'w9.npz'))
        if o8: env.update(ROW16=1, OCR=1)
        c.gen('m9/gen9e.py', hl, env)
        c.check(rel, c.chain.compile(hl, dx))
    c.many([(f, mo, ae, nl, o8) for o8 in (0, 1) for f in 'sml' for mo in ('std', 'ultra') for ae in (0, 1) for nl in (0, 1)], one)


FIRST_GEN = {'f1': ('f1/gen2.py', 'W1F', ('first_w', 'first_wu')), 'm5': ('m5/gen5.py', 'W5', ('w5', 'w5u')),
             'm7': ('m7/gen7.py', 'W7', ('w7', 'w7u'))}
# the tier-0 first layer / middle 5 / middle 7 kernels from the tuning runs (optimize/variants/tuned-*, named after the
# AMD shader each replaces): (folder, AMD shader, generator folder, model, layout, WaveSize attribute)
#   s = the 1080p layout as generated; m = the 3840x2160 layout (relayout.py + plane offsets, as the tuning
#   scripts made them); l = the 7680x4320 layout (the family relayout)
FIRSTS = [('tuned-combo15', '9910f50f3d2f0fe7ea2055688a7e86be48c49135cae2fe4d3bab0da23c8d5d61', 'f1', 'std', 's', 0),
          ('tuned-combo15', '5a0c08654f950393ac2ab8ac1ecb29ac31c45ce5f2b8693a0ffeb5c96d2910bc', 'm5', 'std', 's', 1),
          ('tuned-combo15', 'c6d1b73e838c73aa5e6580fe89dde2ffdad466765f4c719a06255a2c3d64e449', 'm7', 'std', 's', 1),
          ('tuned-ultra2', '6c01267158f13ea7c226e51878b383773c8b81e5f573eda54166f639cfb35894', 'f1', 'ultra', 's', 0),
          ('tuned-ultra2', 'ef45ac3b1d4180fa47c39d58eb03bbdc09dfa6c071a30d2ebb1d68591df9cbb3', 'm5', 'ultra', 's', 1),
          ('tuned-ultra2', 'bdd9747fcd876daa37fa01efa0065115b82830c8de7e46792858b80653bd83e4', 'm7', 'ultra', 's', 1),
          ('tuned-ultra2', '25f898fc3453a2b3ebbe2da5760da26b836879deb5f88ae48dc6c7543bada915', 'f1', 'ultra', 'm', 0),
          ('tuned-ultra2', '70f503d41219a20013d153ed84fdfe23c7dc8fc402d8f36beff893aba13867b2', 'm5', 'ultra', 'm', 1),
          ('tuned-ultra2', 'c984d20de9728d53859516579f048acbcc6cc0a3e14aad6195f797b3e9cc75d3', 'm7', 'ultra', 'm', 1),
          ('tuned-gf16mix', 'b4336c7bb8b143b94eb40febc5be482378667dad81afecf8a9b6d444186a8c70', 'f1', 'std', 'm', 0),
          ('tuned-gf16mix', '3efec580be0dad7d85a643302b5963495c8a347330d3a6bec92e7ff96ba99aa2', 'm5', 'std', 'm', 1),
          ('tuned-gf16mix', '35dbfd6cbbd84819d2ab46849f02c3a87790575ff7d6c3bfa63f239b7abbbcd2', 'm7', 'std', 'm', 1),
          ('tuned-large', '8ad349d409edffc67a4ff944eee026afa1c6c6d72d0f9b539829e552b94a6b84', 'f1', 'std', 'l', 1),
          ('tuned-large', '0869146b125eb1d0913f565e0daba2f051169050f04e81e525d610c0a2db29e8', 'm5', 'std', 'l', 1),
          ('tuned-large', '7f0f5d5d26e5dfb1328d7171c84e51f2420f00822fdd8ba75083955670e34a85', 'm7', 'std', 'l', 1),
          ('tuned-large', 'ac39ecd84b833bf40661653a8114335a1eeabb8abd9a6c0a0f4f25abfdba8c84', 'f1', 'ultra', 'l', 1),
          ('tuned-large', 'f6008d9ea98c5f6f414d3fc526b4ffff09d5a6c1846f582551bc3e1710b131c1', 'm5', 'ultra', 'l', 1),
          ('tuned-large', 'c43f4c46619547f22e45086b2e36ec451d18a2158c88f70b5f80d96e21f2df99', 'm7', 'ultra', 'l', 1)]


def offset_map(scratch, qw, qh):
    """the 1080p layout's plane offsets / strides -> a bigger layout's (the tuning scripts' token substitution)"""
    row = (qw + 2) * 32; plane = row * (qh + 2); offs = [scratch + i * plane for i in range(4)]
    m = dict(zip([25027392, 29222720, 33418048, 37613376], offs)); m.update({15424: row, 479: qw - 1, 269: qh - 1})
    tok = re.compile(r'(?<![\w.])(' + '|'.join(map(str, m)) + r')(u?)(?![\w.])')
    return lambda l: tok.sub(lambda t: (t[0] if int(t[1]) in (479, 269) and not t[2] else str(m[int(t[1])]) + t[2]), l)


def layout_m(src, gen_dir):
    """the 3840x2160 layout of the tuned first / middle kernels: relayout.py, then that family's plane offsets"""
    tmp_in, tmp_out = gen_dir / 'in.hlsl', gen_dir / 'out.hlsl'
    tmp_in.write_text(src)
    subprocess.run(py(GEN / 'relayout.py') + [str(tmp_in), str(tmp_out)], check=True, stdout=subprocess.DEVNULL)
    sub = offset_map(99820992, 960, 540)
    return '\n'.join(l if l.startswith('static const') else sub(l) for l in tmp_out.read_text().split('\n'))


def layout_fam(src, fam):
    """the family relayout (tools/make_first_osplit.py relayout()): the 3840x2160 (m) or 7680x4320 (l) family"""
    hw = {'m': (1920, 1080), 'l': (3840, 2160)}[fam]; qw, qh = hw[0] // 2, hw[1] // 2
    sh = (hw[0] + 2) * 16; sq = (qw + 2) * 16; ph = sh * (hw[1] + 2); pq = sq * (qh + 2)
    M = [('15392', str(sh)), ('7712', str(sq)), ('8342464', str(ph)), ('16684928', str(2 * ph)), ('2097664', str(pq)),
         ('540u', '%du' % hw[1]), ('960u', '%du' % hw[0]), ('480u', '%du' % qw), ('g.x==29', 'g.x==%d' % (hw[0] // 32 - 1)),
         ('g.y==134', 'g.y==%d' % (hw[1] // 4 - 1)), ('18782592', str(2 * ph + pq))]
    sub = offset_map({'m': 99820992, 'l': 398707392}[fam], qw, qh); out = []
    for l in src.split('\n'):
        if l.startswith('static const'):
            out.append(l); continue
        for i, (a, b) in enumerate(M): l = re.sub(r'(?<![0-9])' + re.escape(a) + r'(?![0-9])', '@@%d@@' % i, l)
        for i, (a, b) in enumerate(M): l = l.replace('@@%d@@' % i, b)
        out.append(sub(l))
    return '\n'.join(out)


def step_firsts(c):
    """optimize/variants/tuned-*: the tier-0 first layer / middle 5 / middle 7 kernels"""
    def one(var, amdsha, d, model, lay, ws):
        rel = f'optimize/variants/{var}/{amdsha}.dxil'
        dx = c.p(rel); work = c.p(f'work/firsts/{amdsha[:12]}/x'); work = work.parent
        g, wk, wf = FIRST_GEN[d]
        env = {'F16IO': 1, 'WAVESIZE': ws, wk: c.out / 'weights' / ((wf[1] if model == 'ultra' else wf[0]) + '.npz')}
        if d != 'f1': env['SKIP'] = 1
        if model == 'ultra': env['MODEL'] = 'ultra'
        if lay == 'm': env['SH'] = 30752
        if lay == 'l': env['SH'] = (3840 + 2) * 16
        inp = work / 'input.hlsl'
        c.gen(g, inp, env)
        src = inp.read_text()
        src = layout_m(src, work) if lay == 'm' else layout_fam(src, 'l') if lay == 'l' else src
        hl = dx.with_suffix('.hlsl'); hl.write_text(src)
        c.check(rel, c.chain.compile(hl, dx))
    c.many(FIRSTS, one)


FAMDIR = DATA / 'optimize/own_runtime/fam'


def tools():
    sys.path.insert(0, str(GEN / 'tools'))
    import lower_sm69, wave64
    return lower_sm69, wave64


def configs(tier, pat):
    return [json.loads(f.read_text()) for f in sorted((FAMDIR / tier).glob(pat))]


def step_cfg68(c):
    """tier 2 (fp16 at shader model 6.8 / 6.6): tools/make_sm68_set.py (every tier-0 kernel lowered to cs_6_8, its weight
    tables as a constant buffer), make_first_osplit.py (the first layer regenerated with OSPLIT=2 and lowered), then
    make_sm66_set.py (every cfg68 shader to cs_6_6, AMD's stock shaders too)"""
    lower, w64 = tools()
    src68 = {}   # tier-0 shader -> its cs_6_8 version (stock: unchanged)
    for cfg in configs('cfg9', 'fast-*.json'):
        for p in cfg['passes']:
            if p['kind'] != 'first':
                src68.setdefault(p['dxil'], None)
    PRE8 = ['kernels/mypre/out8/pre-%s-%s-k%02d.dxil' % (f, mo, k) for f in 'sml' for mo in ('std', 'ultra') for k in range(32)]
    POST8 = ['kernels/m9/out8/post-%s-%s-a%dn%d.dxil' % (f, mo, ae, nl) for f in 'sml' for mo in ('std', 'ultra')
             for ae in (0, 1) for nl in (0, 1)]
    for rel in PRE8 + POST8:   # AMD's tiers 8 / 9: the 128-thread prepass (and tier 8's post) lowered the same way
        src68.setdefault(rel, None)

    def lower_one(rel):
        src = c.out / rel; dst = c.p('optimize/variants/sm68/' + src.parent.name + '-' + src.name)
        r = lower.convert(src, dst, c.chain, c.out)
        if r is None:
            src68[rel] = rel; return
        src68[rel] = dst.relative_to(c.out).as_posix()
        c.check(src68[rel], dst.read_bytes())
        if r.get('wcb'):
            c.check(r['wcb'], (c.out / r['wcb']).read_bytes())
    c.many([(r,) for r in src68], lower_one)

    firsts = {}
    def first_one(fam, model):
        out = c.p(f'optimize/variants/first-os2/first-{fam}-{model}.dxil')
        env = {'F16IO': 1, 'OSPLIT': 2, 'W1F': c.out / 'weights' / ('first_wu.npz' if model == 'ultra' else 'first_w.npz')}
        if model == 'ultra': env['MODEL'] = 'ultra'
        if fam != 's': env['SH'] = ({'m': 1920, 'l': 3840}[fam] + 2) * 16
        inp = out.with_suffix('.input.hlsl'); c.gen('f1/gen2.py', inp, env)
        src = inp.read_text(); hl = out.with_suffix('.hlsl')
        hl.write_text(layout_fam(src, fam) if fam != 's' else src)
        c.chain2609.compile(hl, out)   # (built and lowered with DXC 1.9.2609)
        dst = out.with_suffix('.sm68.dxil'); r = lower.convert(out, dst, c.chain2609, c.out) or {}
        firsts[(fam, model)] = dst.relative_to(c.out).as_posix()
        if r.get('wcb'):
            c.check(r['wcb'], (c.out / r['wcb']).read_bytes())
    c.many([(f, m) for f in 'sml' for m in ('std', 'ultra')], first_one)

    src66 = set()   # what cfg68 runs, each to cs_6_6
    for cfg in configs('cfg9', 'fast-*.json'):
        for p in cfg['passes']:
            fam, model = cfg['name'].split('-')[1:3]   # fast-<family>-<model>-k<key>
            src66.add(firsts[(fam, model)] if p['kind'] == 'first' else src68[p['dxil']])
    src66.update(src68[rel] for rel in PRE8 + POST8)

    def to66(rel):
        src = c.out / rel
        dst = c.p('optimize/variants/sm66/' + src.parent.name + '-' + src.stem.replace('.sm68', '') + '.dxil')
        w64.convert(src, dst, w64.keep66, c.chain)
        c.check(dst.relative_to(c.out).as_posix(), dst.read_bytes())
    c.many([(r,) for r in sorted(src66)], to66)


def step_cfgi8(c):
    """tier 3 (RDNA 2+ INT8): tools/make_int8_set.py's own passes (kernels/pascal gen_first / gen_mid / gen_post,
    integer-exact to AMD's INT8 shaders; cs_6_6 in one dxc call); its prepass and AMD's shaders come from tiers 2 / 0"""
    jobs = []
    for f in 'sml':
        for m in ('std', 'ultra'):
            fm = ['--family', f, '--model', m]
            jobs.append(('first-%s-%s' % (f, m), 'gen_first.py', fm))
            jobs.append(('m5-%s-%s' % (f, m), 'gen_mid.py', ['--pass', '5', '--rfold', '1'] + fm))
            jobs.append(('m7-%s-%s' % (f, m), 'gen_mid.py', ['--pass', '7', '--rfold', '1'] + fm))
            for ae in (0, 1):
                for nl in (0, 1):
                    jobs.append(('post-%s-%s-a%dn%d' % (f, m, ae, nl), 'gen_post.py',
                                 fm + ['--ae', str(ae), '--nl', str(nl), '--threads', '256', '--sites', '1', '--pk', '1', '--rfold', '1']))
                    # AMD's tier 9: half-height groups (16x8 sites, 128 threads, runtime pass kind post16; the same output)
                    jobs.append(('post8-%s-%s-a%dn%d' % (f, m, ae, nl), 'gen_post.py',
                                 fm + ['--ae', str(ae), '--nl', str(nl), '--threads', '128', '--grows', '8', '--sites', '1', '--pk', '1',
                                       '--rfold', '1']))

    def one(name, gen, args):
        rel = 'optimize/variants/int8/%s.dxil' % name
        dx = c.p(rel); hl = dx.with_suffix('.hlsl')
        c.gen('pascal/' + gen, hl, {'HLX_WEIGHTS': c.out / 'weights'}, args)
        if name.startswith('post'):   # its lane shuffles assume 32-lane waves: pinned, as make_int8_set.py does
            t = hl.read_text(); assert t.count('[numthreads(') == 1; hl.write_text(t.replace('[numthreads(', '[WaveSize(32)] [numthreads('))
        # the first / middle kernels were built on the Windows PC (DXC 1.9.2609), the post kernels later on Linux (2607)
        c.check(rel, (c.chain if name.startswith('post') else c.chain2609).compile_direct(hl, dx))
    c.many(jobs, one)


PASCAL_M7 = {'afe5a41d77d585a0485cc8d0': 0, 'aa17c4ae039e1fa6784a051b': 0, '99292bcf81a419a37b7ad3df': 0,
             '1f8af22216b5bb7307968e50': 1, '78ca2ff048df709c84261903': 1, 'a401bb1603e2d30bcb4e8f01': 1}


def step_cfgpf(c):
    """tier 1 (Pascal, no native 16-bit ops): tools/make_pascal_fast_set.py - own prepass with H16=0 at cs_6_6 without
    16-bit types, AMD's middle 7 with ids pinned / loops unrolled / weights baked (tools/pascal_opt.py), own DP4A first
    (cs_6_4) and post (cs_6_6) kernels (kernels/pascal/build_all.py)"""
    sys.path.insert(0, str(GEN / 'tools'))
    import pascal_opt
    V = 'optimize/variants/pascal-fast/'
    fw = {'s': 1920, 'm': 3840, 'l': 7680}

    def pre(f, mo, k):
        rel = V + 'pre-%d-%s-k%02d.dxil' % (fw[f], mo, k)
        dx = c.p(rel); hl = dx.with_suffix('.hlsl')
        c.gen('mypre/genpre3.py', hl, dict(ROW=FAMS[f]['row'], INV=k & 1, AE=k >> 1 & 1, DMV=k >> 2 & 1, JIT=k >> 3 & 1,
                                         NL=k >> 4 & 1, H16=0, WEIGHTS=c.out / 'optimize/own_runtime/fam/w' / f'weights_{mo}.bin'))
        c.check(rel, c.chain.compile(hl, dx, target='cs_6_6', f16=False, fold=False, ident='windows'))   # (built on Windows)

    def fp(name, gen, args, tgt):
        rel = V + name + '.dxil'; dx = c.p(rel); hl = dx.with_suffix('.hlsl')
        c.gen('pascal/' + gen, hl, {'HLX_WEIGHTS': c.out / 'weights'}, args)
        c.check(rel, c.chainw.compile_direct(hl, dx, target=tgt))   # (built on Windows, DXC v1.9.2607)

    def m7(h, model):
        rel = V + 'm7-%s-m%d.dxil' % (h, model); dx = c.p(rel)
        src = next((c.out / 'stock').glob(h + '*.dxil'))
        fwt = c.out / 'optimize/own_runtime/fam/w'
        pascal_opt.run(src, dx, model, [fwt / 'weights_std.bin', fwt / 'weights_ultra.bin'], c.chain)
        c.check(rel, dx.read_bytes())

    c.many([(f, mo, k) for f in 'sml' for mo in ('std', 'ultra') for k in range(32)], pre)
    jobs = [('first-%s-%s' % (f, m), 'gen_first.py', ['--family', f, '--model', m, '--px1'], 'cs_6_4') for f in 'sml' for m in ('std', 'ultra')]
    jobs += [('post-%s-%s-a%dn%d' % (f, m, ae, nl), 'gen_post.py', ['--family', f, '--model', m, '--ae', str(ae), '--nl', str(nl),
              '--threads', '256', '--sites', '1', '--pk', '1'], 'cs_6_6') for f in 'sml' for m in ('std', 'ultra') for ae in (0, 1) for nl in (0, 1)]
    c.many(jobs, fp)
    c.many(list(PASCAL_M7.items()), m7)


POSTF = {'s': (15392, 960, 540, 16684928), 'm': (30752, 1920, 1080, 66547328), 'l': (61472, 3840, 2160, 265804928)}


def step_w64(c):
    """tiers 4 / 6 / 5 (wave64-only GCN: Vega fp16, Radeon VII INT8, Polaris fp32), cs_6_6 without a wave size:
    tools/make_w64_sets.py (built on Windows, DXC 1.9.2609), then make_gcn_fp16.py (Vega post / first layer) and
    make_gcn_fast.py (Polaris first / middle 5 / post), both built on Linux (DXC 1.9.2607)"""
    lower, w64 = tools()
    import dot4emu
    W = 'optimize/variants/w64/'
    c9, cl = c.chain2609, c.chain.transforms('linux')

    def fp16_kernel(ch, hl, tch=None):   # cs_6_9 (+ fold) -> cs_6_8 (weight CB) -> cs_6_6 generic
        tch = tch or ch
        ch.compile(hl, hl.with_suffix('.dxil'))
        low = hl.with_suffix('.sm68.dxil'); extra = lower.convert(hl.with_suffix('.dxil'), low, tch, c.out) or {}
        dst = hl.with_suffix('.w64.dxil'); w64.convert(low, dst, w64.generic66, tch)
        c.check(dst.relative_to(c.out).as_posix(), dst.read_bytes())
        if extra.get('wcb'):
            c.check(extra['wcb'], (c.out / extra['wcb']).read_bytes())

    # make_w64_sets.py: prepass (fp16: full chain; fp32: one dxc call), Radeon VII post, every other pass retargeted
    def pre(f, m, k, fp16):
        hl = c.p(W + 'mypre/pre-%s-%s-k%02d-%s.hlsl' % (f, m, k, 'h' if fp16 else 'f'))
        c.gen('mypre/genpre3.py', hl, dict(W64SAFE=1, ROW=FAMS[f]['row'], INV=k & 1, AE=k >> 1 & 1, DMV=k >> 2 & 1, JIT=k >> 3 & 1,
                                         NL=k >> 4 & 1, H16=1 if fp16 else 0,
                                         WEIGHTS=c.out / 'optimize/own_runtime/fam/w' / f'weights_{m}.bin'))
        if fp16:
            fp16_kernel(c9, hl)
        else:
            dx = hl.with_suffix('.w64.dxil'); c.check(dx.relative_to(c.out).as_posix(), c9.compile_direct(hl, dx))
    c.many([(f, m, k, h) for f in 'sml' for m in ('std', 'ultra') for k in range(32) for h in (True, False)], pre)

    def postp(f, m, ae, nl):   # Radeon VII (rfold 1)
        hl = c.p(W + 'postp-%s-%s-a%dn%d-r1.hlsl' % (f, m, ae, nl))
        c.gen('pascal/gen_post.py', hl, {'HLX_WEIGHTS': c.out / 'weights'},
              ['--family', f, '--model', m, '--ae', ae, '--nl', nl, '--threads', 256, '--sites', 1, '--pk', 1, '--coalesce', 0, '--rfold', 1])
        dx = hl.with_suffix('.w64.dxil'); c.check(dx.relative_to(c.out).as_posix(), c9.compile_direct(hl, dx))
    c.many([(f, m, ae, nl) for f in 'sml' for m in ('std', 'ultra') for ae in (0, 1) for nl in (0, 1)], postp)

    gens = {}
    for tier, pat in (('cfg68', 'fast68-*.json'), ('cfgi8', 'int8-*.json'), ('cfgpf', 'pascal-*.json')):
        for cfg in configs(tier, pat):
            for q in cfg['passes']:
                if q['kind'] not in ('pre', 'post'):
                    gens.setdefault(q['dxil'], set()).add(tier)

    def gen_one(d):
        src = c.out / d; dst = c.p(W + 'g/' + src.stem + '-' + src.parent.name + '.dxil')
        w64.convert(src, dst, w64.generic66, c9); c.check(dst.relative_to(c.out).as_posix(), dst.read_bytes())
        if 'cfgpf' in gens[d]:   # Polaris: every dot4 as fused fp32 multiply-adds (exact)
            e = c.p(W + 'emu/' + dst.stem + '-f32.dxil'); dot4emu.convert(dst, e, 'f32', c9)
            c.check(e.relative_to(c.out).as_posix(), e.read_bytes())
    c.many([(d,) for d in sorted(gens)], gen_one)

    # make_gcn_fp16.py: the Vega post and first layer at 2 waves per SIMD
    G16 = W + 'gcn16/'
    def post9(f, m, ae, nl):
        sh, wh, hh, hp = POSTF[f]; hl = c.p(G16 + 'post9-%s-%s-a%dn%d.hlsl' % (f, m, ae, nl))
        c.gen('m9/gen9e.py', hl, dict(W64SAFE=1, W64LDS=1, SH=sh, WH=wh, HH=hh, HP=hp, MODEL=m, AE=ae, NL=nl,
                                      W9=c.out / 'weights' / ('w9u.npz' if m == 'ultra' else 'w9.npz'),
                                      GCNC0=1, GCNHEAD=1, GCNST=1, OSPLIT=4))
        fp16_kernel(c.chain, hl, cl)
    c.many([(f, m, ae, nl) for f in 'sml' for m in ('std', 'ultra') for ae in (0, 1) for nl in (0, 1)], post9)

    def first2(f, m):
        stem = c.p(G16 + 'first2-%s-%s.hlsl' % (f, m)).with_suffix('')
        env = {'F16IO': 1, 'OSPLIT': 4, 'WG2': 1, 'GCN': 1, 'GCNQS': 2,
               'W1F': c.out / 'weights' / ('first_wu.npz' if m == 'ultra' else 'first_w.npz')}
        if m == 'ultra': env['MODEL'] = 'ultra'
        if f != 's': env['SH'] = ({'m': 1920, 'l': 3840}[f] + 2) * 16
        inp = Path(str(stem) + '.input.hlsl'); c.gen('f1/gen2_head.py', inp, env)
        src = inp.read_text(); hl = stem.with_suffix('.hlsl'); hl.write_text(layout_fam(src, f) if f != 's' else src)
        fp16_kernel(c.chain, hl, cl)
    c.many([(f, m) for f in 'sml' for m in ('std', 'ultra')], first2)

    # make_gcn_fast.py: tap-outer first / middle 5 / post for Polaris (fp32 dot4)
    GF = W + 'gcn/'
    def fast(name, gen, args, target, wave):
        hl = c.p(GF + name + '.hlsl'); dx = hl.with_suffix('.dxil')
        c.gen('pascal/' + gen, hl, {'HLX_WEIGHTS': c.out / 'weights'}, args)
        c.chain.compile_direct(hl, dx, target=target)
        if wave:
            g = hl.with_suffix('.w64.dxil'); w64.convert(dx, g, w64.generic66, cl); dx = g
        e = c.p(GF + name + '-f32.dxil'); dot4emu.convert(dx, e, 'f32', cl)
        c.check(e.relative_to(c.out).as_posix(), e.read_bytes())
    jobs = []
    for f in 'sml':
        for m in ('std', 'ultra'):
            jobs.append(('first-%s-%s' % (f, m), 'gen_first.py', ['--family', f, '--model', m, '--tapouter'], 'cs_6_4', True))
            jobs.append(('m5-%s-%s' % (f, m), 'gen_mid.py', ['--pass', 5, '--family', f, '--model', m, '--tapouter'], 'cs_6_4', True))
            for ae in (0, 1):
                for nl in (0, 1):
                    jobs.append(('post-%s-%s-a%dn%d' % (f, m, ae, nl), 'gen_post.py',
                                 ['--family', f, '--model', m, '--ae', ae, '--nl', nl, '--threads', 256, '--sites', 1, '--pk', 1,
                                  '--coalesce', 0, '--rfold', 0, '--tapouter', 1], 'cs_6_6', False))
    c.many(jobs, fast)


STEPS = {'mypre': step_mypre, 'm9': step_m9, 'firsts': step_firsts, 'cfg68': step_cfg68, 'cfgi8': step_cfgi8, 'cfgpf': step_cfgpf,
         'w64': step_w64}


def run_all(c, dll, groups=None):
    """every step for AMD's file (bytes) into c.out; returns (blobs that differ, reference blobs not built)"""
    step_amd(c, dll); step_npz(c)
    for g in (groups or list(STEPS)):
        STEPS[g](c)
    return sorted(c.bad), sorted(set(c.man['blobs']) - c.seen)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('out'); ap.add_argument('--amd'); ap.add_argument('--yes', action='store_true')
    ap.add_argument('--dxc'); ap.add_argument('--assemble'); ap.add_argument('--wine'); ap.add_argument('--prefix')
    ap.add_argument('--dxc2609'); ap.add_argument('--linux-dxc'); ap.add_argument('--linux-dxc2609'); ap.add_argument('--linux-assemble')
    ap.add_argument('--dev-windows-dxc', help='development: the official Windows v1.9.2607 folder, run through --wine')
    ap.add_argument('--groups', default=','.join(STEPS)); ap.add_argument('--jobs', type=int, default=os.cpu_count() or 4)
    a = ap.parse_args()
    if a.linux_dxc:
        lin = lambda d: ch.Chain(Path(d) / 'bin/dxc', Path(d) / 'lib/libdxcompiler.so', a.linux_assemble)
        c, c9 = lin(a.linux_dxc), lin(a.linux_dxc2609)
    else:
        c = ch.Chain.windows(a.dxc, a.assemble, a.wine, a.prefix)
        c9 = ch.Chain.windows(a.dxc2609, a.assemble, a.wine, a.prefix)
    cw = ch.Chain.windows(a.dev_windows_dxc, a.linux_assemble, a.wine, a.prefix) if a.dev_windows_dxc else None
    ctx = Ctx(a.out, c, a.jobs, c9, cw)
    dll = Path(a.amd).read_bytes() if a.amd else amd.get(a.yes)[0]
    bad, missing = run_all(ctx, dll, a.groups.split(','))
    (ctx.out / 'differ.txt').write_text(''.join(b + '\n' for b in bad))
    (ctx.out / 'missing.txt').write_text(''.join(b + '\n' for b in missing))
    print(f'{len(missing)} reference blobs not built (missing.txt)')
    print(f'{ctx.done} blobs checked, {len(ctx.bad)} differ' + (': ' + ', '.join(ctx.bad[:8]) if ctx.bad else ''))
    sys.exit(1 if ctx.bad else 0)


if __name__ == '__main__':
    main()
