#!/usr/bin/env python3
# Copyright 2026 lonewolf0622. All rights reserved (HelixSR Freeware License).
"""HelixSR's games step: helixsr-setup runs it after the build, helixsr-uninstall with `remove`.

    helixsr_install.py RELEASE_DIR [--folder GAME_FOLDER]... [--yes]
    helixsr_install.py RELEASE_DIR remove [--folder GAME_FOLDER]...

Lists your games, numbered: type a game's number (or drag a game's folder into the window) and say what to do with it;
Enter on its own when done. For the game picked, Enter installs it (updates a game that has HelixSR):
    s  HelixSR Scaler next to the game's .exe (pick DLSS in the game; frame generation goes in with it and follows the
       game's DLSS Frame Generation setting)
    f  the FSR drop-in: HelixSR in place of the game's FSR 3.1 DLL (pick AMD FSR in the game)
    r  remove HelixSR from the game (everything put back)
    n  leave the game as it is
It installs through helixsr_bridge.py and helixsr_games.py, the same files as the HelixSR app, so the app and this
setup put the same files into a game, keep the game's own files the same way, and each can update or remove what the
other installed. HelixSR Scaler comes from the helixsr-scaler folder next to setup/.

remove: asks per game, then whether to delete what the setup built here and its downloads (exit code 3: the script
deletes the downloads folder). Uses only Python's standard library."""
import importlib.util
import os
import shutil
import struct
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
SCALER_DIR = 'helixsr-scaler'
WAY = {'scaler': 'HelixSR Scaler', 'fsr': 'FSR drop-in', 'dlss': 'DLSS loader of an earlier version',
       'optiscaler': 'OptiScaler of an earlier version'}
KEY = {'scaler': 's', 'fsr': 'f'}
PICK = {'scaler': 'DLSS', 'fsr': 'AMD FSR'}
# the bridge's lines that speak of the app's buttons: said here in this setup's words, or left out
APP_ONLY = ('frame generation installed', 'frame generation is not set up')
ASSUME_YES = False


def say(m=''):
    print(f'[helixsr-setup] {m}' if m else '', flush=True)


def load_bridge():
    spec = importlib.util.spec_from_file_location('helixsr_bridge', HERE / 'helixsr_bridge.py')
    b = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(b)
    b.INSTALLED_BY = "HelixSR's setup"
    return b


TOLD = set()   # notes said once already (a Steam library that is not reachable is noted at every scan)


def flush(b):
    """The bridge's messages since the last call, indented under the game's name."""
    for m in b._messages:
        if m.lower().startswith(APP_ONLY):
            continue
        if m.startswith('note:'):
            if m in TOLD:
                continue
            TOLD.add(m)
        m = m.replace(' (Choose the method yourself)', ' (the HelixSR app can pick another file name)')
        m = m.replace(': Go back puts it back', ' (the HelixSR app can go back to it)')
        say('  ' + m)
    b._messages.clear()


def answer(q, keys, default):
    """keys: the answers allowed; Enter = default. None when there is no answer (input closed)."""
    if ASSUME_YES:
        print(q + default, flush=True)
        return default
    while True:
        try:
            r = input(q).strip().lower()[:1]
        except EOFError:
            print()
            return None
        if not r:
            return default
        if r in keys:
            return r
        say(f'  type one of: {", ".join(keys)} (or just Enter)')


def yes_no(q, default_yes):
    r = answer(q + (' [Y/n] ' if default_yes else ' [y/N] '), ('y', 'n'), 'y' if default_yes else 'n')
    return r == 'y'


def label(j):
    """The game's line: what it has and what the setup would do."""
    bits = [', '.join(j['inputs'])] if j['inputs'] else []
    return j['name'] + (f' ({"; ".join(bits)})' if bits else '')


