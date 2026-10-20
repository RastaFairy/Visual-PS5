#!/usr/bin/env bash
# Cross-build MAME's libretro core (arcade and more), from my fork ../PS5_MAME
# (github.com/mihawk-99/PS5_MAME) at its pinned revision (tools/core-fork.sh).
#
# Output: build/cores/stage/{cores,info}/mame_libretro.{so,info}; build-title.sh
# stages those in /app0. Every driver is built (the full MAME), with the libretro
# OSD and none of its optional host modules (MIDI, PortAudio, BGFX, OpenGL,
# networking). The fork's PS5 defaults draw MAME's output at 4K through its
# alternate renderer.
#
# MAME's build directory is inside its tree and holds thousands of objects, so
# the checkout's clean spares build/, and ccache (with the tree as its base
# directory) serves a rebuild; precompiled headers are off, since ccache cannot
# cache what compiles against one. A first build takes about an hour and a half.
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
cd "$root"
core_name=mame
source "$root/tools/core-stamp.sh"
source "$root/tools/core-fork.sh"
core_stamp_skip mame \
    "$root/build/cores/stage/cores/mame_libretro.so" \
    "$root/build/cores/stage/info/mame_libretro.info" \
    -- "$root/tools/build-mame.sh" "$root/tools/core-fork.sh"
[[ $# == 0 ]] || { echo "usage: ${0##*/}" >&2; exit 2; }

revision=8f90a8135ef402e04042160537b76cf6b17bcfa5  # ../PS5_MAME main
core_fork_setup
core_fork_checkout PS5_MAME "$revision" "" build/
core_fork_info mame_libretro.info c3a2f1e0d816debfd06e76d427c46fccbce6a7d5fd9b0199754f046348e55509

# make rebuilds only what changed on disk, not what changed in the flags, so a
# new build configuration (MAME's scripts/, which GENie turns into makefiles, or
# this script) starts from an empty build/; ccache makes that cheap.
configuration="$(git -C "$source_dir" rev-parse "$revision:scripts") $(sha256sum < "$root/tools/build-mame.sh")"
if [[ ! -f $source_dir/build/.configuration || $(<"$source_dir/build/.configuration") != "$configuration" ]]; then
    rm -rf -- "$source_dir/build"
    mkdir -p "$source_dir/build"
    printf '%s\n' "$configuration" > "$source_dir/build/.configuration"
fi

# MAME's makefile finds clang by running $(CC) --version, which the SDK's
# wrapper does not answer the way it expects, so the version is given; without
# it the FreeBSD target is taken for GCC.
export CCACHE_BASEDIR="$source_dir" CCACHE_SLOPPINESS=time_macros
make -C "$source_dir" -j"${JOBS:-10}" OSD=retro CONFIG=libretro TARGETOS=freebsd PTR64=1 \
    CLANG_VERSION="$("$CC" --version | sed -n 's/.*clang version \([0-9.]*\).*/\1/p' | head -n1)" \
    PRECOMPILE=0 NOWERROR=1 REGENIE=1 CROSS_BUILD=1 PYTHON_EXECUTABLE=python3 \
    NO_USE_MIDI=1 NO_USE_PORTAUDIO=1 NO_USE_BGFX=1 DONT_USE_NETWORK=1 NO_OPENGL=1 USE_QTDEBUG=0 \
    OVERRIDE_CC="$core_cc" OVERRIDE_CXX="$core_cxx" OVERRIDE_AR="$AR" \
    `# The libretro version script is set on the OSD's static library, which a` \
    `# final link does not see: without it here the core exports all of MAME.` \
    LDOPTS="$core_ldflags $core_libs -Wl,--version-script=$source_dir/src/osd/libretro/libretro-internal/link.T"
core_fork_stage "$source_dir/mame_libretro.so" "$core_info" "$revision" tools/build-mame.sh
