#!/usr/bin/env bash
# Cross-build Beetle Cygne (mednafen_wswan), Mednafen's WonderSwan and WonderSwan Color core, from my fork ../PS5_BeetleWSwan (github.com/mihawk-99/PS5_BeetleWSwan)
# at its pinned revision (tools/core-fork.sh).
#
# Output: build/cores/stage/{cores,info}/mednafen_wswan_libretro.{so,info}; build-title.sh
# stages those in /app0. It renders in software; no BIOS.
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
cd "$root"
core_name=beetle-wswan
source "$root/tools/core-stamp.sh"
source "$root/tools/core-fork.sh"
core_stamp_skip beetle-wswan \
    "$root/build/cores/stage/cores/mednafen_wswan_libretro.so" \
    "$root/build/cores/stage/info/mednafen_wswan_libretro.info" \
    -- "$root/tools/build-beetle-wswan.sh" "$root/tools/core-fork.sh"
[[ $# == 0 ]] || { echo "usage: ${0##*/}" >&2; exit 2; }

revision=8248f1d490cba5a625976aa07787cdc313009635  # ../PS5_BeetleWSwan main
core_fork_setup
core_fork_checkout PS5_BeetleWSwan "$revision"
core_fork_info mednafen_wswan_libretro.info 07f595bdc27cf7ee145091ae226b2dc37eeefa499ef9720b64d5384e54ac5ac1

# LDFLAGS goes in the environment: the makefiles add their own to it.
LDFLAGS="$core_ldflags $core_libs" make -C "$source_dir" -j"${JOBS:-16}" platform=ps5 \
    CC="$core_cc" CXX="$core_cxx" AR="$AR"
core_fork_stage "$source_dir/mednafen_wswan_libretro.so" "$core_info" "$revision" tools/build-beetle-wswan.sh
