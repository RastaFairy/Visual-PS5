#!/usr/bin/env python3
# Copyright 2026 lonewolf0622. All rights reserved (HelixSR Freeware License).
"""HelixSR Desktop's game part: finds the games (every Steam library on Linux, Flatpak Steam and Windows, the other
stores' folders, and folders given by hand), the FSR drop-in (HelixSR in place of a game's FSR 3.1 DLL, the game's
file kept as *.original.dll), and installs of earlier HelixSR versions (the OptiScaler way, the DLSS loader), which are
recognized so they can be switched or removed with everything put back. HelixSR Scaler's own install is in
helixsr_bridge.py.

HelixSR's setup up to 1.9 carried this as setup/helixsr_install.py; from HelixSR 2.0 on the setup carries a copy of this
file and of helixsr_bridge.py and installs through them, the same way as this app. Uses only Python's standard
library."""
import json, os, re, shutil, sys
from pathlib import Path

DLL = 'amd_fidelityfx_dx12.dll'
DLL_SR = 'amd_fidelityfx_upscaler_dx12.dll'
NAMES = (DLL_SR, DLL)                     # a game's FSR 3.1 DLLs, the upscaler one first
NETWORK = ('helixsr_weights.bin', 'helixsr_kernels.pak')
# HLX FSR 4 (FSR 4.1.2 Lite): the FSR drop-in from HelixSR 2.1 on, in the release's HLX-FSR4 folder. It takes the game's
# FSR DLL's place under the game's file name and lists the game's own FSR (kept as *.original.dll) after itself.
HLX_DIR = 'HLX-FSR4'
HLX_MARK = b'HLX FSR 4 ('   # in HLX FSR 4's DLL (its version name, "HLX FSR 4 (4.1.2)")
FOLDER = 'HelixSR'
PKG = Path(__file__).resolve().parent.parent   # the app's own folder: never treated as a game
SCAN_DEPTH = 16   # folders below a game's folder searched for its DLLs (Unreal Engine plugins sit 8 to 10 deep, issue #41)
MARKER = 'helixsr-install.json'
BACKUP = 'backup'
INI = 'helixsr.ini'                               # HelixSR's settings, next to HelixSR's DLL
# Made for the user when a game has none: the settings people change, each at HelixSR's default, so HelixSR behaves
# exactly as without the file. Windows line endings (Notepad).
INI_TEMPLATE = '''\
; HelixSR settings. Change a value, save, and restart the game.

[Sharpening]
; off, nvidia or rcas
Sharpener = off
; 0.0 to 1.0 (used when a sharpener is on)
Sharpness = 0.1

[Compatibility]
; auto, 64 or 32. Leave it on auto unless the picture is broken
WaveSize = auto
'''.replace('\n', '\r\n')
# HelixSR Scaler: what it leaves in a game (HelixSR Desktop and HelixSR Scaler's own setup keep the same record)
SCALER_FILES = 'HelixSR-Scaler.files'
SCALER_BACKUP = 'HelixSR-Scaler-backup'
# anti-cheat that games ship in their own folder: file and folder names (lower case, start of the name)
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
ANTICHEAT_DEPTH = 4
# What installs of earlier versions left in a game (recognized and removed; nothing new is installed that way):
#  - the OptiScaler way: OptiScaler next to the game's .exe, HelixSR and AMD's FSR DLLs in the game's HelixSR folder
OWN = 'helixsr.dll'                               # HelixSR for OptiScaler's FfxDx12Path
OWN_SR = 'helixsr_upscaler.dll'                   # and for its FfxDx12SRPath
AMD_FSR = 'amd_fidelityfx_upscaler_dx12.amd.dll'  # AMD's FSR, listed by OptiScaler after HelixSR
AMD_FG = 'amd_fidelityfx_framegeneration_dx12.dll'   # AMD's frame generation
AMD_SHA256 = {   # AMD's FidelityFX 4.1.1 DLLs as earlier versions shipped them (older records carry no hash)
    AMD_FSR: {'d0dcccc74a43c44ba435b7a369b456e0970d8a4464e4bd683119b374f2c9fb46'},
    AMD_FG: {'02297beedd285e822d3a64f314cf00faf378dcec0edc47ff0c4dd71b3a8c2f18'},
}
MY_FSR = 'my-fsr'                                 # in the game's HelixSR folder: the user's own FSR DLLs (kept if used)
OLD_FILES = ('nvngx.dll', DLL, DLL_SR)            # left in the HelixSR folder by HelixSR 1.5 / 1.6 / early 1.7
#  - the DLSS loader: the loader (under one of these names) and HelixSR as nvngx.dll next to the game's .exe
LOADER_NAMES = ('dxgi.dll', 'version.dll', 'winmm.dll', 'dinput8.dll', 'dbghelp.dll', 'winhttp.dll', 'wininet.dll')
CORE = 'nvngx.dll'
FG_DIR = 'helixsr-fg'                             # frame generation's files next to the loader
SKIP_EXE = re.compile(r'unins|setup|redist|crash|launcher|vc_?redist|dxsetup|easyanticheat|beservice|dotnet|'
                      r'helper|report|prereq|install|7z|ue4prereq|cefprocess|webhelper', re.I)
INPUTS = {'nvngx_dlss.dll': 'DLSS', 'libxess.dll': 'XeSS', 'ffx_fsr2_api_x64.dll': 'FSR 2',
          'ffx_fsr2_api_dx12_x64.dll': 'FSR 2'}


def say(msg):
    print(f'[helixsr-setup] {msg}', flush=True)


def is_helixsr(path):
    try:
        with open(path, 'rb') as f:
            return re.search(rb'HelixSR \d+\.\d+\.\d+', f.read(4 << 20)) is not None
    except OSError:
        return False


def is_hlx(path):
    """HLX FSR 4's DLL (the FSR drop-in from HelixSR 2.1 on)."""
    try:
        return HLX_MARK in Path(path).read_bytes()
    except OSError:
        return False


def hlx_built(path):
    """HLX FSR 4's DLL carries its shaders (the setup builds them from AMD's file and appends them; HelixSR 3.0 on) or
    is an earlier one with them inside."""
    try:
        b = Path(path).read_bytes()
    except OSError:
        return False
    return b[-24:-16] == b'HLXFSR4D' or (HLX_MARK in b and len(b) > 16 << 20)


def is_ours(path):
    """A game's FSR DLL that is HelixSR's drop-in: HelixSR's FidelityFX DLL (up to 2.0) or HLX FSR 4."""
    return is_helixsr(path) or is_hlx(path)


def hlx_source(here):
    """HLX FSR 4 in the release (HLX-FSR4/ next to HelixSR's folder here, or in it), None when the release has none."""
    for d in (Path(here).parent / HLX_DIR, Path(here) / HLX_DIR):
        if (d / DLL_SR).is_file():
            return d / DLL_SR
    return None


def release_version(here):
    """The release's HelixSR version (from HelixSR's DLL in here: helixsr.dll or the FidelityFX DLL)."""
    for n in ('helixsr.dll', DLL):
        if (Path(here) / n).is_file():
            return version_of(Path(here) / n)
    return '?'


def is_loader(path):
    try:
        with open(path, 'rb') as f:
            return b'HelixSR DLSS loader' in f.read(1 << 20)
    except OSError:
        return False


