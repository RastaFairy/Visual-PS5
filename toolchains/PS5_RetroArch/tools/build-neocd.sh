#!/usr/bin/env bash
# Cross-build NeoCD's libretro core (Neo Geo CD), from my fork ../PS5_NeoCD
# (github.com/mihawk-99/PS5_NeoCD) at its pinned revision (tools/core-fork.sh).
#
# Output: build/cores/stage/{cores,info}/neocd_libretro.{so,info}; build-title.sh
# stages those in /app0. It renders in software. Games need a Neo Geo CD BIOS and
# 000-lo.lo in system/neocd/.
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
cd "$root"
core_name=neocd
source "$root/tools/core-stamp.sh"
source "$root/tools/core-fork.sh"
core_stamp_skip neocd \
    "$root/build/cores/stage/cores/neocd_libretro.so" \
    "$root/build/cores/stage/info/neocd_libretro.info" \
    -- "$root/tools/build-neocd.sh" "$root/tools/core-fork.sh"
[[ $# == 0 ]] || { echo "usage: ${0##*/}" >&2; exit 2; }

revision=b9b13d7760336fec2089989e1bdbe98454dece6c  # ../PS5_NeoCD main
core_fork_setup
core_fork_checkout PS5_NeoCD "$revision"
core_fork_info neocd_libretro.info 6ea290bc3814131091c08eec089386492264fc3aaa3f678b7b130874cac0cc37

# LDFLAGS goes in the environment: the makefiles add their own to it.
LDFLAGS="$core_ldflags $core_libs" make -C "$source_dir" -j"${JOBS:-16}" platform=ps5 \
    CC="$core_cc" CXX="$core_cxx" AR="$AR"
core_fork_stage "$source_dir/neocd_libretro.so" "$core_info" "$revision" tools/build-neocd.sh
