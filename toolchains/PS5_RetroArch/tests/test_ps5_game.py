"""Game mode's contract (src/ps5_game.c), shared by eboot.bin and every frontend, on the host."""
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parent.parent


class Ps5Game(unittest.TestCase):
    def test_contract(self):
        with tempfile.TemporaryDirectory() as td:
            binary = str(Path(td) / 'ps5-game-test')
            defines = [f'-DPS5_GAME_CORES="{td}/cores/"', f'-DPS5_GAME_REQUEST_PATH="{td}/game-request.txt"',
                       f'-DPS5_GAME_RESULT_PATH="{td}/game-result.txt"']
            subprocess.run(['cc', '-std=c11', '-O2', '-Wall', '-Wextra', '-Werror', *defines,
                            'tests/ps5_game_test.c', 'src/ps5_library.c', '-o', binary], cwd=ROOT, check=True)
            subprocess.run([binary, td], cwd=ROOT, check=True, timeout=15)


if __name__ == '__main__':
    unittest.main()
