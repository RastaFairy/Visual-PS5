#!/usr/bin/env python3
# Copyright 2026 lonewolf0622. All rights reserved (HelixSR Freeware License).
"""HelixSR Desktop bridge: answers the desktop app in JSON.

    helixsr_bridge.py RELEASE_DIR COMMAND [options]

RELEASE_DIR is an extracted HelixSR release: setup/helixsr_setup.py and HelixSR's DLL, in its HelixSR-fsrfg folder
(HelixSR 2.0 on: the folder the setup builds, with frame generation in HelixSR-fsrfg/helixsr-fg) or next to setup/
(earlier releases). What the release's setup has built is read from its own `--status`. Finding games, the FSR drop-in
and installs of earlier versions are the app's own helixsr_games.py (HelixSR's setup up to 1.9 carried it as
setup/helixsr_install.py; from 2.0 on the setup carries copies of this file and helixsr_games.py, and its text front
end setup/helixsr_install.py calls the same functions, so the app and the setup install the same files and each can
update or remove what the other installed). Two ways into a game; the app picks one (`recommended`):

    scaler  HelixSR Scaler (OptiScaler with HelixSR) next to the game's .exe, for every game with an .exe
            folder (DLSS, XeSS, FSR 2 or FSR 3, also built into the .exe where the scan can't see it): the game's DLSS option runs HelixSR (and DLSS Frame Generation runs HelixSR's frame generation).
            Files: OptiScaler (as dxgi.dll; on GPUs without NVIDIA's driver it also answers the game's NVAPI calls,
            so the game offers DLSS) with its OptiScaler folder and OptiScaler.ini, and HelixSR's one DLL
            (upscaler and DLSS frame generation) as HelixSR-fsrfg/amd_fidelityfx_dx12.dll, with frame generation's
            files (built by HelixSR's setup) in HelixSR-fsrfg/helixsr-fg/. HelixSR Scaler runs it as its FidelityFX
            upscaler (Dx12Upscaler = ffx). They are listed in HelixSR-Scaler.files and the game's own files it
            replaces are kept in HelixSR-Scaler-backup, the same way HelixSR Scaler's setup_linux.sh does it, so each
            can update or remove what the other installed. Settings: OptiScaler.ini ([HelixSR]); sharpening is OptiScaler's own.
            Frame generation is OptiScaler's own choice in OptiScaler.ini ([FrameGen] FGInput = nvngxfg with
            FGNvngxReplacement = HelixSR), in games with DLSS Frame Generation; its files are always in the game.
            Installs of the earlier layout (HelixSR/helixsr.dll with HelixSR/helixsr-fg/) are still recognised:
            an update moves them to this layout (the earlier one is kept for Go back), remove takes either out.
    fsr     the FSR drop-in: HelixSR replaces the game's FSR 3.1 DLL (the original is kept as *.original.dll),
            nothing else in the game changes. Settings: helixsr.ini.

Games with anti-cheat are treated like any other game (the anti-cheat found is still listed in "anticheat"). Installs
of the earlier DLSS loader and of the setup scripts' OptiScaler way are recognised so they can be switched or removed.

Commands (all print one JSON object on stdout):
    status                                   release version, whether the network is built
    games [--folder DIR]...                  every game found, with its ways and what is installed
    install --game DIR [--way auto|scaler|fsr] [--scaler DIR --scaler-version V] [--scaler-name NAME]
                                             install or update (switching way removes the other first); auto (the
                                             default) is the game's recommended way; --scaler is an extracted HelixSR
                                             Scaler download (the folder with OptiScaler.dll); --scaler-name: its
                                             file name in the game (default: picked, see scaler_name)
                                             --fg on|off: HelixSR's frame generation on (games with DLSS Frame
                                             Generation) or off (an update keeps it as it was)
                                             (--anticheat-ok: accepted from earlier apps, not needed)
    scaler-fg --game DIR --on true|false     HelixSR's frame generation on (games with DLSS Frame Generation) or off
                                             in a game with HelixSR Scaler
    remove --game DIR                        remove HelixSR from the game, everything put back
    settings-get --game DIR                  the game's settings (helixsr.ini, or OptiScaler.ini for HelixSR Scaler)
    settings-set --game DIR --values JSON    {"Section.Key": "value" | null}; null comments the line out
    reset-settings --game DIR [--scaler DIR] the game's HelixSR settings back to the defaults: HelixSR Scaler gets the
                                             download's OptiScaler.ini (and frame generation off), the FSR drop-in
                                             loses its helixsr.ini
    log --game DIR                           helixsr.log: the important lines and a report for a bug report
    rollback --game DIR                      back to the version the game had before its last update (kept in
                                             HelixSR-previous.zip by every update; a second rollback goes forward again)
"""
import json
import os
import re
import shutil
import struct
import sys
import traceback
import zipfile
from pathlib import Path

PROTOCOL = 1
WAYS = ('scaler', 'fsr')
SETTINGS = {   # what the app's settings form edits: section, key, allowed values (None = free number)
    'Sharpening.Sharpener': ('off', 'nvidia', 'rcas'),
    'Sharpening.Sharpness': None,
    'Sharpening.UseGameSlider': ('true', 'false'),
    'Compatibility.WaveSize': ('auto', 'default', '64', '32'),
}
# HelixSR Scaler: its settings in OptiScaler.ini ([HelixSR]); sharpening is OptiScaler's own (its menu)
SCALER_SETTINGS = {
    'HelixSR.WaveSize': ('auto', '64', '32'),
    # frame generation quality (NVIDIA's full frame generation): off = Best (auto in the file), fast, fastest. HelixSR
    # Scaler copies it to helixsr.ini [DlssFrameGeneration] QuickFlow when the game starts. (Preset C, NVIDIA's light
    # mode, is removed: HelixSR.FGPreset is no longer a setting; an older app's FGPreset is accepted and ignored.)
    'HelixSR.QuickFlow': ('off', 'fast', 'fastest'),
}
SCALER_DEFAULTS = {'HelixSR.WaveSize': 'auto', 'HelixSR.QuickFlow': 'off'}
SCALER_RETIRED = ('HelixSR.FGPreset',)   # settings an older app may still send: accepted, not written
# values HelixSR Scaler also reads (earlier versions' QuickFlow = on, its own spellings; best = off)
SCALER_ALIASES = {'HelixSR.QuickFlow': {'on': 'fast', 'true': 'fast', '1': 'fast', 'quickflow': 'fast',
                                        'false': 'off', '0': 'off', 'best': 'off'}}
LOG_KEYS = ('wave size', 'int8 network', 'capabilities', 'summary:', 'create:', 'output:', 'GPU id', 'ERROR',
            'error', 'failed', 'network running', 'network inside')

INI = 'helixsr.ini'   # where HelixSR reads its settings (next to its DLL); older releases have no constant for it
MARKER = 'helixsr-install.json'

_messages = []
# who wrote a game's HelixSR-Scaler.files (its first line); HelixSR's setup scripts use this file too and set their own
INSTALLED_BY = 'HelixSR Desktop'


def read_marker(d):
    """The install record the setup writes ({} if there is none)."""
    try:
        return json.loads((Path(d) / MARKER).read_text())
    except (OSError, ValueError):
        return {}


SETUP = 'setup/helixsr_setup.py'   # the release's setup (it builds the network and frame generation)


def load_installer(release):
    """The app's game module (helixsr_games.py next to this script), for a release folder with HelixSR's setup."""
    if not (release / SETUP).is_file() or not release_dll(release).is_file():
        raise BridgeError(f'not a HelixSR release folder (no {SETUP} and HelixSR\'s DLL): {release}')
    import importlib.util
    spec = importlib.util.spec_from_file_location('helixsr_games', Path(__file__).resolve().parent / 'helixsr_games.py')
    hi = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(hi)
    hi.say = lambda m: _messages.append(str(m).strip())
    every_exe_game(hi)
    return hi


_status = {}


def setup_status(release):
    """(network built, frame generation complete) as the release's setup reports it (`--status`: network=0|1 fg=0|1;
    it checks NVIDIA's files by their checksums), for releases with the HelixSR-fsrfg folder (HelixSR 2.0 on); None for
    earlier releases or when the setup does not answer."""
    release = Path(release)
    if release not in _status:
        _status[release] = None
        if release_dll(release).parent != release and release_dll(release).is_file():
            import subprocess
            try:
                p = subprocess.run([sys.executable, '-I', str(release / SETUP), str(release), '--status'],
                                   capture_output=True, text=True, timeout=120)
                m = re.search(r'network=([01])\s+fg=([01])', p.stdout)
                if m:
                    _status[release] = (m.group(1) == '1', m.group(2) == '1')
            except (OSError, subprocess.SubprocessError):
                pass
    return _status[release]


def network_ready(hi, release):
    st = setup_status(release)
    if st is not None:
        return st[0]
    return bool(hi.network_ready(release_dll(release).parent))


# Steam folders with .exe files that are not games (Proton, its runtimes, redistributables)
NOT_GAMES = re.compile(r'^(proton\b|steamworks shared$|steamlinuxruntime|steam linux runtime|steamvr$|'
                       r'steam controller configs$)', re.I)


def every_exe_game(hi):
    """Every folder with a game .exe is a game for HelixSR Scaler, also without a DLSS, XeSS or FSR file the scan can
    see (OptiScaler finds upscalers built into the game's .exe, e.g. FSR 2). helixsr_games lists only games with such a
    file: its games get route 'unsupported' (= HelixSR Scaler only) when they have an .exe folder."""
    init = hi.Game.__init__
    if getattr(init, 'every_exe', False):
        return

    def __init__(self, name, folder, tree):
        init(self, name, folder, tree)
        if self.route is None and self.target and not NOT_GAMES.match(Path(folder).name) \
                and not NOT_GAMES.match(str(name)):
            self.route = 'unsupported'
    __init__.every_exe = True
    hi.Game.__init__ = __init__


class BridgeError(Exception):
    pass


# --- HelixSR Scaler ---------------------------------------------------------------------------------------------------