def is_optiscaler(path):
    try:
        with open(path, 'rb') as f:
            return b'OptiScaler' in f.read(32 << 20)
    except OSError:
        return False


def version_of(dll):
    m = re.search(rb'\x00HelixSR (\d+\.\d+\.\d+)\x00', Path(dll).read_bytes()[:4 << 20])
    return m.group(1).decode() if m else '?'


def copy_checked(src, dst):
    shutil.copyfile(src, dst)
    if Path(dst).read_bytes() != Path(src).read_bytes():
        raise SystemExit(f'{dst} differs from the file just copied: something on this PC changes new files there '
                         '(antivirus or a synced folder). Close the game and try again.')


def sha(path):
    import hashlib
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def read_marker(d):
    """The install record in d ({} if there is none or it cannot be read)."""
    try:
        return json.loads((d / MARKER).read_text())
    except (OSError, ValueError):
        return {}


def make_ini(d, made):
    """A commented helixsr.ini in d if there is none. Returns the sha256 of the file HelixSR made (to remove it on
    uninstall only while unchanged), or `made` (the earlier one, None for a file the user made) if a file is there."""
    p = d / INI
    if p.exists():
        return made
    with open(p, 'w', encoding='ascii', newline='') as f:
        f.write(INI_TEMPLATE)
    return sha(p)


def remove_ini(d, made):
    """Removes the helixsr.ini HelixSR made in d, if unchanged. One the user made or edited is kept."""
    p = d / INI
    if not made or not p.exists():
        return
    if sha(p) == made:
        p.unlink()
    else:
        say(f'  your settings in {p} were left there (edited); delete the file if you no longer need it')


def remove_my_fsr(folder):
    """Removes the game's my-fsr folder unless the user put files there; True if it was kept."""
    d = folder / MY_FSR
    if (d / 'README.txt').exists():
        (d / 'README.txt').unlink()
    try:
        d.rmdir()
    except FileNotFoundError:
        pass
    except OSError:
        return True
    return False


def has_embedded_network(path):
    """True when the DLL carries the network (the setup appends it: one-file DLL)."""
    try:
        with open(path, 'rb') as f:
            f.seek(-32, os.SEEK_END)
            return f.read(8) == b'HXSRNET1'
    except OSError:
        return False


def network_ready(here):
    return is_helixsr(here / DLL) and (has_embedded_network(here / DLL) or all((here / n).exists() for n in NETWORK))


def copy_network(here, folder):
    """Separate network files only when the DLL does not carry the network; otherwise earlier copies are removed (the
    DLL reads its own copy first)."""
    for n in NETWORK:
        if has_embedded_network(here / DLL):
            if (folder / n).exists():
                (folder / n).unlink()
        else:
            copy_checked(here / n, folder / n)


# --- finding games ---------------------------------------------------------------------------------------------------

SCAN_VERSION = 2   # what the game scan covers (2: Bottles, itch, Steam on every Windows drive, launcher entries inside games)

# Windows registry keys the scan reads: (hive, key[, value])
REG_STEAM = [('HKEY_CURRENT_USER', r'Software\Valve\Steam', 'SteamPath'),
             ('HKEY_LOCAL_MACHINE', r'SOFTWARE\WOW6432Node\Valve\Steam', 'InstallPath'),
             ('HKEY_LOCAL_MACHINE', r'SOFTWARE\Valve\Steam', 'InstallPath')]
REG_GOG = [('HKEY_LOCAL_MACHINE', r'SOFTWARE\WOW6432Node\GOG.com\Games'), ('HKEY_LOCAL_MACHINE', r'SOFTWARE\GOG.com\Games')]
REG_UNINSTALL = [('HKEY_LOCAL_MACHINE', r'SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall'),
                 ('HKEY_LOCAL_MACHINE', r'SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall'),
                 ('HKEY_CURRENT_USER', r'SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall')]


def text_of(p):
    return Path(p).read_text(encoding='utf-8', errors='replace')   # launchers write UTF-8 (not the Windows code page)


def reg_value(hive, key, name):
    try:
        import winreg
        with winreg.OpenKey(getattr(winreg, hive), key) as k:
            return winreg.QueryValueEx(k, name)[0]
    except (OSError, ImportError, AttributeError):
        return None


def reg_entries(keys):
    """{value name (lower case): value} of every subkey of the given registry keys."""
    out = []
    try:
        import winreg
    except ImportError:
        return out
    for hive, key in keys:
        try:
            with winreg.OpenKey(getattr(winreg, hive), key) as k:
                for i in range(winreg.QueryInfoKey(k)[0]):
                    try:
                        with winreg.OpenKey(k, winreg.EnumKey(k, i)) as g:
                            vals = {}
                            for j in range(winreg.QueryInfoKey(g)[1]):
                                n, v, _ = winreg.EnumValue(g, j)
                                vals[n.lower()] = os.path.expandvars(v) if isinstance(v, str) else v
                            out.append(vals)
                    except OSError:
                        pass
        except OSError:
            pass
    return out


def drive_roots():
    """Windows: the root of every drive (C:\\, D:\\, ...)."""
    if os.name != 'nt':
        return []
    import string
    try:
        import ctypes
        mask = ctypes.windll.kernel32.GetLogicalDrives()
    except (OSError, AttributeError, ImportError):
        mask = (1 << 26) - 1
    return [Path(f'{c}:\\') for i, c in enumerate(string.ascii_uppercase) if mask >> i & 1]


def steam_roots():
    roots = []
    if os.name == 'nt':
        roots += [Path(v) for v in (reg_value(*r) for r in REG_STEAM) if v]
        roots.append(Path(os.environ.get('ProgramFiles(x86)', r'C:\Program Files (x86)')) / 'Steam')
        for d in drive_roots():   # libraries on other drives (also ones Steam lost track of after a reinstall)
            roots += [d / 'SteamLibrary', d / 'Steam', d / 'Games' / 'SteamLibrary', d / 'Games' / 'Steam',
                      d / 'Program Files (x86)' / 'Steam', d / 'Program Files' / 'Steam']
    else:
        h = Path.home()
        roots += [h / '.local/share/Steam', h / '.steam/steam', h / '.steam/root',
                  h / '.var/app/com.valvesoftware.Steam/.local/share/Steam', h / 'snap/steam/common/.local/share/Steam']
    return roots


def steam_library_paths(text):
    """The library folders listed in Steam's libraryfolders.vdf (text VDF: \\\\ and \\" escapes)."""
    return [re.sub(r'\\(.)', r'\1', p) for p in re.findall(r'"path"\s+"((?:[^"\\]|\\.)*)"', text, re.I)]


MISSING_LIBRARIES = []   # Steam libraries listed in libraryfolders.vdf that are not reachable (drive not mounted?)


def steam_libraries():
    libs, seen = [], set()
    MISSING_LIBRARIES.clear()
    for root in steam_roots():
        vdf = root / 'steamapps' / 'libraryfolders.vdf'
        paths = [root]
        try:
            if vdf.is_file():
                paths += [Path(p) for p in steam_library_paths(text_of(vdf))]
        except OSError:
            pass
        for p in paths:
            common = p / 'steamapps' / 'common'
            try:
                key = common.resolve()
                there = common.is_dir()
            except OSError:   # (no permission to look: Python before 3.12)
                key, there = common, False
            if key in seen:
                continue
            if there:
                seen.add(key)
                libs.append(common)
            elif p != root:
                seen.add(key)
                MISSING_LIBRARIES.append(p)
    return libs


