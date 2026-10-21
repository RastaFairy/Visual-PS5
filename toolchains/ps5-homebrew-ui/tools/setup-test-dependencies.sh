#!/usr/bin/env bash
# ps5-native-app-boilerplate - Host test dependency bootstrapper.
# Copyright (C) 2026 BlackBearReloaded
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Uses a cached archive, or a pinned copy from toolchains/artifacts/ in IDE local-only mode.

set -euo pipefail

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
version="1.17.0"
directory="$root/.deps/test/googletest"
source="$directory/googletest-$version"
archive="$directory/googletest-$version.tar.gz"
stamp="$directory/.source-sha256"
url="https://github.com/google/googletest/archive/refs/tags/v$version.tar.gz"
hash="65fab701d9829d38cb77c14acdc431d2108bfdbf8979e40eb8ae567edf10b27c"

for command in wget sha256sum tar; do
    command -v "$command" >/dev/null || {
        echo "missing required command: $command" >&2
        exit 2
    }
done

mkdir -p "$directory"
if [[ -f $archive ]] &&
    ! printf '%s  %s\n' "$hash" "$archive" | sha256sum --check --strict >/dev/null 2>&1; then
    rm -f -- "$archive"
fi
if [[ ! -f $archive ]]; then
    temporary="$archive.download"
    rm -f -- "$temporary"
    if [[ ${PS5HS_LOCAL_TOOLCHAINS_ONLY:-0} == 1 ]]; then
        local_archive="${PS5HS_TOOLCHAINS_ROOT:-}/artifacts/googletest-$version.tar.gz"
        [[ -n ${PS5HS_TOOLCHAINS_ROOT:-} && -f $local_archive ]] || {
            echo "local-only: missing toolchains/artifacts/googletest-$version.tar.gz (pinned SHA-256 required)" >&2
            exit 2
        }
        cp -- "$local_archive" "$temporary"
    else
        wget -q "$url" -O "$temporary"
    fi
    printf '%s  %s\n' "$hash" "$temporary" | sha256sum --check --strict >/dev/null
    mv "$temporary" "$archive"
fi

if [[ ! -f $source/googletest/include/gtest/gtest.h ||
    ! -f $stamp || $(<"$stamp") != "$hash" ]]; then
    echo "==> [test-deps] Extracting GoogleTest $version" >&2
    rm -rf -- "$source"
    tar -xzf "$archive" -C "$directory"
    printf '%s\n' "$hash" >"$stamp"
fi

[[ -f $source/googletest/src/gtest-all.cc &&
    -f $source/googletest/src/gtest_main.cc ]] || {
    echo "the pinned GoogleTest source tree is incomplete" >&2
    exit 2
}
printf '%s\n' "$source"
