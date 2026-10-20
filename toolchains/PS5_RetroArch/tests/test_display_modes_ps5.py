"""The display modes test's pattern, record and unarmed path; with PS5_WSI_MODES_ICD naming a
host build of RADV with the VideoOut WSI (its loader manifest), also an armed run on it."""
from pathlib import Path
import json
import os
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parent.parent


class DisplayModesPs5(unittest.TestCase):
    def test_pattern_record_and_armed_run(self):
        if not any(Path(p).exists() for p in ('/usr/lib/libvulkan.so', '/usr/lib64/libvulkan.so',
                                              '/usr/lib/x86_64-linux-gnu/libvulkan.so')):
            self.skipTest('no Vulkan loader on this host')
        with tempfile.TemporaryDirectory() as td:
            binary = str(Path(td) / 'display-modes-test')
            subprocess.run(['c++', '-std=c++17', '-O1', '-Wall', '-Wextra', '-Werror', '-Ivendor/retroarch',
                            'tests/display_modes_ps5_test.cpp', '-lvulkan', '-o', binary], cwd=ROOT, check=True)
            subprocess.run([binary, td], cwd=ROOT, check=True, timeout=30)
            icd = os.environ.get('PS5_WSI_MODES_ICD')
            if not icd:
                return
            env = dict(os.environ, VK_DRIVER_FILES=icd, VK_LOADER_LAYERS_DISABLE='~all~')
            subprocess.run([binary, td, 'armed'], cwd=ROOT, check=True, timeout=300, env=env)
            rows = [json.loads(line) for line in (Path(td) / 'display-modes-test.jsonl').read_text().splitlines()]
            self.assertEqual(rows[-1], {'result': 'PASS'})
            sizes = [(row['width'], row['height']) for row in rows[:-1]]
            self.assertIn((1920, 1080), sizes)
            self.assertEqual(sizes[0], sizes[-1])
            shutil.rmtree(td, ignore_errors=True)


if __name__ == '__main__':
    unittest.main()
