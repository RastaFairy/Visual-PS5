#!/usr/bin/env python3
"""XMB playlist icons from the WebUI's system artwork (issue 35).

    python3 tools/xmb-system-icons.py OUT_DIR         write the icons
    python3 tools/xmb-system-icons.py OUT_DIR --sheet SHEET.png   and a contact sheet

XMB shows assets/xmb/<theme>/png/<playlist name>.png on a playlist's tab, and a
playlist is named after its RetroArch database ("Nintendo - Super Nintendo
Entertainment System"). The title's platform table (src/ps5_library.c) ties each
database to a system id, and webui/assets/systems/<id>.webp is that system's artwork
(Linear ES-DE, MIT). Each picture is a controller or console above its logo and year;
XMB prints the name under the icon, so only the hardware is kept: the topmost band of
opaque rows, centred on a square, 256 x 256 (about 256 KiB of texture a tab). Game rows
keep XMB's own content icon: nothing named <playlist>-content.png is written.
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
SIZE = 256
MARGIN = 0.08  # of the icon, on every side
ALPHA = 24  # a pixel at least this opaque is artwork
GAP = 12  # transparent rows (of 800) that end the hardware band


def platforms() -> list[tuple[str, str]]:
    """(system id, database) for every platform that names a database."""
    source = (ROOT / 'src/ps5_library.c').read_text()
    start = source.index('static const struct platform platforms[] = {')
    block = source[start:source.index('\n};', start)]
    found = re.findall(r'\{"([^"]+)",\s*(?:"([^"]+)"|NULL),', block)
    return [(system, database) for system, database in found if database]


def hardware(picture: Image.Image) -> Image.Image:
    """The picture's topmost band of artwork rows: the hardware above its caption."""
    alpha = picture.getchannel('A').point(lambda a: 255 if a >= ALPHA else 0)
    width, height = alpha.size
    rows = [any(alpha.crop((0, y, width, y + 1)).getextrema()[1:]) for y in range(height)]
    top = rows.index(True)
    bottom, blank = top, 0
    for y in range(top, height):
        if rows[y]:
            bottom, blank = y, 0
        else:
            blank += 1
            if blank >= GAP:
                break
    band = alpha.crop((0, top, width, bottom + 1))
    left, _, right, _ = band.getbbox()
    return picture.crop((left, top, right, bottom + 1))


def icon(source: Path) -> Image.Image:
    art = hardware(Image.open(source).convert('RGBA'))
    inner = round(SIZE * (1 - 2 * MARGIN))
    scale = inner / max(art.size)
    art = art.resize((max(1, round(art.width * scale)), max(1, round(art.height * scale))), Image.LANCZOS)
    square = Image.new('RGBA', (SIZE, SIZE), (0, 0, 0, 0))
    square.alpha_composite(art, ((SIZE - art.width) // 2, (SIZE - art.height) // 2))
    return square


def main(argv: list[str]) -> int:
    if not argv or argv[0].startswith('-'):
        print(__doc__.strip().splitlines()[2], file=sys.stderr)
        return 2
    out = Path(argv[0])
    out.mkdir(parents=True, exist_ok=True)
    made = []
    for system, database in platforms():
        source = ROOT / 'webui/assets/systems' / f'{system}.webp'
        if not source.is_file():
            print(f'error: no artwork for {system} ({database})', file=sys.stderr)
            return 1
        picture = icon(source)
        picture.save(out / f'{database}.png', optimize=True)
        made.append((database, picture))
    if '--sheet' in argv:
        columns = 8
        sheet = Image.new('RGBA', (columns * 160, (len(made) + columns - 1) // columns * 160), (24, 18, 40, 255))
        for i, (_, picture) in enumerate(made):
            sheet.alpha_composite(picture.resize((144, 144), Image.LANCZOS), (i % columns * 160 + 8, i // columns * 160 + 8))
        sheet.save(argv[argv.index('--sheet') + 1])
    print(f'==> [xmb] {len(made)} system icons in {out}')
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