# A folder from a list of any programs (Windows' "Installed apps", Steam's non-Steam shortcuts) is only searched when it
# looks like a game within its first PROOF_DEPTH folders: files games ship (store SDKs, engines), an Unreal game's
# -Shipping.exe, or an upscaler DLL next to an .exe. Editors and tools with upscaler DLLs in their plugins are not games.
PROOF_DEPTH = 4
GAME_MARKERS = {'steam_api64.dll', 'steam_api.dll', 'eossdk-win64-shipping.dll', 'galaxy64.dll', 'galaxy.dll',
                'unityplayer.dll', 'gameassembly.dll', 'uplay_r1_loader64.dll', 'uplay_r2_loader64.dll',
                'upc_r2_loader64.dll', 'easyanticheat_x64.dll', 'easyanticheat_eos_setup.exe', 'beclient_x64.dll',
                'bink2w64.dll', 'amd_ags_x64.dll', 'gfsdk_aftermath_lib.x64.dll'}
NOT_GAME_EXES = {'unrealeditor.exe', 'ue4editor.exe', 'unity.exe', 'blender.exe', 'godot.exe', 'devenv.exe'}


def looks_like_game(tree):
    """tree (walk() pairs) looks like a game: no editor's .exe, and a game marker, an Unreal -Shipping.exe or an
    upscaler DLL (DLSS, XeSS, FSR) in a folder with an .exe."""
    game = False
    for _, names in tree:
        low = {n.lower() for n in names}
        if low & NOT_GAME_EXES:
            return False
        if low & GAME_MARKERS or any(n.endswith(('-shipping.exe', '-wingdk-shipping.exe')) for n in low) or \
                (any(n.endswith('.exe') for n in low) and low & (set(INPUTS) | set(NAMES))):
            game = True
    return game


# folders a game scan does not go into: the backup of the game's files HelixSR Scaler replaced
WALK_SKIP = {SCALER_BACKUP.lower()}
# an OptiScaler's own folder (HelixSR Scaler's too): AMD's FSR and Intel's XeSS DLLs in there are not the game's
OPTI_DIR = 'optiscaler'


def walk(folder, depth):
    """(directory, file names) pairs under folder, at most depth levels deep, without following links (not into the
    HelixSR folder or HelixSR Scaler's backup)."""
    out, todo = [], [(Path(folder), 0)]
    while todo:
        d, n = todo.pop()
        try:
            entries = list(os.scandir(d))
        except OSError:
            continue
        out.append((d, [e.name for e in entries if e.is_file(follow_symlinks=False) or e.is_symlink()]))
        if n < depth:
            todo += [(Path(e.path), n + 1) for e in entries if e.is_dir(follow_symlinks=False) and e.name != FOLDER
                     and e.name.lower() not in WALK_SKIP]
    return out


def exe_folder(tree):
    """The folder of the game's main .exe (where HelixSR Scaler goes, and installs of earlier versions are)."""
    for d, names in tree:   # a folder that already has HelixSR Scaler, OptiScaler (or HelixSR) wins
        if SCALER_FILES in names or 'OptiScaler.ini' in names or (d / FOLDER / MARKER).exists():
            return d
    best, size = None, -1
    for d, names in tree:
        for n in names:
            if not n.lower().endswith('.exe') or SKIP_EXE.search(n):
                continue
            s = (d / n).stat().st_size if (d / n).exists() else 0
            if n.lower().endswith('-win64-shipping.exe'):
                s += 1 << 40   # Unreal Engine: always the game itself
            if s > size:
                best, size = d, s
    return best


def original(target):
    return target.with_name(target.stem + '.original.dll')


def anticheat_in(folder, tree):
    """The anti-cheat a game ships in its folder (names; [] if none), from the game's file tree (files and folders at
    most ANTICHEAT_DEPTH levels below the game's folder)."""
    found = set()
    base = len(Path(folder).parts)

    def check(n):
        n = n.lower()
        for name, prefixes in ANTICHEAT:
            if n.startswith(prefixes) or (name == 'BattlEye' and n.endswith('_be.exe')):
                found.add(name)
    for d, names in tree:
        level = len(Path(d).parts) - base
        if 0 < level <= ANTICHEAT_DEPTH + 1:
            check(Path(d).name)   # a folder (EasyAntiCheat, BattlEye)
        if level <= ANTICHEAT_DEPTH:
            for n in names:
                check(n)
    return sorted(found)


class Game:
    """A game the setup found. route (the way the setup installs, or would install, HelixSR there):
      'direct'   the FSR drop-in (the game has FSR 3.1; targets = its FSR 3.1 DLLs)
      'scaler'   HelixSR Scaler next to the game's .exe (DLSS, XeSS or FSR 2 without FSR 3.1, or picked for the game,
                 or already installed there)
      'dlss' / 'optiscaler'  an install of an earlier version in a game where neither way applies: can only be removed
      None       nothing HelixSR can use"""

    def __init__(self, name, folder, tree):
        self.name, self.folder = name, folder
        low = {d: {n.lower(): n for n in names} for d, names in tree}
        base = len(Path(folder).parts)

        def opti_dir(d):   # inside an OptiScaler's folder: its DLLs are not the game's
            return OPTI_DIR in (x.lower() for x in Path(d).parts[base:])
        self.inputs = sorted({INPUTS[n] for d in low if not opti_dir(d) for n in low[d] if n in INPUTS},
                             key=['DLSS', 'XeSS', 'FSR 2'].index)
        fsr = [d / low[d][n] for d in low if not opti_dir(d) for n in NAMES if n in low[d]]
        up = [p for p in fsr if p.name.lower() == DLL_SR]
        self.fsr_targets = up or [p for p in fsr if p.name.lower() == DLL]
        # 1.9.0 could put the drop-in into an OptiScaler's folder: recognized so it can be removed
        self.old_dropins = [d / low[d][n] for d in low if opti_dir(d) for n in NAMES if n in low[d]
                            and original(d / low[d][n]).exists() and is_helixsr(d / low[d][n])]
        self.target = exe_folder(tree)
        self.anticheat = anticheat_in(folder, tree)   # (listed; games with anti-cheat are treated like any other)
        # an install of an earlier version next to the game's .exe (its record says which way)
        marker = self.target / FOLDER / MARKER if self.target else None
        try:
            rec = json.loads(marker.read_text()) if marker and marker.exists() else {}
        except (OSError, ValueError):
            rec = {}
        self.dlss_installed = rec.get('route') == 'dlss'
        self.opti_installed = bool(marker and marker.exists()) and not self.dlss_installed
        self.scaler_installed = bool(self.target and (self.target / SCALER_FILES).is_file())
        # 1.8: OptiScaler picked for an FSR 3.1 game (answer o): HelixSR Scaler takes its place there
        self.chosen = rec.get('chosen') == 'optiscaler' and self.opti_installed
        if self.scaler_installed:
            self.route = 'scaler'    # an update keeps the way the game has
        elif self.fsr_targets and not (self.chosen and self.target):
            self.route = 'direct'
        elif (self.inputs or self.fsr_targets) and self.target:
            self.route = 'scaler'
        elif self.dlss_installed:
            self.route = 'dlss'
        elif self.opti_installed:
            self.route = 'optiscaler'
        else:
            self.route = None

    def ways(self):
        """the ways this game can get: 'direct' (FSR 3.1), 'scaler' (an .exe folder and an upscaler HelixSR Scaler can
        take over)"""
        out = []
        if self.fsr_targets:
            out.append('direct')
        if self.target and (self.inputs or self.fsr_targets):
            out.append('scaler')
        return out

    def old_install(self):
        """the way of an earlier version's install in this game ('dlss' or 'optiscaler'), else None"""
        return 'dlss' if self.dlss_installed else 'optiscaler' if self.opti_installed else None

    def direct_installed(self):
        return any(is_ours(t) for t in self.fsr_targets)

    def current(self):
        """the way HelixSR is in this game now: 'scaler', 'direct', 'dlss', 'optiscaler', 'olddrop' (1.9.0's drop-in in
        an OptiScaler's folder) or None"""
        if self.scaler_installed:
            return 'scaler'
        return self.old_install() or ('direct' if self.direct_installed() else 'olddrop' if self.old_dropins else None)

    def installed(self):
        """HelixSR in this game: HelixSR Scaler, the drop-in (with or without the backup of the game's file) or an
        earlier version's install"""
        return self.scaler_installed or bool(self.old_install()) or self.direct_installed() or bool(self.old_dropins)

    def label(self):
        if self.route == 'scaler':
            return ' / '.join(self.inputs or ['FSR 3.1']) + ': HelixSR Scaler (select DLSS in the game)'
        if self.fsr_targets:
            return 'FSR 3.1: FSR drop-in (HelixSR replaces the game\'s FSR DLL: select AMD FSR in the game)'
        return ' / '.join(self.inputs) + ' only'


