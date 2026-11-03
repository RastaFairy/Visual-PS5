# Copyright 2026 lonewolf0622. All rights reserved (HelixSR Freeware License).
"""HLX FSR 4's data appended to its code-only DLL: AMD's weights (std, ultra) and the built blobs in the order of
data/layout.json, each checked by its SHA-256, then "HLXFSR4D", the data's size and FNV-1a 64 (what the DLL checks).
payload.py BUILD_DIR CODE_DLL OUT_DLL"""
import hashlib, json, struct, sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
MAGIC = b'HLXFSR4D'


def data(build, layout):
    w = Path(build) / 'optimize/own_runtime/fam/w'
    parts = [(w / 'weights_std.bin').read_bytes(), (w / 'weights_ultra.bin').read_bytes()]
    for b, h in zip(parts, layout['weights']):
        if hashlib.sha256(b).hexdigest() != h:
            raise RuntimeError('AMD\'s weights are not the expected ones')
    for rel, h in layout['blobs']:
        b = (Path(build) / rel).read_bytes()
        if hashlib.sha256(b).hexdigest() != h:
            raise RuntimeError(f'{rel}: not the shader this HLX FSR 4 was built for')
        parts.append(b)
    d = b''.join(parts)
    if len(d) != layout['bytes']:
        raise RuntimeError('HLX FSR 4\'s data has the wrong size')
    return d


def append(code_dll, out_dll, build, layout=None):
    """code-only HLX FSR 4 DLL + its data -> out_dll"""
    layout = layout or json.loads((HERE.parent / 'data' / 'layout.json').read_text())
    code = Path(code_dll).read_bytes()
    if code[-24:-16] == MAGIC:
        raise RuntimeError(f'{code_dll} already carries data')
    d = data(build, layout)
    Path(out_dll).write_bytes(code + d + MAGIC + struct.pack('<QQ', len(d), int(layout['fnv1a64'], 16)))
    return len(d)


if __name__ == '__main__':
    n = append(sys.argv[2], sys.argv[3], sys.argv[1])
    print(f'{sys.argv[3]}: {n} bytes of data appended')
