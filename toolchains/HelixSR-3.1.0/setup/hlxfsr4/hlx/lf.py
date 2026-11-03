# Copyright 2026 lonewolf0622. All rights reserved (HelixSR Freeware License).
"""Text files written with LF line ends on Windows too (as on Linux, where every shader was checked): Python writes
CRLF there by default. install() makes text-mode writes without an explicit newline use '\n'; a no-op elsewhere."""
import builtins, io, os

_open = io.open


def _lf_open(file, mode='r', buffering=-1, encoding=None, errors=None, newline=None, closefd=True, opener=None):
    if newline is None and 'b' not in mode and any(c in mode for c in 'wax+'):
        newline = '\n'
    return _open(file, mode, buffering, encoding, errors, newline, closefd, opener)


def install():
    if os.name == 'nt' and io.open is _open:
        io.open = builtins.open = _lf_open
