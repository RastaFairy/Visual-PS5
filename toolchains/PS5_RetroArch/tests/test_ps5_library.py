"""The game library every frontend shows (src/ps5_library.c): RetroArch's playlists and core info, on the host."""
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parent.parent


class Ps5Library(unittest.TestCase):
    def test_library(self):
        with tempfile.TemporaryDirectory() as td:
            binary = str(Path(td) / 'ps5-library-test')
            subprocess.run(['cc', '-std=c11', '-O2', '-Wall', '-Wextra', '-Werror', 'tests/ps5_library_test.c',
                            'src/ps5_library.c', 'src/ps5_game.c', '-o', binary], cwd=ROOT, check=True)
            subprocess.run([binary, td], cwd=ROOT, check=True, timeout=15)


if __name__ == '__main__':
    unittest.main()
