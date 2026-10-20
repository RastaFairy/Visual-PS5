"""Real HTTP requests against the native WebUI handlers and streaming parser."""
import http.client
import json
from pathlib import Path
import socket
import subprocess
import tempfile
import time
import unittest

import sys
sys.path.insert(0, str(__import__("pathlib").Path(__file__).resolve().parent))
import webui_build  # noqa: E402
from urllib.parse import quote

ROOT = Path(__file__).resolve().parent.parent


class WebUI(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        archive = subprocess.check_output(['bash', 'tools/build-webui-http.sh', 'host'], cwd=ROOT, text=True).strip()
        update = subprocess.check_output(['bash', 'tools/build-webui-update.sh', 'host'], cwd=ROOT, text=True).strip()
        cls.temp = tempfile.TemporaryDirectory()
        cls.root = Path(cls.temp.name)
        for name in ('config', 'content', 'webui'):
            (cls.root / name).mkdir()
        (cls.root / 'webui/index.html').write_text('<!doctype html><title>RetroArch</title>')
        cls.original = b'audio_volume = "-6"\ninput_rumble_gain = "75"\nunrelated = "preserve"\n'
        (cls.root / 'config/retroarch.cfg').write_bytes(cls.original)
        cls.binary = cls.root / 'server'
        webui_build.build(cls.binary, 'tests/webui_server_main.cpp')
        cls.process, cls.port, cls.token = webui_build.start(cls.binary, cls.root)

    @classmethod
    def tearDownClass(cls):
        cls.process.terminate(); cls.process.wait(timeout=5)
        cls.temp.cleanup()

    @classmethod
    def request(cls, method, path, body=None, headers=None):
        conn = http.client.HTTPConnection('127.0.0.1', cls.port, timeout=5)
        fields = {'X-RetroArch-Token': getattr(cls, 'token', '')}
        fields.update(headers or {})
        conn.request(method, path, body, fields)
        response = conn.getresponse()
        result = response.status, dict(response.getheaders()), response.read()
        conn.close()
        return result

    def test_origin_session_and_assets(self):
        status, headers, body = self.request('GET', '/')
        self.assertEqual(status, 200)
        self.assertIn(b'RetroArch', body)
        self.assertIn("frame-ancestors 'none'", headers['Content-Security-Policy'])
        self.assertEqual(self.request('GET', '/api/status', headers={'Host': 'attacker.example'})[0], 403)
        self.assertEqual(self.request('POST', '/api/folder?path=nope', headers={'Origin': 'https://attacker.example'})[0], 403)
        self.assertEqual(self.request('POST', '/api/folder?path=nope', headers={'X-RetroArch-Token': 'wrong'})[0], 403)
        self.assertEqual(self.request('GET', '/config/retroarch.cfg')[0], 404)

    def test_alerts_follow_installed_cores_and_custom_system_folder(self):
        catalog = self.root / 'webui/core-metadata'
        catalog.mkdir(exist_ok=True)
        index = catalog / 'index.cfg'
        previous = index.read_bytes() if index.exists() else None
        for folder in ('cores', 'info', 'system/Saturn', 'config/Beetle Saturn'):
            (self.root / folder).mkdir(parents=True, exist_ok=True)
        index.write_text('mednafen_saturn_libretro.so = "Beetle Saturn"\n')
        core = self.root / 'cores/mednafen_saturn_libretro.so'; core.write_bytes(b'fixture')
        info = self.root / 'info/mednafen_saturn_libretro.info'
        info.write_text('firmware0_path = "required.bin"\nfirmware0_opt = "false"\nfirmware0_desc = "Region BIOS"\nfirmware1_path = "optional.bin"\nfirmware1_opt = "true"\n')
        cfg = self.root / 'config/Beetle Saturn/Beetle Saturn.cfg'
        original_cfg = cfg.read_bytes() if cfg.exists() else None
        cfg.unlink(missing_ok=True)
        try:
            # Saturn: one BIOS of either region is enough (its .info calls both required).
            alerts = json.loads(self.request('GET', '/api/alerts')[2])['alerts']
            self.assertEqual([(a['title'], a['level'], a['path']) for a in alerts],
                             [('A Saturn BIOS', 'required', str(self.root/'system/Saturn'))])
            self.assertEqual(alerts[0]['any_of'], ['sega_101.bin', 'mpr-17933.bin'])
            (self.root/'system/Saturn/mpr-17933.bin').write_bytes(b'present')
            self.assertEqual(json.loads(self.request('GET', '/api/alerts')[2])['alerts'], [])
            cfg.write_text(f'system_directory = "{self.root}/custom-bios"\n')
            alerts = json.loads(self.request('GET', '/api/alerts')[2])['alerts']
            self.assertEqual(alerts[0]['path'], str(self.root/'custom-bios'))
            cfg.unlink()
            core.unlink()
            self.assertEqual(json.loads(self.request('GET', '/api/alerts')[2])['alerts'], [])
            # Cores with no option catalog are checked too, by their own .info: a 3DO
            # BIOS (any one), an Amiga Kickstart only for some games, and a core the
            # rules do not know, by its .info's required firmware.
            for stem, text in (('opera', 'display_name = "The 3DO Company - 3DO (Opera)"\ncorename = "Opera"\nfirmware0_path = "panafz10.bin"\nfirmware0_opt = "true"\n'),
                               ('puae', 'display_name = "Commodore - Amiga (PUAE)"\ncorename = "PUAE"\nfirmware0_path = "kick34005.A500"\nfirmware0_opt = "false"\n'),
                               ('other', 'display_name = "Other (Thing)"\ncorename = "Thing"\nfirmware0_path = "thing.bin"\nfirmware0_opt = "false"\nfirmware0_desc = "Thing BIOS"\n')):
                (self.root/f'cores/{stem}_libretro.so').write_bytes(b'fixture')
                (self.root/f'info/{stem}_libretro.info').write_text(text)
            alerts = {a['core']: a for a in json.loads(self.request('GET', '/api/alerts')[2])['alerts']}
            self.assertEqual(sorted(alerts), ['Commodore - Amiga (PUAE)', 'Other (Thing)', 'The 3DO Company - 3DO (Opera)'])
            self.assertEqual((alerts['The 3DO Company - 3DO (Opera)']['title'], alerts['The 3DO Company - 3DO (Opera)']['level']), ('A 3DO BIOS', 'required'))
            self.assertEqual(alerts['Commodore - Amiga (PUAE)']['level'], 'some')
            self.assertEqual((alerts['Other (Thing)']['title'], alerts['Other (Thing)']['path']), ('Thing BIOS', str(self.root/'system/thing.bin')))
            (self.root/'system/goldstar.bin').write_bytes(b'present')
            alerts = {a['core'] for a in json.loads(self.request('GET', '/api/alerts')[2])['alerts']}
            self.assertNotIn('The 3DO Company - 3DO (Opera)', alerts)
            for stem in ('opera', 'puae', 'other'):
                (self.root/f'cores/{stem}_libretro.so').unlink()
        finally:
            if previous is None: index.unlink(missing_ok=True)
            else: index.write_bytes(previous)
            if original_cfg is None: cfg.unlink(missing_ok=True)
            else: cfg.write_bytes(original_cfg)
            core.unlink(missing_ok=True); info.unlink(missing_ok=True)

    def test_update_requests_require_session_and_ready_package(self):
        self.assertEqual(json.loads(self.request('GET', '/api/update')[2])['state'], 'idle')
        self.assertEqual(self.request('POST', '/api/update/download?tag=v1.0.0', headers={'X-RetroArch-Token':'wrong'})[0], 403)
        self.assertEqual(self.request('POST', '/api/update/download?tag=../escape')[0], 409)
        self.assertEqual(self.request('POST', '/api/update/install')[0], 409)

    def test_registered_core_metadata(self):
        status, _, body = self.request('GET', '/api/core-metadata?core=Metadata%20test')
        self.assertEqual(status, 200)
        data = json.loads(body)['runtime']
        self.assertEqual(data['categories'][0]['label'], 'Video')
        setting = data['settings'][0]
        self.assertEqual(setting['label'], 'Resolution <test>')
        self.assertIn('"quotes"', setting['description'])
        self.assertEqual(setting['choices'], [['1', 'Native'], ['2', 'Double']])
        legacy = json.loads(self.request('GET', '/api/core-metadata?core=Legacy%20test')[2])['runtime']
        self.assertEqual(legacy['settings'][0]['choices'], [['normal', 'normal'], ['fast', 'fast']])
        self.assertEqual(self.request('GET', '/api/core-metadata?core=../escape')[0], 400)
        self.assertEqual(json.loads(self.request('GET', '/api/core-metadata?core=Unknown')[2])['runtime']['settings'], [])
        self.assertFalse((self.root / 'config/escape.json').exists())
        (self.root / 'config/webui-metadata/link.json').symlink_to(self.root / 'config/retroarch.cfg')
        self.assertEqual(json.loads(self.request('GET', '/api/core-metadata?core=link')[2])['runtime']['settings'], [])

    def test_installed_core_without_saved_profile(self):
        catalog = self.root / 'webui/core-metadata'
        catalog.mkdir(exist_ok=True)
        (self.root / 'cores').mkdir(exist_ok=True)
        (self.root / 'cores/fresh_libretro.so').write_bytes(b'installed core fixture')
        (catalog / 'index.cfg').write_text('fresh_libretro.so = "Fresh Core"\nmissing_libretro.so = "Missing Core"\n')
        metadata = {'categories': [{'key': 'video', 'label': 'Video', 'description': 'Picture'}],
                    'settings': [{'key': 'fresh_resolution', 'label': 'Resolution', 'description': 'Picture detail.', 'category': 'video', 'choices': [['1', 'Native'], ['2', 'Double']]}]}
        (catalog / 'Fresh Core.json').write_text(json.dumps(metadata))
        (catalog / 'Fresh Core.opt').write_text('fresh_resolution = "2"\n')
        profiles = json.loads(self.request('GET', '/api/cores')[2])['cores']
        self.assertIn('Fresh Core', profiles)
        self.assertNotIn('Missing Core', profiles)
        self.assertFalse((self.root / 'config/Fresh Core').exists())
        response = json.loads(self.request('GET', '/api/core-metadata?core=Fresh%20Core')[2])
        self.assertEqual(response['bundled'], metadata)
        self.assertEqual(response['runtime']['settings'], [])
        url = '/api/config?scope=core-options&core=Fresh%20Core'
        state = json.loads(self.request('GET', url)[2])
        self.assertEqual(state['settings'][0]['value'], '2')
        status, _, _ = self.request('POST', url, b'fresh_resolution=1', {'X-RetroArch-Revision': state['revision']})
        self.assertEqual(status, 200)
        self.assertFalse((self.root / 'config/Fresh Core').exists())
        # A new profile must survive these ports' first-use default migration.
        for stem, core, key in [('ppsspp', 'PPSSPP', 'ppsspp_internal_resolution'),
                                ('dolphin', 'dolphin-emu', 'dolphin_efb_scale')]:
            (self.root / 'cores' / (stem + '_libretro.so')).write_bytes(b'core fixture')
            with (catalog / 'index.cfg').open('a') as index:
                index.write(stem + '_libretro.so = "' + core + '"\n')
            (catalog / (core + '.opt')).write_text(key + ' = "original"\n')
            endpoint = '/api/config?scope=core-options&core=' + quote(core)
            current = json.loads(self.request('GET', endpoint)[2])
            self.assertEqual(self.request('POST', endpoint, (key + '=chosen').encode(),
                             {'X-RetroArch-Revision': current['revision']})[0], 200)
        self.process.terminate(); self.process.wait(timeout=5)
        cls = self.__class__
        cls.process, cls.port, cls.token = webui_build.start(self.binary, self.root)
        self.assertEqual((self.root / 'config/Fresh Core/Fresh Core.opt').read_text(), 'fresh_resolution = "1"\n')
        self.assertFalse((self.root / 'config/webui-cores/Fresh Core.opt').exists())
        for core in ('PPSSPP', 'dolphin-emu'):
            self.assertTrue((self.root / 'config' / core / 'ps5-default-profile-v1').is_file())
            self.assertIn('"chosen"', (self.root / 'config' / core / (core + '.opt')).read_text())
        self.assertEqual(json.loads(self.request('GET', url)[2])['settings'][0]['value'], '1')

    def test_z_catalog_upgrade_ignores_stale_runtime(self):
        catalog = self.root / 'webui/core-metadata'
        catalog.mkdir(exist_ok=True)
        path = '/api/core-metadata?core=Metadata%20test'
        current = json.loads(self.request('GET', path)[2])
        self.assertEqual(current['runtime']['settings'][0]['choices'], [['1', 'Native'], ['2', 'Double']])
        # A new release's binary hash changes even if its static options do not.
        upgraded = {'binary_sha256': 'new-core-build', 'categories': [], 'settings': [
            {'key': 'test_resolution', 'label': 'Resolution', 'description': 'Updated choices',
             'category': '', 'choices': [['1', 'Native'], ['3', 'Triple']]}]}
        (catalog / 'Metadata test.json').write_text(json.dumps(upgraded))
        after = json.loads(self.request('GET', path)[2])
        self.assertEqual(after['bundled'], upgraded)
        self.assertEqual(after['runtime']['settings'], [])
        # An old defaults snapshot must not resurrect removed options either.
        (self.root / 'config/Metadata test').mkdir(exist_ok=True)
        (self.root / 'config/Metadata test/Metadata test.opt').write_text('saved_option = "preserve"\n')
        state = json.loads(self.request('GET', '/api/config?scope=core-options&core=Metadata%20test')[2])
        self.assertEqual([s['key'] for s in state['settings']], ['saved_option'])

    def test_upload_download_and_collision(self):
        self.assertEqual(self.request('POST', '/api/folder?path=PSP')[0], 201)
        content = bytes(range(256)) * 8192
        path = '/api/upload?path=' + quote('PSP/test & game.iso')
        status, _, body = self.request('PUT', path, content)
        self.assertEqual(status, 201, body)
        self.assertEqual((self.root / 'content/PSP/test & game.iso').read_bytes(), content)
        self.assertEqual(self.request('PUT', path, b'replace')[0], 409)
        self.assertEqual(self.request('GET', path.replace('upload', 'download'))[2], content)
        listing = json.loads(self.request('GET', '/api/content?path=PSP')[2])
        self.assertEqual(listing['entries'][0]['name'], 'test & game.iso')
        self.assertEqual(listing['entries'][0]['size'], len(content))

    def test_traversal_symlinks_and_hidden_files(self):
        (self.root / 'content/escape').symlink_to(self.root / 'config', target_is_directory=True)
        for path in ('../config/retroarch.cfg', '/etc/passwd', 'escape/retroarch.cfg', 'a/../b', '.private'):
            for verb, endpoint, body in [('GET', 'content', None), ('PUT', 'upload', b'bad')]:
                status = self.request(verb, '/api/'+endpoint+'?path='+quote(path, safe=''), body)[0]
                self.assertIn(status, (400, 409), path)
        self.assertEqual((self.root / 'config/retroarch.cfg').read_bytes(), self.original)
        self.assertNotIn('escape', [e['name'] for e in json.loads(self.request('GET', '/api/content')[2])['entries']])

    def test_settings_preserve_original_and_validate(self):
        fields = {s['key']: s['value'] for s in json.loads(self.request('GET', '/api/settings')[2])['settings']}
        self.assertEqual(fields['audio_volume'], '-6')
        self.assertEqual(self.request('POST', '/api/settings', b'audio_volume=-12\ninput_rumble_gain=50')[0], 200)
        saved = (self.root / 'config/webui.cfg').read_bytes()
        self.assertIn(b'audio_volume = "-12"', saved)
        self.assertNotIn(b'video_vsync', saved)
        self.assertEqual((self.root / 'config/retroarch.cfg').read_bytes(), self.original)
        for bad in (b'audio_volume=999', b'input_rumble_gain=-1', b'menu_driver=evil', b'savefile_directory=/tmp', b'video_vsync=perhaps'):
            self.assertEqual(self.request('POST', '/api/settings', bad)[0], 400)
            self.assertEqual((self.root / 'config/webui.cfg').read_bytes(), saved)
        self.assertEqual(self.request('POST', '/api/settings', b'a'*17000)[0], 413)
        conn = http.client.HTTPConnection('127.0.0.1', self.port, timeout=5)
        conn.request('POST', '/api/settings', [b'a'*9000, b'b'*9000],
                     {'X-RetroArch-Token': self.token}, encode_chunked=True)
        self.assertEqual(conn.getresponse().status, 413)
        conn.close()
        self.assertEqual((self.root / 'config/webui.cfg').read_bytes(), saved)

    def test_frontend_start_lives_in_its_own_file(self):
        # The frontend the title starts with (src/ps5_frontend_choice.h): "ask" until one is
        # chosen, kept in config/frontend.cfg and never in RetroArch's webui.cfg.
        webui_cfg = self.root / 'config/webui.cfg'
        before = webui_cfg.read_bytes() if webui_cfg.exists() else None
        self.addCleanup(lambda: webui_cfg.write_bytes(before) if before is not None else webui_cfg.unlink(missing_ok=True))
        self.addCleanup(lambda: (self.root / 'config/frontend.cfg').unlink(missing_ok=True))
        fields = {s['key']: s for s in json.loads(self.request('GET', '/api/settings')[2])['settings']}
        self.assertEqual((fields['frontend_start']['value'], fields['frontend_start']['kind']), ('ask', 'frontend'))
        self.assertEqual(self.request('POST', '/api/settings', b'frontend_start=es-de')[0], 200)
        self.assertEqual((self.root / 'config/frontend.cfg').read_text(), 'frontend_start = "es-de"\n')
        self.assertEqual(webui_cfg.read_bytes() if webui_cfg.exists() else None, before)
        fields = {s['key']: s['value'] for s in json.loads(self.request('GET', '/api/settings')[2])['settings']}
        self.assertEqual(fields['frontend_start'], 'es-de')
        for bad in (b'frontend_start=evil', b'frontend_start=', b'frontend_start=es-de"\ninjected=1'):
            self.assertEqual(self.request('POST', '/api/settings', bad)[0], 400)
        self.assertEqual((self.root / 'config/frontend.cfg').read_text(), 'frontend_start = "es-de"\n')
        # With a RetroArch setting in the same request, both files take their part.
        self.assertEqual(self.request('POST', '/api/settings', b'frontend_start=ask\naudio_volume=-3')[0], 200)
        self.assertEqual((self.root / 'config/frontend.cfg').read_text(), 'frontend_start = "ask"\n')
        webui = (self.root / 'config/webui.cfg').read_bytes()
        self.assertIn(b'audio_volume = "-3"', webui)
        self.assertNotIn(b'frontend_start', webui)

    def test_advanced_global_and_per_core_persistence(self):
        # Full saved profiles, including values not in the quick-settings list.
        (self.root / 'retroarch.cfg').write_text('video_rotation = "0"\nvideo_vsync = "true"\n')
        profile = self.root / 'config/Example Core'
        profile.mkdir()
        original = b'example_resolution = "6x"\nexample_filter = "nearest"\n'
        (profile / 'Example Core.opt').write_bytes(original)
        (self.root / 'config/not-a-core').symlink_to(self.root / 'content', target_is_directory=True)
        cores = json.loads(self.request('GET', '/api/cores')[2])['cores']
        self.assertIn('Example Core', cores)
        self.assertNotIn('not-a-core', cores)
        def read(url):
            status, _, body = self.request('GET', url)
            self.assertEqual(status, 200, body)
            return json.loads(body)
        def save(url, body, revision):
            return self.request('POST', url, body, {'X-RetroArch-Revision': revision})[0]
        global_url = '/api/config?scope=global'
        state = read(global_url)
        self.assertEqual(save(global_url, b'video_rotation=2', state['revision']), 200)
        self.assertEqual(save(global_url, b'video_rotation=3', state['revision']), 409)
        for invalid in (b'new_arbitrary_key=1', b'audio_volume=abc', b'video_vsync=yes', b'video_rotation=2"\ninjected=1', b'audio_volume=999'):
            self.assertEqual(save(global_url, invalid, read(global_url)['revision']), 400)
        # A quick setting must retain the advanced override.
        self.assertEqual(self.request('POST', '/api/settings', b'input_rumble_gain=75')[0], 200)
        self.assertIn(b'video_rotation = "2"', (self.root / 'config/webui.cfg').read_bytes())
        # Unknown config fields and core enums remain strings across edits.
        self.assertEqual(save(global_url, b'unrelated=1', read(global_url)['revision']), 200)
        self.assertEqual(save(global_url, b'unrelated=preserve', read(global_url)['revision']), 200)
        options_url = '/api/config?scope=core-options&core=Example%20Core'
        self.assertEqual(save(options_url, b'example_resolution=1', read(options_url)['revision']), 200)
        self.assertEqual(save(options_url, b'example_resolution=4x', read(options_url)['revision']), 200)
        self.assertEqual((profile / 'Example Core.opt').read_bytes(), original, 'Running core profile is untouched')
        override_url = '/api/config?scope=core-settings&core=Example%20Core'
        self.assertEqual(save(override_url, b'video_vsync=false', read(override_url)['revision']), 200)
        self.assertNotEqual(next(x['value'] for x in read(global_url)['settings'] if x['key'] == 'video_vsync'), 'false')
        self.assertEqual(self.request('GET', '/api/config?scope=core-options&core=..%2Fconfig')[0], 404)
        # Simulate the current core saving on exit after the browser edit.
        (profile / 'Example Core.opt').write_bytes(original)
        cls = self.__class__
        cls.process.terminate(); cls.process.wait(timeout=5)
        cls.process, cls.port, cls.token = webui_build.start(cls.binary, cls.root)
        self.assertIn(b'example_resolution = "4x"', (profile / 'Example Core.opt').read_bytes())
        self.assertIn(b'example_filter = "nearest"', (profile / 'Example Core.opt').read_bytes())
        self.assertIn(b'video_vsync = "false"', (profile / 'Example Core.cfg').read_bytes())
        self.assertFalse((self.root / 'config/webui-cores/Example Core.opt').exists())
        self.assertFalse((self.root / 'config/webui-cores/Example Core.cfg').exists())
        self.assertEqual((self.root / 'config/retroarch.cfg').read_bytes(), self.original)
        # Leave the shared fixture's original quick-settings baseline intact.
        (self.root / 'config/webui.cfg').unlink()

    def test_interrupted_upload_is_removed(self):
        with socket.create_connection(('127.0.0.1', self.port)) as s:
            request = (f'PUT /api/upload?path=unfinished.iso HTTP/1.1\r\nHost: 127.0.0.1:{self.port}\r\n'
                       f'X-RetroArch-Token: {self.token}\r\nContent-Length: 1000000\r\n\r\n').encode()
            s.sendall(request + b'a'*1000)
            time.sleep(.05)
        for _ in range(100):
            if not list((self.root / 'content').glob('.upload-*')): break
            time.sleep(.02)
        self.assertFalse(list((self.root / 'content').glob('.upload-*')))
        self.assertFalse((self.root / 'content/unfinished.iso').exists())

    # The transfer engine (src/webui_transfer.h): batches, sessions, ranges, parallel.
    @staticmethod
    def batch(files, end=True):
        out = b''
        for name, data in files:
            raw = name.encode()
            out += len(raw).to_bytes(2, 'little') + raw + len(data).to_bytes(8, 'little') + data
        return out + (b'\0\0' if end else b'')

    def test_batch_upload_many_small_files(self):
        files = [(f'media/{system}/{i:03}.png', bytes([i % 251]) * (i * 37 % 5000))
                 for system in ('snes', 'nes') for i in range(150)]
        status, _, body = self.request('PUT', '/api/upload/batch?folder=batch-a', self.batch(files))
        result = json.loads(body)
        self.assertEqual((status, result['written'], result['skipped'], result['failed']), (200, 300, 0, []))
        for name, data in files:
            self.assertEqual((self.root / 'content/batch-a' / name).read_bytes(), data)
        # Existing files are skipped unless replace; a replace writes them again.
        changed = [(files[0][0], b'new'), ('media/snes/extra.png', b'x')]
        result = json.loads(self.request('PUT', '/api/upload/batch?folder=batch-a', self.batch(changed))[2])
        self.assertEqual((result['written'], result['skipped']), (1, 1))
        self.assertEqual((self.root / 'content/batch-a' / files[0][0]).read_bytes(), files[0][1])
        result = json.loads(self.request('PUT', '/api/upload/batch?folder=batch-a&existing=replace&sync=0',
                                         self.batch(changed))[2])
        self.assertEqual((result['written'], result['skipped']), (2, 0))
        self.assertEqual((self.root / 'content/batch-a' / files[0][0]).read_bytes(), b'new')
        self.assertFalse(list((self.root / 'content/batch-a').rglob('.upload-*')))

    def test_batch_refuses_bad_names_and_bad_streams(self):
        bad = [('../escape.png', b'a'), ('.hidden', b'b'), ('a//b', b'c'), ('ok/fine.png', b'd'), ('/abs', b'e')]
        status, _, body = self.request('PUT', '/api/upload/batch?folder=batch-b', self.batch(bad))
        result = json.loads(body)
        self.assertEqual((status, result['written'], len(result['failed'])), (200, 1, 4))
        self.assertFalse((self.root / 'escape.png').exists())
        self.assertEqual((self.root / 'content/batch-b/ok/fine.png').read_bytes(), b'd')
        # Cut short: the files before the cut stand, the one cut is not left behind.
        stream = self.batch([('whole.png', b'1' * 100)], end=False)
        stream += (8).to_bytes(2, 'little') + b'half.png' + (1000).to_bytes(8, 'little') + b'2' * 10
        status, _, body = self.request('PUT', '/api/upload/batch?folder=batch-c', stream)
        result = json.loads(body)
        self.assertEqual((status, result['complete'], result['written']), (400, False, 1))
        self.assertFalse((self.root / 'content/batch-c/half.png').exists())
        self.assertFalse(list((self.root / 'content/batch-c').glob('.upload-*')))
        # Data past the end marker, and a folder outside content, are refused.
        self.assertEqual(self.request('PUT', '/api/upload/batch?folder=batch-d', self.batch([]) + b'junk')[0], 400)
        self.assertEqual(self.request('PUT', '/api/upload/batch?folder=../x', self.batch([]))[0], 400)
        self.assertEqual(self.request('PUT', '/api/upload/batch?folder=x', self.batch([]),
                                      headers={'X-RetroArch-Token': 'wrong'})[0], 403)

    def test_session_parts_in_parallel_any_order(self):
        import os, random, threading
        data = os.urandom(5 * 1024 * 1024 + 123)
        status, _, body = self.request('POST', '/api/upload/session?path=' + quote('big/game.iso') + f'&size={len(data)}')
        self.assertEqual(status, 201)
        sid = json.loads(body)['id']
        # Missing parts: the commit says what is covered and leaves the session open.
        status, _, body = self.request('POST', f'/api/upload/commit?id={sid}')
        self.assertEqual((status, json.loads(body)['covered']), (409, 0))
        part = 700 * 1024
        ranges = [(o, min(o + part + 4096, len(data))) for o in range(0, len(data), part)]  # overlapping
        random.Random(7).shuffle(ranges)
        results = []
        def send(chunk):
            for start, end in chunk:
                results.append(self.request('PUT', f'/api/upload/part?id={sid}&offset={start}', data[start:end])[0])
        threads = [threading.Thread(target=send, args=(ranges[i::6],)) for i in range(6)]
        [t.start() for t in threads]; [t.join() for t in threads]
        self.assertEqual(set(results), {200})
        self.assertFalse((self.root / 'content/big/game.iso').exists())
        status, _, body = self.request('POST', f'/api/upload/commit?id={sid}')
        self.assertEqual((status, json.loads(body)['bytes']), (201, len(data)))
        self.assertEqual((self.root / 'content/big/game.iso').read_bytes(), data)
        self.assertFalse(list((self.root / 'content/big').glob('.upload-*')))
        # The session is gone; a second commit, or a part, finds nothing.
        self.assertEqual(self.request('POST', f'/api/upload/commit?id={sid}')[0], 404)
        self.assertEqual(self.request('PUT', f'/api/upload/part?id={sid}&offset=0', b'x')[0], 404)
        # The name now exists: a new session for it is refused unless replace.
        self.assertEqual(self.request('POST', '/api/upload/session?path=big/game.iso&size=5')[0], 409)

    def test_session_bounds_abort_and_range_download(self):
        status, _, body = self.request('POST', '/api/upload/session?path=abort.bin&size=10')
        sid = json.loads(body)['id']
        self.assertEqual(self.request('PUT', f'/api/upload/part?id={sid}&offset=8', b'abc')[0], 416)
        self.assertEqual(self.request('PUT', f'/api/upload/part?id={sid}&offset=x', b'a')[0], 416)
        self.assertEqual(self.request('PUT', f'/api/upload/part?id={sid}&offset=0', b'0123456789')[0], 200)
        self.assertEqual(json.loads(self.request('DELETE', f'/api/upload/session?id={sid}')[2])['cancelled'], True)
        self.assertFalse((self.root / 'content/abort.bin').exists())
        self.assertFalse(list((self.root / 'content').glob('.upload-*')))
        self.assertEqual(self.request('POST', '/api/upload/session?path=../x&size=1')[0], 400)
        # Ranges of a download: a slice, an open end, the last bytes, and one past the end.
        (self.root / 'content/range.bin').write_bytes(bytes(range(256)) * 4)
        status, headers, body = self.request('GET', '/api/download?path=range.bin', headers={'Range': 'bytes=10-19'})
        self.assertEqual((status, body, headers['Content-Range']), (206, bytes(range(10, 20)), 'bytes 10-19/1024'))
        self.assertEqual(self.request('GET', '/api/download?path=range.bin', headers={'Range': 'bytes=1000-'})[2],
                         (bytes(range(256)) * 4)[1000:])
        self.assertEqual(self.request('GET', '/api/download?path=range.bin', headers={'Range': 'bytes=-4'})[2],
                         bytes(range(252, 256)))
        self.assertEqual(self.request('GET', '/api/download?path=range.bin', headers={'Range': 'bytes=2000-'})[0], 416)
        status, headers, body = self.request('GET', '/api/download?path=range.bin')
        self.assertEqual((status, len(body), headers['Accept-Ranges']), (200, 1024, 'bytes'))

    def test_parallel_uploads_of_one_name_keep_one(self):
        import threading
        results = []
        def send(i):
            results.append(self.request('PUT', '/api/upload?path=race.bin', str(i).encode() * 100000)[0])
        threads = [threading.Thread(target=send, args=(i,)) for i in range(8)]
        [t.start() for t in threads]; [t.join() for t in threads]
        self.assertEqual(results.count(201), 1)
        self.assertEqual(results.count(409), 7)
        content = (self.root / 'content/race.bin').read_bytes()
        self.assertEqual(len(set(content)), 1)
        self.assertFalse(list((self.root / 'content').glob('.upload-*')))