def ask_game(b, j, plan, named=False):
    """One question per game. plan gets (j, 'scaler'|'fsr'|'remove'). False: no answer, stop. A game
    without HelixSR: Enter leaves it as it is, unless the user named it (named: Enter installs its recommended way)."""
    ways, now = j['ways'], j['installed']
    if now:
        default = now if now in ways else j['recommended']
        keys = [KEY[w] for w in ('scaler', 'fsr') if w in ways] + ['r', 'n']
        ver = f' {j["version"]}' if j.get('version') else ''
        q = f'{label(j)}: installed ({WAY.get(now, now)}{ver}). Update? [Enter/{"/".join(keys)}] '
        r = answer(q, keys, KEY.get(default, 'n'))
    else:
        rec = j['recommended']
        order = ([rec] if rec else []) + [w for w in ('scaler', 'fsr') if w in ways and w != rec]
        keys = [KEY[w] for w in order] + ['n']
        # Enter: leave it (installing is a yes per game); a game the user named: its recommended way
        default = KEY[rec] if named and rec else 'n'
        r = answer(f'{label(j)}: install? [{"/".join(keys)}, Enter = {default}] ', keys, default)
    if r is None:
        return False
    if r == 'n':
        say('  -> left as it is')
        return True
    if r == 'r':
        plan.append((j, 'remove'))
        say('  -> remove (after the last question)')
        return True
    way = 'scaler' if r == 's' else 'fsr'
    plan.append((j, way))
    say(f'  -> {WAY[way]} (installed after the last question)')
    return True


def colours():
    """(bold, dim, teal, violet, amber, reset) for a terminal that shows colours, else empty strings"""
    if not sys.stdout.isatty() or os.environ.get('NO_COLOR'):
        return ('',) * 6
    if os.name == 'nt':   # Windows 10 and newer: colours once the console is told to read them
        try:
            import ctypes
            k = ctypes.windll.kernel32
            h, mode = k.GetStdHandle(-11), ctypes.c_uint32()
            if not k.GetConsoleMode(h, ctypes.byref(mode)) or not k.SetConsoleMode(h, mode.value | 4):
                return ('',) * 6
        except (OSError, AttributeError):
            return ('',) * 6
    return ('\x1b[1m', '\x1b[2m', '\x1b[38;2;45;212;191m', '\x1b[38;2;167;139;250m', '\x1b[38;2;245;184;75m', '\x1b[0m')


SHORT = {'scaler': 'HelixSR Scaler', 'fsr': 'FSR drop-in', 'remove': 'remove', 'dlss': 'DLSS loader',
         'optiscaler': 'OptiScaler'}


def game_list(games, plan):
    """The games, numbered, with what each has (DLSS, FSR 3.1, XeSS), what is installed and what will happen"""
    B, D, T, V, A, N = colours()
    planned = {id(j): way for j, way in plan}
    print()
    print(f'  {B}Your games{N}')
    print()
    for i, j in enumerate(games, 1):
        mark = ''
        if j['installed']:
            ver = f' {j["version"]}' if j.get('version') else ''
            mark = f'{T}● {SHORT.get(j["installed"], j["installed"])}{ver}{N}'
        if id(j) in planned:
            way = planned[id(j)]
            todo = 'update' if way == j['installed'] else SHORT[way]
            mark += (' ' if mark else '') + f'{A}→ {todo}{N}'
        name = j['name'] if len(j['name']) <= 34 else j['name'][:33] + '…'
        print(f'   {B}{i:2}{N}  {name:<34} {V}{" ".join(j["inputs"]):<18}{N}{mark}')
    print()
    print(f'  {D}Or drag a game\'s folder into this window (games the list doesn\'t have).{N}')
    print()


