#!/usr/bin/env python3
# PS5 RetroArch - make the launcher backgrounds (sce_sys/pic0.dds, pic1.dds).
# Copyright (C) 2026 Mihawk-99
# SPDX-License-Identifier: GPL-3.0-or-later
#
# The backgrounds are drawn here, from arithmetic and a fixed random seed, so
# their origin is this script: a starry night sky over a glowing magenta grid
# that runs to the horizon, 3840x2160, in the format the launcher reads (DDS,
# DX10 header, BC7_UNORM, one level). pic0 and pic1 are the same picture.
#
# The grid is a ground plane seen in perspective: its lines along the view meet
# at a vanishing point above the horizon, its lines across it get closer
# together towards the horizon, and both fade into the night with distance.
# The BC7 blocks come from the small mode 6 encoder below (two endpoints and a
# 4-bit index a pixel), so no texture compressor is needed and a run of the
# script gives the same files every time.
#
#   python3 tools/make-title-art.py            write sce_sys/pic0.dds and pic1.dds
#   python3 tools/make-title-art.py --png DIR  also write a PNG preview to DIR
import struct
import sys
from pathlib import Path

import numpy as np

WIDTH, HEIGHT = 3840, 2160
ROOT = Path(__file__).resolve().parent.parent

# The ground plane: lines along the view meet at (CENTRE_X, VANISH_Y) and are
# SPREAD * (y - VANISH_Y) apart. Line n across the view (0 the farthest) is at
# 1 / (y - ACROSS_Y) = DEPTH[0] + DEPTH[1] n + DEPTH[2] n^2, a gently curved
# spacing; the grid starts at HORIZON_Y. Colours fade with 1 / (y - FOG_Y).
CENTRE_X, VANISH_Y, SPREAD = 1911.8, 992.0, 0.20079
HORIZON_Y, ACROSS_Y, FOG_Y = 1496.0, 1276.0, 1000.0
DEPTH = (4.47091e-3, -3.11389e-4, 6.39127e-6)
LINE_HALF_WIDTH = 2.0    # pixels: the bright core of a grid line
GLOW_LENGTH = 6.0        # pixels: how fast the pale glow beside a line fades

NIGHT = np.array([6.0, 0.0, 74.0])        # what the far grid fades into
SKY_TOP = np.array([2.0, 0.0, 7.0])       # the sky above the haze
LINE = np.array([255.0, 0.0, 255.0])      # a near grid line's core
GLOW = np.array([20.0, 85.0, 14.0])      # added beside a near line (pale pink)


# The kinds of star: share, Gaussian radius (sigma, pixels), peak brightness
# (above 1 is a saturated disc), and whether it sparkles
STARS = (
    (0.04, (1.0, 1.2), (0.42, 0.55), False),
    (0.32, (1.1, 1.3), (0.50, 0.62), False),
    (0.09, (1.2, 1.4), (0.70, 0.82), False),
    (0.30, (1.38, 1.52), (0.95, 1.05), False),
    (0.16, (1.55, 1.75), (1.05, 1.18), False),
    (0.07, (1.75, 2.05), (1.30, 1.65), False),
    (0.02, (2.5, 3.0), (2.20, 3.00), True),
)


def fade(u, centre, scale):
    """How much of a colour survives at depth u (1 / pixels below FOG_Y)."""
    return 1.0 / (1.0 + np.exp((u - centre) / scale))


