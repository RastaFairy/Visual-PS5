#!/usr/bin/env python3
# PS5 OpenGL - OpenGL implementation for PlayStation 5.
# Copyright (C) 2026 BlackBearReloaded
# SPDX-License-Identifier: GPL-3.0-or-later

import importlib.util
import tempfile
import unittest
from pathlib import Path

spec = importlib.util.spec_from_file_location(
    "notsupported", Path(__file__).with_name("cts-notsupported-report.py"))
notsupported = importlib.util.module_from_spec(spec)
spec.loader.exec_module(notsupported)


def log(cases):
    lines = []
    for name, (status, why) in cases.items():
        lines += [f"#beginTestCaseResult {name}",
                  f'<TestCaseResult><Result StatusCode="{status}">{why}</Result></TestCaseResult>',
                  "#endTestCaseResult"]
    return "\n".join(lines) + "\n"


class NotSupportedReportTest(unittest.TestCase):
    def run_report(self, files):
        with tempfile.TemporaryDirectory() as temporary:
            run = Path(temporary) / "run"
            run.mkdir()
            for name, cases in files.items():
                (run / name).write_text(log(cases))
            return notsupported.report(run), notsupported

    def test_classes_and_resume_override(self):
        data, module = self.run_report({
            "config-a.qpa": {
                "KHR-GL46.sparse_buffer_tests.x": ("NotSupported", "GL_ARB_sparse_buffer is not supported"),
                "KHR-GL46.texture_swizzle.functional_format_idx_3_target_idx_5":
                    ("NotSupported", "Target not supported"),
                "KHR-GL46.texture_swizzle.functional_format_idx_63_target_idx_2":
                    ("NotSupported", "Target not supported"),
                "KHR-GL46.sample_variables.mask.x": ("NotSupported", "Test sample count greater than MAX_SAMPLES"),
                "KHR-NoContext.gl43.khr_debug.groups":
                    ("NotSupported", "Test not supported in non-windowed context"),
                "KHR-GL46.some.case": ("Fail", "broken"),
            },
            # A resumed session's later log replaces the earlier result.
            "config-a.qpa.resume": {"KHR-GL46.some.case": ("Pass", "Pass")},
            "config-a.qpa.resume.status": {},
        })
        self.assertEqual(data["unclassified"], [])
        session = data["sessions"]["config-a"]
        self.assertEqual(session["results"], {"NotSupported": 5, "Pass": 1})
        self.assertEqual(session["not_supported"], {
            "not-applicable": 2, "optional-extension": 1, "sample-count": 1, "surface-type": 1})
        self.assertIn("| `config-a` | 1 | 5 | 0 |", module.markdown(data))

    def test_unknown_reason_is_not_defaulted(self):
        data, _ = self.run_report({"config-b.qpa": {
            # A real capability gap must not hide behind a similar-looking rule.
            "KHR-GL46.texture_swizzle.functional_format_idx_3_target_idx_7":
                ("NotSupported", "Target not supported"),
            "KHR-GL46.shader_storage_buffer_object.basic":
                ("NotSupported", "Required 1 VS storage blocks but only 0 available."),
            "KHR-GL46.cull_distance.functional_test_item_8_primitive_mode_points_max_culldist_0":
                ("NotSupported", "Not supported"),
        }})
        self.assertEqual(len(data["unclassified"]), 3)
        self.assertEqual(data["rules"], {})


if __name__ == "__main__":
    unittest.main()
