#!/usr/bin/env bash
# ps5-homebrew-ui - Compile the Vulkan backend's GLSL into SPIR-V arrays.
# Copyright (C) 2026 BlackBearReloaded
# Copyright (C) 2026 Mihawk
# SPDX-License-Identifier: GPL-3.0-or-later
#
# usage: tools/compile-vk-shaders.sh [--check]
#
# Each src/gfx/vk/shaders/<name>.<stage> becomes <name>.<stage>.inc, a C
# array that vk_renderer.cpp includes, so the kit carries its shaders and a
# title needs no shader files of its own. Both are committed; --check fails
# when an .inc is missing or does not match its source.

set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
dir="$root/src/gfx/vk/shaders"
check=0
[[ ${1:-} == --check ]] && check=1
command -v glslangValidator >/dev/null || { echo "glslangValidator not found" >&2; exit 2; }

status=0
for source in "$dir"/*.vert "$dir"/*.frag; do
    file=$(basename "$source")
    name=${file%.*}
    stage=${file##*.}
    # batch.vert -> kBatchVert
    symbol="k$(tr '[:lower:]' '[:upper:]' <<<"${name:0:1}")${name:1}$(tr '[:lower:]' '[:upper:]' <<<"${stage:0:1}")${stage:1}"
    output="$source.inc"
    temporary=$(mktemp)
    glslangValidator -V --target-env vulkan1.0 --quiet --vn "$symbol" -o "$temporary" "$source"
    if ((check)); then
        if ! cmp -s "$temporary" "$output"; then
            echo "out of date: ${output#"$root/"}" >&2
            status=1
        fi
        rm -f "$temporary"
    else
        mv "$temporary" "$output"
        echo "${output#"$root/"}"
    fi
done
exit "$status"
