#!/usr/bin/env python3
# Copyright (C) 2026 Mihawk-99
# SPDX-License-Identifier: GPL-3.0-or-later
"""Build self-contained SVG decorations; screenshot bytes stay unchanged."""
import base64
from pathlib import Path
import random
from xml.etree import ElementTree as ET

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / 'assets/readme'


def sky(width, height, seed):
    rng = random.Random(seed)
    stars = ''.join(
        f'<circle cx="{rng.uniform(0, width):.1f}" cy="{rng.uniform(0, height):.1f}" '
        f'r="{rng.uniform(.5, 1.4):.1f}" fill="#e3d6ff" '
        f'opacity="{rng.uniform(.2, .65):.2f}"/>' for _ in range(200)
    )
    return f'''<defs>
<linearGradient id="sky" x2="1" y2=".7"><stop stop-color="#080512"/><stop offset=".55" stop-color="#19102f"/><stop offset="1" stop-color="#342047"/></linearGradient>
<radialGradient id="glow"><stop stop-color="#944acc" stop-opacity=".38"/><stop offset="1" stop-color="#944acc" stop-opacity="0"/></radialGradient>
<linearGradient id="rim"><stop stop-color="#765bad"/><stop offset=".6" stop-color="#aa71c3"/><stop offset="1" stop-color="#d18ebe"/></linearGradient>
</defs>
<rect width="{width}" height="{height}" rx="18" fill="url(#sky)"/>
<ellipse cx="{width * .8}" cy="{height * .75}" rx="{width * .6}" ry="{height * .9}" fill="url(#glow)"/>
{stars}'''


def save(name, width, height, body, title):
    svg = f'''<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" viewBox="0 0 {width} {height}" role="img" aria-labelledby="title">
<title id="title">{title}</title>
{body}
</svg>'''
    ET.fromstring(svg)
    (OUT / name).write_text(svg + '\n')


def frame(source, name, width, height, mime):
    padding = round(width * .028)
    outer_width, outer_height = width + padding * 2, height + padding * 2
    data = base64.b64encode((ROOT / source).read_bytes()).decode('ascii')
    body = sky(outer_width, outer_height, 20261008)
    body += f'''<rect x="{padding - 2}" y="{padding - 2}" width="{width + 4}" height="{height + 4}" rx="2" fill="url(#rim)"/>
<image x="{padding}" y="{padding}" width="{width}" height="{height}" href="data:{mime};base64,{data}"/>
'''
    save(name, outer_width, outer_height, body, 'Original PS5 RetroArch screenshot in a galaxy frame')
    # Validate the embedded screenshot, rather than re-encoding or altering it.
    embedded = ET.parse(OUT / name).find('{http://www.w3.org/2000/svg}image')
    assert base64.b64decode(embedded.attrib['href'].split(',', 1)[1]) == (ROOT / source).read_bytes()


if __name__ == '__main__':
    frame('assets/releases/v1.0.0-beta.1/webui-games-neogeo-b.jpg',
          'galaxy-games.svg', 1264, 1951, 'image/jpeg')
    frame('assets/readme/pre-screen.png', 'galaxy-frontends.svg', 1920, 1080, 'image/png')
    save('starfield-section.svg', 1600, 72, sky(1600, 72, 20261009), 'Subtle violet starfield')
    print('README artwork: two frames verified byte-for-byte; section accent generated')
