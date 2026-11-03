#!/usr/bin/env bash
# Copyright 2026 lonewolf0622. All rights reserved (HelixSR Freeware License).
#
# HelixSR uninstaller for Linux: removes HelixSR (HelixSR Scaler or the FSR drop-in, also installs of earlier versions)
# from the games you pick and puts back every file it replaced; then it can delete what the setup built here and the
# setup's downloads (~/.local/share/HelixSR).
#
#   ./helixsr-uninstall.sh [GAME_FOLDER]..
#
# A GAME_FOLDER adds a game the uninstaller does not find by itself (one you gave helixsr-setup.sh by hand).
set -euo pipefail
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
DATA="${XDG_DATA_HOME:-$HOME/.local/share}/HelixSR"
say() { echo "[helixsr-uninstall] $*"; }
PY=""
for c in python3 "$DATA/python/bin/python3"; do
    if command -v "$c" >/dev/null 2>&1 && "$c" -c 'import sys; sys.exit(0 if sys.version_info >= (3, 8) else 1)' 2>/dev/null; then
        PY=$(command -v "$c"); break
    fi
done
[ -n "$PY" ] || { say "error: no Python 3 found"; exit 1; }
ARGS=()
for f in "$@"; do
    case "$f" in -h|--help) sed -n '3,10p' "$0"; exit 0 ;; esac
    [ -d "$f" ] || { say "error: not a folder: $f"; exit 1; }
    ARGS+=(--folder "$(cd "$f" && pwd)")
done
rc=0
"$PY" "$HERE/setup/helixsr_install.py" "$HERE" remove --data "$DATA" "${ARGS[@]}" || rc=$?
if [ $rc = 3 ]; then
    rm -rf "$DATA"
    say "deleted $DATA"
    rc=0
fi
exit $rc
