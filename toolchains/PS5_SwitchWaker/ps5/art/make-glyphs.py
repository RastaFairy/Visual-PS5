#!/usr/bin/env python3
# Wind Waker for the PlayStation 5 - the DualSense's symbols for the game's button prompts.
# SPDX-License-Identifier: MIT
"""Makes ps5/art/glyphs/*.png: replacement textures for the game's button prompts.

The game draws a button as a coloured shape with a white letter over it, each letter a small
texture of its own. Aurora replaces a texture by a file named after it (Dolphin's scheme:
tex1_<width>x<height>_<hash of its texels>[_<hash of its palette>]_<format>.png), so each
picture here carries the name of what it stands in for and nothing of it: a cross for A, a
square for B, a circle for X and a triangle for Y, as the port's mapping has them (A south,
B west, X east, Y north: where the GameCube pad has them around A), "R2" for R, and for Z, whose button is one picture with its letter,
a button drawn here that says "R1". The C stick's picture (a yellow knob beside an eye) becomes
Kenney's right stick beside an eye drawn here. The A button's green face becomes a blue one, drawn here:
a cross belongs on blue. The names are the GameCube USA disc's (GZLE01), read from a texture
dump (COS_TEXTURE_DUMPS=1).

The symbols are Kenney's Input Prompts (www.kenney.nl, CC0: ps5/art/kenney/): of each of its
outlined buttons the outline is dropped, since the game draws the button itself, and what is
inside is kept.

Needs Python with Pillow.
"""
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

SCALE = 4  # the replacement is this many times the original's size
art = Path(__file__).resolve().parent
out = art / "glyphs"
out.mkdir(exist_ok=True)
for old in out.glob("*.png"):
    old.unlink()


def inside(source):
    """The picture without its outline: the connected shape with the largest bounds goes."""
    alpha = Image.open(art / "kenney" / (source + ".png")).convert("RGBA").getchannel("A")
    w, h = alpha.size
    values = list(alpha.tobytes())
    solid = [v > 40 for v in values]
    label = [0] * (w * h)
    shapes = []  # (bounds' area, label)
    for start in range(w * h):
        if not solid[start] or label[start]:
            continue
        n = len(shapes) + 1
        label[start] = n
        stack = [start]
        x0 = x1 = start % w
        y0 = y1 = start // w
        while stack:
            p = stack.pop()
            x, y = p % w, p // w
            x0, x1, y0, y1 = min(x0, x), max(x1, x), min(y0, y), max(y1, y)
            for q in (p - 1 if x else -1, p + 1 if x < w - 1 else -1, p - w, p + w):
                if 0 <= q < w * h and solid[q] and not label[q]:
                    label[q] = n
                    stack.append(q)
        shapes.append(((x1 - x0) * (y1 - y0), n))
    outline = max(shapes)[1]
    keep = Image.frombytes("L", (w, h), bytes(a if solid[i] and label[i] != outline else 0 for i, a in enumerate(values)))
    return keep.crop(keep.getbbox())


