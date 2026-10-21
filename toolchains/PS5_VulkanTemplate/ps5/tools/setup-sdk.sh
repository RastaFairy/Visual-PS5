#!/usr/bin/env bash
# PS5 Vulkan Template - the payload SDK this title builds with, at a pinned revision.
#
#   ps5/tools/setup-sdk.sh       install it into .deps/native/ps5-payload-sdk (once a revision)
#
# The SDK source must be available locally at toolchains/PS5_PayloadSDK with the exact
# pinned revision in its local Git object database. Vendored snapshots without
# history are not silently substituted: they fail clearly rather than fetching
# an upstream. RADV's archive, link recipe and packaging tools stay PS5_Vulkan's.
#
# Copyright (C) 2026 Mihawk
# SPDX-License-Identifier: MIT
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
cache="$root/.deps/native"
sdk="$cache/ps5-payload-sdk"
sdk_fork="$root/../PS5_PayloadSDK"
# 611893f: /data through the Lapy daemon (ps5platform/elevation.h), an opt-in no sample calls.
# Never older than 6b63a2a, the platform layer's localeconv in the C locale (ps5_localeconv).
sdk_revision=611893fc25ef3e138f5bc2c90d829d8b58174cd2

if [[ ! -f $sdk/.ps5-sdk-revision || $(<"$sdk/.ps5-sdk-revision") != "$sdk_revision" ]]; then
    git -C "$sdk_fork" cat-file -e "$sdk_revision^{commit}" 2>/dev/null || {
        echo "Local-only mode: toolchains/PS5_PayloadSDK at $sdk_fork does not contain the required pinned Git revision $sdk_revision; no network fallback is available." >&2
        exit 2
    }
    mkdir -p "$cache"
    sdk_tree=$(mktemp -d)
    git -C "$sdk_fork" archive "$sdk_revision" | tar -x -C "$sdk_tree"
    bash "$sdk_tree/platform/tools/setup-sdk.sh" "$sdk" "$sdk_revision" "$cache" >&2
    rm -rf -- "$sdk_tree"
fi
[[ -x $sdk/bin/prospero-lld && -d $sdk/target/include ]] || { echo "the pinned PS5 payload SDK is incomplete" >&2; exit 2; }
echo "$sdk"