BIN_DIRS = {'bin', 'bin64', 'bin32', 'binaries', 'x64', 'x86', 'x86_64', 'win64', 'win32', 'retail'}


def game_root(folder):
    """The game's own folder for a folder inside it (launchers that keep the game's .exe or start folder): Unreal
    Engine's <game>/<project>/Binaries/Win64 is <game> (its FSR DLLs are in the plugins there); bin, x64 and such are
    the folder above."""
    p = Path(folder)
    low = [s.lower() for s in p.parts]
    if len(low) > 4 and low[-2] == 'binaries' and low[-1] in ('win64', 'wingdk', 'win32'):
        proj = p.parent.parent
        try:
            up = (proj.parent / 'Engine').is_dir() or (proj.parent / (proj.name + '.exe')).is_file()
        except OSError:
            up = False
        return proj.parent if up else proj
    for _ in range(2):
        if p.name.lower() in BIN_DIRS and len(p.parts) > 3:
            p = p.parent
    return p


SYSTEM_DIRS = {'usr', 'bin', 'sbin', 'lib', 'lib32', 'lib64', 'etc', 'proc', 'sys', 'dev', 'boot'}


def too_broad(p):
    """A folder that cannot be one game: not absolute, the home folder or one above it, a drive or mount point, a
    system folder (a launcher entry for a program started from such a folder)."""
    p = Path(p)
    if not p.is_absolute():
        return True
    h = Path.home()
    if p == h or p in h.parents:
        return True
    low = [s.lower() for s in p.parts]
    if os.name == 'nt':
        return len(low) < 2 or (len(low) == 2 and low[1] in ('windows', 'program files', 'program files (x86)',
                                                              'programdata', 'users', 'xboxgames', 'gog games'))
    return (len(low) < 3 or low[1] in SYSTEM_DIRS or (low[1:3] == ['run', 'media'] and len(low) < 6)
            or (low[1] in ('mnt', 'media') and len(low) < 4))


def binary_vdf(b):
    """Steam's binary VDF (shortcuts.vdf) as nested dicts, keys in lower case."""
    pos = 0

    def cstr():
        nonlocal pos
        end = b.index(b'\x00', pos)
        s, pos = b[pos:end].decode('utf-8', 'replace'), end + 1
        return s

    def obj():
        nonlocal pos
        d = {}
        while pos < len(b):
            t = b[pos]
            pos += 1
            if t == 8:
                return d
            k = cstr().lower()
            if t == 0:
                d[k] = obj()
            elif t == 1:
                d[k] = cstr()
            elif t in (2, 3, 4, 6):
                d[k], pos = int.from_bytes(b[pos:pos + 4], 'little'), pos + 4
            elif t == 7:
                d[k], pos = int.from_bytes(b[pos:pos + 8], 'little'), pos + 8
            else:
                raise ValueError(f'binary VDF: type {t}')
        return d
    return obj()


def steam_shortcuts(data):
    """(name, folder) of the non-Steam games in a shortcuts.vdf: its start folder, else the folder of its .exe."""
    out = []
    try:
        top = binary_vdf(data)
    except (ValueError, IndexError):
        return out
    for e in (top.get('shortcuts') or {}).values():
        if not isinstance(e, dict):
            continue
        start = str(e.get('startdir') or '').strip().strip('"')
        exe = str(e.get('exe') or '').strip()
        exe = exe[1:].split('"')[0] if exe.startswith('"') else exe
        folder = start if start and Path(start).is_absolute() else str(Path(exe).parent) if exe else ''
        if folder:
            out.append((e.get('appname') or None, folder))
    return out


def simple_yaml(text):
    """The maps of a simple YAML file (Bottles' bottle.yml and library.yml): nested 'key: value' lines, plain or quoted
    values (also folded over several lines); lists and other YAML are skipped."""
    root = {}
    stack, last = [(-1, root)], None
    key_re = re.compile(r"""^('(?:[^']|'')*'|"(?:[^"\\]|\\.)*"|[^\s'"#\-?:][^:]*?|-[^\s][^:]*?)\s*:(?:\s+(.*))?$""")
    for line in text.splitlines():
        s = line.strip()
        if not s or s.startswith('#'):
            continue
        ind = len(line) - len(line.lstrip(' '))
        m = key_re.match(s)
        if last and ind > last[2] and (not m or last[3]):   # the value goes on (folded)
            d, k = last[0], last[1]
            d[k] += ' ' + s
            v = d[k]
            last = (d, k, last[2], v[0] in '\'"' and not (len(v) > 1 and v[-1] == v[0]))
            continue
        last = None
        if not m or s.startswith('- '):
            continue
        k, v = unquote_yaml(m.group(1)), (m.group(2) or '').strip()
        while stack[-1][0] >= ind:
            stack.pop()
        d = stack[-1][1]
        if v:
            d[k] = v
            last = (d, k, ind, v[0] in '\'"' and not (len(v) > 1 and v[-1] == v[0]))
        else:
            d[k] = {}
            stack.append((ind, d[k]))

    def fix(d):
        for k, v in d.items():
            d[k] = fix(v) if isinstance(v, dict) else unquote_yaml(v)
        return d
    return fix(root)


def unquote_yaml(v):
    if len(v) > 1 and v[0] == v[-1] == "'":
        return v[1:-1].replace("''", "'")
    if len(v) > 1 and v[0] == v[-1] == '"':
        try:
            return json.loads(v)
        except ValueError:
            return v[1:-1]
    return v


