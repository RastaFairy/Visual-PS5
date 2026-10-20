#!/usr/bin/env bash
# Wind Waker for the PlayStation 5 - build the game into dist/<TITLE_ID>/.
#
#   ps5/tools/build.sh [ninja arguments]
#
# Fetches and patches the sources (tools/setup-source.sh), then configures
# SwitchWaker's own build (vendor/switchwaker/native) with the payload SDK's
# CMake toolchain (once) and ps5/cmake/ps5-game.cmake, which gives it Dawn, SDL3
# and nod for the console and the title's link (tools/link-title.sh). The build
# reads no disc: COS_RUNTIME_ASSETS, with the stub headers of .deps/assets.
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
dawn=$(bash "$ps5/tools/setup-dawn.sh")
sdl=$(bash "$ps5/tools/setup-sdl.sh")
sdk=$(bash "$ps5/tools/setup-sdk.sh")
build=${PS5_BUILD_DIR:-$root/build/game}
ninja=$(command -v ninja || echo "$HOME/.local/bin/ninja")
export PS5_CLANG=${PS5_CLANG:-$(command -v clang || true)}

if [[ ! -f $build/build.ninja ]]; then
    mkdir -p "$build"
    cmake -S "$root/vendor/switchwaker/native" -B "$build" -G Ninja -DCMAKE_MAKE_PROGRAM="$ninja" \
        -DCMAKE_TOOLCHAIN_FILE="$sdk/toolchain/prospero.cmake" \
        -DCMAKE_PROJECT_cos_native_INCLUDE="$ps5/cmake/ps5-game.cmake" \
        -DPS5_PORT_DIR="$root" -DPS5_VULKAN_DIR="$vulkan" -DDAWN_DIR="$dawn" -DSDL_DIR="$sdl" \
        -DFETCHCONTENT_SOURCE_DIR_AURORA="$root/.deps/aurora" -DCOS_AURORA_PREPATCHED=ON \
        -DCOS_RECOMPCORE_DIR="$root/.deps/recompcore" \
        -DCOS_RUNTIME_ASSETS=ON -DCOS_ASSETS_DIR="$root/.deps/assets/GZLE01" \
        -DCMAKE_BUILD_TYPE=Release -DCMAKE_VERBOSE_MAKEFILE=OFF > "$build/configure.log" 2>&1 \
        || { tail -60 "$build/configure.log" >&2; exit 1; }
fi
"$ninja" -C "$build" "${@:-switchwaker}"