def glyph(name, w, h, source, fill=0.8):
    symbol = inside(source)
    box = (w * SCALE * fill, h * SCALE * fill)
    k = min(box[0] / symbol.width, box[1] / symbol.height)
    symbol = symbol.resize((max(1, round(symbol.width * k)), max(1, round(symbol.height * k))), Image.LANCZOS)
    mask = Image.new("L", (w * SCALE, h * SCALE), 0)
    mask.paste(symbol, ((mask.width - symbol.width) // 2, (mask.height - symbol.height) // 2))
    # the game draws these about 30 pixels high at 1080p: Kenney's strokes are thin for that
    mask = mask.filter(ImageFilter.MaxFilter(5))
    white = Image.new("RGBA", mask.size, (255, 255, 255, 0))
    white.putalpha(mask)
    white.save(out / (name + ".png"))


def fitted(source, w, h):
    symbol = inside(source)
    k = min(w / symbol.width, h / symbol.height)
    return symbol.resize((max(1, round(symbol.width * k)), max(1, round(symbol.height * k))), Image.LANCZOS)


def z_button(name, w, h):
    """The Z button whole: a rounded purple button with a light rim, and R1 on it."""
    W, H = w * SCALE, h * SCALE
    picture = Image.new("RGBA", (W * 2, H * 2), (0, 0, 0, 0))
    draw = ImageDraw.Draw(picture)
    draw.rounded_rectangle([6, 14, W * 2 - 7, H * 2 - 15], radius=40, fill=(226, 208, 255, 255))
    draw.rounded_rectangle([18, 26, W * 2 - 19, H * 2 - 27], radius=30, fill=(126, 62, 214, 255))
    picture = picture.resize((W, H), Image.LANCZOS)
    symbol = fitted("playstation_trigger_r1_outline", W * 0.62, H * 0.5)
    white = Image.new("RGBA", symbol.size, (255, 255, 255, 255))
    picture.paste(white, ((W - symbol.width) // 2, (H - symbol.height) // 2), symbol)
    picture.save(out / (name + ".png"))


def face(name, size, colour, rim):
    """A button's round face: a flat disc with a lighter rim, as the game's are shaped."""
    S = size * SCALE
    picture = Image.new("RGBA", (S * 2, S * 2), (0, 0, 0, 0))
    draw = ImageDraw.Draw(picture)
    draw.ellipse([4, 4, S * 2 - 5, S * 2 - 5], fill=rim + (255,))
    draw.ellipse([20, 20, S * 2 - 21, S * 2 - 21], fill=colour + (255,))
    picture.resize((S, S), Image.LANCZOS).save(out / (name + ".png"))


def stick_and_eye(name, w, h):
    """The C stick's prompt, 128x32: a knob at x 27..52 and an eye at x 55..95, both y 0..25."""
    picture = Image.new("RGBA", (w * SCALE * 2, h * SCALE * 2), (0, 0, 0, 0))
    k = SCALE * 2
    stick = Image.open(art / "kenney" / "playstation_stick_r.png").convert("RGBA")
    stick = stick.crop(stick.getbbox()).resize((26 * k, 26 * k), Image.LANCZOS)
    # dark behind it, as the game's own has: the prompt sits over sky and sea
    shadow = Image.new("RGBA", stick.size, (20, 20, 30, 255))
    back = stick.getchannel("A").filter(ImageFilter.MaxFilter(9))
    picture.paste(shadow, (27 * k, 0), back)
    picture.alpha_composite(stick, (27 * k, 0))
    draw = ImageDraw.Draw(picture)
    cx, cy = 75 * k, 13 * k
    rx, ry = 20 * k, 10 * k
    eye = [(cx - rx, cy), (cx - rx // 2, cy - ry * 8 // 10), (cx, cy - ry), (cx + rx // 2, cy - ry * 8 // 10),
           (cx + rx, cy), (cx + rx // 2, cy + ry * 8 // 10), (cx, cy + ry), (cx - rx // 2, cy + ry * 8 // 10)]
    draw.polygon(eye, fill=(255, 255, 255, 255), outline=(20, 20, 30, 255), width=k)
    draw.ellipse([cx - 7 * k, cy - 7 * k, cx + 7 * k, cy + 7 * k], fill=(20, 20, 30, 255))
    picture.resize((w * SCALE, h * SCALE), Image.LANCZOS).save(out / (name + ".png"))


glyph("tex1_16x16_f2ecddd16b5f554a_0", 16, 16, "playstation_button_cross_outline")     # A
glyph("tex1_16x16_0bbde935468955d4_0", 16, 16, "playstation_button_square_outline")    # B
glyph("tex1_16x16_a954694dda754d44_0", 16, 16, "playstation_button_circle_outline")    # X
glyph("tex1_16x16_c78319a187997148_0", 16, 16, "playstation_button_triangle_outline")  # Y
glyph("tex1_16x16_fd8f1a5a26d95e59_0", 16, 16, "playstation_trigger_r2_outline", 1.0)  # R
z_button("tex1_48x24_c07e25b9bca86b7e_ce3f64d5da874475_8", 48, 24)                     # Z
face("tex1_40x40_08daf72f6acc9478_1acd6c849fcbc8cc_9", 40, (58, 110, 226), (170, 200, 255))  # A's face
stick_and_eye("tex1_128x32_523124ff1f96d4bc_e7820c87ebbc4db4_9", 128, 32)             # C stick
print(sorted(p.name for p in out.glob("*.png")))
