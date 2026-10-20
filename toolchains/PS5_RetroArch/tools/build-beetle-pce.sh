#!/usr/bin/env bash
# Cross-build Beetle PCE (mednafen_pce), Mednafen's PC Engine core (PC Engine,
# TurboGrafx-16, PC Engine CD and SuperGrafx), from my fork ../PS5_BeetlePCE
# (github.com/mihawk-99/PS5_BeetlePCE) at its pinned revision (tools/core-fork.sh).
#
# Output: build/cores/stage/{cores,info}/mednafen_pce_libretro.{so,info};
# build-title.sh stages those in /app0. It renders in software. CD games need a
# System Card image in system/ (syscard3.pce); HuCard and SuperGrafx games need none.
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
cd "$root"
core_name=beetle-pce
source "$root/tools/core-stamp.sh"
source "$root/tools/core-fork.sh"
core_stamp_skip beetle-pce \
    "$root/build/cores/stage/cores/mednafen_pce_libretro.so" \
    "$root/build/cores/stage/info/mednafen_pce_libretro.info" \
    -- "$root/tools/build-beetle-pce.sh" "$root/tools/core-fork.sh"
[[ $# == 0 ]] || { echo "usage: ${0##*/}" >&2; exit 2; }

revision=0a69bec30dfb503cfefdf6bf8dd0d2cd3b330060  # ../PS5_BeetlePCE main
core_fork_setup
core_fork_checkout PS5_BeetlePCE "$revision"
core_fork_info mednafen_pce_libretro.info ec52873e28177fb250108ec69ae889a7a258dc352c9d946c051345cc69fbe1db

# LDFLAGS goes in the environment: the makefiles add their own to it.
LDFLAGS="$core_ldflags $core_libs" make -C "$source_dir" -j"${JOBS:-16}" platform=ps5 CC="$core_cc" CXX="$core_cxx" AR="$AR"
core_fork_stage "$source_dir/mednafen_pce_libretro.so" "$core_info" "$revision" tools/build-beetle-pce.sh
