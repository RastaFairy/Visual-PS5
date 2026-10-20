#!/usr/bin/env python3
# Wind Waker for the PlayStation 5 - the table of the title's integer division instructions.
#
#   ps5/tools/make-div-table.py <linked.elf> <out.bin> [--objdump llvm-objdump] [--nm llvm-nm]
#
# The game divides integers by zero in places; x86-64 raises SIGFPE where the GameCube and ARM
# give a quotient. The port's SIGFPE handler (pc_crash.cpp, divFaultHandler) finishes such an
# instruction itself, but the console's code is execute-only, so it cannot read the instruction
# to learn its length: this lists every div/idiv of the linked title (address, length, operand
# size), and the handler looks the faulting address up. Addresses are the ELF's; the handler
# takes the load offset from the anchor function, whose ELF address heads the file.
#
# File: "COSDIV1\0", u64 anchor address, u32 count, then count sorted entries of
# u32 address, u8 length, u8 operand size in bytes (little-endian).
#
# SPDX-License-Identifier: MIT
import argparse
import re
import struct
import subprocess
import sys

ANCHOR = "pc_div_table_anchor"
LINE = re.compile(r"^\s*([0-9a-f]+):\s+((?:[0-9a-f]{2} )+)\s*(?:(?:lock|rep\w*|data16|addr32|cs|ds|es|ss|fs|gs)\s+)*(i?div)([bwlq])\s")
SIZES = {"b": 1, "w": 2, "l": 4, "q": 8}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("elf")
    ap.add_argument("out")
    ap.add_argument("--objdump", default="llvm-objdump")
    ap.add_argument("--nm", default="llvm-nm")
    args = ap.parse_args()

    anchor = None
    for line in subprocess.run([args.nm, args.elf], capture_output=True, text=True, check=True).stdout.splitlines():
        parts = line.split()
        if len(parts) == 3 and parts[2] == ANCHOR:
            anchor = int(parts[0], 16)
    if anchor is None:
        sys.exit(f"make-div-table: no symbol {ANCHOR} in {args.elf}")

    entries = []
    dump = subprocess.Popen([args.objdump, "-d", "--no-print-imm-hex", args.elf], stdout=subprocess.PIPE, text=True)
    for line in dump.stdout:
        if "div" not in line:
            continue
        m = LINE.match(line)
        if m:
            entries.append((int(m.group(1), 16), len(m.group(2).split()), SIZES[m.group(4)]))
    if dump.wait() != 0:
        sys.exit("make-div-table: objdump failed")
    if not entries:
        sys.exit("make-div-table: no division found (objdump's output format changed?)")
    entries.sort()
    with open(args.out, "wb") as f:
        f.write(b"COSDIV1\0" + struct.pack("<QI", anchor, len(entries)))
        for address, length, size in entries:
            f.write(struct.pack("<IBB", address, length, size))
    print(f"make-div-table: {len(entries)} division(s), anchor 0x{anchor:x}: {args.out}")


if __name__ == "__main__":
    main()