def pick_games(b, hi, games, seen, plan, pkg):
    """The list, then one game at a time: its number (or its folder dragged in) and what to do with it, until Enter on
    its own (or the input ends). plan gets (j, way) per game, the last answer for a game counting."""
    while True:
        game_list(games, plan)
        try:
            r = input('  Game (its number; Enter when done): ').strip().strip('"').strip("'").strip()
        except EOFError:
            print()
            return
        if not r:
            return
        if r.isdigit():
            if not 1 <= int(r) <= len(games):
                say(f'  type a number from 1 to {len(games)}, or drag a game\'s folder in')
                continue
            picked = [games[int(r) - 1]]
        else:
            picked = []
            for g in hi.games_from([r], seen):
                seen.append(g)
                j = b.game_json(hi, b.without_scaler_files(hi, g))
                if pkg is None:
                    j['ways'] = [w for w in j['ways'] if w != 'scaler']
                    j['recommended'] = 'fsr' if 'fsr' in j['ways'] else None
                games.append(j)
                picked.append(j)
            flush(b)
            if not picked:
                continue
        for j in picked:
            plan[:] = [(k, w) for k, w in plan if k is not j]
            if not ask_game(b, j, plan, named=True):   # picked: Enter installs it (updates it when installed)
                return


def scaler_package(b, release):
    """(folder, version) of the HelixSR Scaler that comes with this release; (None, None) when it is missing."""
    pkg = release / SCALER_DIR
    if not (pkg / 'OptiScaler.dll').is_file():
        return None, None
    v = b.scaler_pkg_version(pkg)
    return pkg, '.'.join(map(str, v)) if v else None


def install(release, folders):
    b = load_bridge()
    hi = b.load_installer(release)
    if not b.network_ready(hi, release):
        raise SystemExit('the network is not built yet: run helixsr-setup first')
    version = hi.version_of(b.release_dll(release))
    pkg, sv = scaler_package(b, release)
    fg_ready = b.fg_dir(release) is not None
    has_fg = (HERE / 'fg' / 'fg_setup.py').is_file()   # (a release without HelixSR frame generation: no setup/fg)
    say(f'HelixSR {version}' + (f', HelixSR Scaler {sv}' if sv else ''))
    if pkg is None:
        say(f'note: the {SCALER_DIR} folder is missing (extract the whole ZIP): only the FSR drop-in can be installed')
    say('looking for your games ...')
    seen = b.all_games(hi, folders)
    games = [b.game_json(hi, g) for g in seen]
    flush(b)
    if pkg is None:
        for j in games:
            j['ways'] = [w for w in j['ways'] if w != 'scaler']
            if j['recommended'] == 'scaler':
                j['recommended'] = None
    print()
    if games:
        say('Close your games first. Pick a game by its number, then:')
        say('  s = HelixSR Scaler (pick DLSS in the game' + (', frame generation included)' if has_fg else ')'))
        say('  f = FSR drop-in (games with FSR 3.1; pick AMD FSR in the game)')
        say('  r = remove   n = leave it')
        say('  Enter: install (update a game that has HelixSR)')
    else:
        say('no games found in your Steam, Epic, GOG, Xbox, Heroic or Lutris folders')
    plan = []
    named = [Path(hi.clean_path(f)).expanduser() for f in folders]   # games the user named (helixsr-setup GAME_FOLDER)
    if ASSUME_YES:
        # unattended: the games named install (or update) their recommended way, the rest stay as they are
        for j in games:
            ask_game(b, j, plan, any(hi.overlaps(Path(j['folder']), n) for n in named))
    else:
        games.sort(key=lambda j: j['name'].lower())
        # games named on the command line come first, as if picked
        for j in games:
            if any(hi.overlaps(Path(j['folder']), n) for n in named):
                if not ask_game(b, j, plan, named=True):
                    say('no answer: nothing was changed')
                    return
        pick_games(b, hi, games, seen, plan, pkg)
    if not plan:
        say('nothing to do')
        return
    # frame generation's files go in with HelixSR Scaler, wired to the game's DLSS Frame Generation: the game's own
    # setting switches it on and off
    if has_fg and not fg_ready and any(w == 'scaler' for _, w in plan):
        say('frame generation is not built (run the setup again to retry): HelixSR Scaler goes in for upscaling')
    print()
    done = []
    for j, way in plan:
        say(j['name'])
        try:
            if way == 'remove':
                b.cmd_remove(hi, release, {'game': j['folder']})
            else:
                a = {'game': j['folder'], 'way': way}
                if way == 'scaler':
                    a['scaler'] = str(pkg)
                    if sv:
                        a['scaler-version'] = sv
                r = b.cmd_install(hi, release, a)
                done.append(r['game'])
        except (b.BridgeError, SystemExit, OSError) as e:
            flush(b)
            say(f'  error: {e}' + ('' if isinstance(e, b.BridgeError) else ' (close the game and run the setup again)'))
            continue
        flush(b)
    done_message(done, has_fg)


