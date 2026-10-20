#!/usr/bin/env bash
# Cross-build Beetle NeoPop (mednafen_ngp), Mednafen's Neo Geo Pocket and Pocket Color core, from my fork ../PS5_BeetleNGP (github.com/mihawk-99/PS5_BeetleNGP)
# at its pinned revision (tools/core-fork.sh).
#
# Output: build/cores/stage/{cores,info}/mednafen_ngp_libretro.{so,info}; build-title.sh
# stages those in /app0. It renders in software; no BIOS.
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
cd "$root"
core_name=beetle-ngp
source "$root/tools/core-stamp.sh"
source "$root/tools/core-fork.sh"
core_stamp_skip beetle-ngp \
    "$root/build/cores/stage/cores/mednafen_ngp_libretro.so" \
    "$root/build/cores/stage/info/mednafen_ngp_libretro.info" \
    -- "$root/tools/build-beetle-ngp.sh" "$root/tools/core-fork.sh"
[[ $# == 0 ]] || { echo "usage: ${0##*/}" >&2; exit 2; }

revision=3699184c21ec3c129d3ed5ef1abb9d15e06107a5  # ../PS5_BeetleNGP main
core_fork_setup
core_fork_checkout PS5_BeetleNGP "$revision"
core_fork_info mednafen_ngp_libretro.info 1e7485277cffaf01ae4c4c5406a7dfc6f85f4d2a6949273feae5634781ec396b

# LDFLAGS goes in the environment: the makefiles add their own to it.
LDFLAGS="$core_ldflags $core_libs" make -C "$source_dir" -j"${JOBS:-16}" platform=ps5 \
    CC="$core_cc" CXX="$core_cxx" AR="$AR"
core_fork_stage "$source_dir/mednafen_ngp_libretro.so" "$core_info" "$revision" tools/build-beetle-ngp.sh
