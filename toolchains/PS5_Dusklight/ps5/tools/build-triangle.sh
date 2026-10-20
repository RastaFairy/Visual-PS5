#!/usr/bin/env bash
# Dusklight for the PlayStation 5 - build the renderer test into dist/<TITLE_ID>/.
#
#   ps5/tools/build-triangle.sh
#
# Not the game: one triangle through Dawn (WebGPU) on RADV, the first thing to
# run when the driver stack or Dawn's revision changes (ps5/stage1/triangle.cpp).
# It takes the game's place in dist/<TITLE_ID>/ until the game is built again.
#
# Configures ps5/ with the payload SDK's CMake toolchain (once), compiles what
# changed, links with RADV and packages the title folder (tools/link-title.sh).
#
#   PS5_VULKAN_DIR   the PS5_Vulkan checkout (default ../PS5_Vulkan): the RADV
#                    release archive, the link recipe, the native tool and libc.prx
#
# The payload SDK is this title's own pin of Mihawk's fork (tools/setup-sdk.sh).
#   PS5_CLANG        the host clang the compiler wrappers drive (default: clang)
#
# After the PS5 Vulkan Template's build.sh, Copyright (C) 2026 Mihawk
# SPDX-License-Identifier: MIT

set -euo pipefail

ps5=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
root=$(dirname "$ps5")
vulkan=$(cd -- "${PS5_VULKAN_DIR:-$root/../PS5_Vulkan}" && pwd)
bash "$ps5/tools/setup-source.sh"
dawn=$(bash "$ps5/tools/setup-dawn.sh")
sdk=$(bash "$ps5/tools/setup-sdk.sh")
build="$root/build/ps5"
ninja=$(command -v ninja || echo "$HOME/.local/bin/ninja")
export PS5_CLANG=${PS5_CLANG:-$(command -v clang || true)}

if [[ ! -f $build/build.ninja ]]; then
    mkdir -p "$build"
    cmake -S "$ps5" -B "$build" -G Ninja -DCMAKE_MAKE_PROGRAM="$ninja" \
        -DCMAKE_TOOLCHAIN_FILE="$sdk/toolchain/prospero.cmake" \
        -DPS5_VULKAN_DIR="$vulkan" -DDAWN_DIR="$dawn" -DCMAKE_BUILD_TYPE=Release -DCMAKE_VERBOSE_MAKEFILE=OFF > "$build.configure.log" 2>&1 \
        || { cat "$build.configure.log" >&2; exit 1; }
fi
"$ninja" -C "$build" eboot
