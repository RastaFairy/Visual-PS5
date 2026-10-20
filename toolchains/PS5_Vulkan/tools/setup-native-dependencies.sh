#!/usr/bin/env bash
# ps5-native-app-boilerplate - Native dependency bootstrapper.
# Copyright (C) 2026 BlackBearReloaded
# Copyright (C) 2026 Mihawk-99
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Installs the PS5 payload SDK (my fork, pinned below) and static zlib into the
# ignored cache.

set -euo pipefail

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
cache="$root/.deps/native"
sdk="$cache/ps5-payload-sdk"
zlib_directory="$cache/zlib"
zlib_root="$zlib_directory/root"
zlib_version="1.3.2"
zlib_source="$zlib_directory/zlib-$zlib_version"
zlib_archive="$zlib_directory/zlib-$zlib_version.tar.gz"
zlib_stamp="$zlib_root/.source-version"
# The payload SDK is my fork, ../PS5_PayloadSDK: the upstream v0.42 release with
# the PS5 platform layer (libps5platform.a, include/ps5platform) and the
# console's machine-context layout installed over it (platform/README.md
# there). The pinned revision is exported with git archive, so a build never
# depends on the fork's working tree, and the SDK directory records it.
sdk_fork="${PS5_PAYLOAD_SDK_FORK:-$root/../PS5_PayloadSDK}"
sdk_snapshot="${PS5_PAYLOAD_SDK_SNAPSHOT:-$root/../PS5_PayloadSDK-pinned-b83202be}"
sdk_revision=b83202be73e930050e00de0f1b4d9ec46c0391bf
zlib_url="https://zlib.net/fossils/zlib-$zlib_version.tar.gz"
zlib_hash="bb329a0a2cd0274d05519d61c667c062e06990d72e125ee2dfa8de64f0119d16"
skip_sdk=false

if [[ ${1:-} == "--skip-sdk" ]]; then
    skip_sdk=true
elif [[ $# -ne 0 ]]; then
    echo "usage: tools/setup-native-dependencies.sh [--skip-sdk]" >&2
    exit 2
fi

for command in wget unzip sha256sum tar make; do
    command -v "$command" >/dev/null || {
        echo "missing required command: $command" >&2
        exit 2
    }
done
compiler=$(command -v clang || command -v clang-18 || true)
archiver=$(command -v llvm-ar || command -v llvm-ar-18 || command -v ar || true)
ranlib=$(command -v llvm-ranlib || command -v llvm-ranlib-18 || command -v ranlib || true)
[[ -n $compiler && -n $archiver && -n $ranlib ]] || {
    echo "clang, an archive tool, and ranlib are required to build zlib" >&2
    exit 2
}

mkdir -p "$cache"

# The SDK ships its drivers and wrappers as scripts in bin/. A cache restored
# from an archive or copied from a filesystem without Unix permissions can lose
# the executable bit, and the build runs those scripts directly. Restore it
# rather than re-fetching.
restore_sdk_permissions() {
    [[ -d $sdk/bin ]] || return 0
    find "$sdk/bin" -maxdepth 1 -type f -exec chmod +x {} +
}

restore_sdk_permissions
if ! $skip_sdk && [[ ! -f $sdk/.ps5-sdk-revision || $(<"$sdk/.ps5-sdk-revision") != "$sdk_revision" ]]; then
    sdk_tree=$(mktemp -d)
    source_ready=false

    # Prefer a real local Git checkout when it contains the exact pinned commit.
    # This is useful for developers who keep full Git history in their workspace.
    if command -v git >/dev/null 2>&1 &&
        git -C "$sdk_fork" cat-file -e "$sdk_revision^{commit}" 2>/dev/null; then
        git -C "$sdk_fork" archive "$sdk_revision" | tar -x -C "$sdk_tree"
        source_ready=true
    fi

    # Release snapshots ship the exact upstream commit as ordinary files, without
    # a nested .git directory. Use that self-contained copy when available, so a
    # build does not depend on Git history or the upstream owner's account.
    if [[ $source_ready != true ]]; then
        snapshot_commit=$(python3 - "$sdk_snapshot/.ps5hs-source.json" <<'PY'
import json, sys
try:
    with open(sys.argv[1], encoding="utf-8") as f:
        d = json.load(f)
    print(d.get("sourceCommit") or d.get("commit") or "")
except Exception:
    print("")
PY
)
        if [[ $snapshot_commit == "$sdk_revision" &&
            -f "$sdk_snapshot/platform/tools/setup-sdk.sh" ]]; then
            tar -C "$sdk_snapshot" --exclude='.git' -cf - . | tar -xf - -C "$sdk_tree"
            source_ready=true
            echo "Using vendored PS5_PayloadSDK snapshot $sdk_revision" >&2
        fi
    fi

    if [[ $source_ready != true ]]; then
        rm -rf -- "$sdk_tree"
        echo "the pinned PS5 payload SDK source is unavailable locally. Expected Git commit $sdk_revision at $sdk_fork or vendored snapshot $sdk_snapshot" >&2
        exit 2
    fi
    bash "$sdk_tree/platform/tools/setup-sdk.sh" "$sdk" "$sdk_revision" "$cache" >&2
    rm -rf -- "$sdk_tree"
    restore_sdk_permissions
fi
if ! $skip_sdk && [[ ! -x "$sdk/bin/prospero-lld" || ! -d "$sdk/target/include" ]]; then
    echo "the pinned PS5 payload SDK is incomplete" >&2
    exit 2
fi

zlib_library=$(find "$zlib_root" -type f -name libz.a -print -quit 2>/dev/null || true)
if [[ -z $zlib_library || ! -f $zlib_root/usr/include/zlib.h ||
    ! -f $zlib_stamp || $(<"$zlib_stamp") != "$zlib_version" ]]; then
    echo "==> [deps] Building pinned zlib $zlib_version from source" >&2
    mkdir -p "$zlib_directory"
    if [[ -f $zlib_archive ]] &&
        ! printf '%s  %s\n' "$zlib_hash" "$zlib_archive" |
            sha256sum --check --strict >/dev/null 2>&1; then
        rm -f -- "$zlib_archive"
    fi
    if [[ ! -f $zlib_archive ]]; then
        wget -q "$zlib_url" -O "$zlib_archive.download"
        mv "$zlib_archive.download" "$zlib_archive"
    fi
    printf '%s  %s\n' "$zlib_hash" "$zlib_archive" | sha256sum --check --strict >/dev/null
    rm -rf -- "$zlib_source" "$zlib_root"
    tar -xzf "$zlib_archive" -C "$zlib_directory"
    mkdir -p "$zlib_root"
    jobs=${BUILD_JOBS:-$(nproc 2>/dev/null || printf '2')}
    (
        cd "$zlib_source"
        CC="$compiler" AR="$archiver" RANLIB="$ranlib" ./configure --static --prefix=/usr
        make -j "$jobs" CC="$compiler" AR="$archiver" RANLIB="$ranlib"
        make DESTDIR="$zlib_root" install
    ) >"$zlib_directory/build.log"
    printf '%s\n' "$zlib_version" >"$zlib_stamp"
    zlib_library=$(find "$zlib_root" -type f -name libz.a -print -quit 2>/dev/null || true)
fi
if [[ -z $zlib_library ]]; then
    echo "the pinned native zlib archive was not found after compilation" >&2
    exit 2
fi

printf 'SDK_ROOT=%s\nZLIB_INCLUDE=%s\nZLIB_ARCHIVE=%s\n' \
    "$sdk" "$zlib_root/usr/include" "$zlib_library"
