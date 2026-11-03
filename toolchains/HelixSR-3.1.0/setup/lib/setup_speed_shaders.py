# Copyright 2026 lonewolf0622. All rights reserved (HelixSR Freeware License).
"""The speed build's extra pack shaders, made from the network's generated output kernels (like every pack shader):

  split output kernels   px_<k>_s<n><suffix> and px_<k>_split_meta<suffix>: the output kernel in 3 passes (Quality /
                         4K Performance: k5x, k5fx for 32-bit arithmetic, k5, k5f for 16-bit) or 5 (k5nx: Ultra
                         Quality, DLAA), as the owner's Windows lab built them (build_windows_split.py, the eight builds
                         results/combine_pack.py put into the release pack)
  Windows-tuned          px_<k>_win and px_<k>_w64_win: k5, k5f, k5n, k5nx, k5nxf with 32-bit shared-memory words
  output kernels         (PX_LDS_W32; build/rdna2-k5nx/build_win_outputs.py)

speed_jobs() writes the HLSL into work/speed and returns compile jobs in setup_shader_jobs.py's form, (pack name, DXC
command, .cso path), plus the split metadata blobs. The recipes reproduce the lab's generated HLSL file for file, and its
compiled shaders to the instruction (the DXIL differs only in the compiler's version and hash). The tools are split_output.py, motion_comp.py,
native_mlp.py and shadow_half.py next to this file."""
import re
import shutil
import struct
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import split_output as so      # noqa: E402
import motion_comp             # noqa: E402
import native_mlp              # noqa: E402
import shadow_half             # noqa: E402

# k5 / k5f (the 16-bit builds of k5x / k5fx) have their checkpoint shapes
so.REVIEWED.setdefault('k5', so.REVIEWED['k5x'])
so.REVIEWED.setdefault('k5f', so.REVIEWED['k5fx'])

BASE_ARGS = ['-T', 'cs_6_6', '-E', 'main', '-O3', '-HV', '2021', '-D', 'PX_FAST=1']
FP16 = ['-enable-16bit-types', '-D', 'PX_LDS_W32=1']
FP32 = ['-D', 'HX_FP32=1']
FP32_DEFINES = ['HX_R16_IDENTITY=1', 'HX_MC_CELL=1', 'HX_R16_NAN=0x7fffffffu']   # (HX_R16_NAN: shadow-half's)

# (name, kernels, generator, options, 16-bit, wave64); combine_pack.py's choice of kernels per family
SPLITS = (
    ('pascal', ('k5x', 'k5fx'), 'halves', ('lean', 'native_mlp', 'shadow_half', 'mc_k5fx'), False, False),
    ('polaris', ('k5x', 'k5fx'), 'halves', ('lean', 'native_mlp', 'shadow_half', 'mc_k5fx'), False, True),
    ('rdna', ('k5',), 'halves', ('lean',), True, False),   # (not k5f: its split is slower on RDNA)
    ('vega', ('k5', 'k5f'), 'halves', ('lean',), True, True),
    ('k5nx-pascal', ('k5nx',), 'parts', (), False, False),
    ('k5nx-polaris', ('k5nx',), 'parts', (), False, True),
    ('k5nx-rdna', ('k5nx',), 'parts', (), True, False),
    ('k5nx-vega', ('k5nx',), 'parts', (), True, True),
)
WIN_KERNELS = ('k5', 'k5f', 'k5n', 'k5nx', 'k5nxf')
STASH = '#if defined(PX_CPP_H) || defined(HX_FP32)\nvoid k5s_st'
STASH_W32 = '#if defined(PX_CPP_H) || defined(HX_FP32) || defined(PX_LDS_W32)\nvoid k5s_st'


def wave64(text, name):
    """The rewrite setup_shader_jobs.py makes for the pack's wave64 shaders."""
    if text.count('[WaveSize(32)]') != 1:
        raise ValueError(f'{name}: no wave32 attribute')
    text = text.replace('[WaveSize(32)]', '[WaveSize(64)]')
    text, n = re.subn(r'\{ (\w+_body)\(tid, gid\); \}',
                      r'{ PX_SET_GI(tid.x + tid.y * PX_BLOCK_X + tid.z * PX_BLOCK_X * PX_BLOCK_Y); \1(tid, gid); }', text)
    if n != 1:
        raise ValueError(f'{name}: unrecognized entry point')
    return text