SCALER_FILES = 'HelixSR-Scaler.files'      # what HelixSR Scaler put into the game (same file as setup_linux.sh's)
SCALER_BACKUP = 'HelixSR-Scaler-backup'    # the game's own files it replaced
SCALER_REMOVER = 'HelixSR-Scaler-remove.sh'
SCALER_LIST = 'HelixSR-Scaler-package.txt'
SCALER_NAMES = ('dxgi.dll', 'winmm.dll', 'version.dll', 'dbghelp.dll', 'd3d12.dll', 'wininet.dll', 'winhttp.dll')
NOT_COPIED = {'setup_linux.sh', 'setup_windows.bat', 'README.txt', 'README-Linux.txt', SCALER_LIST}
# HelixSR Scaler loads the SR and dedicated FG modules from HELIX_DIR. Frame generation's dependencies
# stay in HELIX_DIR/helixsr-fg; on/off is OptiScaler.ini's [FrameGen] choice.
HELIX_DIR = 'HelixSR-fsrfg'
HELIX_DLL = HELIX_DIR + '/amd_fidelityfx_dx12.dll'
FG_MODULE = HELIX_DIR + '/helixsr_fg.dll'
FG_GAME = HELIX_DIR + '/helixsr-fg'          # frame generation in a game with HelixSR Scaler
FG_PARKED = HELIX_DIR + '/helixsr-fg.off'    # where earlier HelixSR Scaler versions parked it while it was off
# the earlier layout (HelixSR Desktop 1.0, HelixSR up to 1.9): HelixSR's DLL as HelixSR/helixsr.dll
OLD_DIR = 'HelixSR'
OLD_DLL = OLD_DIR + '/helixsr.dll'
OLD_FG_GAME = OLD_DIR + '/helixsr-fg'
OLD_FG_PARKED = OLD_DIR + '/helixsr-fg.off'
# made while the game runs (or by HelixSR Scaler for HelixSR), removed with it; both layouts
SCALER_MADE = ('OptiScaler.log',
               HELIX_DIR + '/helixsr.log', HELIX_DIR + '/helixsr.ini', FG_GAME + '/nvexec.log',
               HELIX_DIR + '/amd_fidelityfx_upscaler_dx12.amd.dll',   # AMD's FSR for HelixSR's list (HelixSR Scaler)
               OLD_DIR + '/helixsr_upscaler.dll', OLD_DIR + '/helixsr.log', OLD_DIR + '/helixsr.ini',
               OLD_FG_GAME + '/nvexec.log')
FG_EXECUTOR = 'nvexec64.dll'   # frame generation's executor, in the release's helixsr-fg folder
FG_FILES = (FG_EXECUTOR, '_nvngx.dll', 'nvngx_dlssg.dll')   # what frame generation needs at least
FG_DATA = 'hxfg_data.bin'      # frame generation's data, when it is not built into HelixSR's DLL


# The layouts HelixSR Scaler installs have in a game: (folder, upscaler DLL, frame generation's folder, its parked
# folder, the dedicated frame-generation DLL), relative to the game's .exe folder.
#   ngx  the HelixSR folder with HelixSR's NGX DLL (helixsr.dll, OptiScaler's DLSS upscaler "HLX DLSS") and the dedicated
#        frame-generation DLL helixsr_fg.dll next to it (an NVIDIA-style DLSS-G provider); releases with
#        HelixSR/helixsr.dll. The install record says "# layout=ngx".
#   new  HelixSR-fsrfg with HelixSR's FidelityFX DLL (HelixSR 2.0)
#   old  the HelixSR folder of releases before 2.0 (an earlier HelixSR Scaler; same folder, other rules)
NGX_FG_MODULE = OLD_DIR + '/helixsr_fg.dll'
LAYOUT_PATHS = {
    'ngx': (OLD_DIR, OLD_DLL, OLD_FG_GAME, OLD_FG_PARKED, NGX_FG_MODULE),
    'new': (HELIX_DIR, HELIX_DLL, FG_GAME, FG_PARKED, FG_MODULE),
    'old': (OLD_DIR, OLD_DLL, OLD_FG_GAME, OLD_FG_PARKED, NGX_FG_MODULE),
}
LAYOUT_LINE = '# layout=ngx'


def layout(t):
    """'ngx' for an install of the NGX layout (its record says so), 'old' for the earlier layout (its record lists
    HelixSR/helixsr.dll without saying ngx), else 'new'."""
    rec = scaler_record(t)
    if rec and OLD_DLL in rec[2]:
        try:
            ngx = LAYOUT_LINE in (Path(t) / SCALER_FILES).read_text(errors='replace').splitlines()
        except OSError:
            ngx = False
        return 'ngx' if ngx else 'old'
    return 'new'


def helix_dir(t):
    """HelixSR's folder in the game (helixsr.ini, helixsr.log, helixsr-fg) for the layout installed there."""
    return LAYOUT_PATHS[layout(t)][0]


def fg_paths(t):
    """(on, parked): frame generation's folders, relative, for the layout installed in t."""
    return LAYOUT_PATHS[layout(t)][2:4]


DLL = 'amd_fidelityfx_dx12.dll'   # HelixSR's upscaler (legacy releases also served NGX frame generation)
NGX_DLL = 'helixsr.dll'          # HelixSR's NGX upscaler (the ngx layout)


def release_layout(release):
    """The layout a release installs: 'ngx' when it carries HelixSR/helixsr.dll, else 'new'."""
    return 'ngx' if (Path(release) / OLD_DLL).is_file() else 'new'


def release_dll(release):
    """HelixSR's DLL in the release: HelixSR/helixsr.dll (the ngx layout), HelixSR-fsrfg/amd_fidelityfx_dx12.dll
    (HelixSR 2.0), else next to setup/."""
    for p in (Path(release) / OLD_DLL, Path(release) / HELIX_DIR / DLL):
        if p.is_file():
            return p
    return Path(release) / DLL


def release_fg(release):
    """The release's frame-generation folder (helixsr-fg next to HelixSR's DLL in the release)."""
    return release_dll(release).parent / 'helixsr-fg'


def dll_has_fg(dll):
    """HelixSR's DLL carries frame generation (the setup builds it in: [DLL][archive][HXSRFG01][network][HXSRNET1])."""
    import struct
    try:
        with open(dll, 'rb') as f:
            f.seek(0, 2)
            size = f.tell()
            f.seek(size - 32)
            foot = f.read(32)
            end = size
            if foot[:8] == b'HXSRNET1':
                nw, npk, _ = struct.unpack('<QQQ', foot[8:32])
                end = size - 32 - nw - npk
            if end < 32:
                return False
            f.seek(end - 32)
            return f.read(8) == b'HXSRFG01'
    except (OSError, struct.error):
        return False


FG_REASON = 'helixsr-desktop-fg.txt'   # why the app's last frame generation setup did not make it (written by the app)


def fg_reason(release):
    """Why frame generation is not set up, from the app's last setup run (None when it is, or nothing is known)."""
    if fg_dir(release) is not None:
        return None
    try:
        return (Path(release) / FG_REASON).read_text(errors='replace').strip() or None
    except OSError:
        return None


def fg_dir(release):
    """The release's frame-generation folder when its setup built frame generation, None if not set up. HelixSR 2.0 on:
    HelixSR-fsrfg/helixsr-fg when the setup's --status says fg=1 (the executor, NVIDIA's NGX core, NVIDIA's DLSS Frame
    Generation DLL 310.3 with its hxfg_data.bin). Earlier releases: a helixsr-fg folder with the
    executor and NVIDIA's files, and frame generation's data built into HelixSR's DLL or as hxfg_data.bin."""
    release = Path(release)
    st = setup_status(release)
    if st is not None:
        return release_fg(release) if st[1] and release_fg(release).is_dir() else None
    dll = release_dll(release)
    for d in (release / 'helixsr-fg', release_fg(release)):
        if all((d / n).is_file() for n in FG_FILES) and (dll_has_fg(dll) or (d / FG_DATA).is_file()):
            return d
    return None


# Anti-cheat that games ship in their own folder: file and folder names (lower case, start of the name)
ANTICHEAT = (
    ('EasyAntiCheat', ('easyanticheat', 'start_protected_game.exe', 'eac_launcher.exe')),
    ('BattlEye', ('battleye', 'beservice', 'beclient')),
    ('nProtect GameGuard', ('gameguard',)),
    ('XIGNCODE3', ('xigncode',)),
    ('EQU8', ('equ8',)),
    ('Anti-Cheat Expert', ('anticheatexpert', 'ace-base')),
    ('EA Javelin', ('eaanticheat', 'eaac.')),
    ('PunkBuster', ('pnkbstr', 'punkbuster', 'pbsvc')),
    ('Denuvo Anti-Cheat', ('denuvo-anti-cheat', 'denuvoanticheat')),
    ('mhyprot', ('mhyprot',)),
    ('NetEase Anti-Cheat', ('neacsafe', 'neac_')),
)


def anticheat(folder, depth=4):
    """The anti-cheat the game folder ships (names), [] if none was found."""
    found = set()

    def walk(d, left):
        try:
            entries = list(os.scandir(d))
        except OSError:
            return
        for e in entries:
            n = e.name.lower()
            for name, prefixes in ANTICHEAT:
                if n.startswith(prefixes) or (name == 'BattlEye' and n.endswith('_be.exe')):
                    found.add(name)
            if left > 0 and e.is_dir(follow_symlinks=False):
                walk(e.path, left - 1)

    walk(folder, depth)
    return sorted(found)


def exe_imports(path):
    """Lower-case names of the DLLs a Windows .exe or .dll imports, delay-loaded ones included (empty if unreadable)."""
    try:
        with open(path, 'rb') as f:
            b = f.read(512 << 20)
        pe = struct.unpack_from('<I', b, 0x3c)[0]
        if b[pe:pe + 4] != b'PE\0\0':
            return set()
        nsec, opt = struct.unpack_from('<H', b, pe + 6)[0], struct.unpack_from('<H', b, pe + 20)[0]
        o = pe + 24
        dd = o + (112 if struct.unpack_from('<H', b, o)[0] == 0x20b else 96)
        secs = [struct.unpack_from('<IIII', b, pe + 24 + opt + 40 * i + 8) for i in range(nsec)]

        def off(rva):
            for vs, va, rs, ro in secs:
                if va <= rva < va + max(vs, rs):
                    return rva - va + ro
            return None

        def name_at(rva):
            n = off(rva)
            return b[n:b.index(b'\0', n)].decode('ascii', 'replace').lower() if n is not None else None

        names = set()
        for entry, size, name_field in ((1, 20, 12), (13, 32, 4)):   # imports, delay-load imports
            d = off(struct.unpack_from('<I', b, dd + 8 * entry)[0] or 0xffffffff)
            while d is not None and d + size <= len(b):
                rva = struct.unpack_from('<I', b, d + name_field)[0]
                if not rva:
                    break
                n = name_at(rva)
                if n:
                    names.add(n)
                d += size
        return names
    except (OSError, ValueError, struct.error):
        return set()


