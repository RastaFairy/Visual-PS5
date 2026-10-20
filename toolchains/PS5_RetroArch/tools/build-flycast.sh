#!/usr/bin/env bash
# Cross-build Flycast's libretro core (Dreamcast, NAOMI, NAOMI 2 and Atomiswave),
# from my fork ../PS5_Flycast (github.com/mihawk-99/PS5_Flycast) at its pinned
# revision (tools/core-fork.sh).
#
# Output: build/cores/stage/{cores,info}/flycast_libretro.{so,info}; build-title.sh
# stages those in /app0. It renders through the frontend's Vulkan device (no
# OpenGL is built) and runs the SH-4, ARM7 and AICA DSP recompilers on the
# console's executable memory; the fork's PS5 defaults render at 2880x2160 with
# per-pixel transparency. Flycast needs its git submodules, so the fork is checked
# out with them. The port began as rpf16rj's (PS5_RetroArch pull request 3).
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
cd "$root"
core_name=flycast
source "$root/tools/core-stamp.sh"
source "$root/tools/core-fork.sh"
core_stamp_skip flycast \
    "$root/build/cores/stage/cores/flycast_libretro.so" \
    "$root/build/cores/stage/info/flycast_libretro.info" \
    -- "$root/tools/build-flycast.sh" "$root/tools/core-fork.sh" "$root/tooling/flycast"
[[ $# == 0 ]] || { echo "usage: ${0##*/}" >&2; exit 2; }

revision=b95c532f64fe01dd49917085e0e32aabfefc33c2  # ../PS5_Flycast main
core_fork_setup
core_fork_checkout PS5_Flycast "$revision" submodules
core_fork_info flycast_libretro.info d32663d9bd4dfcbe8bf84cdf806ac1d7437512c2b5d75287b9a918ebed968898

# Only the libretro core is built: no OpenGL (the console has none), and none of
# the standalone frontend's extras (OpenMP, Discord, UPnP, CD drives, the GDB
# stub, Lua, breakpad).
build="$core_work/build"
cmake -S "$source_dir" -B "$build" \
    ${core_ccache:+-DCMAKE_C_COMPILER_LAUNCHER=$core_ccache -DCMAKE_CXX_COMPILER_LAUNCHER=$core_ccache} \
    -DCMAKE_TOOLCHAIN_FILE="$root/tooling/flycast/ps5-toolchain.cmake" \
    -DPS5_CORE_LINK_INPUTS="$core_work/core_cxx_runtime.o" -DPS5_EMPTY_LIBS="$core_work/empty-libs" \
    -DCMAKE_BUILD_TYPE=Release -DLIBRETRO=ON -DUSE_VULKAN=ON -DUSE_OPENGL=OFF \
    `# zstd's trace hooks are weak imports nothing on the console defines.` \
    -DCMAKE_C_FLAGS=-DZSTD_TRACE=0 -DCMAKE_CXX_FLAGS=-DZSTD_TRACE=0 \
    -DUSE_HOST_GLSLANG=OFF -DUSE_HOST_LIBCHDR=OFF -DUSE_HOST_LIBZIP=OFF -DUSE_OPENMP=OFF \
    -DUSE_DISCORD=OFF -DUSE_MINIUPNPC=OFF -DUSE_LIBCDIO=OFF -DUSE_LUA=OFF -DUSE_BREAKPAD=OFF \
    -DENABLE_GDB_SERVER=OFF -DENABLE_LOG=OFF > "$core_work/configure.log" ||
    { tail -30 "$core_work/configure.log" >&2; exit 1; }
cmake --build "$build" --target flycast_libretro --parallel "${JOBS:-16}"
built=$(find "$build" -name flycast_libretro.so -print -quit)
[[ -n $built ]] || { echo "error: no flycast_libretro.so was produced" >&2; exit 2; }
core_fork_stage "$built" "$core_info" "$revision" tools/build-flycast.sh \
    tooling/flycast/ps5-toolchain.cmake