def wine_path(prefix, p):
    """A Windows path (C:\\...) inside a Wine prefix as a path on this computer; other paths as they are."""
    m = re.match(r'^([A-Za-z]):[\\/]*(.*)$', str(p))
    if not m or os.name == 'nt':
        return Path(p)
    rest = m.group(2).replace('\\', '/')
    return (prefix / 'drive_c' / rest) if m.group(1).lower() == 'c' else (prefix / 'dosdevices' / (m.group(1).lower() + ':') / rest)


PREFIX_SKIP = {'windows', 'users', 'programdata', 'program files', 'program files (x86)', 'common files',
               'internet explorer', 'windows media player', 'windows nt', 'windows defender', 'windowspowershell',
               'windows photo viewer', 'windows mail', 'windows sidebar', 'windows journal', 'windows portable devices',
               'dotnet', 'mono', 'wine', 'temp', 'msbuild', 'reference assemblies', 'gog games', 'games', 'steam',
               'epic games', 'gog galaxy', 'ea games', 'origin games', 'electronic arts', 'ubisoft', 'rockstar games',
               'amazon games', 'battle.net', '$recycle.bin'}
PREFIX_LIBRARIES = ('Steam/steamapps/common', 'Epic Games', 'GOG Galaxy/Games', 'EA Games', 'Origin Games',
                    'Electronic Arts', 'Ubisoft/Ubisoft Game Launcher/games', 'Rockstar Games', 'Amazon Games/Library')


def prefix_games(drive_c):
    """Folders of the games a Wine prefix may hold: in Program Files, GOG Games, Games or right in C:, and in the
    library folders of the Windows launchers installed there."""
    def kids(d):
        try:
            return sorted((Path(e.path) for e in os.scandir(d) if e.is_dir(follow_symlinks=False)
                           and e.name.lower() not in PREFIX_SKIP and not e.name.lower().startswith('microsoft')),
                          key=lambda p: p.name.lower())
        except OSError:
            return []
    out = []
    for t in ('', 'Program Files', 'Program Files (x86)', 'GOG Games', 'Games'):
        out += kids(drive_c / t)
    for base in ('Program Files (x86)', 'Program Files', ''):
        for sub in PREFIX_LIBRARIES:
            out += kids(drive_c / base / sub)
    return out


def epic_games(manifests):
    """(name, folder) from the Epic Games Launcher's manifests (one JSON .item per installed game)."""
    out = []
    try:
        items = sorted(Path(manifests).glob('*.item'))
    except OSError:
        return out
    for m in items:
        try:
            j = json.loads(text_of(m))
            engine = str(j.get('AppName') or '').startswith('UE_') or 'engines' in (j.get('AppCategories') or [])
            if not j.get('bIsIncompleteInstall') and not engine:   # (Unreal Engine installs: not games)
                out.append((j.get('DisplayName'), j.get('InstallLocation') or ''))
        except (OSError, ValueError, AttributeError):
            pass
    return out


def xbox_games(drives):
    """(name, folder) of the Xbox app's / Game Pass games: <drive>\\XboxGames\\<game> (the files under Content)."""
    out = []
    for d in drives:
        try:
            for g in sorted(Path(d, 'XboxGames').iterdir()):
                if g.is_dir():
                    out.append((g.name, g / 'Content' if (g / 'Content').is_dir() else g))
        except OSError:
            pass
    return out


def gog_registry_games(entries):
    """(name, folder) from GOG Galaxy's registry entries (one per game)."""
    return [(e.get('gamename'), e.get('path')) for e in entries if e.get('path')]


SKIP_PUBLISHER = re.compile(r'microsoft|nvidia|advanced micro devices|\bamd\b|intel|realtek|python|adobe|google|mozilla', re.I)


def uninstall_games(entries):
    """(name, folder) from Windows' "Installed apps" entries (EA app, Ubisoft Connect, Battle.net, Rockstar, Amazon and
    most other launchers register their games there): every install folder with an .exe in it."""
    out = []
    for e in entries:
        loc = str(e.get('installlocation') or '').strip().strip('"')
        if not loc or SKIP_PUBLISHER.search(str(e.get('publisher') or '')):
            continue
        p = Path(loc)
        try:
            if len(p.parts) > 2 and (any(p.glob('*.exe')) or any(p.glob('*/*.exe'))):
                out.append((e.get('displayname'), p))
        except OSError:
            pass
    return out


def heroic_games(cfg):
    """(name, folder) of the games of Heroic (config folder cfg): Epic (legendary), GOG, Amazon (nile), added by hand."""
    out = []
    def load(f):
        try:
            return json.loads(text_of(f)) if f.is_file() else None
        except (OSError, ValueError):
            return None
    j = load(cfg / 'legendaryConfig/legendary/installed.json')
    if isinstance(j, dict):
        out += [(v.get('title'), v.get('install_path') or '') for v in j.values() if isinstance(v, dict)]
    j = load(cfg / 'gog_store/installed.json')
    if isinstance(j, dict):
        out += [(v.get('title'), v.get('install_path') or '') for v in j.get('installed') or [] if isinstance(v, dict)]
    j = load(cfg / 'nile_config/nile/installed.json')
    if isinstance(j, list):
        out += [(v.get('title'), v.get('path') or '') for v in j if isinstance(v, dict)]
    j = load(cfg / 'sideload_apps/library.json')
    if isinstance(j, dict):
        for v in j.get('games') or []:
            exe = (v.get('install') or {}).get('executable') if isinstance(v, dict) else None
            if exe:
                out.append((v.get('title'), ('inside', Path(exe).parent)))
    return out


def sqlite_rows(db, query):
    import sqlite3
    con = sqlite3.connect(Path(db).as_uri() + '?mode=ro', uri=True)
    try:
        return con.execute(query).fetchall()
    finally:
        con.close()


def lutris_games(db):
    """(name, folder) of Lutris' installed games (pga.db). A Wine prefix holds the game in its drive_c: the games
    found there are listed, then the prefix."""
    out = []
    try:
        rows = sqlite_rows(db, "SELECT name, directory FROM games WHERE installed = 1 AND directory != ''")
    except Exception:
        return out
    for name, folder in rows:
        d = Path(folder or '')
        inner = prefix_games(d / 'drive_c') if folder and (d / 'drive_c').is_dir() else []
        out += [(name if len(inner) == 1 else None, p) for p in inner] + [(name, folder or '')]
    return out


def itch_games(cfg):
    """(name, folder) of the itch app's installed games (its butler.db, else its default install folder)."""
    out = []
    db = cfg / 'db' / 'butler.db'
    try:
        if db.is_file():
            rows = sqlite_rows(db, 'SELECT g.title, c.custom_install_folder, l.path, c.install_folder_name FROM caves c '
                                   'LEFT JOIN install_locations l ON l.id = c.install_location_id '
                                   'LEFT JOIN games g ON g.id = c.game_id')
            out += [(t, custom or str(Path(loc) / sub)) for t, custom, loc, sub in rows if custom or (loc and sub)]
    except Exception:
        pass
    try:
        out += [(None, p) for p in sorted((cfg / 'apps').iterdir()) if p.is_dir()]
    except OSError:
        pass
    return out


