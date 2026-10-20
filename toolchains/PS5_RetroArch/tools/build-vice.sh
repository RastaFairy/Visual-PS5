#!/usr/bin/env bash
# Cross-build VICE's cycle-exact Commodore 64 core (vice_x64sc), from my fork ../PS5_VICE
# (github.com/mihawk-99/PS5_VICE) at its pinned revision (tools/core-fork.sh).
#
# Output: build/cores/stage/{cores,info}/vice_x64sc_libretro.{so,info};
# build-title.sh stages those in /app0.
# The Commodore ROMs are built into the core (VICE's USE_EMBEDDED), so it needs
# no system files.
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
cd "$root"
core_name=vice
source "$root/tools/core-stamp.sh"
source "$root/tools/core-fork.sh"
core_stamp_skip vice \
    "$root/build/cores/stage/cores/vice_x64sc_libretro.so" \
    "$root/build/cores/stage/info/vice_x64sc_libretro.info" \
    -- "$root/tools/build-vice.sh" "$root/tools/core-fork.sh"
[[ $# == 0 ]] || { echo "usage: ${0##*/}" >&2; exit 2; }

revision=983b9882e8606975646dda07d6331d51df5d43ac  # ../PS5_VICE main
core_fork_setup
core_fork_checkout PS5_VICE "$revision"
core_fork_info vice_x64sc_libretro.info 944370dcfe24e575a3ecf2d21b9324284b885e32311bce9d1c28492e036cf4fb

# LDFLAGS goes in the environment: the makefiles add their own to it.
LDFLAGS="$core_ldflags $core_libs" make -C "$source_dir" -j"${JOBS:-16}" platform=ps5 EMUTYPE=x64sc CC="$core_cc" CXX="$core_cxx" AR="$AR"
core_fork_stage "$source_dir/vice_x64sc_libretro.so" "$core_info" "$revision" tools/build-vice.sh
