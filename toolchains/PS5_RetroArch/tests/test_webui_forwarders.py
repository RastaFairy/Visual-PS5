"""The Game Forwarder page's routes (src/ps5_forwarders.cpp) against a stand-in for
ShadowMountPlus's HTTP API (its docs/api.md, 1.7): a tile is made, listed, edited, given an
icon and removed, and what waits for the title to close (a removal ShadowMountPlus refuses
while a game runs, a new name or icon) is finished the way the WebUI's daemon finishes it."""
import http.client
import http.server
import json
import os
from pathlib import Path
import shutil
import struct
import subprocess
import sys
import tempfile
import threading
import unittest
import zlib

sys.path.insert(0, str(Path(__file__).resolve().parent))
import webui_build  # noqa: E402
from test_webui_transfer_browser import PLAYWRIGHT  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
FINISH_MAIN = r'''
#include "ps5_forwarders.h"
#include <cstdio>
#include <cstdlib>
int main(int argc, char **argv)
{
    if (argc != 4)
        return 2;
    ps5_forwarders::Paths paths;
    paths.homebrew = argv[1];
    paths.title = argv[2];
    paths.shadowmount_port = static_cast<unsigned short>(std::atoi(argv[3]));
    if (ps5_forwarders::finish_pending(paths, [](const char *line) { std::puts(line); }))
        std::puts("nothing waits");
}
'''


def png(width, height, colour=b'\x40\x80\xc0'):
    def chunk(kind, data):
        return struct.pack('>I', len(data)) + kind + data + struct.pack('>I', zlib.crc32(kind + data))
    rows = b''.join(b'\0' + colour * width for _ in range(height))
    return (b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', width, height, 8, 2, 0, 0, 0)) +
            chunk(b'IDAT', zlib.compress(rows)) + chunk(b'IEND', b''))


class ShadowMount(http.server.BaseHTTPRequestHandler):
    """POST routes of ShadowMountPlus's API, with the console's answers."""
    def do_POST(self):
        state = self.server.state
        body = json.loads(self.rfile.read(int(self.headers['Content-Length'])) or b'{}')
        state['calls'].append((self.path, body))
        if state['down']:
            return  # the connection closes with no answer
        code, answer = 200, {'status': 0}
        if self.path == '/api/v1/version':
            answer.update(api_version=1, shadowmount_version='1.7')
        elif self.path == '/api/v1/games':
            answer['games'] = [{'title_id': t, 'installed': i, 'path': f'/mnt/usb0/{t}'}
                               for t, i in state['games'].items()]
            answer['count'] = len(answer['games'])
        elif self.path == '/api/v1/manual/add':
            answer['changed'] = body['path'] not in state['manual']
            state['manual'].add(body['path'])
        elif self.path == '/api/v1/manual/remove':
            answer['changed'] = body['path'] in state['manual']
            state['manual'].discard(body['path'])
        elif self.path == '/api/v1/games/uninstall' and state['busy']:
            code, answer = 409, {'status': 16, 'error': 'A game is active', 'error_reason': 'game_active'}
        elif self.path == '/api/v1/games/uninstall':
            state['games'][body['title_id']] = False
            answer.update(title_id=body['title_id'], uninstall_requested=True, scan_queued=False)
        elif self.path == '/api/v1/scan':
            state['scans'] += 1  # installs every listed source again
            for path in state['manual']:
                state['games'][Path(path).name] = True
            answer.update(queued=True)
        else:
            code, answer = 404, {'status': 2, 'error': 'no such route'}
        data = json.dumps(answer).encode()
        self.send_response(code)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def log_message(self, *args):
        pass


