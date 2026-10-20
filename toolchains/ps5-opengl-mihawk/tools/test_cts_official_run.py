#!/usr/bin/env python3
# PS5 OpenGL - OpenGL implementation for PlayStation 5.
# Copyright (C) 2026 BlackBearReloaded
# SPDX-License-Identifier: GPL-3.0-or-later

import gzip
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

TOOLS = Path(__file__).resolve().parent
EXPORT = TOOLS / "export-cts-official-run.py"
VERIFY = TOOLS / "verify-cts-official-run.py"


def log(cases):
    lines = []
    for name, (status, why) in cases.items():
        lines += [f"#beginTestCaseResult {name}",
                  f'<TestCaseResult><Result StatusCode="{status}">{why}</Result></TestCaseResult>',
                  "#endTestCaseResult"]
    return "\n".join(lines) + "\n"


class OfficialRunTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        root = Path(self.temporary.name)
        self.run = root / "run"
        self.mustpass = root / "dist"
        self.evidence = root / "2026-01-01-gl46-conformance"
        (self.run / "plan").mkdir(parents=True)
        self.mustpass.mkdir()
        (root / "eboot.bin").write_bytes(b"test binary")
        self.eboot = root / "eboot.bin"
        (self.mustpass / "a.txt").write_text("KHR-GL46.a.one\nKHR-GL46.sparse_buffer_tests.x\n")
        (self.mustpass / "b.txt").write_text("KHR-GL46.b.one\n")
        (self.mustpass / "c.txt").write_text("KHR-NoContext.c.one\nKHR-NoContext.c.two\n")
        (self.run / "plan" / "cts-run-summary.xml").write_text(
            '<?xml version="1.0"?><Summary Type="gl46" Conformant="False">'
            '<TestRun FileName="config-a.qpa" CmdLine="--deqp-caselist-file=a.txt --deqp-surface-width=64"/>'
            '<TestRun FileName="config-b.qpa" CmdLine="--deqp-caselist-file=b.txt"/>'
            '<TestRun FileName="config-c.qpa" CmdLine="--deqp-caselist-file=c.txt"/></Summary>')
        self.write("config-a.qpa", {
            "KHR-GL46.a.one": ("Fail", "first attempt"),
            "KHR-GL46.sparse_buffer_tests.x": ("NotSupported", "GL_ARB_sparse_buffer is not supported")})
        # A resumed part supersedes the earlier result of the same case.
        self.write("config-a.qpa.resume", {"KHR-GL46.a.one": ("Pass", "Pass")})
        self.write("config-b.qpa", {"KHR-GL46.b.one": ("CompatibilityWarning", "legal")})
        # The runner skips a case that insists on a window surface.
        self.write("config-c.qpa", {
            "KHR-NoContext.c.one": ("NotSupported", "Test not supported in non-windowed context"),
            "KHR-NoContext.c.two": ("Pass", "Pass")})
        for name in ("config-a.qpa.resume.status", "config-b.qpa.status", "config-c.qpa.status"):
            (self.run / name).write_text("done\n")
        # The supplementary run of that session with an offscreen surface as the window.
        self.window = root / "window"
        (self.window / "plan").mkdir(parents=True)
        (self.window / "plan" / "cts-run-summary.xml").write_text(
            (self.run / "plan" / "cts-run-summary.xml").read_text())
        self.write_window({"KHR-NoContext.c.one": ("Pass", "Pass"), "KHR-NoContext.c.two": ("Pass", "Pass")})
        (self.window / "config-c.qpa.status").write_text("done\n")

    def tearDown(self):
        self.temporary.cleanup()

    def write(self, name, cases):
        (self.run / name).write_text(log(cases))

    def write_window(self, cases):
        (self.window / "config-c.qpa").write_text(log(cases))

    def export(self, window=False):
        return subprocess.run(
            [sys.executable, str(EXPORT), str(self.run), str(self.evidence), "--mustpass",
             str(self.mustpass), "--commit", "0123abc", "--eboot", str(self.eboot),
             "--cts", "opengl-cts-test", "--date", "2026-01-01"] +
            (["--window-run", str(self.window)] if window else []), capture_output=True, text=True)

    def verify(self):
        return subprocess.run([sys.executable, str(VERIFY), str(self.evidence)],
                              capture_output=True, text=True)

    def test_export_and_verify(self):
        result = self.export()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        result = self.verify()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("5 results in 3 sessions, 2 Pass, 2 justified NotSupported, 1 warnings", result.stdout)
        readme = (self.evidence / "README.md").read_text()
        self.assertIn("**5 results in 3 sessions: 2 Pass, 2 NotSupported, 1 warnings, 0 failures.**", readme)
        self.assertNotIn("window", readme)
        # A changed result no longer matches the checksums.
        with gzip.open(self.evidence / "cases.csv.gz", "wt") as stream:
            stream.write("session,case,status\nconfig-a.qpa,KHR-GL46.a.one,Pass\n")
        self.assertNotEqual(self.verify().returncode, 0)

    def test_window_run(self):
        result = self.export(window=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        result = self.verify()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("window run 2 Pass", result.stdout)
        readme = (self.evidence / "README.md").read_text()
        self.assertIn("The 1 surface-type results", readme)
        self.assertIn("all 2 cases of those sessions pass", readme)
        # The window results are part of the checked evidence.
        cases = self.evidence / "window-surface-cases.csv"
        cases.write_text(cases.read_text().replace("KHR-NoContext.c.one", "KHR-NoContext.c.other"))
        self.assertNotEqual(self.verify().returncode, 0)

    def test_window_run_must_pass_and_cover(self):
        self.write_window({"KHR-NoContext.c.one": ("Fail", "Fail"), "KHR-NoContext.c.two": ("Pass", "Pass")})
        result = self.export(window=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("KHR-NoContext.c.one is Fail", result.stderr)
        self.write_window({"KHR-NoContext.c.two": ("Pass", "Pass")})
        result = self.export(window=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("surface-type cases were not run", result.stderr)

    def test_refuses_failures(self):
        self.write("config-a.qpa.resume", {"KHR-GL46.a.one": ("Fail", "still failing")})
        result = self.export()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("not accepted", result.stderr)

    def test_refuses_missing_and_unfinished(self):
        self.write("config-b.qpa", {})
        result = self.export()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("without a result", result.stderr)
        self.write("config-b.qpa", {"KHR-GL46.b.one": ("Pass", "Pass")})
        (self.run / "config-b.qpa.status").unlink()
        result = self.export()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("not complete", result.stderr)

    def test_refuses_unjustified_notsupported(self):
        self.write("config-b.qpa", {"KHR-GL46.b.one": ("NotSupported", "something is missing")})
        result = self.export()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("not justified", result.stderr)


if __name__ == "__main__":
    unittest.main()
