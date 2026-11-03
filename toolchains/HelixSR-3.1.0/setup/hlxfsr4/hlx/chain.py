# Copyright 2026 lonewolf0622. All rights reserved (HelixSR Freeware License).
"""The shader build chain of HLX FSR 4's kernels, as the tested build made them:
HLSL -> dxc -Fc (LLVM IR) -> fixbc fold -> compiler ident made the reference build's -> assemble -> validate -> DXIL.

One Chain per DXC: the Windows DXC the HelixSR setup downloads (dxc.exe + dxcompiler.dll, run natively on Windows or
through Wine on Linux) or, for development, a Linux DXC of the same commit. Both give the same DXIL once the ident is
the reference one (the only difference between the builds)."""
import os, re, subprocess, threading
from pathlib import Path

# the compiler idents in the tested build (DXC 1.9 commit 0d3ee6b5): the Linux build most kernels came from, and the
# official Windows release v1.9.2607 (the HelixSR setup's DXC) the kernels built on Windows came from. Builds of that
# commit differ in this line only.
IDENTS = {'linux': '!0 = !{!"dxc(private) 1.9.0.1 (0d3ee6b5)"}',
          'windows': '!0 = !{!"dxc(private) 1.9.0.5402 (0d3ee6b55-dirty)"}'}
REF_IDENT = IDENTS['linux']
_IDENT = re.compile(r'^!0 = !\{!"dxc\(private\) 1\.9\.0\.[0-9]+ \(0d3ee6b5[0-9a-f]*(?:-dirty)?\)"\}$', re.M)
HERE = Path(__file__).resolve().parent


class _Batch(threading.local):
    """one dxc_assemble batch process per thread (see tools/dxc_assemble.cpp): dxc.exe's work and dxc_assemble's
    commands through the same dxcompiler.dll, without starting a process (under Wine: about 0.12 s) for every call"""
    proc = None


