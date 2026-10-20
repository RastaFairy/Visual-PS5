#!/usr/bin/env bash
# Cross-build PokeMini's libretro core (Pokemon Mini), from my fork ../PS5_PokeMini (github.com/mihawk-99/PS5_PokeMini)
# at its pinned revision (tools/core-fork.sh).
#
# Output: build/cores/stage/{cores,info}/pokemini_libretro.{so,info}; build-title.sh
# stages those in /app0. It renders in software; it has its own free BIOS, and uses bios.min from system/ when there is one.
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
cd "$root"
core_name=pokemini
source "$root/tools/core-stamp.sh"
source "$root/tools/core-fork.sh"
core_stamp_skip pokemini \
    "$root/build/cores/stage/cores/pokemini_libretro.so" \
    "$root/build/cores/stage/info/pokemini_libretro.info" \
    -- "$root/tools/build-pokemini.sh" "$root/tools/core-fork.sh"
[[ $# == 0 ]] || { echo "usage: ${0##*/}" >&2; exit 2; }

revision=df8163e56fcbc6608489432a421ee851411677f3  # ../PS5_PokeMini main
core_fork_setup
core_fork_checkout PS5_PokeMini "$revision"
core_fork_info pokemini_libretro.info 514da066db31dd673aabf9c0e54b1b24e485775615217a02ac7de635d621b8b2

# LDFLAGS goes in the environment: the makefiles add their own to it.
LDFLAGS="$core_ldflags $core_libs" make -C "$source_dir" -f Makefile.libretro -j"${JOBS:-16}" platform=ps5 \
    CC="$core_cc" CXX="$core_cxx" AR="$AR"
core_fork_stage "$source_dir/pokemini_libretro.so" "$core_info" "$revision" tools/build-pokemini.sh
