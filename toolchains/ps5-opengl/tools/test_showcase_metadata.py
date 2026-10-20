#!/usr/bin/env python3
# PS5 OpenGL - OpenGL implementation for PlayStation 5.
# Copyright (C) 2026 BlackBearReloaded
# SPDX-License-Identifier: GPL-3.0-or-later

"""The showcase's param.json: the test title's, with its own name and content version."""

import json
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


class ShowcaseMetadata(unittest.TestCase):
    def test_showcase_param_is_the_template_with_its_name_and_version(self):
        template = json.loads((ROOT / "native-app/param.json").read_text())
        showcase = json.loads((ROOT / "examples/core46-showcase/sce_sys/param.json").read_text())
        self.assertEqual(showcase["titleId"], "PPSA99005")
        self.assertEqual(showcase["localizedParameters"]["en-US"]["titleName"], "PS5 OpenGL Showcase")
        # What a console and the homebrew catalog compare: NN.NNN.NNN.
        self.assertRegex(showcase["contentVersion"], re.compile(r"^\d{2}\.\d{3}\.\d{3}$"))
        showcase["localizedParameters"]["en-US"]["titleName"] = template["localizedParameters"]["en-US"]["titleName"]
        showcase["contentVersion"] = template["contentVersion"]
        self.assertEqual(showcase, template)


if __name__ == "__main__":
    unittest.main()
