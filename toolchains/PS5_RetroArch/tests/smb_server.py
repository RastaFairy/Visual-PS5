"""A Samba server of the tests' own, run as this user on a free port of 127.0.0.1 (no root):
a guest share, "games", and one only a user with a password opens, "locked", both over the
same folder. Its folders are short paths under /tmp: smbd's sockets live there, and a socket's
path has a length limit the tests' long temporary paths can pass."""
import getpass
import os
from pathlib import Path
import shutil
import signal
import socket
import subprocess
import tempfile
import time

AVAILABLE = bool(shutil.which('smbd') and shutil.which('pdbedit'))
USER = getpass.getuser()
PASSWORD = 'Pa55 word!'


class SambaServer:
    def __init__(self):
        self.home = Path(tempfile.mkdtemp(prefix='smb', dir='/tmp'))
        self.share = self.home / 'share'
        for name in ('lock', 'state', 'cache', 'pid', 'private', 'ncalrpc', 'log', 'share'):
            (self.home / name).mkdir()
        with socket.socket() as probe:
            probe.bind(('127.0.0.1', 0))
            self.port = probe.getsockname()[1]
        home = self.home
        (home / 'smb.conf').write_text(f'''[global]
  smb ports = {self.port}
  bind interfaces only = yes
  interfaces = 127.0.0.1
  lock directory = {home}/lock
  state directory = {home}/state
  cache directory = {home}/cache
  pid directory = {home}/pid
  private dir = {home}/private
  ncalrpc dir = {home}/ncalrpc
  log file = {home}/log/%m.log
  passdb backend = tdbsam:{home}/private/passdb.tdb
  disable netbios = yes
  server min protocol = SMB2
  map to guest = Bad User
  server role = standalone server
  load printers = no
  printcap name = /dev/null
[games]
  path = {self.share}
  guest ok = yes
  read only = yes
[locked]
  path = {self.share}
  valid users = {USER}
  read only = yes
''')
        subprocess.run(['pdbedit', '-s', str(home / 'smb.conf'), '-a', '-u', USER, '-t'],
                       input=f'{PASSWORD}\n{PASSWORD}\n', text=True, check=True, capture_output=True)
        self.start()

    def start(self):
        self.log = (self.home / 'log/smbd.out').open('a')
        self.process = subprocess.Popen(['smbd', '-F', '--no-process-group', '-s', str(self.home / 'smb.conf'),
                                         '--debug-stdout', '-d1'],
                                        stdout=self.log, stderr=subprocess.STDOUT,
                                        # smbd -F stops at the end of its input: this pipe stays open
                                        stdin=subprocess.PIPE, start_new_session=True)
        deadline = time.monotonic() + 15
        while time.monotonic() < deadline:
            try:
                socket.create_connection(('127.0.0.1', self.port), timeout=1).close()
                return
            except OSError:
                if self.process.poll() is not None:
                    break
                time.sleep(0.05)
        output = (self.home / 'log/smbd.out').read_text()[-2000:]
        self.stop()
        raise RuntimeError('smbd did not start:\n' + output)

    def restart(self):
        """The server goes away and comes back: every connection to it is dropped."""
        self.halt()
        self.start()

    @property
    def address(self):
        return f'127.0.0.1:{self.port}'

    def halt(self):
        """smbd serves each connection from a child of its own: the whole group goes."""
        try:
            os.killpg(self.process.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        self.process.wait()
        self.process.stdin.close()
        self.log.close()

    def stop(self):
        self.halt()
        shutil.rmtree(self.home, ignore_errors=True)
