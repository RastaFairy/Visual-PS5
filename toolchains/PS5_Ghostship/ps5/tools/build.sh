#!/usr/bin/env bash
# Ghostship for the PlayStation 5 - build the game into dist/<TITLE_ID>/.
#
#   ps5/tools/build.sh [ninja arguments]
#
# Applies the console's patch to vendor/devilutionx (tools/setup-source.sh),
# configures it with the payload SDK's CMake toolchain (once) and
# ps5/cmake/ps5-game.cmake, which gives it SDL3 with the console's drivers and
# the title's link (tools/link-title.sh). The title folder gets eboot.bin,
# sce_sys/, DevilutionX's own assets (assets/ and mods/) and
# the licences. No game data: DIABDAT.MPQ is yours, placed beside eboot.bin.
#
#   PS5_BUILD_DIR    the build tree (default build/game; the Linux VM's own disk
#                    is several times faster than the shared folder)
#   PS5_VULKAN_DIR   the PS5_Vulkan checkout (default ../PS5_Vulkan)
#
# SPDX-License-Identifier: MIT
set -euo pipefail

ps5=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
root=$(dirname "$ps5")
vulkan=$(cd -- "${PS5_VULKAN_DIR:-$root/../PS5_Vulkan}" && pwd)
bash "$ps5/tools/setup-source.sh"
sdl=$(bash "$ps5/tools/setup-sdl.sh")
shaderc=$(bash "$ps5/tools/setup-shaderc.sh")
sdk=$(bash "$ps5/tools/setup-sdk.sh")
build=${PS5_BUILD_DIR:-$root/build/game}
ninja=$(command -v ninja || echo "$HOME/.local/bin/ninja")
export PS5_CLANG=${PS5_CLANG:-$(command -v clang || true)}

if [[ ! -f $build/build.ninja ]]; then
    mkdir -p "$build"
    cmake -S "$root/vendor/ghostship" -B "$build" -G Ninja -DCMAKE_MAKE_PROGRAM="$ninja" \
        -DCMAKE_TOOLCHAIN_FILE="$sdk/toolchain/prospero.cmake" \
        -DCMAKE_PROJECT_Ghostship_INCLUDE="$ps5/cmake/ps5-game.cmake" \
        -DPS5_PORT_DIR="$root" -DPS5_VULKAN_DIR="$vulkan" -DSDL_DIR="$sdl" -DSHADERC_DIR="$shaderc" \
        -DCMAKE_BUILD_TYPE=Release -DCMAKE_VERBOSE_MAKEFILE=OFF > "$build/configure.log" 2>&1 \
        || { tail -60 "$build/configure.log" >&2; exit 1; }
fi
"$ninja" -C "$build" "${@:-Ghostship}"

# The title's name and art, as this tree has them (the link copies them too, but
# only when something relinks)
title_id=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["titleId"])' "$ps5/sce_sys/param.json")
app="${PS5_DIST_DIR:-$root/dist}/$title_id"
if [[ -d $app/sce_sys ]]; then
    cp "$ps5/sce_sys/param.json" "$ps5/sce_sys/icon0.png" "$ps5/sce_sys/pic0.dds" "$ps5/sce_sys/pic1.dds" "$app/sce_sys/"
fi
