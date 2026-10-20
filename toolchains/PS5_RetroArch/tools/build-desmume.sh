#!/usr/bin/env bash
# Cross-build DeSmuME, the Nintendo DS core, from my fork ../PS5_DeSmuME
# (github.com/mihawk-99/PS5_DeSmuME) at its pinned revision (tools/core-fork.sh).
#
# Output: build/cores/stage/{cores,info}/desmume_libretro.{so,info};
# build-title.sh stages those in /app0.
# Its software renderer upscales, so the fork's platform=ps5 builds it without
# OpenGL; by default it renders at 5x (1280x960), the most that holds full
# speed on the console, and the ARM CPUs run on the x86-64
# JIT, whose code buffer is the console's executable memory.
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
cd "$root"
core_name=desmume
source "$root/tools/core-stamp.sh"
source "$root/tools/core-fork.sh"
core_stamp_skip desmume \
    "$root/build/cores/stage/cores/desmume_libretro.so" \
    "$root/build/cores/stage/info/desmume_libretro.info" \
    -- "$root/tools/build-desmume.sh" "$root/tools/core-fork.sh" "$root/tooling/desmume"
[[ $# == 0 ]] || { echo "usage: ${0##*/}" >&2; exit 2; }

revision=54540709d343bd93d021487af4408679ca187825  # ../PS5_DeSmuME main
core_fork_setup
core_fork_checkout PS5_DeSmuME "$revision"
git -C "$source_dir" apply "$root/tooling/desmume/touchpad-stylus.patch"
core_fork_info desmume_libretro.info 82730a4bcd36df5631f1791f50a66f056075ef47b501c19258f703b73966101b

# LDFLAGS goes in the environment: the makefiles add their own to it.
LDFLAGS="$core_ldflags $core_libs" make -C "$source_dir/desmume/src/frontend/libretro" -f Makefile.libretro -j"${JOBS:-16}" platform=ps5 DESMUME_JIT=1 \
    CC="$core_cc" CXX="$core_cxx" AR="$AR"
core_fork_stage "$source_dir/desmume/src/frontend/libretro/desmume_libretro.so" "$core_info" "$revision" tools/build-desmume.sh \
    tooling/desmume/touchpad-stylus.patch
