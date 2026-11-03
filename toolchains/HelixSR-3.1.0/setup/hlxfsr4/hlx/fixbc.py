# Copyright 2026 lonewolf0622. All rights reserved (HelixSR Freeware License).
"""fixbc: fold trunc/lshr/insertelement/bitcast(<2 x i16> -> <2 x half>) of one i32 into a single bitcast, and
or -> add for table indices (the base is a multiple of the stride by construction). The kernels/*/fixbc.py step of the
tested build, as a function (same rules, same output)."""
import re


def fold(text):
    t = text.split('\n'); d = {}
    for l in t:
        m = re.match(r'\s+(%\d+) = (.*)$', l)
        if m: d[m.group(1)] = m.group(2)
    for k, l in enumerate(t):
        m = re.match(r'(\s+)(%\d+) = bitcast <2 x i16> (%\d+) to <2 x half>(.*)$', l)
        if not m: continue
        e = d.get(m.group(3), ''); m2 = re.match(r'insertelement <2 x i16> (%\d+), i16 (%\d+), i(?:32|64) 1', e)
        if not m2: continue
        m3 = re.match(r'insertelement <2 x i16> undef, i16 (%\d+), i(?:32|64) 0', d.get(m2.group(1), ''))
        if not m3: continue
        lo = re.match(r'trunc i32 (%\d+) to i16$', d.get(m3.group(1), '')); hi = re.match(r'trunc i32 (%\d+) to i16$', d.get(m2.group(2), ''))
        if not lo or not hi: continue
        sh = re.match(r'lshr i32 (%\d+), 16$', d.get(hi.group(1), ''))
        if not sh or sh.group(1) != lo.group(1): continue
        t[k] = '%s%s = bitcast i32 %s to <2 x half>%s' % (m.group(1), m.group(2), lo.group(1), m.group(4))
    uses = set(re.findall(r'@T\w+, i32 0, i32 (%\d+)', '\n'.join(t)))
    for k, l in enumerate(t):
        m = re.match(r'(\s+)(%\d+) = or i32 (%\d+), (\d+)$', l)
        if m and m.group(2) in uses:
            t[k] = '%s%s = add i32 %s, %s' % (m.group(1), m.group(2), m.group(3), m.group(4))
    return '\n'.join(t)
