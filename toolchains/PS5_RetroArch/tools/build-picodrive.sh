#!/usr/bin/env bash
# Cross-build PicoDrive's libretro core (Sega 32X, and Mega Drive, Mega-CD, Master
# System and Pico), from my fork ../PS5_PicoDrive (github.com/mihawk-99/PS5_PicoDrive)
# at its pinned revision (tools/core-fork.sh).
#
# Output: build/cores/stage/{cores,info}/picodrive_libretro.{so,info}; build-title.sh
# stages those in /app0. It renders in software; the 32X SH-2s run on the
# interpreter (the fork's ps5 platform says why). PicoDrive needs its git
# submodules, so the fork is checked out with them.
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
cd "$root"
core_name=picodrive
source "$root/tools/core-stamp.sh"
source "$root/tools/core-fork.sh"
core_stamp_skip picodrive \
    "$root/build/cores/stage/cores/picodrive_libretro.so" \
    "$root/build/cores/stage/info/picodrive_libretro.info" \
    -- "$root/tools/build-picodrive.sh" "$root/tools/core-fork.sh"
[[ $# == 0 ]] || { echo "usage: ${0##*/}" >&2; exit 2; }

revision=39b008bd95bf79bb7b1cf0ba905f9f14d9c86d08  # ../PS5_PicoDrive main
core_fork_setup
core_fork_checkout PS5_PicoDrive "$revision" submodules
core_fork_info picodrive_libretro.info 35cef57b4b61d95a86e1ceee3a7c325d9d16bbdc136b4b3a556e808864de06c5

# LDFLAGS goes in the environment: the makefiles add their own to it.
LDFLAGS="$core_ldflags $core_libs" make -C "$source_dir" -f Makefile.libretro -j"${JOBS:-16}" platform=ps5 \
    CC="$core_cc" CXX="$core_cxx" AR="$AR" CC_AS="$CC" GIT_REVISION="-${revision:0:7}"
core_fork_stage "$source_dir/picodrive_libretro.so" "$core_info" "$revision" tools/build-picodrive.sh
