#!/usr/bin/env bash
# Cross-build Azahar's libretro core (Nintendo 3DS), from my fork ../PS5_Azahar
# (github.com/mihawk-99/PS5_Azahar) at its pinned revision (tools/core-fork.sh).
#
# Output: build/cores/stage/{cores,info}/azahar_libretro.{so,info};
# build-title.sh stages those in /app0. It renders through the frontend's Vulkan
# device (no OpenGL is built), runs the ARM CPUs on dynarmic's x86-64 JIT and
# compiles shaders asynchronously; the fork's PS5 defaults render at 18x. Azahar
# needs its git submodules, so the fork is checked out with them.
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
cd "$root"
core_name=azahar
source "$root/tools/core-stamp.sh"
source "$root/tools/core-fork.sh"
core_stamp_skip azahar \
    "$root/build/cores/stage/cores/azahar_libretro.so" \
    "$root/build/cores/stage/info/azahar_libretro.info" \
    -- "$root/tools/build-azahar.sh" "$root/tools/core-fork.sh" "$root/tooling/azahar"
[[ $# == 0 ]] || { echo "usage: ${0##*/}" >&2; exit 2; }

revision=4aef900a1a903d0aa6ea86fdb1e18236fb0d5907  # ../PS5_Azahar main
core_fork_setup
core_fork_checkout PS5_Azahar "$revision" submodules
git -C "$source_dir" apply "$root/tooling/azahar/touchpad-stylus.patch"
core_fork_info azahar_libretro.info c5bff8202e7ed32bce79ef0ab34dbeabde0637a298ef19a9e9c0ff5ea363aac3

# The libretro build turns off every frontend that cannot be part of a core
# (Qt, SDL, OpenAL, cubeb, the web service, the GDB stub); OpenGL is off here
# because the console has none.
build="$core_work/build"
cmake -S "$source_dir" -B "$build" \
    ${core_ccache:+-DCMAKE_C_COMPILER_LAUNCHER=$core_ccache -DCMAKE_CXX_COMPILER_LAUNCHER=$core_ccache} \
    -DCMAKE_TOOLCHAIN_FILE="$root/tooling/azahar/ps5-toolchain.cmake" \
    -DPS5_CORE_LINK_INPUTS="$core_work/core_cxx_runtime.o" -DPS5_EMPTY_LIBS="$core_work/empty-libs" \
    -DCMAKE_BUILD_TYPE=Release -DENABLE_LIBRETRO=ON -DENABLE_OPENGL=OFF -DENABLE_VULKAN=ON \
    `# zstd's trace hooks are weak imports nothing on the console defines.` \
    -DCMAKE_C_FLAGS=-DZSTD_TRACE=0 -DCMAKE_CXX_FLAGS=-DZSTD_TRACE=0 \
    -DENABLE_LTO=OFF -DCITRA_USE_PRECOMPILED_HEADERS=OFF -DCITRA_WARNINGS_AS_ERRORS=OFF \
    -DENABLE_DISCORD_RPC=OFF -DENABLE_TESTS=OFF > "$core_work/configure.log" ||
    { tail -30 "$core_work/configure.log" >&2; exit 1; }
cmake --build "$build" --target citra_libretro --parallel "${JOBS:-16}"
built=$(find "$build" -name azahar_libretro.so -print -quit)
[[ -n $built ]] || { echo "error: no azahar_libretro.so was produced" >&2; exit 2; }
core_fork_stage "$built" "$core_info" "$revision" tools/build-azahar.sh \
    tooling/azahar/ps5-toolchain.cmake \
    tooling/azahar/touchpad-stylus.patch
