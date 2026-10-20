#!/usr/bin/env bash
# Cross-build ProSystem's libretro core (Atari 7800), from my fork ../PS5_ProSystem (github.com/mihawk-99/PS5_ProSystem)
# at its pinned revision (tools/core-fork.sh).
#
# Output: build/cores/stage/{cores,info}/prosystem_libretro.{so,info}; build-title.sh
# stages those in /app0. It renders in software; the 7800 BIOS (7800 BIOS (U).rom in system/) is optional.
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
cd "$root"
core_name=prosystem
source "$root/tools/core-stamp.sh"
source "$root/tools/core-fork.sh"
core_stamp_skip prosystem \
    "$root/build/cores/stage/cores/prosystem_libretro.so" \
    "$root/build/cores/stage/info/prosystem_libretro.info" \
    -- "$root/tools/build-prosystem.sh" "$root/tools/core-fork.sh"
[[ $# == 0 ]] || { echo "usage: ${0##*/}" >&2; exit 2; }

revision=0429c4969f663bd2b1aa0ab7e972b1a61befcd98  # ../PS5_ProSystem main
core_fork_setup
core_fork_checkout PS5_ProSystem "$revision"
core_fork_info prosystem_libretro.info 22e9bc148612082f41147b4de167bb7ade705ec5f4642b8b70c0eb9ad1971681

# LDFLAGS goes in the environment: the makefiles add their own to it.
LDFLAGS="$core_ldflags $core_libs" make -C "$source_dir" -j"${JOBS:-16}" platform=ps5 \
    CC="$core_cc" CXX="$core_cxx" AR="$AR"
core_fork_stage "$source_dir/prosystem_libretro.so" "$core_info" "$revision" tools/build-prosystem.sh
