#!/usr/bin/env python3
# ps5-homebrew-ui - Compare the OpenGL and the Vulkan pictures of the tour.
# Copyright (C) 2026 BlackBearReloaded
# Copyright (C) 2026 Mihawk
# SPDX-License-Identifier: GPL-3.0-or-later
#
# usage: tools/compare-backends.py <OpenGL dir> <Vulkan dir> [--diffs <dir>] [--limit <mean>]
#
# Takes the pictures tools/host-snapshots.sh and tools/host-snapshots-vk.sh
# wrote and prints, for each, the mean and largest channel difference and
# the share of pixels more than 8 levels apart. With --diffs, the pictures
# that differ most are written beside each other with their difference
# (enlarged x8). Exits 1 when a picture is missing or its mean is above
# --limit (0.5 levels in 255 by default).

import argparse
import pathlib
import sys

import numpy as np
from PIL import Image


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("gl")
    parser.add_argument("vk")
    parser.add_argument("--diffs")
    parser.add_argument("--limit", type=float, default=0.5)
    args = parser.parse_args()
    gl = pathlib.Path(args.gl)
    vk = pathlib.Path(args.vk)
    names = sorted(p.name for p in gl.glob("*.png"))
    if not names:
        print(f"no pictures in {gl}", file=sys.stderr)
        return 1
    rows = []
    failed = 0
    for name in names:
        other = vk / name
        if not other.exists():
            print(f"{name}: missing from {vk}")
            failed += 1
            continue
        a = np.asarray(Image.open(gl / name).convert("RGB"), dtype=np.int16)
        b = np.asarray(Image.open(other).convert("RGB"), dtype=np.int16)
        if a.shape != b.shape:
            print(f"{name}: sizes differ {a.shape} {b.shape}")
            failed += 1
            continue
        d = np.abs(a - b)
        mean = float(d.mean())
        rows.append((mean, int(d.max()), float((d.max(axis=2) > 8).mean() * 100), name, d))
        if mean > args.limit:
            failed += 1
    rows.sort(reverse=True)
    for mean, largest, share, name, _ in rows:
        flag = "  over the limit" if mean > args.limit else ""
        print(f"{name}: mean {mean:.4f}, max {largest}, {share:.3f}% of pixels > 8{flag}")
    means = [r[0] for r in rows]
    if means:
        print(f"{len(rows)} pictures: mean of means {sum(means) / len(means):.4f}, "
              f"worst {max(means):.4f} ({rows[0][3]})")
    if args.diffs:
        out = pathlib.Path(args.diffs)
        out.mkdir(parents=True, exist_ok=True)
        for mean, _, _, name, d in rows[:8]:
            if mean == 0.0:
                break
            a = Image.open(gl / name).convert("RGB")
            b = Image.open(vk / name).convert("RGB")
            diff = Image.fromarray(np.clip(d * 8, 0, 255).astype(np.uint8))
            sheet = Image.new("RGB", (a.width * 3, a.height))
            for i, picture in enumerate((a, b, diff)):
                sheet.paste(picture, (a.width * i, 0))
            sheet.save(out / name)
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
