# PS5 OpenGL - OpenGL implementation for PlayStation 5.
# Copyright (C) 2026 BlackBearReloaded
# SPDX-License-Identifier: GPL-3.0-or-later

"""Native titles declare high frame rate when their SDK can present at 120 Hz."""
import importlib
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
METADATA = importlib.import_module("native-display-metadata")


def profile(prefix, fps, modes=False):
    include = prefix / "include"
    include.mkdir(parents=True, exist_ok=True)
    (include / "ps5_opengl_display.h").write_text(
        "#pragma once\n#define PS5_OPENGL_NATIVE_WIDTH 1920\n"
        f"#define PS5_OPENGL_NATIVE_HEIGHT 1080\n#define PS5_OPENGL_NATIVE_FPS {fps}\n")
    if modes:
        (include / "ps5_opengl_display_modes.h").write_text("#pragma once\n")


class DisplayMetadataTest(unittest.TestCase):
    def test_runtime_mode_sdks_declare_high_frame_rate(self):
        with tempfile.TemporaryDirectory() as temp:
            fixed, runtime = Path(temp) / "fixed", Path(temp) / "runtime"
            profile(fixed, 60)
            profile(runtime, 60, modes=True)  # starts at 60 Hz, may switch to 120
            self.assertEqual(METADATA.sdk_presentation_rate(fixed), 60)
            self.assertEqual(METADATA.sdk_presentation_rate(runtime), 120)
            flags = METADATA.with_display_profile({"attribute3": 0x1}, 120)["attribute3"]
            self.assertEqual(flags, 0x1 | METADATA.HFR_FLAGS)
            self.assertEqual(METADATA.with_display_profile({"attribute3": flags}, 60)["attribute3"], 0x1)


if __name__ == "__main__":
    unittest.main()