def known_dlls():
    """Windows: names Windows always loads from System32 (a file of that name next to the game is never loaded)."""
    if sys.platform != 'win32':
        return set()
    try:
        import winreg
        out = set()
        with winreg.OpenKey(winreg.HKEY_LOCAL_MACHINE, r'SYSTEM\CurrentControlSet\Control\Session Manager\KnownDLLs') as k:
            for i in range(winreg.QueryInfoKey(k)[1]):
                v = winreg.EnumValue(k, i)[1]
                if isinstance(v, str):
                    out.add(v.lower())
        return out
    except OSError:
        return set()


def scaler_name(hi, t):
    """HelixSR Scaler's file name in the game's .exe folder t, and a note (or None):
    1. the name of an OptiScaler the game already has (another mod's: two OptiScalers would fight; it is kept in the
       backup and comes back on remove);
    2. dxgi.dll when free (every Direct3D 12 game loads it; Proton takes it from the game folder by itself);
    3. a free name that the game's .exe or a DLL next to it imports (so it is surely loaded);
    4. the first free name (it may not be loaded: then pick another one by hand)."""
    t = Path(t)
    others = [n for n in SCALER_NAMES if (t / n).is_file() and hi.is_optiscaler(t / n)]
    if others:
        return others[0], (f'another OptiScaler was in the game ({others[0]}): HelixSR Scaler takes its place; it is '
                           'kept and comes back when HelixSR Scaler is removed')
    if not (t / 'dxgi.dll').exists():
        return 'dxgi.dll', None
    known = known_dlls()
    free = [n for n in SCALER_NAMES if not (t / n).exists() and n not in known]
    loads = set()
    for f in t.iterdir() if t.is_dir() else []:
        if f.suffix.lower() in ('.exe', '.dll') and f.is_file():
            loads |= exe_imports(f)
    hit = [n for n in free if n in loads]
    if hit:
        return hit[0], f'the game has its own dxgi.dll: HelixSR Scaler goes in as {hit[0]}, which the game loads'
    if free:
        return free[0], (f'the game has its own dxgi.dll and no other name it surely loads: HelixSR Scaler goes in as '
                         f'{free[0]}. If its menu (Insert) does not appear in the game, install again with another '
                         'file name (Choose the method yourself)')
    return 'dxgi.dll', None


def scaler_record(t):
    """(dll name, version, files) from the game's HelixSR-Scaler.files; None when HelixSR Scaler is not installed."""
    p = Path(t) / SCALER_FILES
    if not p.exists():
        return None
    name, version, files = 'dxgi.dll', None, []
    for line in p.read_text(errors='replace').splitlines():
        line = line.strip()
        if line.startswith('# version='):
            version = line.split('=', 1)[1].strip() or None
        elif line.startswith('name='):
            name = line.split('=', 1)[1].strip()
        elif line and not line.startswith('#'):
            files.append(line)
    return name, version, files


# HelixSR's frame generation, HelixSR Scaler 1.1.0 on: OptiScaler's own choice in OptiScaler.ini [FrameGen], HelixSR
# being a DLSS frame-generation provider (FGInput = nvngxfg with FGNvngxReplacement = HelixSR; FGOutput stays auto).
# It runs in DirectX 12 games with DLSS Frame Generation (Streamline's sl.dlss_g.dll in the game): elsewhere the choice
# does nothing, and OptiScaler's own AMD FSR or XeSS frame generation can be picked in HelixSR Scaler's menu.
FG_INPUT = ('FrameGen', 'FGInput')
FG_PROVIDER = ('FrameGen', 'FGNvngxReplacement')
OLD_FG_KEYS = ('FrameGeneration', 'FGPresent')   # earlier HelixSR Scaler versions' own [HelixSR] switches
FG_NEEDS_DLSSG = ('HelixSR frame generation needs a DirectX 12 game with DLSS Frame Generation; in this game AMD FSR '
                  'or XeSS frame generation can be picked in HelixSR Scaler\'s menu (Insert)')


def read_opti(t):
    """The game's OptiScaler.ini (None when there is none)."""
    try:
        return (Path(t) / 'OptiScaler.ini').read_bytes().decode('utf-8', errors='replace')
    except OSError:
        return None


def fg_choice(text):
    """The frame generation OptiScaler.ini picks: 'helixsr' (FGInput = nvngxfg with FGNvngxReplacement = HelixSR),
    'other' (another input or provider, the user's choice), None (auto or nofg: off)."""
    if not text:
        return None
    inp = (ini_get_opti(text, *FG_INPUT) or '').lower()
    if inp == 'nvngxfg' and (ini_get_opti(text, *FG_PROVIDER) or '').lower() == 'helixsr':
        return 'helixsr'
    return 'other' if inp not in ('', 'nofg') else None


def old_fg_setting(text):
    """[HelixSR] FrameGeneration of an earlier HelixSR Scaler: 'on', 'off' or None (auto or not there)."""
    v = (ini_get_opti(text or '', 'HelixSR', 'FrameGeneration') or '').lower()
    return 'off' if v in ('off', 'false', '0') else 'on' if v in ('on', 'true', '1') else None


def fg_installed(t):
    """Frame generation's files are in the game (helixsr-fg; or parked in helixsr-fg.off by an earlier version)."""
    rec = scaler_record(t)
    module = LAYOUT_PATHS[layout(t)][4]
    if rec and module in rec[2] and not (Path(t) / module).is_file():
        return False
    return any((Path(t) / d).is_dir() and any((Path(t) / d).glob('*.dll')) for d in fg_paths(t))


def scaler_fg_state(t):
    """'on' or 'off' for a HelixSR Scaler install: on when OptiScaler.ini picks HelixSR's frame generation and its files
    are in the game. The earlier layout (an earlier HelixSR Scaler): its own [HelixSR] FrameGeneration switch."""
    t = Path(t)
    if layout(t) == 'old':
        return 'off' if old_fg_setting(read_opti(t)) == 'off' or not fg_installed(t) else 'on'
    return 'on' if fg_choice(read_opti(t)) == 'helixsr' and fg_installed(t) else 'off'


def scaler_missing(t):
    """HelixSR Scaler's files listed in the install record that are gone from the game (a game update or a file
    check by the store, or security software, can take them out): [] when all are there."""
    t = Path(t)
    rec = scaler_record(t)
    if rec is None:
        return []
    on, parked = fg_paths(t)

    def there(r):   # frame generation's files can be parked in helixsr-fg.off (the earlier layout's off)
        return (t / r).is_file() or (r.startswith(on + '/') and (t / (parked + r[len(on):])).is_file())

    # OptiScaler.ini is the user's to delete
    return [r for r in rec[2] if r != 'OptiScaler.ini' and not there(r)]


def scaler_seen(t):
    """What the game's OptiScaler.log (written by HelixSR Scaler when the game starts) says since the install:
    'found' (HelixSR Scaler ran and found HelixSR), 'no-helixsr' (it ran without finding HelixSR's folder), or None
    (nothing since the install: not started yet, not loaded, or its logging to a file is off, as by default)."""
    t = Path(t)
    log, rec = t / 'OptiScaler.log', t / SCALER_FILES
    try:
        if log.stat().st_mtime < rec.stat().st_mtime:
            return None
        with open(log, 'rb') as f:
            f.seek(0, 2)
            f.seek(max(0, f.tell() - 1024 * 1024))
            text = f.read().decode('utf-8', errors='replace')
    except OSError:
        return None
    found = max(text.rfind(': HelixSR found in '), text.rfind(": HelixSR's FidelityFX DLL in "))
    missing = text.rfind('HelixSR Scaler: no HelixSR folder')
    if found < 0 and missing < 0:
        return None
    return 'found' if found > missing else 'no-helixsr'


def put_fg(release, t):
    """Frame generation's files from the release into the game's HelixSR-fsrfg/helixsr-fg (always: on or off is
    OptiScaler.ini's choice). Everything the setup made there, sub-folders too, logs left out.
    The files listed in the install record (under helixsr-fg), or [] when the release's setup did not make them."""
    t = Path(t)
    _, _, fg_game, fg_parked, fg_module = LAYOUT_PATHS[release_layout(release)]
    for d in (fg_game, fg_parked):
        shutil.rmtree(t / d, ignore_errors=True)
    fg = fg_dir(release)
    if fg is None:
        return []
    dst = t / fg_game
    listed = []
    provider = release_dll(release).parent / 'helixsr_fg.dll'
    if provider.is_file():
        (t / fg_module).parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(provider, t / fg_module)
        listed.append(fg_module)
    for f in sorted(fg.rglob('*')):
        if not f.is_file() or not fg_file(f.name):
            continue
        rel = f.relative_to(fg).as_posix()
        (dst / rel).parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(f, dst / rel)
        listed.append(f'{fg_game}/{rel}')
    return listed


def fg_file(name):
    """A file of frame generation that goes into the game: not a log (HelixSR Scaler's setup also leaves out rotated
    ones, *.log.*) and not a file the setup was still writing (*.tmp)."""
    n = name.lower()
    return not (n.endswith(('.log', '.tmp')) or '.log.' in n)


def fg_unsupported(t):
    """The game's helixsr.log says the GPU can't run HelixSR's frame generation (no 32-lane waves: Vega, Polaris)."""
    p = Path(t) / helix_dir(t) / 'helixsr.log'
    try:
        with open(p, 'rb') as f:
            f.seek(0, 2)
            f.seek(max(0, f.tell() - 512 * 1024))
            text = f.read().decode('utf-8', errors='replace')
    except OSError:
        return False
    no = text.rfind('frame generation NOT available on this GPU')
    return no >= 0 and no > text.rfind('fg: GPU supports frame generation')


def ini_drop(text, section, key):
    """Removes Key's active lines in [section] (keeps every other line and the line endings)."""
    nl = '\r\n' if '\r\n' in text else '\n'
    out, cur = [], None
    for line in text.split(nl):
        m = re.match(r'^\s*\[([^\]]+)\]\s*$', line)
        if m:
            cur = m.group(1).strip()
        elif cur is not None and cur.lower() == section.lower() and re.match(r'^\s*%s\s*=' % re.escape(key), line, re.I):
            continue
        out.append(line)
    return nl.join(out)


