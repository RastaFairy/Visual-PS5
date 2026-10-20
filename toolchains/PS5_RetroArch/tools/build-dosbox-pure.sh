#!/usr/bin/env bash
# Cross-build DOSBox Pure's libretro core (MS-DOS), from my fork ../PS5_DOSBoxPure (github.com/mihawk-99/PS5_DOSBoxPure)
# at its pinned revision (tools/core-fork.sh).
#
# Output: build/cores/stage/{cores,info}/dosbox_pure_libretro.{so,info}; build-title.sh
# stages those in /app0. It renders in software; its dynamic x86 core's code cache is the console's executable memory (the fork's PS5 commit). Upstream is codeberg.org/schelling/dosbox-pure.
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
cd "$root"
core_name=dosbox-pure
source "$root/tools/core-stamp.sh"
source "$root/tools/core-fork.sh"
core_stamp_skip dosbox-pure \
    "$root/build/cores/stage/cores/dosbox_pure_libretro.so" \
    "$root/build/cores/stage/info/dosbox_pure_libretro.info" \
    -- "$root/tools/build-dosbox-pure.sh" "$root/tools/core-fork.sh"
[[ $# == 0 ]] || { echo "usage: ${0##*/}" >&2; exit 2; }

revision=6ad3c341308b8e2d2de2cf3bbcbe66aba40e3c06  # ../PS5_DOSBoxPure main
core_fork_setup
core_fork_checkout PS5_DOSBoxPure "$revision"
core_fork_info dosbox_pure_libretro.info e59629d975653c3c2a9ec64a112c524efe5aa16b7cf4093c2085222262fb88dd

# LDFLAGS goes in the environment: the makefiles add their own to it.
LDFLAGS="$core_ldflags $core_libs" make -C "$source_dir" -j"${JOBS:-16}" platform=ps5 \
    CC="$core_cc" CXX="$core_cxx" AR="$AR"
core_fork_stage "$source_dir/dosbox_pure_libretro.so" "$core_info" "$revision" tools/build-dosbox-pure.sh
