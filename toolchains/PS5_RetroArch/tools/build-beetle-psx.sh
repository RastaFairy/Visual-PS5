#!/usr/bin/env bash
# Cross-build Beetle PSX HW (mednafen_psx_hw), Mednafen's PlayStation core with its Vulkan
# renderer, from my fork ../PS5_BeetlePSX
# (github.com/mihawk-99/PS5_BeetlePSX) at its pinned revision (tools/core-fork.sh).
#
# Output: build/cores/stage/{cores,info}/mednafen_psx_hw_libretro.{so,info};
# build-title.sh stages those in /app0.
# The fork's platform=ps5 builds the Vulkan renderer alone and renders at 16x
# internal resolution with 8x MSAA by default. PlayStation games need a BIOS in
# system/ (scph5501.bin and the others the core info names).
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
cd "$root"
core_name=beetle-psx
source "$root/tools/core-stamp.sh"
source "$root/tools/core-fork.sh"
core_stamp_skip beetle-psx \
    "$root/build/cores/stage/cores/mednafen_psx_hw_libretro.so" \
    "$root/build/cores/stage/info/mednafen_psx_hw_libretro.info" \
    -- "$root/tools/build-beetle-psx.sh" "$root/tools/core-fork.sh"
[[ $# == 0 ]] || { echo "usage: ${0##*/}" >&2; exit 2; }

revision=9c3146aa9580850bf4af16a776e0dcccc5c1a71e  # ../PS5_BeetlePSX main
core_fork_setup
core_fork_checkout PS5_BeetlePSX "$revision"
core_fork_info mednafen_psx_hw_libretro.info 0790f04425488765bf3c199755036501f0ef09bc4af6b00cd516c209b4358940

# LDFLAGS goes in the environment: the makefiles add their own to it.
LDFLAGS="$core_ldflags $core_libs" make -C "$source_dir" -j"${JOBS:-16}" platform=ps5 CC="$core_cc" CXX="$core_cxx" AR="$AR"
core_fork_stage "$source_dir/mednafen_psx_hw_libretro.so" "$core_info" "$revision" tools/build-beetle-psx.sh