def fg_clear(text):
    """HelixSR's frame generation choice in [FrameGen] back to auto; another input or provider (the user's) stays."""
    if (ini_get_opti(text, *FG_PROVIDER) or '').lower() == 'helixsr':
        if (ini_get_opti(text, *FG_INPUT) or '').lower() == 'nvngxfg':
            text = opti_set(text, *FG_INPUT, 'auto')
        text = opti_set(text, *FG_PROVIDER, 'auto')
    return text


def write_scaler_fg(t, on):
    """HelixSR's frame generation in OptiScaler.ini: on (True: FGInput = nvngxfg, FGNvngxReplacement = HelixSR), off
    (False: both back to auto when they are HelixSR's; another provider the user picked stays) or as the file has it
    (None). The earlier versions' [HelixSR] FrameGeneration and FGPresent lines go (HelixSR Scaler ignores them now),
    and so does the switch earlier versions of this app wrote into HelixSR's own helixsr.ini ([DlssFrameGeneration]
    Enabled = false, which would keep HelixSR Scaler's menu from switching frame generation on): back to true.
    The earlier layout (HelixSR/helixsr.dll, an earlier HelixSR Scaler) keeps its own switches: [HelixSR]
    FrameGeneration and helixsr.ini [FrameGeneration] Enabled."""
    t = Path(t)
    old = layout(t) == 'old'
    p = t / 'OptiScaler.ini'
    if p.is_file():
        text = p.read_bytes().decode('utf-8', errors='replace')
        if old:
            if on is not None:
                text = opti_set(text, 'HelixSR', 'FrameGeneration', 'on' if on else 'off')
            text = fg_clear(text)   # (HelixSR Scaler 1.1.0's choice: an earlier HelixSR Scaler does not know it)
        else:
            for k in OLD_FG_KEYS:
                text = ini_drop(text, 'HelixSR', k)
            if on:
                text = opti_set(opti_set(text, *FG_INPUT, 'nvngxfg'), *FG_PROVIDER, 'HelixSR')
            elif on is False:
                text = fg_clear(text)
        p.write_bytes(text.encode('utf-8'))
    hp = t / helix_dir(t) / INI
    if not old:
        if hp.is_file():
            text = hp.read_bytes().decode('utf-8', errors='replace')
            if (ini_read(text).get('DlssFrameGeneration.Enabled') or '').lower() == 'false':
                hp.write_bytes(ini_set(text, 'DlssFrameGeneration', 'Enabled', 'true').encode('utf-8'))
        return
    if on is None or (on and not hp.is_file()):
        return                       # no file: HelixSR's default (on)
    text = hp.read_bytes().decode('utf-8', errors='replace') if hp.is_file() else ''
    hp.parent.mkdir(parents=True, exist_ok=True)
    hp.write_bytes(ini_set(text, 'FrameGeneration', 'Enabled', 'true' if on else 'false').encode('utf-8'))


def write_scaler_defaults(t):
    """OptiScaler.ini settings HelixSR needs in the HelixSR-fsrfg layout, written only where OptiScaler.ini leaves them on
    auto (or on DLSS, the earlier layout's upscaler): [Upscalers] Dx12Upscaler = ffx (HelixSR's DLL is the FidelityFX
    upscaler; HelixSR Scaler points FfxDx12SRPath at it by itself and runs DirectX 11 / Vulkan games through it as
    ffx_12). Back on the earlier layout (Go back), where HelixSR is the DLSS upscaler on auto, ffx goes back to auto."""
    p = Path(t) / 'OptiScaler.ini'
    if not p.is_file():
        return
    text = p.read_bytes().decode('utf-8', errors='replace')
    up = (ini_get_opti(text, 'Upscalers', 'Dx12Upscaler') or 'auto').lower()
    if layout(t) == 'ngx':
        # HelixSR is OptiScaler's DLSS upscaler (HLX DLSS) through NGX; OptiPatcher (plugins/) needs the ASI loader
        if up in ('auto', 'ffx'):
            text = opti_set(text, 'Upscalers', 'Dx12Upscaler', 'dlss')
        if (ini_get_opti(text, 'DLSS', 'HelixSR') or 'auto').lower() == 'auto':
            text = opti_set(text, 'DLSS', 'HelixSR', 'true')
        if (ini_get_opti(text, 'Plugins', 'LoadAsiPlugins') or 'auto').lower() == 'auto':
            text = opti_set(text, 'Plugins', 'LoadAsiPlugins', 'true')
    elif layout(t) == 'old':
        if up == 'ffx':
            text = opti_set(text, 'Upscalers', 'Dx12Upscaler', 'auto')
    elif up in ('auto', 'dlss'):
        text = opti_set(text, 'Upscalers', 'Dx12Upscaler', 'ffx')
    p.write_bytes(text.encode('utf-8'))


def scaler_set_fg(release, t, on, dlssg=None):
    """HelixSR's frame generation on or off in a game with HelixSR Scaler: OptiScaler.ini's [FrameGen] choice (its files
    stay in helixsr-fg; copied in from the release when they are missing). On only in games with DLSS Frame
    Generation (dlssg: False refuses it, None when not known). The earlier layout (an earlier HelixSR Scaler): its
    files are moved between helixsr-fg and helixsr-fg.off and [HelixSR] FrameGeneration is set to match."""
    t = Path(t)
    rec = scaler_record(t)
    if rec is None:
        raise BridgeError('HelixSR Scaler is not installed in this game')
    name, version, files = rec
    head = [l for l in (t / SCALER_FILES).read_text(errors='replace').splitlines() if l.startswith('#')]
    if layout(t) == 'old':
        fg_on, fg_off = fg_paths(t)
        if on and not fg_installed(t):
            raise BridgeError('frame generation is not in this game: press Update first')
        src, dst = (t / fg_off, t / fg_on) if on else (t / fg_on, t / fg_off)
        if src.is_dir():
            shutil.rmtree(dst, ignore_errors=True)
            os.replace(src, dst)
        keep = [r for r in files if not r.startswith(fg_on + '/')]
        keep += [f'{fg_on}/{f.relative_to(dst).as_posix()}' for f in sorted(dst.rglob('*'))
                 if f.is_file() and fg_file(f.name)] if dst.is_dir() else []
        (t / SCALER_FILES).write_text('\n'.join(head + [f'name={name}'] + keep) + '\n')
    elif on:
        if dlssg is False:
            raise BridgeError(FG_NEEDS_DLSSG)
        _, _, fg_game, fg_parked, fg_module = LAYOUT_PATHS[layout(t)]
        if (t / fg_parked).is_dir() and not (t / fg_game).exists():   # parked by an earlier version
            os.replace(t / fg_parked, t / fg_game)
        if not fg_installed(t):   # taken out, or installed before frame generation was set up
            if fg_dir(release) is None:
                raise BridgeError('frame generation is not set up: use Set up frame generation first')
            keep = [r for r in files if not r.startswith(fg_game + '/') and r != fg_module] + put_fg(release, t)
            (t / SCALER_FILES).write_text('\n'.join(head + [f'name={name}'] + keep) + '\n')
    write_scaler_fg(t, on)
    _messages.append('frame generation off: start the game again' if not on else
                     'frame generation on: start the game again' if layout(t) == 'old' else
                     'frame generation on: start the game again and turn on DLSS Frame Generation in its settings')


# HelixSR 2.0 on (the HelixSR-fsrfg layout) needs this HelixSR Scaler or newer: the one that knows HelixSR's one DLL
# (upscaler and DLSS frame generation in HelixSR-fsrfg) and its defaults
SCALER_FOR_FSRFG = (1, 1, 0)
# HelixSR 3.0 on (the ngx layout: HelixSR/helixsr.dll + helixsr_fg.dll, HLX FSR 4) needs HelixSR Scaler 2.0.0 or newer
SCALER_FOR_NGX = (2, 0, 0)


def version_tuple(s):
    m = re.search(r'(\d+)\.(\d+)\.(\d+)', s or '')
    return tuple(int(x) for x in m.groups()) if m else None


def scaler_pkg_version(pkg, given=None):
    """HelixSR Scaler's version: as the app passes it (--scaler-version), else from its DLL (HelixSR Scaler vX.Y.Z);
    None when neither says (a local test folder)."""
    v = version_tuple(given)
    if v is None:
        try:
            with open(Path(pkg) / 'OptiScaler.dll', 'rb') as f:
                m = re.search(rb'HelixSR Scaler v(\d+\.\d+\.\d+)', f.read(64 << 20))
            v = version_tuple(m.group(1).decode()) if m else None
        except OSError:
            pass
    return v


def check_scaler_pairing(release, pkg, given=None):
    """HelixSR 2.0 (HelixSR-fsrfg in the release) goes into games only with HelixSR Scaler 1.1.0 or newer, HelixSR 3.0 (the
    ngx layout) only with HelixSR Scaler 2.0.0 or newer."""
    if release_dll(release).parent == Path(release):
        return
    v = scaler_pkg_version(pkg, given)
    want = SCALER_FOR_NGX if release_layout(release) == 'ngx' else SCALER_FOR_FSRFG
    if v is not None and v < want:
        need = '.'.join(map(str, want))
        raise BridgeError(f'HelixSR {version_of_release(release)} needs HelixSR Scaler {need} or newer, the app has '
                          f'{".".join(map(str, v))}: update HelixSR Scaler (About > Versions, or Update)')
    if (release_dll(release).parent / 'helixsr_fg.dll').is_file():
        try:
            with open(Path(pkg) / 'OptiScaler.dll', 'rb') as f:
                dedicated_loader = b'HelixSR_SeparateFgLoaderVersion\0' in f.read(64 << 20)
        except OSError:
            dedicated_loader = False
        if not dedicated_loader:
            raise BridgeError('this release uses a separate frame-generation provider: install its matching '
                              'HelixSR Scaler package (dedicated FG loader support is missing)')


def version_of_release(release):
    try:
        m = re.search(rb'\x00HelixSR (\d+\.\d+\.\d+)\x00', release_dll(release).read_bytes()[:4 << 20])
        return m.group(1).decode() if m else ''
    except OSError:
        return ''


def scaler_name_by_hand(t):
    """Whether the installed HelixSR Scaler's file name was picked by hand (kept by updates)."""
    p = Path(t) / SCALER_FILES
    try:
        return '# name picked by hand' in p.read_text(errors='replace').splitlines()
    except OSError:
        return False


