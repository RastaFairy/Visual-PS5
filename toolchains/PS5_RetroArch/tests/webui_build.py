"""Builds the WebUI's server for the host (the tests' fixtures): the given main, the
server's sources and its libraries, with defines. One list of sources for every test."""
from pathlib import Path
import http.client
import json
import socket
import subprocess
import time

ROOT = Path(__file__).resolve().parent.parent
SOURCES = ['src/webui_ps5.cpp', 'src/webui_transfer.cpp', 'src/webui_update.cpp', 'src/scraper.cpp',
           'src/scraper_http.cpp', 'src/ps5_forwarders.cpp']
C_SOURCES = ['src/ps5_library.c', 'src/ps5_smb.c']


def build(output, main, defines=(), flags=('-O1', '-g')):
    output = Path(output)
    http = subprocess.check_output(['bash', 'tools/build-webui-http.sh', 'host'], cwd=ROOT, text=True).strip()
    update = subprocess.check_output(['bash', 'tools/build-webui-update.sh', 'host'], cwd=ROOT, text=True).strip()
    smb2 = subprocess.check_output(['bash', 'tools/build-libsmb2.sh', 'host'], cwd=ROOT, text=True).strip()
    objects = []
    for source in C_SOURCES:
        obj = output.with_name(output.name + '-' + Path(source).stem + '.o')
        subprocess.run(['cc', '-std=c11', '-D_DEFAULT_SOURCE', *flags, '-I' + smb2 + '/include', '-c', source, '-o', str(obj)], cwd=ROOT, check=True)
        objects.append(str(obj))
    subprocess.run(['c++', '-std=c++17', *flags, '-pthread', '-Isrc', '-I' + smb2 + '/include',
                    '-I' + str(ROOT / '.deps/webui/libmicrohttpd-1.0.10/src/include'),
                    '-I' + str(ROOT / '.deps/native/zlib/zlib-1.3.2/contrib/minizip'),
                    '-I' + str(ROOT / 'vendor/retroarch/deps/mbedtls'),
                    '-DPS5_SCRAPER_CURL',  # the daemon's HTTP client, the host's libcurl
                    *[f'-D{d}' for d in defines], main, *SOURCES, *objects, http, update, smb2 + '/lib/libsmb2.a', '-lz', '-lcurl',
                    '-o', str(output)], cwd=ROOT, check=True)
    return output


def start(binary, root, env=None, seconds=8.0):
    """Starts a server built above (tests/webui_server_main.cpp) for the title folder root on a
    free port, once it answers: its process, port and session token. A port found free can be
    taken before the server binds it (another connection gets it as its own port): the server
    then exits at once, "Address already in use", and starts again on another."""
    for _ in range(5):
        with socket.socket() as probe:
            probe.bind(('127.0.0.1', 0))
            port = probe.getsockname()[1]
        process = subprocess.Popen([str(binary), str(root), str(port)], env=env,
                                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        deadline = time.monotonic() + seconds
        while process.poll() is None and time.monotonic() < deadline:
            try:
                connection = http.client.HTTPConnection('127.0.0.1', port, timeout=5)
                connection.request('GET', '/api/status')
                token = json.loads(connection.getresponse().read())['token']
                connection.close()
                return process, port, token
            except (OSError, http.client.HTTPException):
                time.sleep(0.02)
        if process.poll() is None:  # running, and no answer: no port problem
            process.kill()
            process.wait()
            break
    raise RuntimeError('the server did not start')
