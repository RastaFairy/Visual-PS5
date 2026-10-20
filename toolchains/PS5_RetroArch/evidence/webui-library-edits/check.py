"""Console checks for issues 58, 55 and 57 through the WebUI, with a test ROM made here (a
minimal NES program that loops), so none of the owner's games is touched. Run from the
repository while RetroArch runs on the console (.env names it):
    python3 evidence/webui-library-edits/check.py
Leaves the console as it found it: the test ROM, its details and the temporary playlist go."""
import ftplib
import io
import json
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

env = {}
for line in Path('.env').read_text().splitlines():
    if '=' in line and not line.lstrip().startswith('#'):
        key, value = line.split('=', 1)
        env[key.strip()] = value.strip().strip('"').strip("'")
base = f"http://{env['PS5_HOST']}:6769"
token = json.load(urllib.request.urlopen(base + '/api/status', timeout=20))['token']
TITLE = '/data/homebrew/PPSA99169'
PLAYLIST = 'Nintendo - Nintendo Entertainment System.lpl'


def call(method, route, body=None):
    request = urllib.request.Request(base + route, data=body, method=method, headers={'X-RetroArch-Token': token})
    try:
        with urllib.request.urlopen(request, timeout=120) as response:
            return response.status, response.read()
    except urllib.error.HTTPError as error:
        return error.code, error.read()


def ftp():
    f = ftplib.FTP()
    f.connect(env['PS5_HOST'], int(env.get('FTP_PORT', '2121')), timeout=20)
    f.login(env.get('PS5_FTP_USER') or 'anonymous', env.get('PS5_FTP_PASSWORD') or '')
    return f


def get(path):
    out = io.BytesIO()
    try:
        with ftp() as f:
            f.retrbinary(f'RETR {path}', out.write)
        return out.getvalue()
    except ftplib.all_errors:
        return None


def put(path, data):
    with ftp() as f:
        f.storbinary(f'STOR {path}', io.BytesIO(data))


def remove(path):
    try:
        with ftp() as f:
            f.delete(path)
    except ftplib.all_errors:
        pass


results = {}
# Issue 58: the RetroAchievements password reads as saved while a token is kept.
fields = {s['key']: s for s in json.loads(call('GET', '/api/config?scope=global')[1])['settings']}
results['58 password field'] = {k: ('set' if fields.get(k, {}).get('set') else 'not set') for k in ('cheevos_password', 'cheevos_token')}
results['58 username present'] = bool(fields.get('cheevos_username', {}).get('value'))

assert get(f'{TITLE}/playlists/{PLAYLIST}') is None, 'a real NES playlist exists; not touching it'
prg = bytearray(16384)
prg[0:3] = bytes([0x4C, 0x00, 0xC0])  # JMP $C000
for at in (0x3FFA, 0x3FFC, 0x3FFE):  # NMI, RESET and IRQ at $C000
    prg[at:at + 2] = bytes([0x00, 0xC0])
rom = b'NES\x1a\x01\x01' + bytes(10) + bytes(prg) + bytes(8192)
status, body = call('PUT', '/api/library/add?' + urllib.parse.urlencode({'system': 'nes', 'filename': 'Claude Test.nes'}), rom)
results['add game'] = status
game = json.loads(body)
path = game['path']
try:
    put(f'{TITLE}/playlists/{PLAYLIST}', json.dumps({'version': '1.5', 'items': [
        {'path': path, 'label': 'Claude Test', 'core_path': 'DETECT', 'core_name': 'DETECT', 'crc32': '', 'db_name': PLAYLIST}]}).encode())
    query = urllib.parse.urlencode({'system': game['system'], 'game': game['key'], 'path': path})
    # Issue 55: a rename reaches the playlist's label.
    status, _ = call('POST', '/api/library/game?' + query, json.dumps({'partial': 'true', 'name': 'Claude Test Renamed'}).encode())
    label = json.loads(get(f'{TITLE}/playlists/{PLAYLIST}'))['items'][0]['label']
    results['55 rename'] = (status, label)
    # Issue 57: delete takes the file, the playlist entry and the details.
    status, body = call('POST', '/api/library/delete?' + query)
    left = json.loads(get(f'{TITLE}/playlists/{PLAYLIST}'))['items']
    results['57 delete'] = (status, body.decode()[:60], 'file gone' if get(f'{TITLE}/content/nes/Claude Test.nes') is None else 'FILE LEFT',
                            f'{len(left)} playlist entries left',
                            'details gone' if get(f"{TITLE}/library/{game['system']}/metadata/{game['key']}.meta") is None else 'DETAILS LEFT')
    listed = any(g['path'] == path for s in json.loads(call('GET', '/api/library')[1])['systems'] for g in s['games'])
    results['57 library'] = 'still listed' if listed else 'gone from the library'
finally:
    remove(f'{TITLE}/playlists/{PLAYLIST}')
    remove(f'{TITLE}/content/nes/Claude Test.nes')
    remove(f"{TITLE}/library/{game['system']}/metadata/{game['key']}.meta")
    results['cleanup'] = 'playlist and test files removed' if get(f'{TITLE}/playlists/{PLAYLIST}') is None else 'PLAYLIST LEFT'
for key, value in results.items():
    print(f'{key}: {value}')
