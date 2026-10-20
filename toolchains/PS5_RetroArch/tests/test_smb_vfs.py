"""smb:// paths in RetroArch's VFS (src/ps5_smb_vfs.c) against a Samba server of the test's
own (tests/smb_server.py), signed in with a password: tests/smb_vfs_test.c lists, stats,
reads, seeks and stages a 24 MiB file, and reads on after the server restarts."""
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parent))
import smb_server  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent


@unittest.skipUnless(smb_server.AVAILABLE, 'smbd and pdbedit (Samba) are not installed')
class SmbVfs(unittest.TestCase):
    def test_vfs_against_samba(self):
        samba = smb_server.SambaServer()
        try:
            games = samba.share / 'Games'
            (games / 'Homebrew').mkdir(parents=True)
            size = 24 << 20
            data = bytes(((i * 2654435761) >> 13) & 255 for i in range(size))
            (games / 'demo game.bin').write_bytes(data)
            with tempfile.TemporaryDirectory() as temp:
                temp = Path(temp)
                config = temp / 'smb.cfg'
                config.write_text(f'smb_server = "{samba.address}"\nsmb_share = "locked"\nsmb_folder = ""\n'
                                  f'smb_user = "{smb_server.USER}"\nsmb_password = "{smb_server.PASSWORD}"\n')
                (temp / 'cache').mkdir()
                smb2 = subprocess.check_output(['bash', 'tools/build-libsmb2.sh', 'host'], cwd=ROOT,
                                               text=True).strip()
                binary = temp / 'smb-vfs'
                subprocess.run(['cc', '-std=c11', '-D_DEFAULT_SOURCE', '-O1', '-g', '-Wall', '-Wextra', '-Werror',
                                f'-DPS5_SMB_CONFIG="{config}"', f'-I{smb2}/include',
                                '-Ivendor/retroarch/libretro-common/include', 'tests/smb_vfs_test.c',
                                'src/ps5_smb_vfs.c', 'src/ps5_smb.c', f'{smb2}/lib/libsmb2.a', '-lpthread',
                                '-o', str(binary)], cwd=ROOT, check=True)
                read, back = temp / 'read', temp / 'back'
                run = subprocess.Popen([str(binary), samba.address, str(temp / 'cache'), str(read), str(back)],
                                       stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
                deadline = time.monotonic() + 120
                while not read.exists() and run.poll() is None and time.monotonic() < deadline:
                    time.sleep(0.02)
                samba.restart()
                back.touch()
                output = run.communicate(timeout=120)[0]
                self.assertEqual(run.returncode, 0, output)
                self.assertIn('PASS', output)
                self.assertIn('[SMB] reconnected to locked', output)
        finally:
            samba.stop()


if __name__ == '__main__':
    unittest.main()
