"""For a present-stream recording: how far each generated picture is from the mean of its two
real neighbours, and whether it keeps the real pictures' side bars. python3 <this> <rec dir>"""
import sys
from pathlib import Path
import numpy as np
d = Path(sys.argv[1]); w, h, n = map(int, (d / 'size.txt').read_text().split())
px = np.frombuffer((d / 'frames.rgba').read_bytes(), np.uint8).reshape(n, h, w, 4)[..., :3].astype(np.float32)
gen = [int(l.split()[3]) for l in (d / 'index.txt').read_text().splitlines() if not l.startswith('#')]
diffs, bars = [], []
for i in range(1, n - 1):
    if gen[i] and not gen[i - 1] and not gen[i + 1]:
        diffs.append(np.abs(px[i] - (px[i - 1] + px[i + 1]) / 2).mean())
        bars.append(px[i][:, :w // 10].mean())  # the left bar: black in a 4:3 picture on 16:9
real_bars = [px[i][:, :w // 10].mean() for i in range(n) if not gen[i]]
real_bar = np.mean(real_bars) if real_bars else float('nan')
# Any neighbours: at a rate that is not a whole number of pictures (50 Hz on 120), generated
# pictures follow each other; each still lies between the pictures beside it.
near = [np.abs(px[i] - (px[i - 1] + px[i + 1]) / 2).mean() for i in range(1, n - 1) if gen[i]]
# The same for the real pictures: what this content's motion gives a picture that is right.
# its real neighbours two places away (no generated picture in the comparison).
near_real = [np.abs(px[i] - (px[i - 2] + px[i + 2]) / 2).mean() for i in range(2, n - 2)
             if not gen[i] and not gen[i - 2] and not gen[i + 2]]
near_text = (f'; against any neighbours {np.mean(near):.1f} over {len(near)}' if near else '') + \
    (f' (real pictures {np.mean(near_real):.1f} over {len(near_real)})' if near_real else '')
if not diffs:
    print(f'0 generated pictures between real ones{near_text}; picture brightness {px.mean():.1f}')
    sys.exit(0)
print(f'{len(diffs)} generated pictures: mean difference from their neighbours {np.mean(diffs):.1f}, '
      f'left bar {np.mean(bars):.1f} (real pictures {real_bar:.1f}){near_text}; picture brightness {px.mean():.1f}')
