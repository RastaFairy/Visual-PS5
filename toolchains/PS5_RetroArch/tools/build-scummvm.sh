#!/usr/bin/env bash
# Cross-build ScummVM's libretro core, every engine, from my fork ../PS5_ScummVM
# (github.com/mihawk-99/PS5_ScummVM: scummvm/scummvm v2026.3.0 plus the ps5 platform)
# at its pinned revision (tools/core-fork.sh).
#
# Output: build/cores/stage/{cores,info}/scummvm_libretro.{so,info}; build-title.sh
# stages those in /app0. Its Makefile fetches libretro-deps and libretro-common at
# the commits it pins into backends/platform/libretro/deps, which the clean keeps.
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
cd "$root"
core_name=scummvm
source "$root/tools/core-stamp.sh"
source "$root/tools/core-fork.sh"
core_stamp_skip scummvm \
    "$root/build/cores/stage/cores/scummvm_libretro.so" \
    "$root/build/cores/stage/info/scummvm_libretro.info" \
    -- "$root/tools/build-scummvm.sh" "$root/tools/core-fork.sh"
[[ $# == 0 ]] || { echo "usage: ${0##*/}" >&2; exit 2; }

revision=967fd9757170b14c28590837186b31cc7d5cc46c  # ../PS5_ScummVM main
core_fork_setup
core_fork_checkout PS5_ScummVM "$revision" "" backends/platform/libretro/deps
core_fork_info scummvm_libretro.info dfd544230a99cda60eb907b93b3387419b5b1eda9c582beba2120b0c29f8899c

# ScummVM's Makefile empties LDFLAGS first, so the title's link flags go in as
# PS5_LDFLAGS, which the fork's ps5 platform adds. AR carries its flags, as the
# Makefile has it (ar cru).
make -C "$source_dir/backends/platform/libretro" -j"${JOBS:-16}" platform=ps5 \
    CC="$core_cc" CXX="$core_cxx" AR="$AR cru" PS5_LDFLAGS="$core_ldflags $core_libs"
core_fork_stage "$source_dir/backends/platform/libretro/scummvm_libretro.so" "$core_info" "$revision" tools/build-scummvm.sh