def prepare_split(src, out, k, generator, options, fp16):
    """One output kernel's split passes in out (build_windows_split.py's prepare, for the options used): the layout."""
    if generator == 'parts':
        layout = so.generate_parts(src / k, out, k)
    else:
        layout = so.generate_halves(src / k, out, k)
    passes = layout.get('passes', 2)
    if fp16 and k == 'k5nx':   # its stash helpers take the 32-bit word helpers under PX_LDS_W32 (the same bits)
        for i in range(passes):
            body = out / f'{k}_s{i}_body.h'
            body.write_text(body.read_text().replace(STASH, STASH_W32))
    if 'lean' in options:
        # only checkpoint slots 0..9 (the filter parameters) are read before being redefined in passes 1 and 2
        if passes != 3:
            raise ValueError('lean checkpoint needs the halves split')
        keep, old = 10, layout['words_per_cta']
        new = keep * 256
        for i in range(passes):
            body = out / f'{k}_s{i}_body.h'
            text = body.read_text()
            text, n = re.subn(r'(uint _hx_base=[^\n]*\*)' + str(old) + r'u;', lambda m: m[1] + str(new) + 'u;', text)
            if n != 1:
                raise ValueError('checkpoint group stride absent')
            text = re.sub(r'HX_SPLIT\.Store\(\(_hx_base\+(\d+)u\*256u\+tid\.x\)\*4u,(x_r\d+)\);',
                          lambda m: m[0] if int(m[1]) < keep else f'/* slot {m[1]} dropped */', text)
            text = re.sub(r'(x_r\d+)=HX_SPLIT\.Load\(\(_hx_base\+(\d+)u\*256u\+tid\.x\)\*4u\);',
                          lambda m: m[0] if int(m[2]) < keep else f'/* slot {m[2]} dropped */ {m[1]}=0u;', text)
            body.write_text(text)
        layout.update(words_per_cta=new, state_words=keep)
    if 'mc_k5fx' in options and k == 'k5fx':   # motion-compensated filter parameters (bilinear), k5fx only
        layout['motion_comp'] = {f'{k}_s{i}': motion_comp.apply_bilinear(out / f'{k}_s{i}_body.h') for i in (1, 2)}
        for i in range(passes):
            motion_comp.root_signature(out / f'{k}_s{i}.hlsl')
    if 'native_mlp' in options:
        native_mlp.apply(out / f'{k}_s0_body.h')
    if 'shadow_half' in options:
        for i in range(passes):
            cfg = (out / f'{k}_s{i}_cfg.h').read_text()
            for flag in ('PX_HALF_ADD_NO_BARRIER', 'PX_HALF_FMA_NO_BARRIER', 'PX_HALF_UNPACK'):
                if f'#define {flag} 1' not in cfg:
                    raise ValueError(f'shadow-half requires {flag}')
            shadow_half.apply(out / f'{k}_s{i}_body.h')
    return layout


def speed_jobs(src, work, rt, dxc, want64=True, fp32=True, fp32b=True):
    """(jobs, metadata): compile jobs (pack name, DXC command, .cso path) for every speed shader this setup builds, and
    the split metadata blobs [(pack name, bytes)]. src: the generated kernels (src/<kernel>); rt: kernels/rt."""
    work = Path(work) / 'speed'
    shutil.rmtree(work, ignore_errors=True)
    jobs, meta = [], []
    for name, kernels, generator, options, fp16, w64 in SPLITS:
        if (w64 and not want64) or (not fp16 and not fp32):
            continue
        out = work / name
        out.mkdir(parents=True)
        suffix = ('_w64' if w64 else '') if fp16 else ('_w64_fp32' if w64 else '_fp32')
        defines = [] if fp16 else list(FP32_DEFINES)
        for k in kernels:
            layout = prepare_split(Path(src), out, k, generator, options, fp16)
            passes = layout.get('passes', 2)
            for i in range(passes):
                stem = f'{k}_s{i}'
                extra = []
                if w64:
                    p = out / f'{stem}.hlsl'
                    p.write_text(wave64(p.read_text(), stem))
                    extra = ['PX_LDS_SHUFFLE=1']
                cso = out / f'px_{stem}{suffix}.cso'
                cmd = [str(dxc), *BASE_ARGS, *(FP16 if fp16 else FP32), *[x for d in defines + extra for x in ('-D', d)],
                       '-I', str(out), '-I', str(rt), '-Fo', str(cso), str(out / f'{stem}.hlsl')]
                jobs.append((f'px_{stem}{suffix}', cmd, cso))
                # GTX 10 (wave32, 32-bit arithmetic): also with the bias-corrected conversion, as the Windows lab built
                # these passes (_fp32b; the DLL takes them only on GTX 10 where f32tof16 truncates)
                if fp32b and not fp16 and not w64:
                    csob = out / f'px_{stem}_fp32b.cso'
                    jobs.append((f'px_{stem}_fp32b', [*cmd[:-3], '-D', 'HX_F2H_HW=1', '-D', 'HX_F2H_TRUNC_BIAS=4', '-Fo',
                                                      str(csob), cmd[-1]], csob))
            version = 4 if 'motion_comp' in layout else 2   # 4: the host binds the motion vectors, writes the filter age
            meta.append((f'px_{k}_split_meta{suffix}', struct.pack('<4sIIII', b'HXOS', version, layout['words_per_cta'],
                                                                   256, passes)))
    out = work / 'win'
    for k in WIN_KERNELS:
        for w64 in ((False, True) if want64 else (False,)):
            d = out / (k + ('_w64' if w64 else ''))
            shutil.copytree(Path(src) / k, d)
            body = d / f'{k}_body.h'
            body.write_text(body.read_text().replace(STASH, STASH_W32))
            hlsl = d / f'{k}.hlsl'
            extra = []
            if w64:
                hlsl.write_text(wave64(hlsl.read_text(), k))
                extra = ['-D', 'PX_LDS_SHUFFLE=1']
            name = f'px_{k}{"_w64" if w64 else ""}_win'
            cso = d / f'{name}.cso'
            jobs.append((name, [str(dxc), *BASE_ARGS[:-2], *FP16[:1], *BASE_ARGS[-2:], *FP16[1:], *extra, '-I', str(d),
                                '-I', str(rt), '-Fo', str(cso), str(hlsl)], cso))
    return jobs, meta
