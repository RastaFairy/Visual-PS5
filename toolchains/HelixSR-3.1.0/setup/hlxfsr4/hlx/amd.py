# Copyright 2026 lonewolf0622. All rights reserved (HelixSR Freeware License).
"""AMD's FSR 4 driver file (amdxcffx64.dll 2.4.0.4370, AMD Software: Adrenalin Edition 26.10.1): the copy of an
installed AMD driver when it is that version, else the one in AMD's driver package, downloaded from AMD (after the
user agrees). Only the part of the package that holds the file is fetched (a 7z solid block: LZMA2 + x86 BCJ, which
Python's lzma decodes); nothing but this file is kept. Then: AMD's weights and stock shaders, cut out by SHA-256."""
import glob, hashlib, lzma, os, sys, time, urllib.request
from pathlib import Path

SHA256 = 'c33a287f3048bf02311cae430b6a977500b94ca7b315cd7bff751e6b03e483e3'
SIZE = 85684104
PACKAGE = 'https://drivers.amd.com/drivers/whql-amd-software-adrenalin-edition-26.10.1-win11-b.exe'
PACKAGE_PAGE = 'https://www.amd.com/en/support/download/drivers.html'
PACKAGE_BYTES = 1026657048
# the 7z folder holding the file: packed stream (absolute offsets in the .exe), LZMA2 dictionary, the file's offset in
# the folder's output (from the archive's header)
PACK_POS, PACK_SIZE, DICT, FILE_AT = 314872995, 466564014, 16 << 20, 1735473880


def sha256(b):
    return hashlib.sha256(b).hexdigest()


def installed():
    """amdxcffx64.dll of an installed AMD driver (Windows), when it is the supported version"""
    if os.name != 'nt':
        return None
    root = os.environ.get('SystemRoot', r'C:\Windows')
    cands = [os.path.join(root, 'System32', 'amdxcffx64.dll')]
    cands += glob.glob(os.path.join(root, 'System32', 'DriverStore', 'FileRepository', '*', 'amdxcffx64.dll'))
    cands += glob.glob(os.path.join(root, 'System32', 'DriverStore', 'FileRepository', '*', '*', 'amdxcffx64.dll'))
    for c in cands:
        try:
            if os.path.getsize(c) == SIZE:
                b = Path(c).read_bytes()
                if sha256(b) == SHA256:
                    return b, c
        except OSError:
            pass
    return None


def download(progress=None):
    """the file out of AMD's driver package (streams the block that holds it, about 420 MB)"""
    dec = lzma.LZMADecompressor(lzma.FORMAT_RAW, filters=[{'id': lzma.FILTER_X86}, {'id': lzma.FILTER_LZMA2, 'dict_size': DICT}])
    rq = urllib.request.Request(PACKAGE, headers={'Range': f'bytes={PACK_POS}-{PACK_POS + PACK_SIZE - 1}',
                                                  'Referer': 'https://www.amd.com/', 'User-Agent': 'Mozilla/5.0'})
    pos = 0; got = bytearray(); fetched = 0
    with urllib.request.urlopen(rq, timeout=60) as resp:
        while len(got) < SIZE:
            chunk = resp.read(1 << 20)
            if not chunk:
                raise RuntimeError('AMD\'s driver package ended early')
            fetched += len(chunk)
            out = dec.decompress(chunk)
            while True:
                lo, hi = max(pos, FILE_AT), min(pos + len(out), FILE_AT + SIZE)
                if lo < hi:
                    got += out[lo - pos:hi - pos]
                pos += len(out)
                if len(got) >= SIZE or dec.needs_input:
                    break
                out = dec.decompress(b'')
            if progress:
                progress(min(1.0, fetched / (PACK_SIZE * 0.9)))
    b = bytes(got)
    if sha256(b) != SHA256:
        raise RuntimeError('amdxcffx64.dll from AMD\'s package is not the expected file (AMD changed the package?)')
    return b


def cut(dll, pieces):
    """the pieces of AMD's file the build uses ({name: [offset, size, sha256]}, data/amd_pieces.json): AMD's weights
    and stock shaders, each checked by its SHA-256 -> {name: bytes}"""
    if sha256(dll) != SHA256:
        raise RuntimeError('not the supported amdxcffx64.dll')
    out = {}
    for name, (o, n, h) in pieces.items():
        b = dll[o:o + n]
        if sha256(b) != h:
            raise RuntimeError(f'{name}: not where it should be in amdxcffx64.dll')
        out[name] = b
    return out


def get(yes=False, progress=None, log=print):
    """(AMD's file, where it came from): the installed driver's copy, else downloaded from AMD's package"""
    got = installed()
    if got:
        log(f'AMD\'s FSR 4 file from the installed driver: {got[1]}')
        return got
    log('AMD\'s FSR 4 file (amdxcffx64.dll 2.4.0.4370) comes from AMD\'s driver package '
        f'(AMD Software: Adrenalin Edition 26.10.1, {PACKAGE_PAGE}); about 420 MB of it are downloaded.')
    if not yes:
        if not sys.stdin.isatty() or input('Download it from AMD now? [Y/n] ').strip().lower() not in ('', 'y', 'yes'):
            raise SystemExit('AMD\'s file is needed for HLX FSR 4')
    t0 = time.time()
    b = download(progress)
    log(f'amdxcffx64.dll from AMD\'s package ({time.time() - t0:.0f} s)')
    return b, PACKAGE
