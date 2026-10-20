#!/usr/bin/env bash
# Cross-build Virtual Jaguar's libretro core (Atari Jaguar), from my fork ../PS5_VirtualJaguar (github.com/mihawk-99/PS5_VirtualJaguar)
# at its pinned revision (tools/core-fork.sh).
#
# Output: build/cores/stage/{cores,info}/virtualjaguar_libretro.{so,info}; build-title.sh
# stages those in /app0. It renders in software; no BIOS (it carries its own boot code). Compatibility is limited.
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
cd "$root"
core_name=virtualjaguar
source "$root/tools/core-stamp.sh"
source "$root/tools/core-fork.sh"
core_stamp_skip virtualjaguar \
    "$root/build/cores/stage/cores/virtualjaguar_libretro.so" \
    "$root/build/cores/stage/info/virtualjaguar_libretro.info" \
    -- "$root/tools/build-virtualjaguar.sh" "$root/tools/core-fork.sh"
[[ $# == 0 ]] || { echo "usage: ${0##*/}" >&2; exit 2; }

revision=45dd657d26d7f39e1505da5378ac50e059dffb8f  # ../PS5_VirtualJaguar main
core_fork_setup
core_fork_checkout PS5_VirtualJaguar "$revision"
core_fork_info virtualjaguar_libretro.info c6338c31a4d72706a110e89a94686254a08718479735ad5df156059a1144500a

# LDFLAGS goes in the environment: the makefiles add their own to it.
LDFLAGS="$core_ldflags $core_libs" make -C "$source_dir" -j"${JOBS:-16}" platform=ps5 \
    CC="$core_cc" CXX="$core_cxx" AR="$AR"
core_fork_stage "$source_dir/virtualjaguar_libretro.so" "$core_info" "$revision" tools/build-virtualjaguar.sh
