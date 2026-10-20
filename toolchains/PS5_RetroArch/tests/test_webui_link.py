"""The WebUI link (src/webui_link.h) against a loader, a launcher and a daemon played
here: neither, the daemon sent and linked to, its install request, a stale daemon, and
the daemon started by the homebrew launcher when there is no loader."""
from pathlib import Path
import socket
import subprocess
import tempfile
import threading
import time
import unittest

ROOT = Path(__file__).resolve().parent.parent
ELF = b'\x7fELF' + bytes(range(256)) * 300


def free_port():
    with socket.socket() as s:
        s.bind(('127.0.0.1', 0))
        return s.getsockname()[1]


def listener(port):
    s = socket.socket()
    s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    s.bind(('127.0.0.1', port))
    s.listen(4)
    s.settimeout(10)
    return s


def read_line(conn):
    data = b''
    while not data.endswith(b'\n'):
        chunk = conn.recv(1)
        if not chunk:
            break
        data += chunk
    return data.decode()


class WebuiLink(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.TemporaryDirectory()
        self.addCleanup(self.dir.cleanup)
        app = Path(self.dir.name)
        (app / 'sce_sys').mkdir()
        (app / 'sce_sys/param.json').write_text('{"contentId": "x", "titleId": "PPSA99169"}')
        (app / 'webui').mkdir()
        (app / 'webui/ps5-retroarch-webui.elf').write_bytes(ELF)
        self.link, self.loader, self.launcher = free_port(), free_port(), free_port()
        self.binary = str(app / 'link-test')
        subprocess.run(['c++', '-std=c++17', '-O2', '-Wall', '-Wextra', '-Werror', '-pthread',
                        f'-DPS5_WEBUI_APP0="{app}"', f'-DPS5_WEBUI_LINK_PORT={self.link}',
                        f'-DPS5_WEBUI_LOADER_PORT={self.loader}', f'-DPS5_WEBUI_LAUNCHER_PORT={self.launcher}',
                        'tests/webui_link_test.cpp',
                        '-o', self.binary], cwd=ROOT, check=True)

    def run_link(self):
        return subprocess.Popen([self.binary], stdout=subprocess.PIPE, text=True)

    def loader_then_daemon(self, replies, received):
        """The loader takes the ELF whole; then a daemon per reply answers the hello."""
        for reply in replies:
            with listener(self.loader) as loader:
                conn, _ = loader.accept()
                with conn:
                    data = b''
                    while chunk := conn.recv(65536):
                        data += chunk
                received.append(('elf', data == ELF))
            with listener(self.link) as daemon:
                conn, _ = daemon.accept()
                with conn:
                    received.append(('hello', read_line(conn)))
                    conn.sendall(reply.encode() + b'\n')
                    if reply != 'ok':
                        continue
                    received.append(('frontend', read_line(conn)))
                    conn.sendall(b'install\n')
                    time.sleep(0.5)

    def test_no_loader(self):
        start = time.monotonic()
        out, _ = self.run_link().communicate(timeout=20)
        self.assertLess(time.monotonic() - start, 5)
        self.assertIn('wait=0', out)
        self.assertIn(f'no ELF loader on {self.loader}', out)
        self.assertIn(f'no homebrew launcher on {self.launcher}', out)
        self.assertIn('install=0', out)

    def test_daemon_started_linked_and_install(self):
        received = []
        thread = threading.Thread(target=self.loader_then_daemon, args=(['ok'], received))
        thread.start()
        time.sleep(0.2)
        out, _ = self.run_link().communicate(timeout=30)
        thread.join()
        self.assertEqual(received, [('elf', True), ('hello', 'hello title PPSA99169\n'),
                                    ('frontend', 'frontend retroarch\n')])
        self.assertIn('wait=1', out)
        self.assertIn('install=1 callbacks=1', out)

    def test_stale_daemon_replaced(self):
        received = []
        thread = threading.Thread(target=self.loader_then_daemon, args=(['stale', 'ok'], received))
        thread.start()
        time.sleep(0.2)
        out, _ = self.run_link().communicate(timeout=30)
        thread.join()
        self.assertEqual([r[0] for r in received], ['elf', 'hello', 'elf', 'hello', 'frontend'])
        self.assertTrue(all(ok for kind, ok in received if kind == 'elf'))
        self.assertIn('another build', out)
        self.assertIn('install=1 callbacks=1', out)

    def test_launcher_when_no_loader(self):
        received = []

        def launcher_then_daemon():
            with listener(self.launcher) as launcher:
                conn, _ = launcher.accept()
                with conn:
                    received.append(read_line(conn))
                    conn.sendall(b'HTTP/1.1 200 OK\r\nContent-Length: 0\r\n\r\n')
            with listener(self.link) as daemon:
                conn, _ = daemon.accept()
                with conn:
                    received.append(read_line(conn))
                    conn.sendall(b'ok\n')
                    received.append(read_line(conn))

        thread = threading.Thread(target=launcher_then_daemon)
        thread.start()
        time.sleep(0.2)
        out, _ = self.run_link().communicate(timeout=30)
        thread.join()
        self.assertEqual(received, [
            'GET /hbldr?daemon=1&pipe=0&path=/system_ex/app/PPSA99169/webui/ps5-retroarch-webui.elf HTTP/1.0\r\n',
            'hello title PPSA99169\n', 'frontend retroarch\n'])
        self.assertIn(f'no ELF loader on {self.loader}', out)
        self.assertIn('wait=1', out)


if __name__ == '__main__':
    unittest.main()
