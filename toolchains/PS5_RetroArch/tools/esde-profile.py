#!/usr/bin/env python3
"""Where EmulationStation's CPU time goes on the console: a report of the samples
tools/run-title.sh --frontend-profile collects (frontends/es-de/ps5/capture_ps5.cpp).

    tools/esde-profile.py klog/frontend-<run>/profile-frontend-<run>.txt [--top 30]

Each sample line is the interrupted instruction and the return addresses of its
frame-pointer chain, in hex. Addresses in es-de.bin (loaded at 0x400000) are
symbolized against build/frontend/es-de/es-de.elf, the image the run deployed;
others are the console's own modules. The report gives each function's share of
the samples where it was running (self) and where it was on the stack (total).
"""
from collections import Counter
from pathlib import Path
import argparse
import subprocess

BASE = 0x400000
ELF = Path(__file__).resolve().parent.parent / 'build' / 'frontend' / 'es-de' / 'es-de.elf'


def symbolize(addresses):
    """Function names for addresses in the image, by llvm-symbolizer."""
    inside = sorted(a for a in addresses if BASE <= a < BASE + 0x10000000)
    names = {}
    if inside:
        query = '\n'.join(hex(a - BASE) for a in inside) + '\n'
        out = subprocess.run(['llvm-symbolizer', f'--obj={ELF}', '--functions=linkage', '--demangle',
                              '--no-inlines', '--output-style=GNU'],
                             input=query, capture_output=True, text=True, check=True).stdout
        lines = out.splitlines()
        for index, address in enumerate(inside):
            name = lines[2 * index] if 2 * index < len(lines) else '??'
            names[address] = name[:140]
    for address in addresses:
        names.setdefault(address, f'[console module {address:#x}]' if address else '[none]')
    return names


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('samples')
    parser.add_argument('--top', type=int, default=30)
    args = parser.parse_args()
    rows = [[int(field, 16) for field in line.split()] for line in Path(args.samples).read_text().splitlines()
            if line.strip()]
    names = symbolize({address for row in rows for address in row})
    self_count, total_count = Counter(), Counter()
    for row in rows:
        self_count[names[row[0]]] += 1
        for name in {names[address] for address in row if address}:
            total_count[name] += 1
    print(f'{len(rows)} samples (1 ms of CPU time each)')
    print('\nself (running):')
    for name, count in self_count.most_common(args.top):
        print(f'  {100 * count / len(rows):5.1f}%  {name}')
    print('\ntotal (on the stack):')
    for name, count in total_count.most_common(args.top):
        print(f'  {100 * count / len(rows):5.1f}%  {name}')


if __name__ == '__main__':
    main()
