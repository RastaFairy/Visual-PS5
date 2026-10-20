"""Run the relaunch test's chain against a mocked LoadExec, then read its record as JSON."""
from pathlib import Path
import json
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parent.parent


class RelaunchPs5(unittest.TestCase):
    def test_chain_and_record(self):
        with tempfile.TemporaryDirectory() as td:
            binary = str(Path(td) / 'relaunch-test')
            subprocess.run(['c++', '-std=c++17', '-O2', '-Wall', '-Wextra', '-Werror', '-Isrc',
                            'tests/relaunch_ps5_test.cpp', '-o', binary], cwd=ROOT, check=True)
            subprocess.run([binary, td], cwd=ROOT, check=True, timeout=15)
            rows = [json.loads(line) for line in (Path(td) / 'relaunch-test.jsonl').read_text().splitlines()]
            chain = [row for row in rows if row['run'] == 'chain-1']
            self.assertEqual([row['generation'] for row in chain], [0, 1, 2, 3])
            self.assertEqual([row['action'] for row in chain], ['restart'] * 3 + ['continue'])
            escaped = next(row for row in rows if row['run'] == 'escaped')
            self.assertEqual(escaped['argv'], ['eboot', 'quote"back\\slash', 'tab\there'])


if __name__ == '__main__':
    unittest.main()