def bottles_games(data):
    """(name, folder) of the games in Bottles (data folder): the programs added to its library and to each bottle,
    and the games in each bottle's drive_c."""
    out = []
    try:
        lib = simple_yaml(text_of(data / 'library.yml')) if (data / 'library.yml').is_file() else {}
    except OSError:
        lib = {}
    try:
        bottles = sorted(p for p in (data / 'bottles').iterdir() if p.is_dir())
    except OSError:
        bottles = []
    for v in lib.values():
        if isinstance(v, dict) and v.get('path'):
            b = v.get('bottle') if isinstance(v.get('bottle'), dict) else {}
            prefix = data / 'bottles' / str(b.get('path') or b.get('name') or '')
            out.append((v.get('name'), ('inside', wine_path(prefix, v['path']).parent)))
    for b in bottles:
        try:
            y = simple_yaml(text_of(b / 'bottle.yml')) if (b / 'bottle.yml').is_file() else {}
        except OSError:
            y = {}
        progs = y.get('External_Programs')
        for v in (progs.values() if isinstance(progs, dict) else []):
            if isinstance(v, dict) and (v.get('folder') or v.get('path')):
                f = wine_path(b, v['folder']) if v.get('folder') else wine_path(b, v['path']).parent
                out.append((v.get('name'), ('inside', f)))
        out += [(None, p) for p in prefix_games(b / 'drive_c')]
    return out


def other_stores():
    """(name, folder, proof) of games installed by other stores: Epic, Xbox / Game Pass, GOG and the launchers in Windows'
    installed apps (Windows); Heroic, Lutris, Bottles (Linux); legendary, itch and Steam's non-Steam games (both). proof:
    a folder from a list of any programs (installed apps, non-Steam shortcuts), a game only when looks_like_game()."""
    found, seen = [], set()
    def add(name, folder, proof=False):
        inside = isinstance(folder, tuple)   # ('inside', folder): a folder inside the game (of its .exe)
        if inside:
            folder = folder[1]
        try:
            if not folder:
                return
            p = Path(folder)
            if inside:
                p = game_root(p)
            if too_broad(p) or not p.is_dir():
                return
            key = p.resolve()
            if key not in seen:   # each folder once (several stores / Steam users)
                seen.add(key)
                found.append((name or p.name, p, proof))
        except (OSError, ValueError):
            pass
    def add_all(pairs, proof=False):
        for name, folder in pairs:
            add(name, folder, proof)
    h = Path.home()
    if os.name == 'nt':
        add_all(epic_games(Path(os.environ.get('ProgramData', r'C:\ProgramData')) / 'Epic' / 'EpicGamesLauncher' / 'Data' / 'Manifests'))
        add_all(gog_registry_games(reg_entries(REG_GOG)))
        appdata = Path(os.environ.get('APPDATA') or h / 'AppData' / 'Roaming')
        add_all(heroic_games(appdata / 'heroic'))
        add_all(itch_games(appdata / 'itch'))
    else:
        for cfg in (h / '.config/heroic', h / '.var/app/com.heroicgameslauncher.hgl/config/heroic'):
            add_all(heroic_games(cfg))
        for db in (h / '.local/share/lutris/pga.db', h / '.var/app/net.lutris.Lutris/data/lutris/pga.db'):
            add_all(lutris_games(db))
        for cfg in (h / '.config/itch', h / '.var/app/io.itch.itch/config/itch'):
            add_all(itch_games(cfg))
        for data in (h / '.local/share/bottles', h / '.var/app/com.usebottles.bottles/data/bottles'):
            add_all(bottles_games(data))
    leg = h / '.config/legendary/installed.json'                      # legendary on its own (also Rare)
    try:
        j = json.loads(text_of(leg)) if leg.is_file() else {}
        add_all((v.get('title'), v.get('install_path') or '') for v in j.values() if isinstance(v, dict))
    except (OSError, ValueError, AttributeError):
        pass
    for root in steam_roots():   # Steam: non-Steam games added to the library
        try:
            for f in sorted(root.glob('userdata/*/config/shortcuts.vdf')):
                add_all(((n, ('inside', d)) for n, d in steam_shortcuts(f.read_bytes())), proof=True)
        except OSError:
            pass
    if os.name == 'nt':
        add_all(xbox_games(drive_roots()))
        mwa = Path(os.environ.get('ProgramFiles', r'C:\Program Files')) / 'ModifiableWindowsApps'
        try:
            add_all((d.name, d) for d in (sorted(mwa.iterdir()) if mwa.is_dir() else []))
        except OSError:
            pass
        add_all(uninstall_games(reg_entries(REG_UNINSTALL)), proof=True)
        for d in drive_roots():
            try:
                add_all((g.name, g) for g in sorted(Path(d, 'GOG Games').iterdir()))
            except OSError:
                pass
    else:
        games_dir = h / 'Games'                                   # Lutris' and Heroic's default install folders
        try:
            for d in sorted(games_dir.iterdir()):
                if d.name == 'Heroic' and d.is_dir():
                    add_all((g.name, g) for g in sorted(d.iterdir()) if g.name != 'Prefixes')
                else:
                    add(d.name, d)
        except OSError:
            pass
    return found


def games(extra):
    out = []
    libs = steam_libraries()
    def real(p):
        try:
            return Path(p).resolve()
        except OSError:
            return Path(p)
    real_libs = [real(c) for c in libs]
    for common in libs:
        try:
            entries = sorted(common.iterdir(), key=lambda p: p.name.lower())
        except OSError as e:
            say(f'note: Steam library {common} could not be read ({e}); its games are not listed')
            continue
        for d in entries:
            try:
                if not d.is_dir() or overlaps(d, PKG):
                    continue
            except OSError:
                continue
            g = Game(d.name, d, walk(d, SCAN_DEPTH))
            if g.route:
                out.append(g)
    done = []   # (folder, listed) of the other stores' folders already searched
    for name, d, proof in other_stores():   # games from other stores (skipped when already listed)
        d = real(d)
        if any(overlaps(d, c) for c in real_libs) or overlaps(d, PKG) or \
                any(d == f or f in d.parents or (listed and d in f.parents) for f, listed in done):
            continue
        if proof and not looks_like_game(walk(d, PROOF_DEPTH)):   # a program that is not a game: not searched
            continue
        g = Game(name, d, walk(d, SCAN_DEPTH))
        done.append((d, bool(g.route)))
        if g.route:
            out.append(g)
    for p in MISSING_LIBRARIES:
        say(f'note: Steam library {p} is not reachable (drive not mounted?); its games are not listed')
    return out + games_from(extra, out)


def clean_path(f):
    """A path as typed, pasted or dragged into a terminal: quotes, file:// URLs (%20), backslash-escaped spaces, a file
    inside the game folder (its folder is used)."""
    from urllib.parse import unquote
    f = f.strip().strip('"').strip("'").strip()
    if f.lower().startswith('file://'):
        f = unquote(f[7:])
    if os.name != 'nt':
        f = re.sub(r'\\(.)', r'\1', f)
    p = Path(f).expanduser()
    return str(p.parent if p.is_file() else p)


def overlaps(a, b):
    a, b = Path(a), Path(b)
    return a == b or a in b.parents or b in a.parents