class Forwarders(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp = tempfile.TemporaryDirectory()
        cls.homebrew = Path(cls.temp.name)
        cls.root = cls.homebrew / 'PPSA99169'
        shutil.copytree(ROOT / 'webui', cls.root / 'webui')
        for name, data in {'content/snes/Game (World).zip': b'game', 'cores/snes9x_libretro.so': b'core',
                           'info/snes9x_libretro.info': b'# info\ncorename = "Snes9x"\n'
                           b'database = "Nintendo - Super Nintendo Entertainment System"\n'
                           b'supported_extensions = "smc|sfc|zip"\n',
                           'forwarder/eboot.bin': b'tile app', 'forwarder/launch.elf': b'launch payload',
                           'sce_module/libc.prx': b'libc', 'sce_sys/icon0.png': png(512, 512)}.items():
            (cls.root / name).parent.mkdir(parents=True, exist_ok=True)
            (cls.root / name).write_bytes(data)
        (cls.homebrew / 'PPSA99170').mkdir()  # a folder of the range that is no tile
        cls.smp = http.server.ThreadingHTTPServer(('127.0.0.1', 0), ShadowMount)
        cls.smp.state = {'calls': [], 'down': False, 'busy': True, 'scans': 0, 'manual': set(),
                         'games': {'PPSA99171': True}}  # an installed title of the range elsewhere
        threading.Thread(target=cls.smp.serve_forever, daemon=True).start()
        cls.binary = cls.homebrew / 'server'
        webui_build.build(cls.binary, 'tests/webui_server_main.cpp')
        cls.finish = cls.homebrew / 'finish'
        (cls.homebrew / 'finish.cpp').write_text(FINISH_MAIN)
        subprocess.run(['c++', '-std=c++17', '-O1', '-Wall', '-Werror', '-Isrc', str(cls.homebrew / 'finish.cpp'),
                        'src/ps5_forwarders.cpp', '-o', str(cls.finish)], cwd=ROOT, check=True)
        cls.process, cls.port, cls.token = webui_build.start(
            cls.binary, cls.root, {**os.environ, 'PS5_FORWARDERS_SHADOWMOUNT_PORT': str(cls.smp.server_port)})

    @classmethod
    def tearDownClass(cls):
        cls.process.terminate()
        cls.process.wait(timeout=5)
        cls.smp.shutdown()
        cls.smp.server_close()
        cls.temp.cleanup()

    @classmethod
    def request(cls, method, path, body=None):
        conn = http.client.HTTPConnection('127.0.0.1', cls.port, timeout=10)
        if isinstance(body, dict):
            body = json.dumps(body)
        conn.request(method, path, body, {'X-RetroArch-Token': getattr(cls, 'token', '')})
        response = conn.getresponse()
        result = response.status, response.read()
        conn.close()
        return result

    def tiles(self):
        status, body = self.request('GET', '/api/forwarders')
        self.assertEqual(status, 200)
        return json.loads(body)

    def run_finish(self):
        return subprocess.run([str(self.finish), str(self.homebrew), str(self.root), str(self.smp.server_port)],
                              check=True, capture_output=True, text=True, timeout=60).stdout

    def create(self, tile):
        status, body = self.request('POST', '/api/forwarders', tile)
        self.assertEqual(status, 201, body)
        return json.loads(body)['id']

    def test_a_tile_from_creation_to_removal(self):
        state = self.smp.state
        listing = self.tiles()
        self.assertTrue(listing['shadowmount']['answers'])
        self.assertEqual(listing['shadowmount']['version'], '1.7')
        self.assertEqual((listing['first'], listing['last']), ('PPSA99170', 'PPSA99269'))
        self.assertEqual(listing['cores'], [{'id': 'snes9x', 'name': 'Snes9x'}])
        self.assertNotIn('PPSA99170', [t['id'] for t in listing['tiles']])  # no forward.txt: no tile

        # what a tile may hold
        for tile, words in [({'name': ' ', 'rom': 'snes/Game (World).zip'}, 'name'),
                            ({'name': 'One\nTwo', 'rom': 'snes/Game (World).zip'}, 'name'),
                            ({'name': 'Tile', 'rom': '../PPSA99169/eboot.bin'}, 'your library'),
                            ({'name': 'Tile', 'rom': '/data/x.zip'}, 'your library'),
                            ({'name': 'Tile', 'rom': '/mnt/usb0/../data/x.zip'}, 'your library'),
                            ({'name': 'Tile', 'rom': 'snes/Missing.zip'}, 'your library'),
                            ({'name': 'Tile', 'rom': 'snes/Game (World).zip\n--core'}, 'your library'),
                            ({'name': 'Tile', 'rom': 'snes/Game (World).zip', 'core': '../x'}, 'core'),
                            ({'name': 'Tile', 'rom': 'snes/Game (World).zip', 'core': 'mgba'}, 'core')]:
            status, body = self.request('POST', '/api/forwarders', tile)
            self.assertEqual(status, 400, tile)
            self.assertIn(words, json.loads(body)['error'])
        self.assertEqual(self.request('POST', '/api/forwarders', b'not json')[0], 400)

        # made: the first free id (a folder has PPSA99170, ShadowMountPlus knows PPSA99171)
        tile_id = self.create({'name': 'My "game"', 'rom': 'snes/Game (World).zip', 'core': 'snes9x'})
        self.assertEqual(tile_id, 'PPSA99172')
        folder = self.homebrew / tile_id
        for name, source in [('eboot.bin', 'forwarder/eboot.bin'), ('launch.elf', 'forwarder/launch.elf'),
                             ('sce_module/libc.prx', 'sce_module/libc.prx'), ('sce_sys/icon0.png', 'sce_sys/icon0.png')]:
            self.assertEqual((folder / name).read_bytes(), (self.root / source).read_bytes(), name)
        self.assertEqual((folder / 'forward.txt').read_text(),
                         '--rom\nsnes/Game (World).zip\n--core\nsnes9x\n--exit-after-game\n')
        param = json.loads((folder / 'sce_sys/param.json').read_text())
        self.assertEqual((param['titleId'], param['conceptId'], param['contentId']),
                         ('PPSA99172', '99172', 'UP9000-PPSA99172_00-FORWARDER0099172'))
        self.assertEqual(param['localizedParameters']['en-US']['titleName'], 'My "game"')
        self.assertIn(str(folder), state['manual'])
        tile = next(t for t in self.tiles()['tiles'] if t['id'] == tile_id)
        self.assertEqual(tile, {'id': tile_id, 'name': 'My "game"', 'rom': 'snes/Game (World).zip',
                                'core': 'snes9x', 'exit_after_game': True, 'state': 'waiting'})

        # edited before ShadowMountPlus installs it: the arguments now, nothing to re-register
        status, _ = self.request('POST', f'/api/forwarders/edit?id={tile_id}',
                                 {'name': 'Renamed', 'rom': 'snes/Game (World).zip', 'core': '',
                                  'exit_after_game': False})
        self.assertEqual(status, 200)
        self.assertEqual((folder / 'forward.txt').read_text(), '--rom\nsnes/Game (World).zip\n')
        self.assertEqual(json.loads((folder / 'sce_sys/param.json').read_text())
                         ['localizedParameters']['en-US']['titleName'], 'Renamed')
        self.assertFalse((folder / 'refresh.pending').exists())

        # installed (RetroArch closed): a new icon waits for the title to close again
        state['games'][tile_id] = True
        self.assertEqual(next(t for t in self.tiles()['tiles'] if t['id'] == tile_id)['state'], 'installed')
        for bad in (png(256, 256), b'GIF89a' + bytes(64), b''):
            status, body = self.request('PUT', f'/api/forwarders/icon?id={tile_id}', bad)
            self.assertEqual(status, 400)
            self.assertIn('512 x 512', json.loads(body)['error'])
        icon = png(512, 512, b'\xff\x20\x20')
        self.assertEqual(self.request('PUT', f'/api/forwarders/icon?id={tile_id}', icon)[0], 200)
        self.assertEqual(self.request('GET', f'/api/forwarders/icon?id={tile_id}'), (200, icon))
        self.assertEqual(self.request('GET', '/api/forwarders/icon?id=PPSA99170')[0], 404)
        self.assertEqual(self.request('PUT', '/api/forwarders/icon?id=PPSA99169', png(512, 512))[0], 400)
        self.assertEqual(next(t for t in self.tiles()['tiles'] if t['id'] == tile_id)['state'], 'updating')

        # removed while RetroArch runs: out of the list now, uninstalled once the title closes
        status, body = self.request('POST', f'/api/forwarders/delete?id={tile_id}')
        self.assertEqual((status, json.loads(body)), (200, {'state': 'pending'}))
        self.assertNotIn(str(folder), state['manual'])
        self.assertTrue((folder / 'remove.pending').exists())
        self.assertEqual(next(t for t in self.tiles()['tiles'] if t['id'] == tile_id)['state'], 'removing')
        output = self.run_finish()
        self.assertIn(f'forwarder {tile_id}: not removed yet: A game is active (game_active)', output)
        self.assertNotIn('nothing waits', output)
        self.assertTrue(folder.exists())
        state['busy'] = False
        output = self.run_finish()
        self.assertIn(f'forwarder {tile_id}: removed', output)
        self.assertIn('nothing waits', output)
        self.assertFalse(folder.exists())
        self.assertFalse(state['games'][tile_id])
        self.assertNotIn(tile_id, [t['id'] for t in self.tiles()['tiles']])
        # never a folder that is no tile, nor the title
        for other in ('PPSA99170', 'PPSA99169', '../PPSA99169'):
            self.assertEqual(self.request('POST', f'/api/forwarders/delete?id={other}')[0], 400)
        self.assertTrue((self.homebrew / 'PPSA99170').is_dir() and self.root.is_dir())

    @unittest.skipUnless(PLAYWRIGHT and shutil.which('node') and Path('/usr/bin/chromium').exists(),
                         'needs node, Playwright and Chromium')
    def test_page_in_chromium(self):
        system = json.loads(self.request('GET', '/api/library')[1])['systems'][0]
        for folder, picture in (('covers', png(300, 420, b'\xe0\x20\x20')), ('marquees', png(400, 100, b'\x20\xd0\x40'))):
            path = self.root / 'library' / system['id'] / folder / (system['games'][0]['key'] + '.png')
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(picture)
        run = subprocess.run(['node', 'tests/webui_forwarders_browser.cjs'], cwd=ROOT, capture_output=True, text=True,
                             timeout=300, env={**os.environ, 'PLAYWRIGHT_PATH': PLAYWRIGHT,
                                               'WEBUI_TEST_URL': f'http://127.0.0.1:{self.port}'})
        self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
        self.assertIn('PASS:', run.stdout)

    def test_waiting_tile_goes_at_once_and_new_names_install_again(self):
        state = self.smp.state
        state['busy'] = False
        waiting = self.create({'name': 'Waiting', 'rom': 'snes/Game (World).zip'})
        status, body = self.request('POST', f'/api/forwarders/delete?id={waiting}')
        self.assertEqual((status, json.loads(body)), (200, {'state': 'removed'}))
        self.assertFalse((self.homebrew / waiting).exists())
        self.assertNotIn(str(self.homebrew / waiting), state['manual'])

        tile_id = self.create({'name': 'Before', 'rom': 'snes/Game (World).zip', 'core': 'snes9x'})
        folder = self.homebrew / tile_id
        state['games'][tile_id] = True
        state['manual'].discard(str(folder))  # 1.7-beta5fix1 dropped the source as it installed
        self.assertEqual(self.request('POST', f'/api/forwarders/edit?id={tile_id}',
                                      {'name': 'After', 'rom': 'snes/Game (World).zip', 'core': 'snes9x'})[0], 200)
        self.assertTrue((folder / 'refresh.pending').exists())
        (folder / 'launch.elf').write_bytes(b'an older payload')
        scans = state['scans']
        output = self.run_finish()
        self.assertIn(f'forwarder {tile_id}: launch.elf brought up to this build', output)
        self.assertIn(f'forwarder {tile_id}: installed again with its new name or icon', output)
        self.assertIn('nothing waits', output)
        self.assertEqual((folder / 'launch.elf').read_bytes(), b'launch payload')
        self.assertFalse((folder / 'refresh.pending').exists())
        self.assertEqual(state['scans'], scans + 1)
        self.assertTrue(state['games'][tile_id])
        uninstalls = [body for path, body in state['calls'] if path == '/api/v1/games/uninstall']
        self.assertIn({'title_id': tile_id}, uninstalls)
        self.assertEqual(self.request('POST', f'/api/forwarders/delete?id={tile_id}')[0], 200)
        self.assertFalse(folder.exists())

    def test_without_shadowmount(self):
        state = self.smp.state
        state['down'] = True
        try:
            listing = self.tiles()
            self.assertFalse(listing['shadowmount']['answers'])
            self.assertIn('ShadowMountPlus', listing['shadowmount']['error'])
            before = sorted(p.name for p in self.homebrew.iterdir())
            status, body = self.request('POST', '/api/forwarders', {'name': 'Tile', 'rom': 'snes/Game (World).zip'})
            self.assertEqual(status, 400)
            self.assertIn('ShadowMountPlus does not answer', json.loads(body)['error'])
            self.assertEqual(sorted(p.name for p in self.homebrew.iterdir()), before)
        finally:
            state['down'] = False


if __name__ == '__main__':
    unittest.main()
