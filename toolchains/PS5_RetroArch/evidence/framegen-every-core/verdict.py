"""Frame generation verdict per core from a batch (fg_all2.sh): crash, pacing, picture size.
python3 <this> <run dir>   (tab-separated: core, verdict, why, figures)"""
import re
import subprocess
import sys
from pathlib import Path

CHECK = 'evidence/framegen-hardware-image-size/check.py'
for log in sorted(Path(sys.argv[1]).glob('*.log')):
    core, text = log.stem, log.read_text(errors='replace')
    stamp = re.search(r'klog/run-PPSA99169-(\d+)\.log', text) or re.search(r'klog/pad-(\d{6})', text)
    stamp = stamp[1] if stamp else None
    ra = Path(f'klog/retroarch-{stamp}.log') if stamp else None
    r = ra.read_text(errors='replace') if ra and ra.exists() else ''
    fresh = bool(re.search(r'saved retroarch\.log to', text))
    pace = [tuple(map(float, m)) for m in re.findall(r'pace: ([\d.]+) presents/s, ([\d.]+) generated/s, ([\d.]+) new frames/s', r)]
    windows = re.findall(r'pace: ([\d.]+) presents/s, [\d.]+ generated/s, ([\d.]+) new frames/s[^\n]*\n(?:[^\n]*\n){0,2}?[^\n]*spacing \(ms\): real n (\d+) ', r)
    # a window with no real frame at a whole number of pictures per new frame (2x): the slow-core fault
    pacing_faults = sum(1 for p, f, real in windows if real == '0' and float(f) > 5 and abs(float(p) / float(f) - 2.0) < 0.15)
    gen_rate = sum(g for _, g, _ in pace) / len(pace) if pace else 0.0
    new_rate = sum(f for _, _, f in pace) / len(pace) if pace else 0.0
    recs = sorted(Path(f'klog/pad-{stamp}').glob('rec-*')) if stamp else []
    sizes, figures = [], []
    for rec in recs:
        out = subprocess.run(['python3', CHECK, str(rec)], capture_output=True, text=True).stdout.strip()
        tri = re.search(r'(\d+) generated pictures: mean difference from their neighbours ([\d.]+)', out)
        near = re.search(r'against any neighbours ([\d.]+) over (\d+)', out)
        real2 = re.search(r'\(real pictures ([\d.]+) over (\d+)\)', out)
        bright = re.search(r'brightness ([\d.]+)', out)
        gen_diff = float(tri[2]) if tri else (float(near[1]) if near else None)
        base = float(real2[1]) if real2 else (0.0 if gen_diff is not None else None)  # no real pairs: the noise floor alone
        figures.append(f'{rec.name}: gen {gen_diff} real {base} bright {bright[1] if bright else "?"}')
        if gen_diff is not None and base is not None:
            sizes.append(gen_diff <= 2 * base + 3.0)  # the crop fault: 31.5 against 6.7; noise on still pictures: 1.5
    if 'crash: signal' in text:
        verdict, why = 'FAIL', 'crash'
    elif not fresh or not r:
        verdict, why = 'NO DATA', 'no fresh RetroArch log'
    elif pacing_faults:
        verdict, why = 'FAIL', f'{pacing_faults} windows with no real frame at 2 pictures a frame'
    elif sizes and not all(sizes):
        verdict, why = 'FAIL', 'generated pictures further from their neighbours than real ones'
    elif sizes:
        verdict, why = 'PASS', f'{len(sizes)} recording(s) compared'
    elif gen_rate < 1:
        verdict, why = 'NOT EXERCISED', f'nothing generated ({new_rate:.1f} new frames/s)'
    else:
        verdict, why = 'NOT EXERCISED', f'generated {gen_rate:.0f}/s but no recording had real and generated pictures to compare'
    print(f'{core}\t{verdict}\t{why}\tnew {new_rate:.1f}/s gen {gen_rate:.1f}/s\t' + ' | '.join(figures))
