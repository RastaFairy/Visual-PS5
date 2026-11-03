# Copyright 2026 lonewolf0622. All rights reserved (HelixSR Freeware License).
"""Shader job construction shared with the distributed local network setup."""
import re


def combined_stores(name, directory, filename):
    """An input kernel (px_k8_*) with write-combined network-input stores (HX_GST16_COMBINE: the same memory contents;
    the Windows lab's GTX 10 builds), as a new source next to it; None when its shape does not allow it (the
    combining needs stores in program order to a buffer the kernel never reads, and no early return)."""
    stem = name[3:]
    if not stem.startswith('k8_'):
        return None
    source = directory / filename
    text = source.read_text()
    call = f'{{ {stem}_body(tid, gid); }}'
    body = directory / f'{stem}_body.h'
    if text.count(call) != 1 or not body.is_file():
        return None
    b = body.read_text()
    if 'return;' in b or re.search(r'PX_GLD\w*\(0,', b):
        return None
    out = directory / ('gst_' + filename)
    out.write_text(text.replace(call, f'{{ {stem}_body(tid, gid); HX_GST_FLUSH(); }}'))
    return out


def shader_jobs(shaders, work, rt, dxc, dxc_args, lds_reads, wave64=True, fp32=True, fp32h=True, fp32b=True):
    """fp32h: also the FP32 builds with the GPU's own fp32 -> fp16 conversion (_fp32h, _w64_fp32h), which the DLL
    selects only where a run-time check finds that conversion rounding to nearest even.
    fp32b: and wave32 FP32 builds of the conversion with an integer bias (HX_F2H_TRUNC_BIAS=4: round to nearest even for
    normal fp16 values; the input kernels also with combined stores), the Windows lab's quality-gated GTX 10 builds,
    which the DLL selects only on GTX 10 where the conversion truncates (Windows). Identical ones are left out later."""
    jobs = []
    args32 = [x for x in dxc_args if x != '-enable-16bit-types'] + ['-D', 'HX_FP32=1']
    args32h = args32 + ['-D', 'HX_F2H_HW=1']
    args32b = args32h + ['-D', 'HX_F2H_TRUNC_BIAS=4']
    for name, directory, filename in shaders:
        source = directory / filename
        # '#define HX_FP32_ONLY 1' in a shader: an alternative for 32-bit arithmetic only (its native builds would be
        # another shader's): only the _fp32 / _fp32h / _w64_fp32 / _w64_fp32h builds
        fp32_only = '#define HX_FP32_ONLY 1' in source.read_text()
        if fp32_only and not fp32:
            continue
        variants = [] if fp32_only else [('', dxc_args, source)]
        if fp32:
            variants.append(('_fp32', args32, source))
            if fp32h:
                variants.append(('_fp32h', args32h, source))
            if fp32h and fp32b:
                gst = combined_stores(name, directory, filename)
                variants.append(('_fp32b', args32b + (['-D', 'HX_GST16_COMBINE=1'] if gst else []), gst or source))
        if wave64:
            text = source.read_text()
            if '[WaveSize(32)]' not in text:
                raise ValueError(f'{name}: no wave32 attribute')
            text = text.replace('[WaveSize(32)]', '[WaveSize(64)]')
            extra = []
            if name[3:] in lds_reads or name[3:].startswith(('k8_', 'm8_', 'c8_')):
                text, count = re.subn(
                    r'\{ (\w+_body)\(tid, gid\); \}',
                    r'{ PX_SET_GI(tid.x + tid.y * PX_BLOCK_X + tid.z * PX_BLOCK_X * PX_BLOCK_Y); \1(tid, gid); }', text)
                if count != 1:
                    raise ValueError(f'{name}: unrecognized entry point')
                extra = ['-D', 'PX_LDS_SHUFFLE=1']
            source64 = directory / ('w64_' + filename)
            source64.write_text(text)
            if not fp32_only:
                variants.append(('_w64', dxc_args + extra, source64))
            if fp32:
                variants.append(('_w64_fp32', args32 + extra, source64))
                if fp32h:
                    variants.append(('_w64_fp32h', args32h + extra, source64))
        for suffix, args, source in variants:
            output = work / (name + suffix + '.cso')
            jobs.append((name + suffix, [dxc] + args + ['-I', directory, '-I', rt, '-Fo', output, source], output))
    return jobs
