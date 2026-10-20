"""EmulationStation's FreeImage functions over stb_image and libwebp (frontends/es-de/ps5):
FreeImage's layout, conversions, rescaling, saving, a GIF's frames with their times and a WebP."""
from pathlib import Path
import base64
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parent.parent
STB = ROOT / '.deps' / 'stb-2c980bb59875b0d32144a71867fbdebb2f77cd20'
PNG = ROOT / 'assets' / 'readme' / 'webui-overview.png'
# Two 8x8 frames, red then blue, 200 ms each (ImageMagick: -set delay 20).
# Lossless 3x2 (Pillow): red, green, blue; white at half alpha, clear, (10, 20, 30).
SMALL_WEBP = base64.b64decode('UklGRkAAAABXRUJQVlA4TDQAAAAvAkAAEC8gECCI8J9qQ0iQ0P2/V4EAQYn/SgSSNjYfT/4A8CfHXhUUpG3A4u4pWUT/4+oA')
TWO_FRAMES = base64.b64decode('R0lGODlhCAAIAPAAAP8AAAAAACH/C05FVFNDQVBFMi4wAwEAAAAh+QQAFAAAACwAAAAACAAIAAACB4SPqcvtXQAAIfkEABQAAAAsAAAAAAgACACAAAD/AAAAAgeEj6nL7V0AADs=')


class EsdeFreeImage(unittest.TestCase):
    def test_layout_conversions_and_gif(self):
        if not (STB / 'stb_image_resize2.h').is_file():
            self.skipTest('stb headers not fetched (tools/build-esde.sh fetches them)')
        if not Path('/usr/include/webp/decode.h').is_file():
            self.skipTest("libwebp's headers are not installed on this host")
        with tempfile.TemporaryDirectory() as td:
            gif = Path(td) / 'two.gif'
            gif.write_bytes(TWO_FRAMES)
            webp = Path(td) / 'small.webp'
            webp.write_bytes(SMALL_WEBP)
            binary = str(Path(td) / 'freeimage-test')
            subprocess.run(['c++', '-std=c++17', '-O1', '-Wall', '-Wextra', '-Werror',
                            '-Ifrontends/es-de/ps5/include', '-isystem', str(STB),
                            'tests/esde_freeimage_test.cpp', '-o', binary, '-lwebp'], cwd=ROOT, check=True)
            subprocess.run([binary, td, str(PNG), str(gif), str(webp)], cwd=ROOT, check=True, timeout=60)


if __name__ == '__main__':
    unittest.main()
