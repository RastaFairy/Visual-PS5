#!/usr/bin/env bash
# Cross-build Handy's libretro core (Atari Lynx), from my fork ../PS5_Handy (github.com/mihawk-99/PS5_Handy)
# at its pinned revision (tools/core-fork.sh).
#
# Output: build/cores/stage/{cores,info}/handy_libretro.{so,info}; build-title.sh
# stages those in /app0. It renders in software; games need the Lynx boot ROM in system/ (lynxboot.img).
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
cd "$root"
core_name=handy
source "$root/tools/core-stamp.sh"
source "$root/tools/core-fork.sh"
core_stamp_skip handy \
    "$root/build/cores/stage/cores/handy_libretro.so" \
    "$root/build/cores/stage/info/handy_libretro.info" \
    -- "$root/tools/build-handy.sh" "$root/tools/core-fork.sh"
[[ $# == 0 ]] || { echo "usage: ${0##*/}" >&2; exit 2; }

revision=558fc62aeaed1b10e9dba5e03efe7fca56ab9d08  # ../PS5_Handy main
core_fork_setup
core_fork_checkout PS5_Handy "$revision"
core_fork_info handy_libretro.info a059661e377deb24ede5a77c725fbbdd4829666d0996f30bb9c2c9a10ee0461d

# LDFLAGS goes in the environment: the makefiles add their own to it.
LDFLAGS="$core_ldflags $core_libs" make -C "$source_dir" -j"${JOBS:-16}" platform=ps5 \
    CC="$core_cc" CXX="$core_cxx" AR="$AR"
core_fork_stage "$source_dir/handy_libretro.so" "$core_info" "$revision" tools/build-handy.sh
