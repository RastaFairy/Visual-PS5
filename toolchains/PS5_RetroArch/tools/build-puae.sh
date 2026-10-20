#!/usr/bin/env bash
# Cross-build PUAE's libretro core (Commodore Amiga), from my fork ../PS5_PUAE
# (github.com/mihawk-99/PS5_PUAE) at its pinned revision (tools/core-fork.sh).
#
# Output: build/cores/stage/{cores,info}/puae_libretro.{so,info}; build-title.sh
# stages those in /app0. It renders in software. Without Kickstart ROMs in system/
# (kick34005.A500, kick40068.A1200...) it boots its built-in AROS replacement.
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
cd "$root"
core_name=puae
source "$root/tools/core-stamp.sh"
source "$root/tools/core-fork.sh"
core_stamp_skip puae \
    "$root/build/cores/stage/cores/puae_libretro.so" \
    "$root/build/cores/stage/info/puae_libretro.info" \
    -- "$root/tools/build-puae.sh" "$root/tools/core-fork.sh"
[[ $# == 0 ]] || { echo "usage: ${0##*/}" >&2; exit 2; }

revision=9d130883e04227891fe96459d1b25f892a3099a9  # ../PS5_PUAE main
core_fork_setup
core_fork_checkout PS5_PUAE "$revision"
core_fork_info puae_libretro.info fc400817a4e304fe2721b9c7fbe3b4a0dfe7d9429366938abe48946aa56b43a3

# LDFLAGS goes in the environment: the makefiles add their own to it.
LDFLAGS="$core_ldflags $core_libs" make -C "$source_dir" -j"${JOBS:-16}" platform=ps5 \
    CC="$core_cc" CXX="$core_cxx" AR="$AR"
core_fork_stage "$source_dir/puae_libretro.so" "$core_info" "$revision" tools/build-puae.sh
