#!/usr/bin/env bash
# Ghostship for the PlayStation 5 - the archives the title reads, made on this machine.
#
#   ps5/tools/assets.sh              ghostship.o2r (Ghostship's own assets) into dist/<TITLE_ID>/
#   ps5/tools/assets.sh ROM.z64      ... and sm64.o2r from your own Super Mario 64 (US or JP),
#                                    into game/<TITLE_ID>/ for tools/console-files.sh
#
# Both are written by Torch, Ghostship's asset tool, built here for this machine
# (once, into $PS5_BUILD_DIR/../torch). ghostship.o2r holds the port's fonts,
# textures and shaders and belongs in a release. sm64.o2r is the game: it stays
# out of dist/ and out of git, and goes to the console by itself.
#
# SPDX-License-Identifier: MIT
set -euo pipefail
ps5=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
root=$(dirname "$ps5")
game="$root/vendor/ghostship"
build=${PS5_BUILD_DIR:-$root/build/game}
torch_build="$(dirname "$build")/torch"
work="$(dirname "$build")/assets"
title_id=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["titleId"])' "$ps5/sce_sys/param.json")
version=$(sed -n 's/^project(Ghostship VERSION \([0-9.]*\).*/\1/p' "$game/CMakeLists.txt")
app="${PS5_DIST_DIR:-$root/dist}/$title_id"
bash "$ps5/tools/setup-source.sh"

if [[ ! -x $torch_build/torch ]]; then
    mkdir -p "$torch_build"
    # the machine's own compiler, not the console's
    CC=gcc CXX=g++ cmake -S "$game/Torch" -B "$torch_build" -G Ninja -DCMAKE_BUILD_TYPE=Release > "$torch_build/configure.log" 2>&1 ||
        { tail -40 "$torch_build/configure.log" >&2; exit 1; }
    ninja -C "$torch_build" > "$torch_build/build.log" 2>&1 || { tail -40 "$torch_build/build.log" >&2; exit 1; }
fi

# Torch works in the current directory: a scratch copy of what it reads
rm -rf "$work"
mkdir -p "$work/port" "$app"
cp -R "$game/config.yml" "$game/assets" "$work/"
cp -R "$game/port/." "$work/port/"
mkdir -p "$work/port/shaders"
cp -R "$game/libultraship/src/fast/shaders/." "$work/port/shaders/"
(cd "$work" && "$torch_build/torch" pack port ghostship.o2r o2r -u "$version" > pack.log 2>&1) || { tail -20 "$work/pack.log" >&2; exit 1; }
cp "$work/ghostship.o2r" "$app/ghostship.o2r"
# what the title's own extraction reads when it is given a ROM instead of sm64.o2r
rm -rf "$app/assets"
cp "$game/config.yml" "$app/config.yml"
cp -R "$game/assets" "$app/assets"
printf '==> %s (%s bytes)\n' "$app/ghostship.o2r" "$(stat -c %s "$app/ghostship.o2r")"

if [[ $# -ge 1 ]]; then
    rom=$(realpath "$1")
    mkdir -p "$root/game/$title_id"
    cp "$rom" "$work/baserom.z64"
    (cd "$work" && "$torch_build/torch" o2r baserom.z64 -u "$version" > o2r.log 2>&1) || { tail -20 "$work/o2r.log" >&2; exit 1; }
    rm -f "$work/baserom.z64"
    cp "$work/sm64.o2r" "$root/game/$title_id/sm64.o2r"
    printf '==> %s (%s bytes)\n' "$root/game/$title_id/sm64.o2r" "$(stat -c %s "$root/game/$title_id/sm64.o2r")"
fi