def draw() -> np.ndarray:
    """The picture as RGB, HEIGHT x WIDTH x 3, values 0..255."""
    y = np.arange(HEIGHT, dtype=np.float64)[:, None]
    x = np.arange(WIDTH, dtype=np.float64)[None, :]
    img = np.zeros((HEIGHT, WIDTH, 3))

    # The sky: black, then a deep blue haze down to the horizon
    t = np.clip((y - 1000.0) / (HORIZON_Y - 1000.0), 0.0, 1.0)
    s = t * t * (3.0 - 2.0 * t)
    sky = np.concatenate([SKY_TOP[0] + 5.0 * s, 0.0 * s, SKY_TOP[2] + 67.0 * s], axis=1)
    img[:] = sky[:, None, :]

    # The grid, from the horizon down
    rows = np.arange(int(HORIZON_Y), HEIGHT)
    yg = rows.astype(np.float64)[:, None]
    u = 1.0 / (yg - FOG_Y)
    # Tiles fade from magenta near by into the night at the horizon
    tile = np.stack([NIGHT[0] + (190.0 - NIGHT[0]) * fade(u, 1.285e-3, 0.120e-3),
                     NIGHT[1] + (30.0 - NIGHT[1]) * fade(u, 1.100e-3, 0.215e-3),
                     NIGHT[2] + (225.0 - NIGHT[2]) * fade(u, 1.235e-3, 0.150e-3)], axis=-1)
    tile = np.broadcast_to(tile, (len(rows), WIDTH, 3)).copy()
    # Lines glow further than tiles: theirs fades later
    glow_r = fade(u, 1.49e-3, 0.165e-3)
    glow_b = fade(u, 1.49e-3, 0.170e-3)
    core = np.stack([NIGHT[0] + (267.5 - NIGHT[0]) * glow_r,
                     np.zeros_like(glow_r),
                     NIGHT[2] + (264.7 - NIGHT[2]) * glow_b], axis=-1)
    core = np.minimum(core, LINE)
    # The pale glow beside a line fades with distance as the tiles do
    strength = fade(u, 1.285e-3, 0.120e-3)[..., None]

    # Distance to the nearest line along the view (a slanted line through the
    # vanishing point), measured across the line
    spread = SPREAD * (yg - VANISH_Y)
    j = np.round((x - CENTRE_X) / spread)
    d_along = np.abs(x - (CENTRE_X + j * spread)) / np.sqrt(1.0 + (j * SPREAD) ** 2)
    # Distance to the nearest line across the view
    c0, c1, c2 = DEPTH
    u_across = 1.0 / (yg - ACROSS_Y)
    n = (-c1 - np.sqrt(np.maximum(c1 * c1 - 4.0 * c2 * (c0 - u_across), 0.0))) / (2.0 * c2)
    n = np.clip(np.round(n), 0.0, 17.0)
    y_line = ACROSS_Y + 1.0 / (c0 + c1 * n + c2 * n * n)
    d_across = np.abs(yg - y_line)
    # The nearest line's edge: a bright strip glows at the bottom of the frame too
    d_across = np.minimum(d_across, np.abs(yg - float(HEIGHT)))
    d = np.minimum(d_along, np.broadcast_to(d_across, d_along.shape))

    glow = np.exp(-np.maximum(d - LINE_HALF_WIDTH, 0.0) / GLOW_LENGTH)
    both = np.exp(-np.maximum(d_along - LINE_HALF_WIDTH, 0.0) / GLOW_LENGTH) + \
        np.exp(-np.maximum(np.broadcast_to(d_across, d_along.shape) - LINE_HALF_WIDTH, 0.0) / GLOW_LENGTH)
    glow = np.minimum(np.maximum(glow, both), 1.0)
    floor = tile + glow[..., None] * GLOW * strength
    cover = np.clip(LINE_HALF_WIDTH + 0.5 - d, 0.0, 1.0)[..., None]
    floor = floor * (1.0 - cover) + core * cover
    img[int(HORIZON_Y):] = floor

    # Stars: round white points over the sky, a little fewer and dimmer towards
    # the horizon, a few of them faintly over the far grid. STARS gives each
    # kind's share, size and brightness; the brightest sparkle.
    rng = np.random.default_rng(20261001)
    stars = np.zeros((HEIGHT, WIDTH))
    density = ((0.0, 1.0), (750.0, 0.95), (1000.0, 0.85), (1620.0, 0.8))
    shares = np.cumsum([kind[0] for kind in STARS])
    count = 0
    while count < 2700:
        sx, sy = rng.uniform(0, WIDTH), rng.uniform(0, 1620)
        if rng.uniform() > np.interp(sy, [d[0] for d in density], [d[1] for d in density]):
            continue
        count += 1
        dim = 1.0 if sy < 1050 else max(1.0 - 0.55 * (sy - 1050) / (HORIZON_Y - 1050), 0.45)
        if sy > HORIZON_Y:
            dim *= max(1.0 - (sy - HORIZON_Y) / (1620.0 - HORIZON_Y), 0.0) * 0.5
        _, sizes, amps, sparkle = STARS[min(int(np.searchsorted(shares, rng.uniform())), len(STARS) - 1)]
        sigma, amp = rng.uniform(*sizes), rng.uniform(*amps)
        r = 18 if sparkle else 8
        x0, x1 = max(int(sx) - r, 0), min(int(sx) + r + 1, WIDTH)
        y0, y1 = max(int(sy) - r, 0), min(int(sy) + r + 1, HEIGHT)
        py = np.arange(y0, y1)[:, None] + 0.5 - sy
        px = np.arange(x0, x1)[None, :] + 0.5 - sx
        q = px * px + py * py
        spot = amp * np.exp(-q / (2 * sigma * sigma))
        if sparkle:
            # A soft halo and sixteen short, thin rays from the edge of the disc
            spot += 0.10 * np.exp(-q / (2 * 4.5 * 4.5))
            dist = np.sqrt(q)
            reach = np.exp(-np.maximum(dist - 2.0 * sigma, 0.0) / 3.2) * (dist > 1.4 * sigma)
            for angle in np.arange(16) * np.pi / 8 + rng.uniform(0, np.pi / 8):
                along = px * np.cos(angle) + py * np.sin(angle)
                across = -px * np.sin(angle) + py * np.cos(angle)
                spot += 0.38 * (along > 0) * np.exp(-across * across / 0.7) * reach
        stars[y0:y1, x0:x1] += spot * dim
    stars = np.clip(stars, 0.0, 1.0)[..., None]
    img = img + (255.0 - img) * stars
    return np.clip(img, 0.0, 255.0)


