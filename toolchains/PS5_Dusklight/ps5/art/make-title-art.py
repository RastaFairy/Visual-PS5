#!/usr/bin/env python3
# Dusklight for the PlayStation 5 - the title's pictures, drawn here.
#
#   python3 ps5/art/make-title-art.py OUTPUT_DIR
#
# Writes icon0.png (512x512) from icon0-source.png, and pic0.png and pic1.png
# (3840x2160, the same picture) from pic-source.jpg: a young swordsman and a black
# wolf split by a seam of twilight, over carved stone, made for this port by Gary
# Riches with an image generator; nothing in them is from the game.
# tools/png-to-title-dds.py turns pic0.png into sce_sys/pic0.dds, and pic1.dds is
# a copy of it.
#
# Writes res/ too: the pictures the game's menus load, drawn by this script (a
# dusk sky over hills), to go over Dusklight's own in a title (ps5/art/res/ holds
# them, and tools/link-title.sh lays them in).
#
# Nothing in res/ is Nintendo's. Of Dusklight's own artwork only the lettering of
# res/logo.png is used: its mascot, its application icon, its organisation icon
# and its pre-launch background all depict the game (a character, the Triforce,
# a screenshot) and stay out of the title. The lettering is cut from the logo
# by colour, which leaves the mascot beside it behind.
#
# SPDX-License-Identifier: MIT
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter

ROOT = Path(__file__).resolve().parents[2]
DUSKLIGHT = ROOT / "vendor/dusklight"


