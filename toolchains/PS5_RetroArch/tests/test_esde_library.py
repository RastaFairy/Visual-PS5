"""EmulationStation's systems and game lists from RetroArch's playlists (frontends/es-de/ps5/library_ps5.cpp)."""
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parent.parent
PUGIXML = ROOT / 'build' / 'pugixml-ps5' / 'src' / 'src'


class EsdeLibrary(unittest.TestCase):
    def test_systems_and_game_lists(self):
        if not (PUGIXML / 'pugixml.cpp').is_file():
            self.skipTest('pugixml not fetched (tools/build-pugixml.sh fetches it)')
        with tempfile.TemporaryDirectory() as td:
            objects = []
            for source in ('src/ps5_library.c', 'src/ps5_game.c'):
                obj = str(Path(td) / (Path(source).stem + '.o'))
                subprocess.run(['cc', '-std=c11', '-O2', '-Wall', '-Wextra', '-Werror', '-c', source, '-o', obj],
                               cwd=ROOT, check=True)
                objects.append(obj)
            binary = str(Path(td) / 'esde-library-test')
            subprocess.run(['c++', '-std=c++17', '-O2', '-Wall', '-Wextra', '-Werror', '-Isrc', '-isystem',
                            str(PUGIXML), 'tests/esde_library_test.cpp', 'frontends/es-de/ps5/library_ps5.cpp',
                            str(PUGIXML / 'pugixml.cpp'), *objects, '-o', binary], cwd=ROOT, check=True)
            subprocess.run([binary, td], cwd=ROOT, check=True, timeout=15)


if __name__ == '__main__':
    unittest.main()