class Chain:
    """dxc / assemble command lines. wrap: a command prefix (Wine) and path converter for Windows tools on Linux.
    batch: the Windows DXC's calls go to dxc_assemble batch processes (one per worker thread) instead of one process each
    (HELIXSR_DXC_BATCH=0: one process per call, as before)."""

    def __init__(self, dxc, dxcompiler, assemble, wrap=None, topath=None, batch=False):
        self.dxc, self.lib, self.asm = str(dxc), str(dxcompiler), str(assemble)
        self.wrap = list(wrap or []); self.topath = topath or (lambda p: str(p))
        self.batch = batch and os.environ.get('HELIXSR_DXC_BATCH', '1') != '0'
        self._local = _Batch(); self._procs = []; self._plock = threading.Lock()

    @classmethod
    def windows(cls, dxc_dir, assemble, wine=None, prefix=None):
        """the setup's DXC (dxc.exe, dxcompiler.dll) and dxc_assemble.exe; on Linux through Wine"""
        d = Path(dxc_dir)
        if os.name == 'nt' or not wine:
            return cls(d / 'dxc.exe', d / 'dxcompiler.dll', assemble, batch=True)
        env = ['env', 'WINEDEBUG=-all'] + (['WINEPREFIX=' + str(prefix)] if prefix else [])
        return cls(d / 'dxc.exe', d / 'dxcompiler.dll', assemble, wrap=env + [str(wine)],
                   topath=lambda p: 'Z:' + str(Path(p).resolve()).replace('/', '\\'), batch=str(assemble).endswith('.exe'))

    def _job(self, words):
        """one batch job (its words as dxc_assemble batch reads them): (exit code, messages)"""
        p = self._local.proc
        if p is None or p.poll() is not None:
            asm = self.topath(Path(self.asm)) if self.wrap else self.asm
            lib = self.topath(Path(self.lib)) if self.wrap else self.lib
            p = subprocess.Popen(self.wrap + [asm, lib, 'batch'], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                 stderr=subprocess.DEVNULL, encoding='utf-8')
            self._local.proc = p
            with self._plock:
                self._procs.append(p)
        p.stdin.write('\t'.join(words) + '\n'); p.stdin.flush()
        line = p.stdout.readline()
        if not line.startswith('RC '):
            raise RuntimeError(f'dxc_assemble batch ended ({" ".join(words)[:200]})')
        rc, _, msg = line[3:].rstrip('\n').partition('\t')
        return int(rc), msg.replace('\x1f', '\n')

    def close(self):
        """ends the batch processes (they also end with this program)"""
        with self._plock:   # (in place: the transforms() copies share the list)
            procs = self._procs[:]; self._procs.clear()
        for p in procs:
            try:
                p.stdin.close(); p.wait(timeout=30)
            except (OSError, subprocess.TimeoutExpired):
                p.kill()

    def _run(self, exe, *args):
        conv = [self.topath(a) if isinstance(a, Path) else a for a in args]
        if self.batch and '--version' not in args:   # dxc.exe ARGS, or dxc_assemble LIB CMD ARGS: the job without the library
            # (dxc --version runs dxc.exe itself: the setup's first call, which may have to set up the Wine prefix)
            rc, msg = self._job(['dxc'] + conv if exe == self.dxc else conv[1:])
            r = subprocess.CompletedProcess(args, rc, b'', msg.encode())
        else:
            exe = self.topath(exe) if self.wrap else str(exe)
            r = subprocess.run(self.wrap + [exe] + conv, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        if r.returncode:
            raise RuntimeError(f'{Path(str(exe)).name} {" ".join(map(str, args))}: '
                               f'{(r.stderr or r.stdout).decode(errors="replace").strip()[-400:]}')
        return r

    def compile(self, hlsl, dxil, target='cs_6_9', f16=True, fold=True, extra=(), ident='linux'):
        """HLSL -> DXIL (the kernels/*/build.sh steps); returns the DXIL bytes"""
        hlsl, dxil = Path(hlsl), Path(dxil)
        stem = dxil.with_suffix('')
        raw, ll, uns = Path(str(stem) + '.raw.ll'), Path(str(stem) + '.ll'), Path(str(stem) + '.unsigned')
        args = ['-T', target, '-E', 'main'] + (['-enable-16bit-types'] if f16 else []) + ['-O3'] + list(extra)
        self._run(self.dxc, *args, '-Fc', raw, hlsl)
        text = raw.read_text()
        if fold:
            from . import fixbc
            text = fixbc.fold(text)
        ll.write_text(normalize(text, ident))
        return self.assemble(ll, dxil, uns)

    def compile_direct(self, hlsl, dxil, target='cs_6_6', extra=()):
        """HLSL -> DXIL in one dxc call (-Fo), as tools/make_int8_set.py / make_pascal_*_set.py build"""
        self._run(self.dxc, '-T', target, '-E', 'main', *extra, '-O3', Path(hlsl), '-Fo', Path(dxil))
        return Path(dxil).read_bytes()

    def assemble(self, ll, dxil, uns=None):
        """LLVM IR text -> validated DXIL"""
        ll, dxil = Path(ll), Path(dxil)
        uns = Path(uns) if uns else dxil.with_suffix('.unsigned')
        self._run(self.asm, Path(self.lib) if self.wrap else self.lib, 'assemble', ll, uns)
        self._run(self.asm, Path(self.lib) if self.wrap else self.lib, 'validate', uns, dxil)
        return dxil.read_bytes()

    relabel = None   # 'linux' / 'windows': disassembled text gets that compiler ident (see transforms())

    def disasm(self, dxil, ll):
        """DXIL -> LLVM IR text (dxc -dumpbin)"""
        self._run(self.dxc, '-dumpbin', Path(dxil), '-Fc', Path(ll))
        text = Path(ll).read_text()
        if self.relabel:
            text = normalize(text, self.relabel); Path(ll).write_text(text)
        return text

    def transforms(self, ident):
        """this chain for DXIL transforms whose output carries the reference build's ident (a shader compiled with
        another build of the same commit is relabelled when disassembled)"""
        import copy
        c = copy.copy(self); c.relabel = ident; return c

    def tool(self, cmd, *args, check=True):
        """dxc_assemble DLL CMD ARGS (assemble | validate | opt ... passes); returns (returncode, stderr text)"""
        conv = [self.topath(a) if isinstance(a, Path) else a for a in args]
        if self.batch:
            rc, err = self._job([cmd] + conv)
            r = subprocess.CompletedProcess(args, rc)
        else:
            lib = self.topath(Path(self.lib)) if self.wrap else self.lib
            asm = self.topath(Path(self.asm)) if self.wrap else self.asm
            r = subprocess.run(self.wrap + [asm, lib, cmd] + conv, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            err = (r.stderr or b'').decode(errors='replace') + (r.stdout or b'').decode(errors='replace')
        if check and r.returncode:
            raise RuntimeError(f'dxc_assemble {cmd}: {err.strip()[-600:]}')
        return r.returncode, err


def normalize(text, ident='linux'):
    """the compiler ident of the reference build ('linux' or 'windows', see IDENTS)"""
    return _IDENT.sub(lambda m: IDENTS[ident], text)
