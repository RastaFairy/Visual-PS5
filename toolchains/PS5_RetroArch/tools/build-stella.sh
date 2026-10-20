#!/usr/bin/env bash
# Cross-build Stella's libretro core (Atari 2600), from my fork ../PS5_Stella (github.com/mihawk-99/PS5_Stella)
# at its pinned revision (tools/core-fork.sh).
#
# Output: build/cores/stage/{cores,info}/stella_libretro.{so,info}; build-title.sh
# stages those in /app0. It renders in software; no BIOS.
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
cd "$root"
core_name=stella
source "$root/tools/core-stamp.sh"
source "$root/tools/core-fork.sh"
core_stamp_skip stella \
    "$root/build/cores/stage/cores/stella_libretro.so" \
    "$root/build/cores/stage/info/stella_libretro.info" \
    -- "$root/tools/build-stella.sh" "$root/tools/core-fork.sh"
[[ $# == 0 ]] || { echo "usage: ${0##*/}" >&2; exit 2; }

revision=34e824a73fb5c2d6d83a47b62810c85cd0b8d357  # ../PS5_Stella main
core_fork_setup
core_fork_checkout PS5_Stella "$revision"
core_fork_info stella_libretro.info ad01fae0d3c0b620a97fe84c5879ee96d241024f58f3d609cabb98eef6f67a35

# LDFLAGS goes in the environment: the makefiles add their own to it.
LDFLAGS="$core_ldflags $core_libs" make -C "$source_dir/src/os/libretro" -j"${JOBS:-16}" platform=ps5 \
    CC="$core_cc" CXX="$core_cxx" AR="$AR"
core_fork_stage "$source_dir/src/os/libretro/stella_libretro.so" "$core_info" "$revision" tools/build-stella.sh