def scaler_package_files(pkg):
    """The download's files (relative, with /), from its list when it has one."""
    lst = pkg / SCALER_LIST
    if lst.exists():
        rels = [l.strip().replace('\\', '/') for l in lst.read_text(errors='replace').splitlines() if l.strip()]
    else:
        rels = sorted(str(p.relative_to(pkg)).replace('\\', '/') for p in pkg.rglob('*') if p.is_file())
    out = []
    for r in rels:
        if r in NOT_COPIED or r.startswith(('!! ', OLD_DIR + '/', HELIX_DIR + '/', SCALER_BACKUP + '/')) \
                or not (pkg / r).is_file():
            continue
        out.append(r)
    if 'OptiScaler.dll' not in out:
        raise BridgeError(f'not a HelixSR Scaler download (no OptiScaler.dll): {pkg}')
    return out


def scaler_uninstall(t, quiet=False, keep=()):
    """Takes HelixSR Scaler out of t and puts the game's own files back. keep: relative paths left in place."""
    t = Path(t)
    rec = scaler_record(t)
    if rec is None:
        return
    _, _, files = rec
    for r in files:
        if r in keep:
            continue
        f = t / r
        if f.is_file() or f.is_symlink():
            f.unlink()
    for r in SCALER_MADE:
        if r not in keep and (t / r).is_file():
            (t / r).unlink()
    for d in (FG_PARKED, OLD_FG_PARKED):   # frame generation parked (the earlier layout's off, earlier versions)
        shutil.rmtree(t / d, ignore_errors=True)
    backup = t / SCALER_BACKUP
    if backup.is_dir():
        for f in sorted(backup.rglob('*')):
            if f.is_file():
                dst = t / f.relative_to(backup)
                dst.parent.mkdir(parents=True, exist_ok=True)
                os.replace(f, dst)
        shutil.rmtree(backup, ignore_errors=True)
    for n in (SCALER_FILES, SCALER_REMOVER):
        if (t / n).exists():
            (t / n).unlink()
    # folders HelixSR Scaler brought, when nothing else is in them now
    dirs = {(t / r).parent for r in files} | {t / OLD_DIR, t / FG_GAME, t / HELIX_DIR, t / OLD_FG_GAME}
    for d in sorted(dirs, key=lambda p: len(p.parts), reverse=True):
        while d != t and d.is_dir() and not any(d.iterdir()):
            d.rmdir()
            d = d.parent
    if not quiet:
        _messages.append(f'HelixSR Scaler removed from {t}; the game\'s own files are back')


def scaler_install(hi, release, t, pkg, version, name_choice=None, fg_mode=None, dlssg=None):
    """HelixSR Scaler from the download pkg into the game's .exe folder t, with HelixSR's built DLL as
    t/HelixSR-fsrfg/amd_fidelityfx_dx12.dll and frame generation in t/HelixSR-fsrfg/helixsr-fg (when the release's
    setup made it). An install of the earlier layout (t/HelixSR/helixsr.dll) is taken out first: it is moved, and so
    is everything else of the earlier install that this package does not have (all of it is in the install record).
    fg_mode: 'on' or 'off' for HelixSR's frame generation, None for the default: on (the game's DLSS Frame Generation
    setting switches it), on only where the game has DLSS Frame Generation (dlssg: False keeps frame generation on auto,
    None when not known)."""
    t, pkg = Path(t), Path(pkg)
    rels = scaler_package_files(pkg)
    helix = release_dll(release)
    lay = release_layout(release)
    helix_folder, helix_dest = LAYOUT_PATHS[lay][:2]
    if not network_ready(hi, release):
        raise BridgeError('the network is not built yet')

    if name_choice and name_choice not in SCALER_NAMES:
        raise BridgeError(f'--scaler-name must be one of {", ".join(SCALER_NAMES)}')
    old = scaler_record(t)
    # a name picked by hand is kept by updates (remembered in the install record)
    by_hand = name_choice or (old[0] if old and scaler_name_by_hand(t) else None)
    # an update keeps the game's OptiScaler.ini (the settings)
    settings = (t / 'OptiScaler.ini').read_bytes() if old and (t / 'OptiScaler.ini').is_file() else None
    fg_want = {'on': True, 'off': False}.get(fg_mode)
    if fg_want is None:
        # HelixSR's frame generation is wired to the game's DLSS Frame Generation: the game's own setting switches it
        # on and off. Not when the user picked another frame generation in HelixSR Scaler's menu (AMD FSR, XeSS,
        # another provider): that stays
        text = settings.decode('utf-8', errors='replace') if settings is not None else ''
        fg_want = None if fg_choice(text) == 'other' else True
    if old:
        was = layout(t)
        moved = LAYOUT_PATHS[was][0] != helix_folder
        scaler_uninstall(t, quiet=True)
        _messages.append('updating HelixSR Scaler (settings kept)' +
                         (f': HelixSR moves from {LAYOUT_PATHS[was][0]} to {helix_folder}' if moved else ''))
    if by_hand:
        name = by_hand
        if (t / name).exists():
            _messages.append(f'the game\'s own {name} is kept in the backup and comes back when HelixSR Scaler is removed')
    else:
        name, note = scaler_name(hi, t)
        if note:
            _messages.append(note)

    listed, backed_up = [], 0

    def put(src, rel):
        nonlocal backed_up
        dst = t / rel
        if dst.exists() or dst.is_symlink():
            b = t / SCALER_BACKUP / rel
            b.parent.mkdir(parents=True, exist_ok=True)
            os.replace(dst, b)
            backed_up += 1
        dst.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(src, dst)
        listed.append(rel)

    for r in rels:
        put(pkg / r, name if r == 'OptiScaler.dll' else r)
    # what is left in HelixSR's folders now is not HelixSR Desktop's (put in by hand, or another layout's): kept in the
    # backup
    for folder in dict.fromkeys((HELIX_DIR, helix_folder)):
        if not (t / folder).is_dir():
            continue
        for f in sorted((t / folder).rglob('*')):
            if f.is_file() or f.is_symlink():
                b = t / SCALER_BACKUP / f.relative_to(t)
                b.parent.mkdir(parents=True, exist_ok=True)
                os.replace(f, b)
                backed_up += 1
        shutil.rmtree(t / folder, ignore_errors=True)
    put(helix, helix_dest)
    fg_files = put_fg(release, t)
    listed += fg_files
    no_dlssg = fg_want and dlssg is False
    if not fg_files or no_dlssg:
        fg_want = False if not fg_files else None   # (HelixSR's choice without its files: back to auto)
    # the install record first: the settings below follow the layout it says
    lines = [f'# HelixSR Scaler, installed by {INSTALLED_BY}', f'# version={version or ""}'] + \
        ([LAYOUT_LINE] if lay == 'ngx' else []) + (['# name picked by hand'] if by_hand else []) + \
        [f'name={name}'] + listed
    (t / SCALER_FILES).write_text('\n'.join(lines) + '\n')
    if settings is not None:
        (t / 'OptiScaler.ini').write_bytes(settings)
    write_scaler_defaults(t)
    write_scaler_fg(t, fg_want)
    if not fg_files:
        _messages.append('frame generation is not set up: HelixSR Scaler installed for upscaling only')
    elif no_dlssg:
        _messages.append('frame generation installed, not used: ' + FG_NEEDS_DLSSG)
    elif scaler_fg_state(t) == 'on':
        _messages.append('frame generation installed: the game\'s DLSS Frame Generation setting switches it on and off')
    else:
        _messages.append('frame generation installed; the frame generation picked in HelixSR Scaler\'s menu (Insert) '
                         'stays')
    if os.name != 'nt' and (pkg / 'setup_linux.sh').is_file():   # the same remover setup_linux.sh leaves
        shutil.copyfile(pkg / 'setup_linux.sh', t / SCALER_REMOVER)
        os.chmod(t / SCALER_REMOVER, 0o755)
    _messages.append(f'HelixSR Scaler installed as {name}' +
                     (f' ({backed_up} of the game\'s files kept in {SCALER_BACKUP})' if backed_up else ''))


# --- the previous version: kept by every update, for going back offline -------------------------------------------

PREVIOUS = 'HelixSR-previous.zip'   # the files of the version the game had before its last update (stored, not packed)
PREV_META = 'previous.json'         # in the zip: {"way", "version", "scaler_version", "name"}


def previous_zip(hi, g, way):
    """Where the game's previous version is kept: next to HelixSR Scaler (its .exe folder), or for the FSR drop-in
    next to the game's first FSR 3.1 DLL. A zip, so no older DLL sits where a game or a scan could load it."""
    if way == 'scaler' and g.target:
        return Path(g.target) / PREVIOUS
    if way == 'fsr' and g.fsr_targets:
        return Path(g.fsr_targets[0]).parent / PREVIOUS
    return None


def previous_info(hi, g, way):
    """What the previous version is ({"version", "scaler_version"}), None when none is kept."""
    z = previous_zip(hi, g, way) if way else None
    if not z or not z.is_file():
        return None
    try:
        with zipfile.ZipFile(z) as f:
            meta = json.loads(f.read(PREV_META))
    except (OSError, ValueError, KeyError, zipfile.BadZipFile):
        return None
    if meta.get('way') != way:
        return None
    return {'version': meta.get('version'), 'scaler_version': meta.get('scaler_version')}


def installed_files(hi, g, way):
    """(base folder, [relative paths]) of what HelixSR put into the game on this way, as it is now."""
    if way == 'scaler':
        t = Path(g.target)
        rec = scaler_record(t)
        if rec is None:
            return t, []
        rels = [SCALER_FILES]
        on, parked = fg_paths(t)
        for r in rec[2]:
            if r == 'OptiScaler.ini':   # the settings stay as they are
                continue
            if r.startswith(on + '/') and not (t / r).is_file():
                r = parked + r[len(on):]   # frame generation switched off: parked
            if (t / r).is_file():
                rels.append(r)
        return t, rels
    base = Path(g.folder)
    rels = []
    for t in g.fsr_targets:
        if not hi.is_ours(t):
            continue
        for f in [t, t.parent / MARKER] + [t.parent / n for n in getattr(hi, 'NETWORK', ())]:
            if f.is_file():
                rels.append(f.relative_to(base).as_posix())
    return base, rels


