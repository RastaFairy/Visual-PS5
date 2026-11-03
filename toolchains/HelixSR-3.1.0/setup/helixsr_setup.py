#!/usr/bin/env python3
# Copyright 2026 lonewolf0622. All rights reserved (HelixSR Freeware License).
"""helixsr_setup.py RELEASE_DIR [--dlss NVNGX_DLSS_DLL] [--dlssg NVNGX_DLSSG_DLL]... [--yes] [--dxc DXC] [--keep WORK_DIR]
                   [--no-wave64] [--no-fp32] [--no-fp32h] [--no-fp32b] [--no-speed-shaders] [--no-fg | --fg-only] [--status]
                   [--dxc-dir DIR --dxc2609-dir DIR [--wine WINE --wineprefix PFX]] [--amd AMDXCFFX64_DLL] [--no-hlx]

HelixSR 2.0 setup: builds HelixSR's network and its DLSS frame generation on the user's machine. The result is the
folder RELEASE_DIR/HelixSR (HelixSR's NGX DLL with the network inside, helixsr.ini and helixsr-fg with
frame generation), ready for HelixSR Scaler.
Network, from NVIDIA's DLSS 310.7.0 DLL, downloaded from NVIDIA's own GitHub (github.com/NVIDIA/DLSS, after the user
agrees) or taken from a local copy (--dlss, e.g. from a game):
  1. weights  (plain fp32 tensors in the DLL, converted as NVIDIA does)
  2. PTX of the network kernels (CUDA fatbins in the DLL; sm_89 when present, else sm_80)
  3. fragment tables of the family kernels (PTX simulator on launches built by HelixSR's host model)
  4. HLSL of every network kernel (translator + HelixSR's scheduling recipes)
  5. DXIL shaders; weights and shaders are appended to HelixSR/helixsr.dll
Frame generation (fg/fg_setup.py --layout ngx): NVIDIA's DLSS Frame Generation DLL 310.3 (Streamline SDK
on NVIDIA's GitHub, or --dlssg files), NVIDIA's NGX core (NVIDIA's Linux driver package), each checked by SHA-256, and
the kernel archives built from them into HelixSR/helixsr-fg (shader model 6.6; with variants for GPUs with
64-lane waves only and for GPUs without native 16-bit shader ops, as the network's shaders).
HLX FSR 4 (setup/hlxfsr4): AMD's FSR 4 driver file amdxcffx64.dll 2.4.0.4370 (an installed AMD driver's copy, --amd, or the
part of AMD's driver package AMD Software 26.10.1 that holds it, downloaded from AMD after the user agrees); AMD's weights
and stock shaders are cut out of it, every HLX FSR 4 shader is generated and compiled from them (DXC v1.9.2607 and
v1.9.2609 for Windows: --dxc-dir / --dxc2609-dir, through --wine on Linux) and checked against the tested build's SHA-256,
then appended to the release's HLX FSR 4 DLLs (HLX-FSR4/ and helixsr-scaler/OptiScaler/).
--status prints what is built (network=0|1 fg=0|1 hlx=0|1). Nothing leaves the machine. Needs Python 3 with numpy and DXC (the
DirectX shader compiler)."""
import os as _o, sys as _s; _s.path.insert(0, _o.path.dirname(_o.path.abspath(__file__)))  # helixsr-setup
import hashlib, json, os, re, shutil, struct, subprocess, sys, tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
# NVIDIA's DLSS SDK release v310.7.0, the DLL this setup is verified with (checked before use)
DLSS_URL = 'https://raw.githubusercontent.com/NVIDIA/DLSS/v310.7.0/lib/Windows_x86_64/rel/nvngx_dlss.dll'
DLSS_SHA256 = 'be6e434a94ca32499515eb62ca0e6c274526055d568d0426e4c652dcdfb6ee6e'
DLSS_LICENSE = 'https://github.com/NVIDIA/DLSS/blob/v310.7.0/LICENSE.txt'


def download_dlss(work, assume_yes):
    print(f"HelixSR needs NVIDIA's DLSS 310.7.0 DLL to build its network on this PC. It will be downloaded from\n"
          f"NVIDIA's GitHub ({DLSS_URL}), used once and deleted. The DLL is NVIDIA's, under NVIDIA's license:\n"
          f"{DLSS_LICENSE}")
    if not assume_yes and input('Download it now? [Y/n] ').strip().lower() not in ('', 'y', 'yes'):
        raise SystemExit('Nothing was built: HelixSR does not work until the setup has built its network. Run the setup '
                         'again and answer y, or pass a local copy of the DLL with --dlss <path>.')
    import urllib.request
    path = work / 'nvngx_dlss.dll'
    step('downloading nvngx_dlss.dll from NVIDIA')
    with urllib.request.urlopen(DLSS_URL, timeout=120) as r, open(path, 'wb') as f:
        size = int(r.headers.get('Content-Length') or 0)
        got = 0
        while True:
            chunk = r.read(1 << 20)
            if not chunk:
                break
            f.write(chunk)
            got += len(chunk)
            BAR.draw(100.0 * got / size if size else 0, f'download {got >> 20}/{size >> 20} MB', 0)
    BAR.clear()
    data = path.read_bytes()
    if hashlib.sha256(data).hexdigest() != DLSS_SHA256:
        path.unlink()
        raise SystemExit('the downloaded file is not the expected DLSS 310.7.0 DLL; nothing was built')
    path.unlink()
    return data