# BC7 mode 6: one subset, RGBA endpoints of 7 bits and a p-bit, 4-bit indices
WEIGHTS = np.array([0, 4, 9, 13, 17, 21, 26, 30, 34, 38, 43, 47, 51, 55, 60, 64], dtype=np.int64)


def quantise(e: np.ndarray) -> np.ndarray:
    """Endpoint colours to the 7 stored bits (the p-bit is 1, for alpha 255)."""
    return np.clip(np.round((e - 1.0) / 2.0), 0, 127).astype(np.int64)


def palette(q0: np.ndarray, q1: np.ndarray) -> np.ndarray:
    """The 16 colours two quantised endpoints give, (blocks, 16, 3)."""
    e0, e1 = (q0 * 2 + 1)[:, None, :], (q1 * 2 + 1)[:, None, :]
    w = WEIGHTS[None, :, None]
    return ((64 - w) * e0 + w * e1 + 32) >> 6


def choose(px: np.ndarray, q0: np.ndarray, q1: np.ndarray):
    """Each pixel's best index for these endpoints, and the block's error."""
    pal = palette(q0, q1)
    err = ((px[:, :, None, :] - pal[:, None, :, :]) ** 2).sum(-1)
    idx = err.argmin(-1)
    return idx, np.take_along_axis(err, idx[..., None], -1)[..., 0].sum(-1)


def encode_blocks(px: np.ndarray) -> bytes:
    """BC7 mode 6 for blocks of 16 RGB pixels (blocks, 16, 3), alpha 255."""
    pf = px.astype(np.float64)
    mean = pf.mean(1)
    cen = pf - mean[:, None, :]
    cov = np.einsum('nki,nkj->nij', cen, cen)
    axis = np.ones((len(px), 3)) / np.sqrt(3.0)
    for _ in range(8):
        axis = np.einsum('nij,nj->ni', cov, axis)
        norm = np.sqrt((axis * axis).sum(1, keepdims=True))
        axis = np.where(norm > 1e-9, axis / np.maximum(norm, 1e-9), 1.0 / np.sqrt(3.0))
    proj = np.einsum('nki,ni->nk', cen, axis)
    q0 = quantise(mean + proj.min(1, keepdims=True) * axis)
    q1 = quantise(mean + proj.max(1, keepdims=True) * axis)
    idx, err = choose(px, q0, q1)
    # One least-squares refit of the endpoints to the chosen indices
    w = WEIGHTS[idx].astype(np.float64) / 64.0
    a, b, c = ((1 - w) ** 2).sum(1), ((1 - w) * w).sum(1), (w * w).sum(1)
    d0 = ((1 - w)[..., None] * pf).sum(1)
    d1 = (w[..., None] * pf).sum(1)
    det = a * c - b * b
    ok = det > 1e-9
    safe = np.where(ok, det, 1.0)[:, None]
    r0 = quantise(np.where(ok[:, None], (c[:, None] * d0 - b[:, None] * d1) / safe, mean))
    r1 = quantise(np.where(ok[:, None], (a[:, None] * d1 - b[:, None] * d0) / safe, mean))
    idx2, err2 = choose(px, r0, r1)
    better = (err2 < err)[:, None]
    q0, q1 = np.where(better, r0, q0), np.where(better, r1, q1)
    idx = np.where(better, idx2, idx)
    # The first pixel's index is stored in 3 bits: swap the ends if it needs 4
    swap = idx[:, 0] >= 8
    q0, q1 = np.where(swap[:, None], q1, q0), np.where(swap[:, None], q0, q1)
    idx = np.where(swap[:, None], 15 - idx, idx)

    lo = np.full(len(px), 1 << 6, dtype=np.uint64)   # mode 6
    hi = np.zeros(len(px), dtype=np.uint64)
    pos = 7

    def put(value: np.ndarray, bits: int):
        nonlocal pos
        for bit in range(bits):
            v = ((value >> bit) & 1).astype(np.uint64)
            if pos < 64:
                lo[:] |= v << np.uint64(pos)
            else:
                hi[:] |= v << np.uint64(pos - 64)
            pos += 1

    for ch in range(3):
        put(q0[:, ch], 7)
        put(q1[:, ch], 7)
    alpha = np.full(len(px), 127, dtype=np.int64)
    put(alpha, 7)
    put(alpha, 7)
    one = np.ones(len(px), dtype=np.int64)
    put(one, 1)   # P0
    put(one, 1)   # P1
    put(idx[:, 0], 3)
    for i in range(1, 16):
        put(idx[:, i], 4)
    out = np.empty(len(px) * 2, dtype="<u8")
    out[0::2], out[1::2] = lo, hi
    return out.tobytes()