def save_previous(hi, g, way, version, scaler_version, dest=None, quiet=False):
    """The game's HelixSR as it is now into HelixSR-previous.zip (or dest), replacing an older one."""
    z = dest or previous_zip(hi, g, way)
    base, rels = installed_files(hi, g, way)
    if z is None or not rels:
        return
    meta = {'way': way, 'version': version, 'scaler_version': scaler_version,
            'name': scaler_record(g.target)[0] if way == 'scaler' else None}
    tmp = z.with_name(z.name + '.new')
    with zipfile.ZipFile(tmp, 'w', zipfile.ZIP_STORED) as f:
        f.writestr(PREV_META, json.dumps(meta))
        for r in rels:
            f.write(base / r, 'files/' + r)
    os.replace(tmp, z)
    if not quiet:
        _messages.append(f'the version before ({version or "?"}) is kept: Go back puts it back')


# the game's own frame generation, by its files (lower case)
GAME_FG_FILES = {'nvngx_dlssg.dll': 'DLSS', 'sl.dlss_g.dll': 'DLSS', 'amd_fidelityfx_framegeneration_dx12.dll': 'FSR',
                 'libxess_fg.dll': 'XeSS'}
DLSSG_FILE = 'sl.dlss_g.dll'   # Streamline's DLSS Frame Generation: what HelixSR's frame generation runs through


def game_fg_files(hi, g):
    """The game's own frame-generation files (lower-case names of GAME_FG_FILES), None when the release's game module
    can't search a folder. HelixSR's own folder is not searched (it carries nvngx_dlssg.dll for its frame generation),
    nor an OptiScaler folder (HelixSR Scaler's DLLs; earlier versions also brought Streamline's there) or the backup."""
    if not hasattr(hi, 'walk'):
        return None
    found = set()
    ours = {'optiscaler', HELIX_DIR.lower(), OLD_DIR.lower(), SCALER_BACKUP.lower()}
    for d, names in hi.walk(g.folder, 8):
        if ours & {x.lower() for x in Path(d).relative_to(Path(g.folder)).parts}:
            continue
        found |= {n.lower() for n in names if n.lower() in GAME_FG_FILES}
    return found


def game_fg(hi, g, files=None):
    """The frame generation the game ships (['DLSS', 'FSR', 'XeSS'], sorted), for what the window says to switch on in
    the game."""
    files = game_fg_files(hi, g) if files is None else files
    return sorted({GAME_FG_FILES[n] for n in files or ()}, key=['DLSS', 'FSR', 'XeSS'].index)


def game_dlssg(hi, g, files=None):
    """The game has DLSS Frame Generation (Streamline's sl.dlss_g.dll): where HelixSR's frame generation runs. None
    when not known (a release whose game module can't search a folder)."""
    files = game_fg_files(hi, g) if files is None else files
    return None if files is None else DLSSG_FILE in files


def drop_previous(hi, g, way):
    z = previous_zip(hi, g, way) if way else None
    if z and z.is_file():
        z.unlink()


def cmd_rollback(hi, release, a):
    """Back to the version kept by the game's last update; the version it has now is kept in its place."""
    g = find_game(hi, one(a, 'game'))
    way = installed_way(hi, g)
    if way not in WAYS:
        raise BridgeError(f'HelixSR is not installed in {g.name}' if not way else
                          f'{g.name} has HelixSR from an earlier way: install it again')
    z = previous_zip(hi, g, way)
    if previous_info(hi, g, way) is None:
        raise BridgeError(f'{g.name} has no earlier version kept (it is kept from the next update on)')
    with zipfile.ZipFile(z) as f:
        meta = json.loads(f.read(PREV_META))
        names = [n for n in f.namelist() if n.startswith('files/') and not n.endswith('/')]
        rels = [n[len('files/'):] for n in names]
        if any(r.startswith('/') or '..' in Path(r).parts for r in rels):
            raise BridgeError('the kept version is damaged: install again instead')
        if way == 'scaler' and meta.get('name') and meta['name'] != scaler_record(g.target)[0]:
            raise BridgeError(f'the kept version went in as {meta["name"]}, this one as {scaler_record(g.target)[0]}: '
                              'install the version you want from Versions instead')
        data = {r: f.read(n) for r, n in zip(rels, names)}
    # what the game has now becomes the kept version (so going back can be undone); z is replaced only at the end
    now = z.with_name(z.name + '.now')
    scaler_now = scaler_record(g.target)[1] if way == 'scaler' else None
    save_previous(hi, g, way, installed_version(hi, g, way), scaler_now, dest=now, quiet=True)
    try:
        if way == 'scaler':
            t = Path(g.target)
            fg_on = scaler_fg_state(t) == 'on'
            now_dir = helix_dir(t)   # read before the install record goes
            _, cur = installed_files(hi, g, way)
            for r in cur:
                (t / r).unlink()
            for d in (FG_GAME, FG_PARKED, OLD_FG_GAME, OLD_FG_PARKED):
                shutil.rmtree(t / d, ignore_errors=True)
            # the kept version can be of the other layout (an update moved HelixSR to HelixSR-fsrfg): then what the
            # game made in the folder of the layout it has now goes too
            if (OLD_DLL in data) != (now_dir == OLD_DIR):
                for r in SCALER_MADE:
                    if r.startswith(now_dir + '/') and (t / r).is_file():
                        (t / r).unlink()
                if (t / now_dir).is_dir() and not any(f.is_file() for f in (t / now_dir).rglob('*')):
                    shutil.rmtree(t / now_dir, ignore_errors=True)
            # (the ngx layout shares the HelixSR folder with the earlier layout, but its off is OptiScaler.ini's choice)
            kept_ngx = LAYOUT_LINE.encode() in data.get(SCALER_FILES, b'').splitlines()
            for r, b in data.items():
                for on, parked in ((FG_GAME, FG_PARKED), (OLD_FG_GAME, OLD_FG_PARKED)):
                    if r.startswith(parked + '/'):
                        r = on + r[len(parked):]
                    # frame generation stays as the user has it: the earlier layout's off is its files parked
                    if on == OLD_FG_GAME and r.startswith(on + '/') and not fg_on and not kept_ngx:
                        r = parked + r[len(on):]
                (t / r).parent.mkdir(parents=True, exist_ok=True)
                (t / r).write_bytes(b)
            write_scaler_defaults(t)
            # the earlier layout: its own switch; HelixSR-fsrfg: OptiScaler.ini's choice, which stays (frame generation
            # on in the earlier layout becomes HelixSR's choice where [FrameGen] leaves the input on auto)
            if layout(t) == 'old':
                write_scaler_fg(t, fg_on)
            else:
                write_scaler_fg(t, True if fg_on and ini_get_opti(read_opti(t) or '', *FG_INPUT) is None and
                                game_dlssg(hi, g) is not False else None)
        else:
            base = Path(g.folder)
            for r, b in data.items():
                dst = base / r
                tmp = dst.with_name(dst.name + '.helixsr-new')
                tmp.write_bytes(b)
                os.replace(tmp, dst)
    except Exception as e:
        recovery = f'; the pre-rollback files are kept in {now.name}' if now.exists() else ''
        raise BridgeError(f'going back stopped ({e}): install again to repair the game\'s HelixSR{recovery}')
    if now.exists():
        os.replace(now, z)
    else:
        z.unlink()
    _messages.append(f'back to HelixSR {meta.get("version") or ""}'.strip() + ': start the game again')
    g = find_game(hi, str(g.folder))
    return {'game': game_json(hi, g)}


def launch_options(name):
    """What Steam needs on Linux so Proton loads HelixSR Scaler's DLL from the game folder: nothing for dxgi.dll
    (Proton already takes the game's own dxgi.dll), the override for the other names."""
    if name.lower() == 'dxgi.dll':
        return None
    return f'WINEDLLOVERRIDES="{Path(name).stem}=n,b" %command%'


def ini_get_opti(text, section, key):
    """A value in OptiScaler.ini; None for auto or missing."""
    v = ini_read(text).get(f'{section}.{key}')
    if v is None:
        for k, val in ini_read(text).items():   # case-insensitive, as OptiScaler reads it
            if k.lower() == f'{section}.{key}'.lower():
                v = val
                break
    if v is None or v.strip().lower() == 'auto' or v.strip() == '':
        return None
    return v.strip()


def scaler_settings_read(text):
    """The app's view of HelixSR Scaler's settings, as its menu shows them."""
    out = {}
    for name, allowed in SCALER_SETTINGS.items():
        v = (ini_get_opti(text, *name.split('.', 1)) or '').lower()
        v = SCALER_ALIASES.get(name, {}).get(v, v)
        out[name] = v if v in allowed else SCALER_DEFAULTS[name]
    return out


def opti_set(text, section, key, value):
    """Key=value in OptiScaler.ini's style (no spaces, auto rather than a removed line)."""
    text = ini_set(text, section, key, value)
    return re.sub(r'(?m)^%s = ' % re.escape(key), f'{key}=', text)


def scaler_settings_write(text, values):
    checked = {}
    for name, v in values.items():
        if name in SCALER_RETIRED:
            continue
        if name not in SCALER_SETTINGS:
            raise BridgeError(f'unknown setting {name}')
        v = str(v).strip().lower() if v is not None else SCALER_DEFAULTS[name]
        if v not in SCALER_SETTINGS[name]:
            raise BridgeError(f'{name}: one of {", ".join(SCALER_SETTINGS[name])}')
        checked[name] = v
    for name, v in checked.items():
        section, key = name.split('.', 1)
        text = opti_set(text, section, key, v)
    return text


# --- games -------------------------------------------------------------------------------------------------------------

def installed_way(hi, g):
    if g.target and scaler_record(g.target) is not None:
        return 'scaler'
    if g.dlss_installed:
        return 'dlss'
    if any(hi.is_ours(t) for t in g.fsr_targets):   # with or without the backup of the game's file
        return 'fsr'
    if g.opti_installed:
        return 'optiscaler'   # installed by the setup scripts; the app can switch or remove it
    return None


def ways(g):
    out = []
    if g.target:   # OptiScaler finds the game's upscaler when it runs, also one the scan can't see
        out.append('scaler')
    if g.fsr_targets:
        out.append('fsr')
    return out


def recommended(g, ac=None):
    """The way the app picks: HelixSR Scaler, else the FSR drop-in (games with anti-cheat as any other game; ac is
    accepted from earlier callers and not used)."""
    w = ways(g)
    return w[0] if w else None


