#!/usr/bin/env bash
# Wind Waker for the PlayStation 5 - the sources the build needs, with the console's changes.
#
#   ps5/tools/setup-source.sh    check out and patch everything; safe before every build
#
# SwitchWaker (vendor/switchwaker) is a submodule at an upstream revision. What
# the console needs changed in it is ps5/patches/switchwaker.patch, every hunk
# behind __PROSPERO__. Three things SwitchWaker fetches for itself are fetched
# here instead, into .deps/, so the build needs no network and no disc:
#
#   .deps/aurora        Aurora at SwitchWaker's pin (native/cmake/Aurora.cmake),
#                       with SwitchWaker's own patches (native/patches/aurora) and
#                       then ps5/patches/aurora.patch (the console's surface)
#   .deps/recompcore    Dolphin's DSP HLE sources (native/tools/fetch_recompcore.sh)
#   .deps/assets/GZLE01 stub asset headers (native/tools/gen_assets.sh --stubs):
#                       names and sizes only, from the decompilation's symbol
#                       list. The arrays are read from the player's disc when
#                       the title starts (docs/RUNTIME_ASSETS.md), so nothing of
#                       the game is compiled in. Needs PyYAML.
#
# SPDX-License-Identifier: MIT
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
upstream="$root/vendor/switchwaker"
deps="$root/.deps"

[[ -f $upstream/native/CMakeLists.txt ]] || git -C "$root" submodule update --init vendor/switchwaker >&2

patch="$root/ps5/patches/switchwaker.patch"
if [[ -s $patch ]] && ! git -C "$upstream" apply --reverse --check "$patch" 2>/dev/null; then
    git -C "$upstream" apply --check "$patch" || {
        echo "setup-source.sh: switchwaker.patch does not apply to $upstream (a different upstream revision, or local edits: git -C vendor/switchwaker diff > ps5/patches/switchwaker.patch)" >&2
        exit 2
    }
    git -C "$upstream" apply --whitespace=nowarn "$patch"
    echo "setup-source.sh: applied switchwaker.patch" >&2
fi

# Aurora
aurora="$deps/aurora"
pin=$(sed -n 's/^set(COS_AURORA_COMMIT "\([0-9a-f]\{40\}\)".*/\1/p' "$upstream/native/cmake/Aurora.cmake")
[[ -n $pin ]] || { echo "setup-source.sh: no COS_AURORA_COMMIT in native/cmake/Aurora.cmake" >&2; exit 2; }
stamp="$pin $(cat "$upstream"/native/patches/aurora/*.patch "$root/ps5/patches/aurora.patch" | sha256sum | cut -d' ' -f1)"
if [[ ! -f $aurora/.ps5-aurora || $(<"$aurora/.ps5-aurora") != "$stamp" ]]; then
    {
        if [[ ! -d $aurora/.git ]]; then
            mkdir -p "$aurora"
            git -C "$aurora" init -q
            git -C "$aurora" remote add origin https://github.com/encounter/aurora.git
        fi
        if [[ $(git -C "$aurora" rev-parse -q --verify HEAD 2>/dev/null) != "$pin" ]]; then
            git -C "$aurora" fetch -q --depth 1 origin "$pin"
            git -C "$aurora" checkout -q -f FETCH_HEAD
        fi
        git -C "$aurora" checkout -q -f HEAD -- .
        git -C "$aurora" clean -q -fd
        for each in "$upstream"/native/patches/aurora/*.patch "$root/ps5/patches/aurora.patch"; do
            git -C "$aurora" apply --whitespace=nowarn "$each" || {
                echo "setup-source.sh: ${each##*/} does not apply to Aurora ${pin:0:7}" >&2
                exit 2
            }
        done
    } >&2
    echo "$stamp" > "$aurora/.ps5-aurora"
fi

# Dolphin's DSP HLE
[[ -f $deps/recompcore/Source/Core/Core/HW/DSPHLE/UCodes/UCodes.cpp ]] ||
    bash "$upstream/native/tools/fetch_recompcore.sh" "$deps/recompcore" >&2

# Stub asset headers
if [[ ! -f $deps/assets/GZLE01/include/assets/cos_assets.h ]]; then
    bash "$upstream/native/tools/gen_assets.sh" --stubs --decomp "$deps/decomp" --out "$deps/assets/GZLE01" >&2
fi