def done_message(done, has_fg=True):
    print()
    if not done:
        say('Done.')
        return
    say('Done. Start the game and pick this as its upscaler in its graphics settings:')
    for g in done:
        line = f'  {g["name"]}: {PICK.get(g["installed"], "AMD FSR")}'
        if g.get('launch_options'):
            line += f'  (first paste this into the game\'s Steam launch options: {g["launch_options"]})'
        say(line)
    scaler = [g for g in done if g['installed'] == 'scaler']
    if scaler and has_fg:
        on = [g for g in scaler if g.get('frame_generation') == 'on']
        # HelixSR's frame generation runs through the game's DLSS Frame Generation (DirectX 12 games that have it)
        none = [g for g in scaler if g not in on and g.get('fg_possible') is False]
        off = [g for g in scaler if g not in on and g not in none and g.get('fg_installed')]
        if on:
            say('Frame generation follows the game: turn DLSS Frame Generation on or off in its settings:')
            for g in on:
                say(f'  {g["name"]}')
        if off:
            say('Frame generation picked in HelixSR Scaler\'s menu (Insert) stays in ' + ', '.join(g['name'] for g in off) + '.')
        if none:
            say('HelixSR frame generation is not available in ' + ', '.join(g['name'] for g in none) + ' (no DLSS')
            say('Frame Generation in the game): AMD FSR or XeSS frame generation can be picked in HelixSR Scaler\'s')
            say('menu (Insert) instead.')
    if scaler:
        say('Insert opens HelixSR Scaler\'s menu in the game (upscaler, sharpening, frame generation).')
    say('helixsr.log (in the game\'s HelixSR-fsrfg folder, or next to the game\'s FSR DLL) shows what HelixSR does.')
    say('A game that was not listed: run the setup with its folder (helixsr-setup.sh GAME_FOLDER, or drop the folder')
    say('onto helixsr-setup.bat).')


# --- remove ---------------------------------------------------------------------------------------------------------

SHIPPED_FG = {'nvexec64.dll'}   # the only file of HelixSR-fsrfg/helixsr-fg that comes in the ZIP
BUILT = ('fsr3-drop-in', 'helixsr_setup.json', 'helixsr_fg_setup.json', 'helixsr_ngx_core.txt')


def strip_network(dll):
    """Cuts the network the setup appended off HelixSR's DLL (back to the DLL as it came in the ZIP)."""
    with open(dll, 'r+b') as f:
        size = f.seek(0, os.SEEK_END)
        if size < 32:
            return False
        f.seek(size - 32)
        tail = f.read(32)
        if tail[:8] != b'HXSRNET1':
            return False
        nw, np_, _ = struct.unpack('<QQQ', tail[8:])
        if 32 + nw + np_ > size:
            return False
        f.truncate(size - 32 - nw - np_)
        return True


def strip_hlx(dll):
    """Cuts HLX FSR 4's data the setup appended (built from AMD's file) off its DLL: back to the DLL as in the ZIP."""
    try:
        f = open(dll, 'r+b')
    except OSError:
        return False
    with f:
        size = f.seek(0, os.SEEK_END)
        if size < 24:
            return False
        f.seek(size - 24)
        tail = f.read(24)
        if tail[:8] != b'HLXFSR4D':
            return False
        n = struct.unpack('<Q', tail[8:16])[0]
        if 24 + n > size:
            return False
        f.truncate(size - 24 - n)
        return True