def settings_dir(hi, g, way):
    """Where HelixSR reads helixsr.ini for this game (next to HelixSR's DLL)."""
    if way == 'fsr':
        return g.fsr_targets[0].parent if g.fsr_targets else None
    if way == 'dlss':
        return g.target
    if way == 'optiscaler':
        return g.target / hi.FOLDER if g.target else None
    if way == 'scaler':
        return g.target / helix_dir(g.target) if g.target else None   # helixsr.log; the settings: OptiScaler.ini
    return None


def installed_version(hi, g, way):
    if way == 'scaler':
        try:
            return hi.version_of(g.target / LAYOUT_PATHS[layout(g.target)][1])
        except Exception:
            return None
    d = settings_dir(hi, g, way)
    if way in ('dlss', 'optiscaler'):
        d = g.target / hi.FOLDER if g.target else None
    if not d:
        return None
    return read_marker(d).get('helixsr')


def game_json(hi, g):
    way = installed_way(hi, g)
    ac = anticheat(g.folder)
    d = settings_dir(hi, g, way) if way else None
    scaler = scaler_record(g.target) if way == 'scaler' else None
    fg_files = game_fg_files(hi, g) if scaler else None
    return {
        'id': str(g.folder),
        'name': g.name,
        'folder': str(g.folder),
        'inputs': list(g.inputs) + (['FSR 3.1'] if g.fsr_targets else []),
        'inputs_found': bool(g.inputs or g.fsr_targets),   # false: HelixSR Scaler looks for it when the game runs
        'ways': ways(g),
        'recommended': recommended(g, ac),
        'anticheat': ac,
        'installed': way,
        'version': installed_version(hi, g, way) if way else None,
        'settings_path': str(g.target / 'OptiScaler.ini') if scaler else (str(d / INI) if d else None),
        'log_path': str(d / 'helixsr.log') if d else None,
        'supported': bool(ways(g)),
        'blocked': None,   # (earlier: 'anti-cheat'; anti-cheat games are treated like any other game now)
        'exe_folder': str(g.target) if g.target else None,
        'scaler_version': scaler[1] if scaler else None,
        'scaler_dll': scaler[0] if scaler else None,
        'scaler_layout': layout(g.target) if scaler else None,   # ngx / new / old (old: moved by an update)
        'launch_options': launch_options(scaler[0]) if scaler and os.name != 'nt' else None,
        'frame_generation': scaler_fg_state(g.target) if scaler else None,
        # HelixSR's frame generation can be switched on here (a game with DLSS Frame Generation; None: not known)
        'fg_possible': (game_dlssg(hi, g, fg_files) if layout(g.target) in ('new', 'ngx') else True) if scaler else False,
        # the game's OptiScaler.ini picks another frame generation (AMD FSR, XeSS, another provider: the user's)
        'fg_other': fg_choice(read_opti(g.target)) == 'other' if scaler and layout(g.target) in ('new', 'ngx') else False,
        'fg_installed': fg_installed(g.target) if scaler else False,
        'fg_unsupported': fg_unsupported(g.target) if scaler else False,
        'scaler_missing': scaler_missing(g.target) if scaler else [],
        'scaler_seen': scaler_seen(g.target) if scaler else None,
        'previous': previous_info(hi, g, way) if way in WAYS else None,
        'game_fg': game_fg(hi, g, fg_files) if scaler else [],   # only for what the window says to switch on in the game
    }


def without_scaler_files(hi, g):
    """HelixSR Scaler's own FSR DLLs (OptiScaler/amd_fidelityfx_*.dll, listed in its install record) are not the
    game's FSR 3.1: they would make an installed HelixSR Scaler look like an FSR 3.1 game (and the FSR drop-in would
    replace OptiScaler's file)."""
    rec = scaler_record(g.target) if g.target else None
    if not g.fsr_targets:
        return g
    own = {(Path(g.target) / r).as_posix().lower() for r in rec[2]} if rec else set()
    # HelixSR's DLL in a HelixSR-fsrfg folder is never the game's FSR (also one put in by hand, without a record)
    mine = lambda p: Path(p).as_posix().lower() in own or Path(p).parent.name.lower() == HELIX_DIR.lower()
    if not any(mine(t) for t in g.fsr_targets):
        return g
    # the game's own FSR 3.1 DLLs, picked the way helixsr_games picks them (the upscaler DLL first)
    if not hasattr(hi, 'walk'):
        g.fsr_targets = [t for t in g.fsr_targets if not mine(t)]
        return g
    found = [Path(d) / n for d, names in hi.walk(g.folder, getattr(hi, 'SCAN_DEPTH', 16)) for n in names
             if n.lower() in hi.NAMES and SCALER_BACKUP not in Path(d).parts and not mine(Path(d) / n)]
    up = [p for p in found if p.name.lower() == hi.DLL_SR]
    g.fsr_targets = sorted(up or [p for p in found if p.name.lower() == hi.DLL])
    return g


def all_games(hi, extra):
    return [without_scaler_files(hi, g) for g in hi.games(extra)]


def find_game(hi, folder):
    """The game in folder: from the full scan when it is listed there (keeps its store name), else from the folder."""
    want = Path(hi.clean_path(folder)).expanduser()
    try:
        want = want.resolve()
    except OSError:
        pass
    for g in hi.games([]):
        try:
            if Path(g.folder).resolve() == want:
                return without_scaler_files(hi, g)
        except OSError:
            continue
    found = hi.games_from([str(want)])
    if not found:
        raise BridgeError(f'no game (.exe) found in {want}')
    return without_scaler_files(hi, found[0])


# --- helixsr.ini -------------------------------------------------------------------------------------------------------

def ini_read(text):
    """{'Section.Key': value} of the active (not commented) lines."""
    out, section = {}, ''
    for line in text.splitlines():
        s = line.strip()
        m = re.match(r'^\[([^\]]+)\]\s*$', s)
        if m:
            section = m.group(1).strip()
            continue
        if not s or s.startswith((';', '#')):
            continue
        k, sep, v = s.partition('=')
        if sep:
            out[f'{section}.{k.strip()}'] = v.strip()
    return out


def ini_set(text, section, key, value):
    """Sets (value) or comments out (None) Key in [section]; keeps every other line and the line endings."""
    nl = '\r\n' if '\r\n' in text else '\n'
    lines = text.split(nl) if text else []
    cur, sec_start, sec_end, hits = None, None, None, []
    for i, line in enumerate(lines):
        m = re.match(r'^\s*\[([^\]]+)\]\s*$', line)
        if m:
            if cur is not None and cur.lower() == section.lower() and sec_end is None:
                sec_end = i
            cur = m.group(1).strip()
            if cur.lower() == section.lower() and sec_start is None:
                sec_start = i
            continue
        if cur is not None and cur.lower() == section.lower():
            if re.match(r'^\s*[;#]?\s*%s\s*=' % re.escape(key), line, re.I):
                hits.append(i)
    if sec_start is not None and sec_end is None:
        sec_end = len(lines)
    active = [i for i in hits if not lines[i].lstrip().startswith((';', '#'))]
    if value is None:
        for i in active:
            lines[i] = ';' + lines[i].lstrip()
        return nl.join(lines)
    new = f'{key} = {value}'
    if active:
        lines[active[0]] = new
        for i in active[1:]:
            lines[i] = ';' + lines[i].lstrip()
    elif hits:
        lines[hits[-1]] = new          # the template's commented example line becomes the setting
    elif sec_start is not None:
        lines.insert(sec_start + 1, new)
    else:
        while lines and lines[-1] == '':
            lines.pop()
        lines += ['', f'[{section}]', new, '']
    return nl.join(lines)


def check_value(name, value):
    if name not in SETTINGS:
        raise BridgeError(f'unknown setting {name}')
    if value is None:
        return None
    value = str(value).strip()
    allowed = SETTINGS[name]
    if allowed is None:
        try:
            v = float(value)
        except ValueError:
            raise BridgeError(f'{name}: not a number: {value}')
        if not 0.0 <= v <= 1.0:
            raise BridgeError(f'{name}: must be between 0.0 and 1.0')
        return f'{v:g}'
    if value.lower() not in allowed:
        raise BridgeError(f'{name}: one of {", ".join(allowed)}')
    return value.lower()


# --- commands ----------------------------------------------------------------------------------------------------------

def cmd_status(hi, release, a):
    dll = release_dll(release)
    return {
        'version': hi.version_of(dll) if dll.exists() else None,
        'network_ready': bool(network_ready(hi, release)),
        'fg_ready': fg_dir(release) is not None,
        'fg_reason': fg_reason(release),
        # a release without HelixSR frame generation (3.0: no setup/fg) has nothing to set up
        'fg_available': (Path(release) / 'setup' / 'fg' / 'fg_setup.py').is_file(),
        # HLX FSR 4 built by the setup (None: the release has none)
        'hlx_ready': (lambda h: None if h is None else bool(hi.hlx_built(h)))(hi.hlx_source(dll.parent)),
        'release': str(release),
    }


def cmd_games(hi, release, a):
    gl = all_games(hi, a.get('folder', []))
    return {'games': [game_json(hi, g) for g in gl]}