def games_from(folders, listed=()):
    """Games in folders given by hand (dropped onto the setup, passed, or typed at its prompt). A folder of a game that
    is already listed (or inside it) is skipped; a folder inside a game (e.g. Binaries\\Win64) is taken from the
    nearest parent where the game's FSR 3.1 DLL is found (up to four levels)."""
    out = []
    for f in folders:
        d = Path(clean_path(f)).expanduser()
        if not d.is_dir():
            say(f'not a folder: {d}')
            continue
        d = d.resolve()
        if overlaps(d, PKG):
            say(f'{d} is HelixSR Desktop\'s own folder (or holds it), not a game')
            continue
        same = next((g for g in list(listed) + out if overlaps(g.folder, d)), None)
        if same:
            say(f'{d} is {same.name}, already in the list')
            continue
        g = Game(d.name, d, walk(d, SCAN_DEPTH))
        if not g.fsr_targets:
            up = d
            for _ in range(6):
                if up.parent == up or up.parent.name.lower() in ('', 'common', 'steamapps') or up.parent == Path.home():
                    break
                up = up.parent
                h = Game(up.name, up, walk(up, SCAN_DEPTH))
                if h.route and h.target and overlaps(h.target, d) and (h.fsr_targets or not g.route):
                    g = h
                    break
        if g.route:
            out.append(g)
        else:
            say(f'no DLSS, XeSS or FSR in {d}')
    return out


# --- OptiScaler.ini (installs of earlier versions) ----------------------------------------------------------------

def key_re(key):
    # one "key = value" line; works with Windows (CRLF) and Linux line endings
    return re.compile(r'(?m)^(?P<key>%s)[ \t]*=[ \t]*(?P<val>[^\r\n]*?)[ \t]*(?=\r?$)' % re.escape(key))


def set_value(text, key, value, section=None):
    """Sets key = value. A missing key is added at the start of [section]."""
    found = list(key_re(key).finditer(text))
    if len(found) > 1:
        raise SystemExit(f'OptiScaler.ini: more than one "{key} =" line')
    if found:
        return key_re(key).sub(lambda m: f'{m.group("key")} = {value}', text, count=1)
    m = re.search(r'(?m)^\[%s\][ \t]*(\r?\n)' % re.escape(section or ''), text) if section else None
    if not m:
        raise SystemExit(f'OptiScaler.ini: no "{key} =" line' + (f' and no [{section}] section' if section else ''))
    return text[:m.end()] + f'{key} = {value}' + m.group(1) + text[m.end():]


def read_ini(p):
    with open(p, encoding='utf-8', errors='surrogateescape', newline='') as f:
        return f.read()


def write_ini(p, text):
    with open(p, 'w', encoding='utf-8', errors='surrogateescape', newline='') as f:
        f.write(text)


# --- installs of earlier versions: the OptiScaler way ----------------------------------------------------------------

def uninstall_optiscaler(t):
    folder = t / FOLDER
    marker = folder / MARKER
    if not marker.exists():
        return
    rec = read_marker(folder)
    rec.setdefault('moved', [])
    if 'previous' in rec:   # HelixSR 1.5: it only changed lines in the user's own OptiScaler.ini; put them back
        if (t / 'OptiScaler.ini').exists():
            text = read_ini(t / 'OptiScaler.ini')
            for key, value in rec['previous'].items():
                try:
                    text = set_value(text, key, value)
                except SystemExit:
                    pass
            write_ini(t / 'OptiScaler.ini', text)
    else:
        opti = rec.get('optiscaler', 'dxgi.dll')
        if ((t / opti).exists() or (t / opti).is_symlink()) and is_optiscaler(t / opti):   # (not another mod's file)
            (t / opti).unlink()
        if rec.get('ini') == 'created':
            if (t / 'OptiScaler.log').exists():
                (t / 'OptiScaler.log').unlink()
            ini = t / 'OptiScaler.ini'   # kept when the user edited it since (recorded hash; older records: removed as before)
            if ini.exists() and (not rec.get('ini_sha') or sha(ini) == rec['ini_sha']):
                ini.unlink()
            elif ini.exists():
                say(f'  your edited {ini} was left there')
        elif (folder / BACKUP / 'OptiScaler.ini').exists():
            os.replace(folder / BACKUP / 'OptiScaler.ini', t / 'OptiScaler.ini')
    for n in rec.get('created', []):
        if (t / n).exists():
            (t / n).unlink()
    for name in rec['moved']:
        src = folder / BACKUP / name
        if src.exists() or src.is_symlink():
            os.replace(src, t / name)
    # AMD's DLLs: removed when they are the copies the install put there (hash in the record, or AMD's as shipped)
    amd = {n: AMD_SHA256[n] | ({rec[k]} if rec.get(k) else set()) for n, k in ((AMD_FSR, 'amd_fsr'), (AMD_FG, 'amd_fg'))}
    for n in (OWN, OWN_SR, AMD_FSR, AMD_FG, MARKER, 'helixsr.log') + NETWORK + OLD_FILES:
        f = folder / n
        if not f.exists() or (n in OLD_FILES and not is_helixsr(f)):
            continue
        if n in amd and sha(f) not in amd[n]:
            say(f'  {f} was replaced by hand: left there')
            continue
        f.unlink()
    remove_ini(folder, rec.get('ini_made'))
    kept = remove_my_fsr(folder)
    for d in (folder / BACKUP, folder):
        try:
            d.rmdir()
        except OSError:
            pass
    say(f'  removed from {t} (everything put back as it was)')
    if kept:
        say(f'  your files in {folder / MY_FSR} were left there')


# --- the drop-in: the game's FSR 3.1 DLL ----------------------------------------------------------------------------

def put_file(src, dst):
    """dst becomes a checked copy of src in one step (a copy next to it, then renamed over it): the game always has a
    complete file there, the old one or the new one."""
    tmp = dst.with_name(dst.name + '.helixsr-new')
    try:
        copy_checked(src, tmp)
        os.replace(tmp, dst)
    finally:
        if tmp.exists():
            tmp.unlink()


def install_direct(g, here):
    hlx = hlx_source(here)
    src = hlx or here / DLL   # HLX FSR 4 from HelixSR 2.1 on, else (earlier releases) HelixSR's FidelityFX DLL
    for t in g.fsr_targets:
        orig = original(t)
        kept = True
        if is_ours(t):
            if not orig.exists():
                kept = False
                say(f'  {t}: no backup of the game\'s own file ({orig.name}); HelixSR updated. To get the game\'s file '
                    'back later: verify the game\'s files (Steam: Properties, Installed Files)')
            put_file(src, t)   # update
        else:
            if orig.exists() and orig.read_bytes() != t.read_bytes():
                # the game was updated or its files verified since HelixSR was installed: the file there now is the
                # game's own, newer than the backup
                say(f'  {t.name}: the game replaced HelixSR (a game update?); its new file becomes the backup')
            # the game's file is copied to the backup first and replaced only once HelixSR's copy is complete
            put_file(t, orig)
            put_file(src, t)
        made = read_marker(t.parent).get('ini_made')
        if hlx:
            # HLX FSR 4 carries its own network and has no helixsr.ini: an earlier drop-in's files there go
            for n in NETWORK:
                if (t.parent / n).exists():
                    (t.parent / n).unlink()
            remove_ini(t.parent, made)
            rec = {'helixsr': release_version(here), 'upscaler': 'HLX FSR 4', 'files': [t.name], 'route': 'direct',
                   'ini_made': None}
        else:
            copy_network(here, t.parent)
            rec = {'helixsr': version_of(here / DLL), 'files': [t.name], 'route': 'direct',
                   'ini_made': make_ini(t.parent, made)}
        (t.parent / MARKER).write_text(json.dumps(rec, indent=1) + '\n')
        say(f'  installed {"HLX FSR 4" if hlx else "HelixSR"} in {t}' +
            (f' (the game\'s file kept as {orig.name})' if kept else ''))