def delete_built(release):
    fsr = release / 'HelixSR-fsrfg'
    if (fsr / 'amd_fidelityfx_dx12.dll').is_file():   # (HelixSR 2.0's layout)
        strip_network(fsr / 'amd_fidelityfx_dx12.dll')
    if (release / 'HelixSR' / 'helixsr.dll').is_file():   # HelixSR 3.0 on
        strip_network(release / 'HelixSR' / 'helixsr.dll')
    for d in (release / 'HLX-FSR4' / 'amd_fidelityfx_upscaler_dx12.dll',
              release / SCALER_DIR / 'OptiScaler' / 'amd_fidelityfx_upscaler_dx12.dll'):
        strip_hlx(d)
    fg = fsr / 'helixsr-fg'
    if fg.is_dir():
        for p in sorted(fg.iterdir()):
            if p.name.lower() in SHIPPED_FG:
                continue
            shutil.rmtree(p) if p.is_dir() else p.unlink()
    for n in ('helixsr.log',):
        if (fsr / n).is_file():
            (fsr / n).unlink()
    for n in BUILT:
        p = release / n
        if p.is_dir():
            shutil.rmtree(p)
        elif p.exists():
            p.unlink()


def remove(release, folders, data):
    b = load_bridge()
    hi = b.load_installer(release)
    say('looking for games with HelixSR ...')
    games = [b.game_json(hi, g) for g in b.all_games(hi, folders)]
    flush(b)
    inst = [j for j in games if j['installed']]
    if not inst:
        say('HelixSR is not in any game the uninstaller finds (another game: pass its folder, or drop it onto '
            'helixsr-uninstall.bat)')
    else:
        print()
        say('Close your games first. For each game: Enter = remove, n = keep.')
        todo = []
        for j in inst:
            r = answer(f'{j["name"]}: remove HelixSR ({WAY.get(j["installed"], j["installed"])})? [Y/n] ', ('y', 'n'), 'y')
            if r is None:
                say('no answer: nothing was changed')
                return 0
            if r == 'y':
                todo.append(j)
        for j in todo:
            say(j['name'])
            try:
                b.cmd_remove(hi, release, {'game': j['folder']})
            except (b.BridgeError, SystemExit, OSError) as e:
                flush(b)
                say(f'  error: {e} (close the game and try again)')
                continue
            flush(b)
    print()
    built = b.network_ready(hi, release) or (release / 'HelixSR-fsrfg' / 'helixsr-fg' / '_nvngx.dll').exists()
    built = built or any((release / d).is_file() and (release / d).read_bytes()[-24:-16] == b'HLXFSR4D'
                         for d in ('HLX-FSR4/amd_fidelityfx_upscaler_dx12.dll',))
    q = 'Also delete what the setup built here (the network in HelixSR\'s DLL, HLX FSR 4\'s shaders, frame generation\'s ' \
        'files) and the ' \
        f'setup\'s downloads ({data})?' if built else f'Also delete the setup\'s downloads ({data})?'
    if not ASSUME_YES and yes_no(q, False):
        delete_built(release)
        say('deleted: what the setup built (run helixsr-setup again to build it)')
        return 3
    say('done')
    return 0


def main(argv):
    global ASSUME_YES
    if not argv:
        raise SystemExit(__doc__)
    release = Path(argv[0]).expanduser().resolve()
    rest = argv[1:]
    cmd = rest.pop(0) if rest and rest[0] == 'remove' else 'install'
    folders, data, i = [], None, 0
    while i < len(rest):
        k = rest[i]
        if k == '--folder' and i + 1 < len(rest):
            folders.append(rest[i + 1])
            i += 2
        elif k == '--data' and i + 1 < len(rest):
            data = rest[i + 1]
            i += 2
        elif k in ('--yes', '-y'):
            ASSUME_YES = True
            i += 1
        else:
            raise SystemExit(f'unknown argument: {k}\n\n{__doc__}')
    if cmd == 'remove':
        if data is None:
            data = os.path.join(os.environ.get('LOCALAPPDATA', ''), 'HelixSR') if os.name == 'nt' else \
                os.path.join(os.environ.get('XDG_DATA_HOME') or os.path.expanduser('~/.local/share'), 'HelixSR')
        return remove(release, folders, data)
    install(release, folders)
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