def bc7(img: np.ndarray) -> bytes:
    """The picture as BC7 blocks, row of blocks by row of blocks."""
    rgb = np.clip(np.round(img), 0, 255).astype(np.int64)
    by, bx = HEIGHT // 4, WIDTH // 4
    blocks = rgb.reshape(by, 4, bx, 4, 3).transpose(0, 2, 1, 3, 4).reshape(by * bx, 16, 3)
    step = bx * 16
    return b"".join(encode_blocks(blocks[i:i + step]) for i in range(0, len(blocks), step))


def dds_header() -> bytes:
    """The DDS header of the launcher art the console has shown: DX10, BC7_UNORM
    (98), 2D, one level, straight alpha."""
    DDSD_CAPS, DDSD_HEIGHT, DDSD_WIDTH, DDSD_PIXELFORMAT = 0x1, 0x2, 0x4, 0x1000
    DDSD_MIPMAPCOUNT, DDSD_LINEARSIZE = 0x20000, 0x80000
    flags = DDSD_CAPS | DDSD_HEIGHT | DDSD_WIDTH | DDSD_PIXELFORMAT | DDSD_MIPMAPCOUNT | DDSD_LINEARSIZE
    linear = WIDTH * HEIGHT               # BC7: 16 bytes a 4x4 block, one byte a pixel
    header = struct.pack("<4sIIIIIII", b"DDS ", 124, flags, HEIGHT, WIDTH, linear, 1, 1)
    header += b"\0" * 44                  # reserved
    header += struct.pack("<II4sIIIII", 32, 0x4, b"DX10", 0, 0, 0, 0, 0)
    header += struct.pack("<IIIII", 0x1000, 0, 0, 0, 0)   # caps: texture
    header += struct.pack("<IIIII", 98, 3, 0, 1, 1)       # BC7_UNORM, TEXTURE2D, array 1, straight alpha
    assert len(header) == 148
    return header


def main() -> int:
    png_dir = None
    if len(sys.argv) == 3 and sys.argv[1] == "--png":
        png_dir = Path(sys.argv[2])
    elif len(sys.argv) != 1:
        print("usage: make-title-art.py [--png DIR]", file=sys.stderr)
        return 2
    img = draw()
    data = dds_header() + bc7(img)
    for name in ("pic0.dds", "pic1.dds"):
        (ROOT / "sce_sys" / name).write_bytes(data)
        print(f"sce_sys/{name}: {len(data)} bytes")
    if png_dir:
        from PIL import Image
        png_dir.mkdir(parents=True, exist_ok=True)
        Image.fromarray(np.clip(np.round(img), 0, 255).astype(np.uint8), "RGB").save(png_dir / "title-art.png")
    return 0


if __name__ == "__main__":
    sys.exit(main())
