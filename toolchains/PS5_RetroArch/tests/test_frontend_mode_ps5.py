"""Which frontend a launch of eboot.bin starts (src/frontend_mode_ps5.cpp), against a mocked LoadExec."""
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parent.parent


class FrontendModePs5(unittest.TestCase):
    def test_decisions_and_launches(self):
        with tempfile.TemporaryDirectory() as td:
            binary = str(Path(td) / 'frontend-mode-test')
            # Game mode's contract (src/ps5_game.c) is C, with its cores folder in the scratch folder.
            defines = [f'-DPS5_GAME_CORES="{td}/cores/"']
            contract = str(Path(td) / 'ps5_game.o')
            library = str(Path(td) / 'ps5_library.o')
            subprocess.run(['cc', '-std=c11', '-O2', '-Wall', '-Wextra', '-Werror', *defines, '-c',
                            'src/ps5_game.c', '-o', contract], cwd=ROOT, check=True)
            subprocess.run(['cc', '-std=c11', '-O2', '-Wall', '-Wextra', '-Werror', '-c',
                            'src/ps5_library.c', '-o', library], cwd=ROOT, check=True)
            subprocess.run(['c++', '-std=c++17', '-O2', '-Wall', '-Wextra', '-Werror', '-Isrc', *defines,
                            'tests/frontend_mode_ps5_test.cpp', contract, library, '-o', binary], cwd=ROOT,
                           check=True)
            subprocess.run([binary, td], cwd=ROOT, check=True, timeout=15)


if __name__ == '__main__':
    unittest.main()
