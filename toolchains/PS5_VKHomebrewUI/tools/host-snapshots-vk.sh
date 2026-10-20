#!/usr/bin/env bash
# ps5-homebrew-ui - Render every design on the host through the Vulkan backend to PNG.
# Copyright (C) 2026 BlackBearReloaded
# Copyright (C) 2026 Mihawk
# SPDX-License-Identifier: GPL-3.0-or-later
#
# usage: tools/host-snapshots-vk.sh [output dir] [design id|all] [width height]
#
# The Vulkan twin of tools/host-snapshots.sh: the same tour, drawn by
# gfx::VkRenderer (src/gfx/vk/) on the PC's Vulkan driver (lavapipe unless
# HUI_VK_DEVICE names another; HUI_VK_VALIDATION=1 adds the validation
# layer). tools/compare-backends.py sets the two sets of pictures side by side.

set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
source "$root/tools/ninja-build.sh"
cxx=$(command -v "${HOST_CXX:-clang++}")
cc=$(command -v "${HOST_CC:-clang}")
build="$root/build/host-snapshots-vk"
ninja_begin "$build/build.ninja"

# Everything under src/ except the console platform layer, the entry point
# and the OpenGL backend.
sources=("$root/host/vk_snapshot_main.cpp" "$root/host/platform_host.cpp")
while IFS= read -r -d '' source; do
    sources+=("$source")
done < <(find "$root/src" -type f \( -name '*.cpp' -o -name '*.c' \) \
    ! -path "$root/src/platform/*" ! -path "$root/src/runtime/*" ! -name main.cpp \
    ! -name 'gl_*.cpp' ! -path "$root/src/gfx/backdrop.cpp" ! -path "$root/src/gfx/canvas.cpp" \
    -print0 | sort -z)

objects=()
for source in "${sources[@]}"; do
    relative=${source#"$root/"}
    object="$build/obj/${relative//\//_}.o"
    if [[ $source == *.c ]]; then
        ninja_inputs=("$source" "$cc")
        ninja_edge CC "$object" "${compiler_cache[@]}" "$cc" -std=c11 -O2 -w -I"$root/src" \
            -MD -MF "$object.d" -c "$source" -o "$object"
    else
        ninja_inputs=("$source" "$cxx")
        ninja_edge CXX "$object" "${compiler_cache[@]}" "$cxx" -std=c++20 -O2 -Wall -Wextra \
            -I"$root/src" -I"$root/host" -MD -MF "$object.d" -c "$source" -o "$object"
    fi
    objects+=("$object")
done
ninja_inputs=("${objects[@]}")
ninja_edge LINK "$build/hui_vk_snapshots" "$cxx" "${objects[@]}" -lvulkan -lm -o "$build/hui_vk_snapshots"
if ! ninja_run >"$build/build.log" 2>&1; then
    grep -E 'error|FAILED|warning' -A6 "$build/build.log" | head -80 >&2
    exit 1
fi
grep -E 'warning' -A4 "$build/build.log" | grep -v stb_image_write | head -40 >&2 || true

output=${1:-"$root/build/snapshots-vk"}
mkdir -p "$output"
"$build/hui_vk_snapshots" "$root/assets" "$output" "${@:2}"