def scene(width: int, height: int, seed: int = 7) -> Image.Image:
    """A sky from indigo to amber, a low sun, stars and four ridges of hills."""
    rng = np.random.default_rng(seed)
    y = np.linspace(0.0, 1.0, height)[:, None]
    x = np.linspace(0.0, 1.0, width)[None, :]
    aspect = width / height
    stops = [(0.00, (14, 12, 40)), (0.35, (46, 30, 86)), (0.58, (150, 64, 92)),
             (0.72, (236, 132, 62)), (0.82, (255, 196, 110)), (1.00, (255, 214, 140))]
    sky = np.zeros((height, width, 3))
    for channel in range(3):
        sky[..., channel] = np.interp(y, [s[0] for s in stops], [s[1][channel] for s in stops])
    # the sun and its glow
    sun_x, sun_y = 0.68, 0.70
    distance = np.hypot((x - sun_x) * aspect, y - sun_y)
    glow = np.exp(-(distance / 0.22) ** 2)[..., None]
    sky += glow * np.array([70, 60, 30])
    disc = np.clip((0.045 - distance) / 0.004, 0, 1)[..., None]
    sky = sky * (1 - disc) + disc * np.array([255, 244, 214])
    # stars, in the dark of the sky only
    stars = (rng.random((height, width)) > 0.99985).astype(float)
    stars = np.asarray(Image.fromarray((stars * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(width / 2600)),
                       dtype=float) / 255.0 * 6
    sky += (np.clip(stars, 0, 1) * np.clip(1 - y / 0.45, 0, 1))[..., None] * 255
    # ridges, far to near: each a sum of sines, darker and lower than the one before
    columns = np.linspace(0, 1, width)
    for base, amplitude, colour in ((0.74, 0.050, (120, 62, 92)), (0.80, 0.045, (78, 40, 76)),
                                    (0.87, 0.040, (40, 22, 52)), (0.94, 0.030, (14, 10, 26))):
        ridge = np.full(width, base)
        for octave in range(1, 7):
            ridge += amplitude / octave * np.sin(columns * np.pi * 2 * octave * rng.uniform(0.8, 1.9) + rng.uniform(0, 6.3))
        edge = np.clip((y - ridge[None, :]) * height / 2.0, 0, 1)[..., None]
        sky = sky * (1 - edge) + edge * np.array(colour)
    # a vignette
    sky *= (1 - 0.35 * np.clip(np.hypot((x - 0.5) * 1.1, (y - 0.5) * 1.1) - 0.35, 0, 1) ** 1.5)[..., None]
    return Image.fromarray(np.clip(sky, 0, 255).astype(np.uint8), "RGB")


def wordmark() -> Image.Image:
    """The letters of res/logo.png: its warm pixels, right of the mascot."""
    logo = np.asarray(Image.open(DUSKLIGHT / "res/logo.png").convert("RGBA")).astype(float)
    r, g, b, a = (logo[..., i] for i in range(4))
    warm = (r > 150) & (g > 50) & (b < 150) & (r > b + 60)
    keep = np.where(warm, a, 0.0)
    keep[:, :362] = 0          # the mascot
    keep[100:400, :398] = 0    # and what of it overlaps the D, between the D's serifs
    letters = np.dstack([r, g, b, keep]).astype(np.uint8)
    image = Image.fromarray(letters, "RGBA")
    return image.crop(image.getbbox())


def with_shadow(mark: Image.Image, blur: float, opacity: float) -> Image.Image:
    pad = int(blur * 4)
    canvas = Image.new("RGBA", (mark.width + pad * 2, mark.height + pad * 2), (0, 0, 0, 0))
    alpha = Image.new("L", canvas.size, 0)
    alpha.paste(mark.getchannel("A"), (pad, pad + int(blur * 0.6)))
    alpha = alpha.filter(ImageFilter.GaussianBlur(blur)).point(lambda v: int(min(255, v * opacity * 1.6)))
    canvas.putalpha(alpha)
    canvas.alpha_composite(mark, (pad, pad))
    return canvas


def place(picture: Image.Image, mark: Image.Image, width: int, centre: tuple[float, float]) -> None:
    scaled = mark.resize((width, round(mark.height * width / mark.width)), Image.LANCZOS)
    picture.alpha_composite(scaled, (round(picture.width * centre[0] - scaled.width / 2),
                                     round(picture.height * centre[1] - scaled.height / 2)))


def main() -> int:
    out = Path(sys.argv[1])
    out.mkdir(parents=True, exist_ok=True)
    art = Path(__file__).resolve().parent
    # pic0, behind the title on the home screen, and pic1, the splash: one picture
    picture = Image.open(art / "pic-source.jpg").convert("RGB").resize((3840, 2160), Image.LANCZOS)
    picture.save(out / "pic0.png")
    picture.save(out / "pic1.png")
    Image.open(art / "icon0-source.png").convert("RGB").resize((512, 512), Image.LANCZOS).save(out / "icon0.png")

    # the drawn sky, square, with the wordmark's first letter: the game's own icon
    icon = scene(1024, 1024, seed=11).convert("RGBA")
    mark = wordmark()
    # the D ends at the first empty column
    columns = np.asarray(mark.getchannel("A")).max(axis=0)
    end = next(x for x in range(40, mark.width) if columns[x] == 0)
    initial = with_shadow(mark.crop((0, 0, end, mark.height)), 10, 0.8)
    place(icon, initial, 430, (0.50, 0.45))

    # res/: the pictures the game's own menus load. Dusklight's show the game (a
    # character as mascot, the Triforce in the emblem, a screenshot behind the
    # pre-launch menu); a PS5 title carries these in their place, same names and sizes.
    res = out / "res"
    res.mkdir(exist_ok=True)
    original = Image.open(DUSKLIGHT / "res/logo.png")
    logo = Image.new("RGBA", original.size, (0, 0, 0, 0))
    lettering = with_shadow(mark, 8, 0.8)
    logo.alpha_composite(lettering, ((logo.width - lettering.width) // 2, (logo.height - lettering.height) // 2))
    logo.save(res / "logo.png")
    icon.save(res / "icon.png")
    # behind the pre-launch menu: dark, soft, darkest on the left where the menu is
    backdrop = np.asarray(scene(1920, 1080).filter(ImageFilter.GaussianBlur(6)), dtype=float)
    shade = np.linspace(0.30, 0.62, 1920)[None, :, None]
    Image.fromarray(np.clip(backdrop * shade, 0, 255).astype(np.uint8), "RGB").save(res / "prelaunch-bg.png")
    # the emblem (a loading mark, in three parts that turn): rings and a sun, in white
    from PIL import ImageDraw
    import math

    def emblem(parts: set[str]) -> Image.Image:
        size = 2048  # drawn large, then reduced: smooth edges
        picture = Image.new("RGBA", (size, size), (0, 0, 0, 0))
        draw = ImageDraw.Draw(picture)
        centre = size / 2
        white = (255, 255, 255, 255)

        def ring(radius: float, width: int) -> None:
            draw.ellipse((centre - radius, centre - radius, centre + radius, centre + radius), outline=white, width=width)

        if "outer" in parts:
            ring(980, 36)
            ring(820, 36)
            for step in range(24):
                angle = math.tau * step / 24
                draw.line((centre + 838 * math.cos(angle), centre + 838 * math.sin(angle),
                           centre + 962 * math.cos(angle), centre + 962 * math.sin(angle)), fill=white, width=30)
        if "inner" in parts:
            ring(700, 32)
            for step in range(12):
                angle = math.tau * (step + 0.5) / 12
                draw.line((centre + 470 * math.cos(angle), centre + 470 * math.sin(angle),
                           centre + 690 * math.cos(angle), centre + 690 * math.sin(angle)), fill=white, width=28)
        if "center" in parts:
            # a sun half below a horizon
            draw.pieslice((centre - 300, centre - 260, centre + 300, centre + 340), 180, 360, outline=white, width=34)
            draw.line((centre - 400, centre + 40, centre + 400, centre + 40), fill=white, width=34)
            draw.line((centre - 250, centre + 150, centre + 250, centre + 150), fill=white, width=30)
            draw.line((centre - 120, centre + 250, centre + 120, centre + 250), fill=white, width=26)
        return picture.resize((512, 512), Image.LANCZOS)

    emblem({"outer"}).save(res / "org-icon-outer.png")
    emblem({"inner"}).save(res / "org-icon-inner.png")
    emblem({"center"}).save(res / "org-icon-center.png")
    emblem({"outer", "inner", "center"}).save(res / "org-icon.png")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