def cmd_install(hi, release, a):
    way = a.get('way') or 'auto'
    if way not in WAYS + ('auto',):
        raise BridgeError('--way must be auto, scaler or fsr')
    g = find_game(hi, one(a, 'game'))
    if way == 'auto':
        way = recommended(g)
        if way is None:
            raise BridgeError(f'{g.name} has no upscaler HelixSR can take over')
    if way not in ways(g):
        raise BridgeError(f'{g.name} cannot use the {way} way (it has: {", ".join(ways(g)) or "neither"})')
    # HLX FSR 4 (the fsr way from HelixSR 2.1 on) has its own network: only HelixSR's DLL needs the built one; its
    # shaders are built by the setup from AMD's file (HelixSR 3.0 on)
    hlx = hi.hlx_source(release_dll(release).parent) if way == 'fsr' else None
    if hlx and not hi.hlx_built(hlx):
        raise BridgeError('HLX FSR 4 is not built yet: run the setup again (it builds it from AMD\'s FSR 4 driver file)')
    if not network_ready(hi, release) and not hlx:
        raise BridgeError('the network is not built yet')
    current = installed_way(hi, g)
    new_version = hi.version_of(release_dll(release))
    if way == 'scaler':
        pkg = a.get('scaler')
        if not pkg:
            raise BridgeError('HelixSR Scaler has not been downloaded yet')
        check_scaler_pairing(release, pkg, a.get('scaler-version'))
        # Reject unusable input before removing the current install or its recovery archive.
        fg = a.get('fg')
        if fg not in (None, 'on', 'off'):
            raise BridgeError('--fg must be on or off')
        name = a.get('scaler-name')
        if name and name not in SCALER_NAMES:
            raise BridgeError(f'--scaler-name must be one of {", ".join(SCALER_NAMES)}')
        scaler_package_files(Path(pkg))
        if current and current != way:
            drop_previous(hi, g, current)
        if current == 'scaler':   # an update (not a repair with the same versions): keep what the game has now
            now = (installed_version(hi, g, way), scaler_record(g.target)[1])
            # moving an install to the release's layout is an update too, also with the same versions
            if now != (new_version, a.get('scaler-version') or now[1]) or layout(g.target) != release_layout(release):
                save_previous(hi, g, way, *now)
        if current and current != 'scaler':
            _messages.append('removing the other HelixSR install first')
            hi.uninstall(g)
        scaler_install(hi, release, g.target, Path(pkg), a.get('scaler-version'), a.get('scaler-name'), fg,
                       game_dlssg(hi, g))
        g = find_game(hi, str(g.folder))
        return {'game': game_json(hi, g)}
    if current and current != way:
        drop_previous(hi, g, current)
    if current == 'scaler':
        _messages.append('removing HelixSR Scaler first')
        scaler_uninstall(g.target, quiet=True)
        g = find_game(hi, str(g.folder))
    if current == 'fsr' and installed_version(hi, g, 'fsr') != new_version:
        save_previous(hi, g, 'fsr', installed_version(hi, g, 'fsr'), None)
    g.route = 'direct'
    g.chosen = False
    hi.install(g, release_dll(release).parent)
    g = find_game(hi, str(g.folder))
    return {'game': game_json(hi, g)}


def cmd_scaler_fg(hi, release, a):
    g = find_game(hi, one(a, 'game'))
    if installed_way(hi, g) != 'scaler':
        raise BridgeError(f'HelixSR Scaler is not installed in {g.name}')
    on = one(a, 'on')
    if on not in ('true', 'false'):
        raise BridgeError('--on must be true or false')
    scaler_set_fg(release, g.target, on == 'true', game_dlssg(hi, g))
    g = find_game(hi, str(g.folder))
    return {'game': game_json(hi, g)}


def cmd_remove(hi, release, a):
    g = find_game(hi, one(a, 'game'))
    way = installed_way(hi, g)
    if not way:
        raise BridgeError(f'HelixSR is not installed in {g.name}')
    drop_previous(hi, g, way)
    if way == 'scaler':
        scaler_uninstall(g.target)
    else:
        hi.uninstall(g)
    g = find_game(hi, str(g.folder))
    return {'game': game_json(hi, g)}


def settings_file(hi, a):
    g = find_game(hi, one(a, 'game'))
    way = installed_way(hi, g)
    if not way:
        raise BridgeError(f'HelixSR is not installed in {g.name}')
    return g, Path(settings_dir(hi, g, way)) / INI


def scaler_settings_file(hi, a):
    g = find_game(hi, one(a, 'game'))
    if installed_way(hi, g) != 'scaler':
        return None
    return g.target / 'OptiScaler.ini'


def cmd_settings_get(hi, release, a):
    p = scaler_settings_file(hi, a)
    if p is not None:
        text = hi.read_ini(p) if p.exists() else ''
        return {'kind': 'scaler', 'path': str(p), 'exists': p.exists(), 'values': scaler_settings_read(text),
                'other': {}}
    g, p = settings_file(hi, a)
    text = hi.read_ini(p) if p.exists() else ''
    vals = ini_read(text)
    return {'kind': 'helixsr', 'path': str(p), 'exists': p.exists(),
            'values': {k: vals.get(k) for k in SETTINGS},
            'other': {k: v for k, v in vals.items() if k not in SETTINGS}}


def cmd_settings_set(hi, release, a):
    try:
        values = json.loads(one(a, 'values'))
    except ValueError:
        raise BridgeError('--values is not JSON')
    p = scaler_settings_file(hi, a)
    if p is not None:
        if not p.exists():
            raise BridgeError(f'OptiScaler.ini is missing in {p.parent}: install HelixSR Scaler again')
        hi.write_ini(p, scaler_settings_write(hi.read_ini(p), values))
        return cmd_settings_get(hi, release, a)
    g, p = settings_file(hi, a)
    checked = {k: check_value(k, v) for k, v in values.items()}
    if p.exists():
        text = hi.read_ini(p)
    else:
        text = getattr(hi, 'INI_TEMPLATE', '') or '; HelixSR settings. HelixSR reads this file next to its DLL.\n'
        text = text.replace('\r\n', '\n').replace('\n', '\r\n')   # Windows line endings (Notepad)
    for name, v in checked.items():
        section, key = name.split('.', 1)
        text = ini_set(text, section, key, v)
    hi.write_ini(p, text)
    if installed_way(hi, g) == 'fsr':
        # games with HelixSR in more than one folder (e.g. Unreal Engine plugin folders): every copy gets the settings
        for d in sorted({t.parent for t in g.fsr_targets if hi.is_ours(t)} - {p.parent}):
            q = d / INI
            other = hi.read_ini(q) if q.exists() else text
            for name, v in checked.items():
                section, key = name.split('.', 1)
                other = ini_set(other, section, key, v)
            hi.write_ini(q, other)
    return cmd_settings_get(hi, release, a)


def cmd_reset_settings(hi, release, a):
    """The game's HelixSR settings back to the defaults (an update or a reinstall keeps them)."""
    g = find_game(hi, one(a, 'game'))
    way = installed_way(hi, g)
    if way == 'scaler':
        pkg = a.get('scaler')
        src = Path(pkg) / 'OptiScaler.ini' if pkg else None
        if src is None or not src.is_file():
            raise BridgeError('HelixSR Scaler has not been downloaded yet: its default settings come with it')
        t = g.target
        shutil.copyfile(src, t / 'OptiScaler.ini')
        made = t / helix_dir(t) / INI   # written from OptiScaler.ini by HelixSR Scaler when the game starts
        if made.is_file():
            made.unlink()
        write_scaler_defaults(t)
        if layout(t) == 'old' and fg_installed(t):
            scaler_set_fg(release, t, False)   # (the earlier layout: its files parked)
            _messages.append('HelixSR Scaler\'s settings are back to the defaults (frame generation off)')
        else:
            # HelixSR's frame generation stays wired to the game's DLSS Frame Generation (where the game has it)
            on = fg_installed(t) and game_dlssg(hi, g) is not False
            write_scaler_fg(t, True if on else False)
            _messages.append('HelixSR Scaler\'s settings are back to the defaults' +
                             (' (frame generation follows the game\'s DLSS Frame Generation setting)' if on else ''))
    elif way == 'fsr':
        dirs = {t.parent for t in g.fsr_targets if hi.is_ours(t)}
        if settings_dir(hi, g, way):
            dirs.add(Path(settings_dir(hi, g, way)))
        for d in sorted(dirs):
            if (d / INI).is_file():
                (d / INI).unlink()
        _messages.append('HelixSR\'s settings are back to the defaults')
    elif way:
        raise BridgeError(f'{g.name} has HelixSR from an earlier way: install it again to reset its settings')
    else:
        raise BridgeError(f'HelixSR is not installed in {g.name}')
    g = find_game(hi, str(g.folder))
    return {'game': game_json(hi, g)}


def cmd_log(hi, release, a):
    g = find_game(hi, one(a, 'game'))
    way = installed_way(hi, g)
    d = settings_dir(hi, g, way) if way else None
    files = []
    if d:
        files.append(Path(d) / 'helixsr.log')
    if way == 'dlss' and g.target:
        files.append(g.target / 'helixsr_loader.log')
    if way == 'scaler' and g.target:
        files.append(g.target / 'OptiScaler.log')
    out = {'files': [], 'important': [], 'report': ''}
    for f in files:
        if not f.exists():
            continue
        text = f.read_text(errors='replace')
        lines = text.splitlines()
        imp = [l for l in lines if any(k in l for k in LOG_KEYS)]
        out['files'].append({'path': str(f), 'lines': len(lines), 'tail': lines[-200:]})
        out['important'] += imp[-40:]
    st = cmd_status(hi, release, a)
    report = [f'**Game:** {g.name}', f'**Way:** {way or "not installed"}', f'**HelixSR:** {st["version"]}',
              f'**OS:** {sys.platform}', '', '```'] + out['important'][-40:] + ['```']
    out['report'] = '\n'.join(report)
    return out


COMMANDS = {'status': cmd_status, 'games': cmd_games, 'install': cmd_install, 'remove': cmd_remove,
            'scaler-fg': cmd_scaler_fg, 'reset-settings': cmd_reset_settings,
            'settings-get': cmd_settings_get, 'settings-set': cmd_settings_set, 'log': cmd_log,
            'rollback': cmd_rollback}


def one(a, k):
    v = a.get(k)
    if not v:
        raise BridgeError(f'--{k} is required')
    return v[-1] if isinstance(v, list) else v


def parse(argv):
    a = {}
    i = 0
    while i < len(argv):
        k = argv[i]
        if not k.startswith('--') or i + 1 >= len(argv):
            raise BridgeError(f'bad argument: {k}')
        k = k[2:]
        if k == 'folder':
            a.setdefault('folder', []).append(argv[i + 1])
        else:
            a[k] = argv[i + 1]
        i += 2
    return a


def main(argv):
    out = {'protocol': PROTOCOL, 'ok': False}
    try:
        if len(argv) < 2 or argv[1] not in COMMANDS:
            raise BridgeError('usage: helixsr_bridge.py RELEASE_DIR ' + '|'.join(COMMANDS) + ' [options]')
        release = Path(argv[0]).expanduser().resolve()
        hi = load_installer(release)
        out.update(COMMANDS[argv[1]](hi, release, parse(argv[2:])))
        out['ok'] = True
    except BridgeError as e:
        out['error'] = str(e)
    except SystemExit as e:   # helixsr_games stops with SystemExit(message) on problems
        out['error'] = str(e.code) if e.code not in (None, 0) else 'stopped'
    except Exception as e:
        out['error'] = f'{type(e).__name__}: {e}'
        out['trace'] = traceback.format_exc()
    out['messages'] = _messages
    sys.stdout.write(json.dumps(out) + '\n')
    sys.stdout.flush()
    return 0 if out['ok'] else 1


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
