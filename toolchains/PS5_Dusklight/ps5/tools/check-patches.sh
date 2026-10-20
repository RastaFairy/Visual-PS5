#!/usr/bin/env bash
# Dusklight for the PlayStation 5 - do the Dawn and SDL3 patches still apply?
#
#   ps5/tools/check-patches.sh
#
# Aurora pins a Dawn commit and an SDL3 release (cmake/AuroraDependencyVersions.cmake),
# and both move when Dusklight moves. This fetches each at its pin, without
# Dawn's third-party sources, and tries ps5/patches/dawn.patch and sdl.patch on
# it. It does not build anything: a patch that applies can still fail to compile.
# (ps5/patches/dawn-abseil.patch is for one of those third-party sources and is
# not checked here.)
#
# SPDX-License-Identifier: MIT
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
versions="$root/vendor/dusklight/extern/aurora/cmake/AuroraDependencyVersions.cmake"
dawn_revision=$(sed -n 's/^_aurora_dependency_version(AURORA_DAWN_REF "\([0-9a-f]\{40\}\)".*/\1/p' "$versions")
sdl_tag=$(sed -n 's/^_aurora_dependency_version(AURORA_SDL3_REF "refs\/tags\/\([^"]*\)".*/\1/p' "$versions")
[[ -n $dawn_revision && -n $sdl_tag ]] || { echo "check-patches.sh: no Dawn or SDL3 pin in $versions" >&2; exit 2; }
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
status=0

git init -q "$work/dawn"
git -C "$work/dawn" remote add origin https://github.com/encounter/dawn.git
git -C "$work/dawn" fetch -q --depth 1 origin "$dawn_revision"
git -C "$work/dawn" checkout -q FETCH_HEAD
if git -C "$work/dawn" apply --check "$root/ps5/patches/dawn.patch"; then
    echo "dawn.patch applies to Dawn ${dawn_revision:0:10}"
else
    echo "dawn.patch does NOT apply to Dawn ${dawn_revision:0:10}"
    status=1
fi

git clone -q --depth 1 -b "$sdl_tag" https://github.com/libsdl-org/SDL.git "$work/sdl" 2>/dev/null
if git -C "$work/sdl" apply --check "$root/ps5/patches/sdl.patch"; then
    echo "sdl.patch applies to SDL $sdl_tag"
else
    echo "sdl.patch does NOT apply to SDL $sdl_tag"
    status=1
fi
exit $status
