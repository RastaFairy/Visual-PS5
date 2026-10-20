#!/usr/bin/env bash
# Cross-build Beetle VB (mednafen_vb), Mednafen's Virtual Boy core, from my fork ../PS5_BeetleVB (github.com/mihawk-99/PS5_BeetleVB)
# at its pinned revision (tools/core-fork.sh).
#
# Output: build/cores/stage/{cores,info}/mednafen_vb_libretro.{so,info}; build-title.sh
# stages those in /app0. It renders in software; no BIOS.
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
cd "$root"
core_name=beetle-vb
source "$root/tools/core-stamp.sh"
source "$root/tools/core-fork.sh"
core_stamp_skip beetle-vb \
    "$root/build/cores/stage/cores/mednafen_vb_libretro.so" \
    "$root/build/cores/stage/info/mednafen_vb_libretro.info" \
    -- "$root/tools/build-beetle-vb.sh" "$root/tools/core-fork.sh"
[[ $# == 0 ]] || { echo "usage: ${0##*/}" >&2; exit 2; }

revision=44a3e754bad72026dfa85b81a92f053ac6a1605e  # ../PS5_BeetleVB main
core_fork_setup
core_fork_checkout PS5_BeetleVB "$revision"
core_fork_info mednafen_vb_libretro.info 425e0ef983f72b7e938af8cc170d2ddc1cb6b0a19a98aa4fce49bb2957567236

# LDFLAGS goes in the environment: the makefiles add their own to it.
LDFLAGS="$core_ldflags $core_libs" make -C "$source_dir" -j"${JOBS:-16}" platform=ps5 \
    CC="$core_cc" CXX="$core_cxx" AR="$AR"
core_fork_stage "$source_dir/mednafen_vb_libretro.so" "$core_info" "$revision" tools/build-beetle-vb.sh
