"""RetroArch's passwords and sign-in tokens (cheevos_password, cheevos_token,
netplay_password...) never leave the console through the WebUI's settings editor: a
password can be set, not read, and a token cannot be written at all."""
from pathlib import Path
import http.client
import json
import subprocess
import tempfile
import unittest

import sys
ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(Path(__file__).resolve().parent))
from test_webui_language import Server  # noqa: E402


class Secrets(unittest.TestCase):
    def test_passwords_are_write_only(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp) / 'title'
            for name in ('config', 'content', 'webui'):
                (root / name).mkdir(parents=True)
            (root / 'webui/index.html').write_text('<!doctype html><title>RetroArch</title>')
            (root / 'config/retroarch.cfg').write_text(
                'cheevos_username = "player"\ncheevos_password = "hunter2"\ncheevos_token = "abcdef123456"\n'
                'netplay_password = "lan-secret"\nvideo_smooth = "false"\n')
            server = Server(root)

            def call(method, body=b'', revision=None):
                conn = http.client.HTTPConnection('127.0.0.1', server.port, timeout=5)
                headers = {'X-RetroArch-Token': server.token}
                if revision:
                    headers['X-RetroArch-Revision'] = revision
                conn.request(method, '/api/config?scope=global', body, headers)
                response = conn.getresponse(); data = response.read(); conn.close()
                return response.status, data

            try:
                status, raw = call('GET')
                self.assertEqual(status, 200)
                for secret in (b'hunter2', b'abcdef123456', b'lan-secret'):
                    self.assertNotIn(secret, raw)
                listing = json.loads(raw)
                fields = {s['key']: s for s in listing['settings']}
                self.assertEqual(fields['cheevos_password'], {'key': 'cheevos_password', 'value': '', 'kind': 'text', 'secret': True, 'set': True})
                self.assertEqual((fields['cheevos_token']['value'], fields['cheevos_token']['secret']), ('', True))
                self.assertEqual(fields['cheevos_username']['value'], 'player')
                # The online settings show before RetroArch has written them (its defaults).
                self.assertEqual(fields['netplay_public_announce']['value'], 'true')
                self.assertEqual(fields['cheevos_enable']['kind'], 'bool')
                revision = listing['revision']
                self.assertEqual(call('POST', b'cheevos_token=forged', revision)[0], 400)
                self.assertEqual(call('POST', b'cheevos_enable=maybe', revision)[0], 400)
                # An empty password leaves the saved one; a new one is kept for RetroArch.
                self.assertEqual(call('POST', b'cheevos_password=\ncheevos_enable=true', revision)[0], 200)
                saved = (root / 'config/webui.cfg').read_text()
                self.assertIn('cheevos_enable = "true"', saved)
                self.assertNotIn('cheevos_password', saved)
                revision = json.loads(call('GET')[1])['revision']
                self.assertEqual(call('POST', b'cheevos_password=correct horse', revision)[0], 200)
                self.assertIn('cheevos_password = "correct horse"', (root / 'config/webui.cfg').read_text())
                self.assertNotIn(b'correct horse', call('GET')[1])
                # The new password signs in, not the old account's token...
                self.assertIn('cheevos_token = ""', (root / 'config/webui.cfg').read_text())
                # ...and once RetroArch has its own token (patches/series 0130) the password
                # leaves webui.cfg; the other settings stay.
                helper = Path(temp) / 'forget'
                (Path(temp) / 'forget.c').write_text(
                    'int ps5_cheevos_forget_password(const char *path, int token_too);\n'
                    'int main(int c, char **v) { return ps5_cheevos_forget_password(v[1], c < 3) == (c < 3 ? 2 : 1) ? 0 : 1; }\n')
                subprocess.run(['cc', '-std=c11', '-Wall', '-Wextra', '-Werror', str(Path(temp) / 'forget.c'),
                                str(ROOT / 'src/ps5_cheevos.c'), '-o', str(helper)], check=True)
                subprocess.run([str(helper), str(root / 'config/webui.cfg')], check=True)
                left = (root / 'config/webui.cfg').read_text()
                self.assertNotIn('cheevos_password', left)
                self.assertNotIn('cheevos_token', left)
                self.assertIn('cheevos_enable = "true"', left)
                # Nothing left to remove: the file is not rewritten.
                self.assertEqual(subprocess.run([str(helper), str(root / 'config/webui.cfg')]).returncode, 1)
                # retroarch.cfg loses the password and keeps its token.
                subprocess.run([str(helper), str(root / 'config/retroarch.cfg'), 'keep-token'], check=True)
                kept = (root / 'config/retroarch.cfg').read_text()
                self.assertNotIn('hunter2', kept)
                self.assertIn('cheevos_token = "abcdef123456"', kept)
                # Signed in: the password is gone but the token is kept, so the page still
                # shows the account as saved (issue 58), and neither is ever sent.
                raw = call('GET')[1]
                self.assertNotIn(b'abcdef123456', raw)
                fields = {s['key']: s for s in json.loads(raw)['settings']}
                self.assertEqual((fields['cheevos_password']['value'], fields['cheevos_password']['set']), ('', True))
                (root / 'config/retroarch.cfg').write_text(kept.replace('abcdef123456', ''))
                fields = {s['key']: s for s in json.loads(call('GET')[1])['settings']}
                self.assertFalse(fields['cheevos_password']['set'])
            finally:
                server.stop()


if __name__ == '__main__':
    unittest.main()