LIB = HERE / 'lib'
sys.path.insert(0, str(LIB))
PAK_MAGIC = b'HXSRKPAK'
PAK_VERSION = 2
# wave64 kernels whose cross-lane reads go through LDS (verified bit-identical with wave32; not the small reductions)
LDS_READS = {'k5', 'k5f', 'k5n', 'k5x', 'k5fx', 'k5nx', 'k5nxf', 'k7', 'k9', 'k10', 'k11'}
DXC_ARGS = ['-T', 'cs_6_6', '-E', 'main', '-O3', '-HV', '2021', '-enable-16bit-types', '-D', 'PX_FAST=1']


def step(msg):
    BAR.clear()
    print(f'[helixsr-setup] {msg}', flush=True)


class Progress:
    """One bar for the whole build. Each stage has a share of the bar (its typical share of the build time) and
    reports how far it is (0..1). On a terminal the bar is redrawn in place; in a log only stage changes are printed."""
    STAGES = [('weights', 2), ('ptx', 5), ('tables', 6), ('sources', 12), ('shaders', 75)]   # measured (16 threads)

    def __init__(self, stages=None):
        self.STAGES = stages or self.STAGES
        self.tty = True   # lines, not in-place redraws: fine for terminals and logs alike
        self.start = {k: sum(w for _, w in self.STAGES[:i]) for i, (k, _) in enumerate(self.STAGES)}
        self.weight = dict(self.STAGES)
        self.total = sum(self.weight.values())
        self.shown = False
        self.times = {}
        import time, threading
        self.clock = time.monotonic
        self.t0 = None
        self.lock = threading.Lock()
        self.cur = None   # (stage, frac or a function returning it, label): redrawn twice a second while active
        self.ticker = None

    def update(self, stage, frac, label):
        now = self.clock()
        with self.lock:
            if self.t0 is None:
                self.t0 = now
            self.times.setdefault(stage, now)
            self.cur = (stage, frac, label)
            self._redraw(now)
        if self.tty and self.ticker is None:
            import threading
            self.ticker = threading.Thread(target=self._tick, daemon=True)
            self.ticker.start()

    def _redraw(self, now):
        stage, frac, label = self.cur
        f = frac() if callable(frac) else frac
        pct = 100.0 * (self.start[stage] + self.weight[stage] * min(max(f, 0.0), 1.0)) / self.total
        if f < 1.0:
            pct = min(pct, 99.0)
        self.draw(pct, label() if callable(label) else label, now - self.t0)

    def _tick(self):
        import time
        while True:
            time.sleep(0.5)
            with self.lock:
                if self.cur is not None:
                    self._redraw(self.clock())

    def draw(self, pct, label, elapsed):
        """A new line whenever the bar moves on by 5% (or every 5 seconds): no in-place redrawing, which some terminals
        (and log views) do not show, so it reads the same everywhere."""
        now = self.clock()
        step5 = int(pct // 5)
        if step5 == getattr(self, '_last5', None) and now - getattr(self, '_lastT', 0) < 5:
            return
        self._last5, self._lastT = step5, now
        n = int(20 * pct / 100)
        el = int(elapsed)
        print(f'[helixsr-setup] [{"#" * n}{"-" * (20 - n)}] {pct:4.0f}%  {el // 60}:{el % 60:02d}  {label}', flush=True)

    def report_times(self):
        """HELIXSR_SETUP_TIMES=1: seconds per stage (to tune STAGES)."""
        if not os.environ.get('HELIXSR_SETUP_TIMES'):
            return
        ks = [k for k, _ in self.STAGES if k in self.times] + ['end']
        self.times['end'] = self.clock()
        print('[helixsr-setup] stage seconds: ' + ', '.join(f'{a} {self.times[b] - self.times[a]:.0f}' for a, b in zip(ks, ks[1:])))

    def clear(self):
        with self.lock:
            self.cur = None   # the ticker stops drawing until the next update
            self._clear()

    def _clear(self):
        if self.shown:
            sys.stdout.write('\n')
            self.shown = False


BAR = Progress()


def run(cmd, env=None, **kw):
    p = subprocess.run([str(c) for c in cmd], env=env, capture_output=True, text=True, **kw)
    if p.returncode:
        raise SystemExit(f'failed: {" ".join(map(str, cmd))}\n{p.stdout[-2000:]}{p.stderr[-2000:]}')
    return p.stdout


def amd_gpus():
    """PCI device ids of this PC's AMD display GPUs (Linux: sysfs, Windows: the registry); empty if none found."""
    ids = set()
    if os.name == 'nt':
        try:
            import winreg
            with winreg.OpenKey(winreg.HKEY_LOCAL_MACHINE, r'SYSTEM\CurrentControlSet\Enum\PCI') as pci:
                for k in range(4096):
                    try:
                        name = winreg.EnumKey(pci, k)
                    except OSError:
                        break
                    if not name.upper().startswith('VEN_1002&DEV_'):
                        continue
                    with winreg.OpenKey(pci, name) as dk:
                        for j in range(64):
                            try:
                                inst = winreg.EnumKey(dk, j)
                            except OSError:
                                break
                            try:
                                with winreg.OpenKey(dk, inst) as ik:
                                    if str(winreg.QueryValueEx(ik, 'Class')[0]).lower() == 'display':
                                        ids.add(int(name[13:17], 16))
                            except OSError:
                                pass
        except OSError:
            pass
    else:
        for d in Path('/sys/class/drm').glob('card[0-9]*/device'):
            try:
                if (d / 'vendor').read_text().strip() == '0x1002' and (d / 'class').read_text().startswith('0x03'):
                    ids.add(int((d / 'device').read_text(), 16))
            except (OSError, ValueError):
                pass
    return ids


def rdna3_or_newer(dev):
    """Same rule as the DLL: these GPUs run the network kernels at 64 lanes."""
    return (0x7440 <= dev <= 0x74ff or 0x7550 <= dev <= 0x75ff or
            dev in (0x15bf, 0x15c8, 0x1900, 0x1901, 0x150e, 0x1586, 0x1114))


EMBED_MAGIC = b'HXSRNET1'
DROP_IN_README = '''HelixSR for FSR 3.1 games, one file (the network is inside the DLL).

Most FSR 3.1 games: go to the folder that holds the game's amd_fidelityfx_upscaler_dx12.dll (or, if there is none,
amd_fidelityfx_dx12.dll), rename the game's file to amd_fidelityfx_upscaler_dx12.original.dll (or
amd_fidelityfx_dx12.original.dll), and copy the file with the same name from this folder there. Start the game and
pick AMD FSR. Keep the .original.dll: FSR frame generation keeps working through it, and renaming it back undoes
everything. helixsr.log next to the DLL shows what HelixSR is doing.

These DLLs contain NVIDIA's network: they are for your own PC, do not share or upload them. For DLSS frame generation
and for games without FSR 3.1, use the HelixSR-fsrfg folder with HelixSR Scaler instead.
'''


def network_sizes(footer, file_size):
    """Validate an embedded network's footer before trusting its sizes."""
    if len(footer) != 32 or footer[:8] != EMBED_MAGIC:
        return None
    nw, np_, version = struct.unpack('<QQQ', footer[8:])
    if version != 1 or not (0 < nw < 1 << 31 and 0 < np_ < 1 << 31):
        return None
    if nw + np_ > file_size - 32:
        return None
    return nw, np_


def embed(dll_path, weights, pak):
    """Appends the network to HelixSR's DLL: [DLL][weights][pak][footer: magic, u64 weights size, u64 pak size,
    u64 format 1]. Windows does not map data after a DLL's sections; HelixSR reads it from its own file. An earlier
    payload is replaced."""
    data = dll_path.read_bytes()
    if data[-32:-24] == EMBED_MAGIC:
        sizes = network_sizes(data[-32:], len(data))
        if sizes is None:
            raise SystemExit(f'{dll_path} has an invalid network footer; restore the DLL from the package before rebuilding')
        nw, np_ = sizes
        data = data[:len(data) - 32 - nw - np_]
    if data[:2] != b'MZ':
        raise SystemExit(f'{dll_path} is not a DLL')
    tmp = dll_path.with_name(dll_path.name + '.tmp')
    want = data + weights + pak + EMBED_MAGIC + struct.pack('<QQQ', len(weights), len(pak), 1)
    tmp.write_bytes(want)
    os.replace(tmp, dll_path)
    # check what is on disk now (security software or sync folders can block or change a fresh DLL)
    got = dll_path.read_bytes()
    if got != want:
        raise SystemExit(f'{dll_path} is not what was written: {len(got)} bytes on disk, {len(want)} written'
                         f'{" (no network at its end)" if got[-32:-24] != EMBED_MAGIC else ""}. Something on this PC changes '
                         'or replaces new DLLs in this folder (antivirus, a synced folder such as OneDrive): extract HelixSR '
                         'into a plain folder such as C:\\HelixSR and run the setup there.')
    return len(got)


FSRFG = 'HelixSR-fsrfg'
NGX = 'HelixSR'


def release_dirs(p):
    """Prefer the NGX package; retain the explicitly selected FidelityFX layout."""
    p = Path(p).resolve()
    # The extracted package may itself be called HelixSR. Prefer a populated
    # child layout before treating that package name as the DLL folder.
    if (p / NGX / 'helixsr.dll').is_file():
        return p, p / NGX
    if (p / FSRFG / 'amd_fidelityfx_dx12.dll').is_file():
        return p, p / FSRFG
    if p.name.lower() in (NGX.lower(), FSRFG.lower()):
        return p.parent, p
    return p, p / FSRFG


def upscaler_dll(out):
    return next((out / n for n in ('helixsr.dll', 'amd_fidelityfx_dx12.dll', 'nvngx.dll')
                 if (out / n).is_file()), out / 'helixsr.dll')


def fg_module():
    import importlib.util
    spec = importlib.util.spec_from_file_location('fg_setup', HERE / 'fg' / 'fg_setup.py')
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m


def status(p):
    """(network built into HelixSR's DLL, frame generation complete in helixsr-fg)"""
    _, fsr = release_dirs(p)
    d = upscaler_dll(fsr)
    try:
        with open(d, 'rb') as f:
            size = f.seek(0, 2)
            f.seek(-32, 2)
            net = network_sizes(f.read(32), size) is not None
    except OSError:
        net = False
    try:
        fg = not fg_module().fg_ready(fsr)
    except Exception:
        fg = False
    return net, fg


def build_fg(out, dxc, a):
    """frame generation (fg/fg_setup.py --layout ngx) into out/helixsr-fg; 0 when it is complete. A failure leaves the
    upscaler as it is. A package without the frame-generation setup (no fg folder) builds the network only."""
    if '--no-fg' in a or not (HERE / 'fg' / 'fg_setup.py').is_file():
        return 0
    cmd = [sys.executable, '-I', str(HERE / 'fg' / 'fg_setup.py'), str(out), '--dxc', str(dxc), '--layout', 'ngx']
    for k in ('--yes', '--no-ngx-core'):
        if k in a:
            cmd.append(k)
    for i, x in enumerate(a):
        if x == '--dlssg' and i + 1 < len(a):
            cmd += ['--dlssg', a[i + 1]]
    if '--keep' in a:
        cmd += ['--keep', str(Path(a[a.index('--keep') + 1]) / 'fg')]
    # the frame-generation kernels' variants follow the network's options: w64 (64-lane waves), fp32 (no native 16-bit
    # ops) and w64_fp32, each left out with --no-wave64 / --no-fp32
    v = [x for x in ('w64', 'fp32', 'w64_fp32')
         if not ('--no-wave64' in a and 'w64' in x) and not ('--no-fp32' in a and 'fp32' in x)]
    cmd += ['--variants', ','.join(v) if v else 'none']
    step('frame generation: NVIDIA\'s DLSS Frame Generation 310.3 for HelixSR Scaler')
    r = subprocess.run(cmd)
    if r.returncode:
        step('frame generation was not built (the upscaler works as before); run the setup again to retry')
    return r.returncode


HLX_DLL = 'amd_fidelityfx_upscaler_dx12.dll'
HLX_MAGIC = b'HLXFSR4D'


def hlx_targets(rel):
    """the release's HLX FSR 4 DLLs (code only until the setup appends their data)"""
    return [p for p in (rel / 'HLX-FSR4' / HLX_DLL, rel / 'helixsr-scaler' / 'OptiScaler' / HLX_DLL) if p.is_file()]


def hlx_data(dll):
    """(code bytes, has data) of an HLX FSR 4 DLL"""
    b = Path(dll).read_bytes()
    if len(b) > 24 and b[-24:-16] == HLX_MAGIC:
        n = struct.unpack_from('<Q', b, len(b) - 16)[0]
        return b[:len(b) - 24 - n], True
    return b, False


DXC2609 = ('https://github.com/microsoft/DirectXShaderCompiler/releases/download/v1.9.2609/dxc_2026_09_29.zip',
           'ad31b1fc8443175d204f77a611fdb3ef2ec42759bdc2f1167368de24a4a7e7f1')


def hlx_compilers(a):
    """(DXC 2607 folder, DXC 2609 folder, wine, wine prefix) for HLX FSR 4: what the setup scripts pass, else found from
    --dxc alone (HelixSR's app passes only that: dxc.exe on Windows, its dxc-wine.sh wrapper on Linux). DXC 2609 is
    downloaded next to the 2607 folder when it is missing (Microsoft's GitHub release, checked by SHA-256)."""
    opt = lambda k: a[a.index(k) + 1] if k in a else None
    d7, d9, wine, pfx = opt('--dxc-dir'), opt('--dxc2609-dir'), opt('--wine'), opt('--wineprefix')
    dxc = opt('--dxc')
    if not d7 and dxc:
        dp = Path(dxc)
        if dp.name.lower() == 'dxc.exe':
            d7 = str(dp.parent)
        elif dp.is_file():   # a wrapper: WINEPREFIX="P" WINEDEBUG=-all exec "WINE" "DXC.EXE" ...
            import re
            m = re.search(r'WINEPREFIX="([^"]+)".*?exec "([^"]+)" "([^"]+dxc\.exe)"', dp.read_text(errors='replace'))
            if m:
                pfx, wine, d7 = pfx or m.group(1), wine or m.group(2), str(Path(m.group(3)).parent)
    if d7 and not d9:
        d9p = Path(d7).parent / 'dxc2609'
        if not (d9p / 'dxc.exe').is_file():
            import hashlib, io, urllib.request, zipfile
            step('downloading the DirectX Shader Compiler 1.9.2609 (HLX FSR 4 needs it too)')
            data = urllib.request.urlopen(DXC2609[0], timeout=120).read()
            if hashlib.sha256(data).hexdigest() != DXC2609[1]:
                raise RuntimeError('the DirectX Shader Compiler 1.9.2609 download is not the expected file')
            with zipfile.ZipFile(io.BytesIO(data)) as z:
                for n in z.namelist():
                    t = n.replace('\\', '/')
                    if t.startswith('bin/x64/') and not t.endswith('/'):
                        d9p.mkdir(parents=True, exist_ok=True)
                        (d9p / t[len('bin/x64/'):]).write_bytes(z.read(n))
        d9 = str(d9p)
    return d7, d9, wine, pfx


def hlx_exit(r, a):
    """Exit code for HLX FSR 4 not built: 4 for the setup scripts (they pass --dxc-dir and say so at the end); 0 for
    HelixSR's app, which takes any other code as the network build failing (the reason is in the lines above)."""
    return r if '--dxc-dir' in a else 0


def build_hlx(rel, a):
    """HLX FSR 4's shaders from AMD's FSR 4 driver file, appended to the release's HLX FSR 4 DLLs; 0 when done"""
    targets = hlx_targets(rel)
    if '--no-hlx' in a or not targets or not (HERE / 'hlxfsr4' / 'hlx').is_dir():
        return 0
    if all(hlx_data(t)[1] for t in targets) and '--rebuild' not in a:
        return 0
    opt = lambda k: a[a.index(k) + 1] if k in a else None
    try:
        d7, d9, wine, pfx = hlx_compilers(a)
    except Exception as e:
        step(f'HLX FSR 4 was not built: {e}'); return 4
    if not d7:
        step('HLX FSR 4 was not built: the shader compiler (dxc.exe) was not found')
        return 4
    sys.path.insert(0, str(HERE / 'hlxfsr4'))
    from hlx import amd, build as hb, chain as ch, payload
    bar = Progress([('amd', 25), ('hlx', 75)])   # (AMD's download, when there is one: about a minute)
    step('HLX FSR 4: its shaders are built from AMD\'s FSR 4 driver file (amdxcffx64.dll 2.4.0.4370)')
    try:
        if opt('--amd'):
            dll = Path(opt('--amd')).read_bytes()
            if amd.sha256(dll) != amd.SHA256:
                raise SystemExit(f'{opt("--amd")} is not amdxcffx64.dll 2.4.0.4370 (AMD Software 26.10.1)')
        else:
            dll = amd.get('--yes' in a, progress=lambda f: bar.update('amd', f, "AMD's driver package"), log=step)[0]
            bar.clear()
    except Exception as e:   # (a download or unpacking error of any kind: the rest of the setup goes on)
        bar.clear(); step(f'HLX FSR 4 was not built: {e}'); return 4
    asm = HERE / 'hlxfsr4' / 'tools' / 'dxc_assemble.exe'
    c = ch.Chain.windows(d7, asm, wine, pfx)
    c9 = ch.Chain.windows(d9, asm, wine, pfx)
    work = Path(tempfile.mkdtemp(prefix='helixsr-hlx-'))
    try:
        c._run(c.dxc, '--version')   # alone first: it may have to set up the compiler's Wine prefix
        ctx = hb.Ctx(work, c, compile_workers(64), c9)
        ctx.progress = lambda f: bar.update('hlx', f, 'HLX FSR 4 shaders')
        bad, missing = hb.run_all(ctx, dll)
        bar.clear()
        if bad or missing:
            step(f'HLX FSR 4 was not built: {len(bad)} shaders did not come out as tested, {len(missing)} were not made '
                 f'(first: {(bad + missing)[0]})')
            return 4
        for t in targets:
            code, _ = hlx_data(t)
            tmp = t.with_suffix('.code.tmp'); tmp.write_bytes(code)
            payload.append(tmp, t.with_suffix('.new.tmp'), work)
            os.replace(t.with_suffix('.new.tmp'), t); tmp.unlink()
        step(f'done: HLX FSR 4 built ({len(ctx.seen)} shaders, checked) into {", ".join(str(t) for t in targets)}')
        step('they contain data built from AMD\'s FSR 4 driver file: they are for your own PC, do not share or upload them')
        return 0
    except (OSError, RuntimeError) as e:
        bar.clear(); step(f'HLX FSR 4 was not built: {e}'); return 4
    finally:
        shutil.rmtree(work, ignore_errors=True)


def compile_workers(n):
    """Shader compilers to run at once: one per CPU thread, as many as the free memory allows (about 600 MB each
    under Wine), HELIXSR_SETUP_JOBS to set it."""
    env = os.environ.get('HELIXSR_SETUP_JOBS', '')
    if env.isdigit() and int(env) > 0:
        return max(1, min(n, int(env)))
    cpus = os.cpu_count() or 4
    try:
        avail = next(int(l.split()[1]) for l in open('/proc/meminfo') if l.startswith('MemAvailable:')) // 1024
        cpus = min(cpus, max(2, avail // 600))
    except (OSError, StopIteration, ValueError):
        pass
    return max(1, min(n, cpus))


def main():
    a = sys.argv[1:]
    opt = lambda k: a[a.index(k) + 1] if k in a else None
    dxc = opt('--dxc') or shutil.which('dxc')
    keep = Path(opt('--keep')) if opt('--keep') else None
    pos = [x for i, x in enumerate(a)
           if not x.startswith('--') and (i == 0 or a[i - 1] not in ('--dxc', '--keep', '--dlss', '--dlssg', '--dxc-dir',
                                                                     '--dxc2609-dir', '--wine', '--wineprefix', '--amd'))]
    if '--status' in a and len(pos) == 1:   # for the setup scripts and HelixSR's app: what is built already
        net, fg = status(Path(pos[0]))
        hlx = all(hlx_data(t)[1] for t in hlx_targets(release_dirs(Path(pos[0]))[0])) or not (HERE / 'hlxfsr4' / 'hlx').is_dir()
        print(f'network={int(net)} fg={int(fg)} hlx={int(hlx)}')
        return
    if len(pos) != 1 or not dxc:
        raise SystemExit(__doc__)
    rel, out = release_dirs(Path(pos[0]))
    target = upscaler_dll(out)
    if not target.is_file():
        raise SystemExit(f'{target} is missing: extract the whole HelixSR package and run the setup '
                         'in its folder')
    if '--fg-only' in a:   # the network is there already: HLX FSR 4 and frame generation
        r = hlx_exit(build_hlx(rel, a), a)
        sys.exit(build_fg(out, dxc, a) or r)
    work = keep or Path(tempfile.mkdtemp(prefix='helixsr-setup-'))
    work.mkdir(parents=True, exist_ok=True)
    dll = Path(opt('--dlss')).read_bytes() if opt('--dlss') else download_dlss(work, '--yes' in a)
    dll_sha = hashlib.sha256(dll).hexdigest()

    step('building the network (this can take several minutes)')
    BAR.update('weights', 0, 'weights')
    import extract_weights
    (out / 'helixsr_weights.bin').write_bytes(extract_weights.extract(dll))

    BAR.update('ptx', 0, 'reading the network kernels')
    import extract_ptx
    from kernels import ENTRY
    ptx = work / 'ptx'
    ptx.mkdir(exist_ok=True)
    have = set()
    for entry, sm, text in extract_ptx.modules(dll):
        (ptx / f'{entry}.sm_{sm}.ptx').write_text(text)
        have.add((entry, sm))
    sm = next((s for s in (89, 80) if all((e, s) in have for e in ENTRY.values())), None)
    if sm is None:
        raise SystemExit('this nvngx_dlss.dll does not contain the network kernels HelixSR uses')
    env = dict(os.environ, HELIXSR_PTX_DIR=str(ptx), HELIXSR_PTX_SM=str(sm),
               HELIXSR_FAMILY_TABLES=str(work / 'tables'))
    BAR.update('tables', 0, 'fragment tables')
    m = LIB / 'model'
    synth = m / ('launch_synth.exe' if os.name == 'nt' else 'launch_synth')   # prebuilt, static
    if not synth.exists():
        cxx = os.environ.get('CXX') or shutil.which('g++') or shutil.which('clang++')
        if not cxx:
            raise SystemExit('no prebuilt launch_synth and no C++ compiler found')
        synth = work / synth.name
        run([cxx, '-std=c++17', '-O2', f'-I{m}', m / 'model.cpp', m / 'launch_synth.cpp', '-o', synth])
    families = ['k4', 'k9', 'k10', 'k11', 'k7', 'u5', 'u6', 'u8', 'u9']
    from concurrent.futures import ThreadPoolExecutor, as_completed
    BAR.update('tables', 0, f'fragment tables 0/{len(families)}')
    with ThreadPoolExecutor(max_workers=max(1, min(len(families), os.cpu_count() or 4))) as pool:
        futs = [pool.submit(run, [sys.executable, LIB / 'trace_tables.py', work / 'tables', '--model', synth, k], env=env)
                for k in families]
        for i, fut in enumerate(as_completed(futs), 1):
            fut.result()
            BAR.update('tables', i / len(families), f'fragment tables {i}/{len(families)}')

    BAR.update('sources', 0, 'preparing shaders')
    src = work / 'kernels'
    run([sys.executable, LIB / 'regen_kernels.py', src], env=env)

    import regen_kernels
    rt = HERE / 'kernels/rt'
    shaders = [(f'px_{n}', src / n, f'{n}.hlsl') for n in list(regen_kernels.RECIPES) + list(regen_kernels.DERIVED)]
    shaders.append(('px_u5_table', src / 'u5/table', 'u5.hlsl'))
    blobs = []
    # Every shader is also built for 64-lane waves ("<name>_w64"): GPUs without wave32 (GCN/Vega) use those. The text
    # is the same with the wave-size attribute changed; the arithmetic does not depend on the wave size. --no-wave64
    # skips them (about half the build time) for GPUs known to run wave32 (RDNA 1-4).
    # Both sizes are always built (as 1.4.3), whatever this PC's GPU: the DLL picks per GPU at run time; --no-wave64
    # skips the 64-lane copies.
    want64 = '--no-wave64' not in a
    from setup_shader_jobs import shader_jobs
    jobs = shader_jobs(shaders, work, rt, dxc, DXC_ARGS, LDS_READS, want64, '--no-fp32' not in a, '--no-fp32h' not in a,
                       '--no-fp32b' not in a)
    # the speed build's shaders from the same generated kernels: the split output kernels (3 / 5 passes) and the
    # Windows-tuned output kernels (lib/setup_speed_shaders.py); --no-speed-shaders leaves them out
    speed_meta = []
    if '--no-speed-shaders' not in a:
        from setup_speed_shaders import speed_jobs
        speed, speed_meta = speed_jobs(src, work, rt, dxc, want64, '--no-fp32' not in a,
                                       '--no-fp32h' not in a and '--no-fp32b' not in a)
        jobs += speed
    workers = compile_workers(len(jobs))
    # measured compile seconds (16 threads busy): the slow ones start first so they do not trail at the end, and the
    # bar counts each shader by its cost, with the ones still compiling counted in part (scaled to this PC's speed)
    secs = {'px_k8_hdr_colvar_mvhi': 27, 'px_u8': 27, 'px_u9': 26, 'px_k5n': 26, 'px_k10': 17, 'px_u5_table': 15,
            'px_u5': 15, 'px_u6': 14, 'px_k7': 10, 'px_k9': 9, 'px_u4': 6, 'px_k8_rel': 6, 'px_k4': 5, 'px_k5': 4,
            'px_u10': 4, 'px_k5f': 4, 'px_k5nx': 26, 'px_k5nxf': 14}
    est = [secs.get(n[:-4] if n.endswith('_w64') else n, 3 if n.startswith('px_k8_') else 1) for n, _, _ in jobs]
    warm = min(range(len(jobs)), key=lambda i: est[i])   # a quick one starts the compiler (and its Wine prefix) alone
    order = sorted((i for i in range(len(jobs)) if i != warm), key=lambda i: -est[i])
    import time as _t
    total = float(sum(est))
    state = {'done': 0.0, 'n': 0, 'running': {}}

    def frac():
        now = _t.monotonic()
        part = sum(min((now - s) / est[i], 0.95) * est[i] for i, s in list(state['running'].items()))
        return (state['done'] + part) / total

    def label():
        return f'shaders {state["n"]}/{len(jobs)}' if state['n'] else 'starting the shader compiler'

    def timed(i):
        state['running'][i] = s = _t.monotonic()
        run(jobs[i][1])
        secs = _t.monotonic() - s
        del state['running'][i]
        state['done'] += est[i]
        state['n'] += 1
        return jobs[i][0], secs

    BAR.update('shaders', frac, label)
    timed(warm)   # alone first: it may have to set up the compiler's Wine prefix
    with ThreadPoolExecutor(max_workers=workers) as pool:
        for fut in as_completed([pool.submit(timed, i) for i in order]):
            jname, secs = fut.result()   # raises (SystemExit with the compiler output) if a compile failed
            if os.environ.get('HELIXSR_SETUP_TIMES'):
                BAR.clear(); print(f'[helixsr-setup] compile {jname} {secs:.1f} s', flush=True)
                BAR.update('shaders', frac, label)
    blobs = [(name, cso.read_bytes()) for name, _, cso in jobs] + speed_meta   # same order as before, then the speed build's
    # the bias-corrected GTX 10 builds (_fp32b) only where they differ from the plain _fp32 one (shaders without fp16
    # conversions come out the same; the DLL then takes the _fp32 build)
    plain = {n: b for n, b in blobs if n.endswith('_fp32')}
    blobs = [(n, b) for n, b in blobs if not (n.endswith('_fp32b') and plain.get(n[:-1]) == b)]
    table = b''.join(struct.pack('<32sII', n.encode(), 0, len(b)) for n, b in blobs)
    offs, pos_ = [], 16 + len(table)
    for _, b in blobs:
        offs.append(pos_)
        pos_ += len(b)
    table = b''.join(struct.pack('<32sII', n.encode(), o, len(b)) for (n, b), o in zip(blobs, offs))
    # pak version 2: k7/k11 carry split-K (the DLL splits their K loop only with these shaders)
    (out / 'helixsr_kernels.pak').write_bytes(PAK_MAGIC + struct.pack('<II', PAK_VERSION, len(blobs)) + table +
                                              b''.join(b for _, b in blobs))
    (rel / 'helixsr_setup.json').write_text(json.dumps(dict(
        source_sha256=dll_sha, ptx_target=f'sm_{sm}', shaders=len(blobs), wave64=want64, fp32='--no-fp32' not in a, fp32h='--no-fp32' not in a and '--no-fp32h' not in a,
        weights_sha256=hashlib.sha256((out / 'helixsr_weights.bin').read_bytes()).hexdigest()), indent=1) + '\n')
    BAR.update('shaders', 1, 'done')
    BAR.clear()
    BAR.report_times()
    if not keep:
        shutil.rmtree(work, ignore_errors=True)
    # one-file DLL: the network is appended to the package's HelixSR DLL and the two files are removed (the installer
    # copies only the DLL; fsr3-drop-in/ gets copies under FSR 3.1's file names). A 1.5/1.6 nvngx.dll is still filled.
    target = upscaler_dll(out)
    if '--separate-files' not in a and target.exists():
        size = embed(target, (out / 'helixsr_weights.bin').read_bytes(), (out / 'helixsr_kernels.pak').read_bytes())
        (out / 'helixsr_weights.bin').unlink()
        (out / 'helixsr_kernels.pak').unlink()
        step(f'done: {target} now carries the network ({len(blobs)} shaders, {size / 1e6:.1f} MB, checked on disk)')
        if target.name == 'amd_fidelityfx_dx12.dll':
            drop = rel / 'fsr3-drop-in'
            drop.mkdir(exist_ok=True)
            for n in ('amd_fidelityfx_dx12.dll', 'amd_fidelityfx_upscaler_dx12.dll'):
                shutil.copyfile(target, drop / n)
            (drop / 'README.txt').write_text(DROP_IN_README, newline='\r\n' if os.name != 'nt' else None)
            step(f'drop-in DLLs for FSR 3.1 games: {drop}')
        step('they contain NVIDIA\'s network: they are for your own PC, do not share or upload them')
    else:
        for n in ('helixsr_weights.bin', 'helixsr_kernels.pak'):   # what is on disk now (antivirus, synced folders)
            if not (out / n).exists() or (out / n).stat().st_size == 0:
                raise SystemExit(f'{out / n} is missing after the build: something on this PC removes new files in this folder '
                                 '(antivirus or a synced folder). Extract HelixSR into a plain folder such as C:\\HelixSR.')
        step(f'done: the network is built: {out}/helixsr_weights.bin and helixsr_kernels.pak ({len(blobs)} shaders)')
    r = hlx_exit(build_hlx(rel, a), a)   # 4: the network is built; HLX FSR 4 is not (the reason is in the lines above)
    if build_fg(out, dxc, a):
        sys.exit(3)   # the network is built; frame generation is not (the reason is in the lines above)
    sys.exit(r)


if __name__ == '__main__':
    main()
