#!/usr/bin/env bash
# Cross-build a5200's libretro core (Atari 5200), from my fork ../PS5_A5200 (github.com/mihawk-99/PS5_A5200)
# at its pinned revision (tools/core-fork.sh).
#
# Output: build/cores/stage/{cores,info}/a5200_libretro.{so,info}; build-title.sh
# stages those in /app0. It renders in software.
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
cd "$root"
core_name=a5200
source "$root/tools/core-stamp.sh"
source "$root/tools/core-fork.sh"
core_stamp_skip a5200 \
    "$root/build/cores/stage/cores/a5200_libretro.so" \
    "$root/build/cores/stage/info/a5200_libretro.info" \
    -- "$root/tools/build-a5200.sh" "$root/tools/core-fork.sh"
[[ $# == 0 ]] || { echo "usage: ${0##*/}" >&2; exit 2; }

revision=c21e2ef8c63300890cdaf02363543872660ccd33  # ../PS5_A5200 main
core_fork_setup
core_fork_checkout PS5_A5200 "$revision"
core_fork_info a5200_libretro.info e707b742d0c12e87483986742e316ea530b2592ce74aaa74f5617267a9abafab

# a5200's Makefile empties LDFLAGS first, so the title's link flags go in as
# PS5_LDFLAGS, which the fork's ps5 platform adds.
make -C "$source_dir" -j"${JOBS:-16}" platform=ps5 \
    CC="$core_cc" CXX="$core_cxx" AR="$AR" PS5_LDFLAGS="$core_ldflags $core_libs"
core_fork_stage "$source_dir/a5200_libretro.so" "$core_info" "$revision" tools/build-a5200.sh