def uninstall_direct(g):
    for t in list(g.fsr_targets) + list(getattr(g, 'old_dropins', [])):
        restore_dropin(t)


def restore_dropin(t):
    """The game's own FSR DLL back in place of HelixSR's at t (the drop-in's files next to it removed)."""
    orig = original(t)
    if not orig.exists():
        if t.exists() and is_ours(t):
            t.unlink()
            say(f'  removed HelixSR from {t}; the game\'s own file was not backed up: verify the game\'s files '
                '(Steam: Properties, Installed Files) to get it back')
        else:
            return
    elif t.exists() and not is_ours(t):
        say(f'  {t} is not HelixSR (the game may have been updated); {orig.name} left in place')
        return
    else:
        os.replace(orig, t)   # over HelixSR's file in one step: the game is never without its file
        say(f'  restored the game\'s {t}')
    remove_ini(t.parent, read_marker(t.parent).get('ini_made'))
    for extra in (MARKER, 'helixsr.log') + NETWORK:
        if (t.parent / extra).exists():
            (t.parent / extra).unlink()


# --- installs of earlier versions: the DLSS loader -------------------------------------------------------------------

def uninstall_dlss(t):
    folder = t / FOLDER
    marker = folder / MARKER
    if not marker.exists():
        return
    rec = read_marker(folder)
    rec.setdefault('moved', [])
    for name, ours in [(n, is_loader) for n in LOADER_NAMES] + [(CORE, is_helixsr)]:
        if (t / name).exists() and ours(t / name):
            (t / name).unlink()
    fg = t / FG_DIR   # frame generation's files (only ours; anything else stays)
    for n in rec.get('fg_files', []):
        if (fg / n).exists():
            (fg / n).unlink()
    if fg.is_dir() and not any(fg.iterdir()):
        fg.rmdir()
    for name in rec.get('moved', []):
        src = folder / BACKUP / name
        if src.exists() or src.is_symlink():
            os.replace(src, t / name)
    remove_ini(t, rec.get('ini_made'))
    for n in (MARKER, 'helixsr.log'):
        if (folder / n).exists():
            (folder / n).unlink()
    for n in ('helixsr.log', 'helixsr_loader.log'):
        if (t / n).exists():
            (t / n).unlink()
    for d in (folder / BACKUP, folder):
        try:
            d.rmdir()
        except OSError:
            pass
    say(f'  removed from {t} (everything put back as it was)')


# --- HelixSR Scaler ---------------------------------------------------------------------------------------------------

def scaler_record(t):
    """What HelixSR Scaler's record in the game's .exe folder t says: {'name', 'version', 'by_hand', 'files'}; None when
    HelixSR Scaler is not installed there."""
    p = Path(t) / SCALER_FILES
    try:
        lines = p.read_text(errors='replace').splitlines()
    except OSError:
        return None
    rec = {'name': 'dxgi.dll', 'version': None, 'by_hand': False, 'files': []}
    for line in lines:
        line = line.strip()
        if line.startswith('# version='):
            rec['version'] = line.split('=', 1)[1].strip() or None
        elif line == '# name picked by hand':
            rec['by_hand'] = True
        elif line.startswith('name='):
            rec['name'] = line.split('=', 1)[1].strip()
        elif line and not line.startswith('#'):
            rec['files'].append(line.replace('\\', '/'))
    return rec


def ini_section_get(text, section, key):
    """key's value in [section] of an ini text (None if missing)."""
    cur = None
    for line in text.splitlines():
        s = line.strip()
        m = re.match(r'^\[([^\]]+)\]$', s)
        if m:
            cur = m.group(1).strip().lower()
        elif cur == section.lower() and not s.startswith((';', '#')):
            k, sep, v = s.partition('=')
            if sep and k.strip().lower() == key.lower():
                return v.strip()
    return None


def ini_section_set(text, section, key, value):
    """key=value (OptiScaler's style) in [section]: the first active line is changed, else the line is added at the
    start of the section, else the section is added at the end. Keeps every other line and the line endings."""
    nl = '\r\n' if '\r\n' in text else '\n'
    lines = text.split(nl)
    cur, start = None, None
    for i, line in enumerate(lines):
        s = line.strip()
        m = re.match(r'^\[([^\]]+)\]$', s)
        if m:
            cur = m.group(1).strip().lower()
            if cur == section.lower() and start is None:
                start = i
            continue
        if cur == section.lower() and not s.startswith((';', '#')):
            k, sep, _ = s.partition('=')
            if sep and k.strip().lower() == key.lower():
                lines[i] = f'{key}={value}'
                return nl.join(lines)
    if start is not None:
        lines.insert(start + 1, f'{key}={value}')
        return nl.join(lines)
    while lines and lines[-1] == '':
        lines.pop()
    return nl.join(lines + ['', f'[{section}]', f'{key}={value}', ''])


# --- installing and removing -----------------------------------------------------------------------------------------

def install(g, here):
    """The FSR drop-in into g (HelixSR's DLL from the folder here). An earlier version's install in the game is removed
    first; HelixSR Scaler is taken out by the bridge before this."""
    if not g.fsr_targets:
        raise SystemExit(f'{g.name} has no FSR 3.1 DLL: the FSR drop-in cannot be used there')
    if g.dlss_installed:
        say('  removing the DLSS loader of an earlier version first')
        uninstall_dlss(g.target)
        g.dlss_installed = False
    if g.opti_installed:
        say('  removing the OptiScaler install of an earlier version first')
        uninstall_optiscaler(g.target)
        g.opti_installed = False
    if getattr(g, 'old_dropins', None):
        say('  removing the FSR drop-in an earlier version put into an OptiScaler\'s folder first')
        for t in g.old_dropins:
            restore_dropin(t)
        g.old_dropins = []
    g.route = 'direct'
    install_direct(g, here)
    if g.target and (g.target / 'OptiScaler.ini').exists() and not (g.target / SCALER_FILES).exists():
        say('  NOTE: an OptiScaler that HelixSR did not install is next to the game\'s .exe (OptiScaler.ini); it can take '
            'over the game\'s FSR calls. For the drop-in, remove it (its dxgi.dll / winmm.dll etc. and OptiScaler.ini).')


def uninstall(g):
    """Removes the drop-in and any install of an earlier version from g (everything put back); HelixSR Scaler is the
    bridge's."""
    if g.dlss_installed:
        uninstall_dlss(g.target)
        g.dlss_installed = False
    if g.opti_installed:
        uninstall_optiscaler(g.target)
        g.opti_installed = False
    uninstall_direct(g)
