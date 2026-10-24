#!/usr/bin/env bash
# PS5 Vulkan Template - the payload SDK this title builds with, at a pinned revision.
#
#   ps5/tools/setup-sdk.sh       install it into .deps/native/ps5-payload-sdk (once a revision)
#
# The SDK is my fork, ../PS5_PayloadSDK: the upstream release with the PS5
# platform layer (libps5platform.a, include/ps5platform) installed over it. The
# pinned revision is exported with git archive, so a build never depends on the
# fork's working tree, and the SDK directory records it, as PS5 RetroArch and
# PS5 vkQuake pin theirs. RADV's archive, its link recipe and the packaging
# tools stay PS5_Vulkan's.
#
# Copyright (C) 2026 Mihawk
# SPDX-License-Identifier: MIT
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
cache="$root/.deps/native"
sdk="$cache/ps5-payload-sdk"
sdk_fork="${PS5_PAYLOAD_SDK_FORK:-$root/../PS5_PayloadSDK}"
sdk_toolchains_root="${PS5HS_TOOLCHAINS_ROOT:-$root/..}"
sdk_snapshot="${PS5_PAYLOAD_SDK_SNAPSHOT:-$sdk_toolchains_root/PS5_PayloadSDK-pinned-611893fc}"
# 611893f: /data through the Lapy daemon (ps5platform/elevation.h), an opt-in no sample calls.
# Never older than 6b63a2a, the platform layer's localeconv in the C locale (ps5_localeconv).
sdk_revision=611893fc25ef3e138f5bc2c90d829d8b58174cd2

if [[ ! -f $sdk/.ps5-sdk-revision || $(<"$sdk/.ps5-sdk-revision") != "$sdk_revision" ]]; then
    sdk_tree=$(mktemp -d)
    source_ready=false

    # Full developer checkouts may export the pinned revision directly.
    if command -v git >/dev/null 2>&1 &&
        git -C "$sdk_fork" cat-file -e "$sdk_revision^{commit}" 2>/dev/null; then
        git -C "$sdk_fork" archive "$sdk_revision" | tar -x -C "$sdk_tree"
        source_ready=true
    fi

    # The IDE ships exact source snapshots without nested Git history.
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
        echo "the pinned PS5 payload SDK source is unavailable locally. Expected Git commit $sdk_revision at $sdk_fork or snapshot $sdk_snapshot" >&2
        exit 2
    fi

    # Keep the exact fork export, while using the IDE's offline-aware release resolver.
    [[ -f $sdk_fork/platform/tools/setup-sdk.sh ]] || {
        rm -rf -- "$sdk_tree"
        echo "the vendored payload SDK installer is missing at $sdk_fork/platform/tools/setup-sdk.sh" >&2
        exit 2
    }
    install -m 0644 "$sdk_fork/platform/tools/setup-sdk.sh" "$sdk_tree/platform/tools/setup-sdk.sh"
    mkdir -p "$cache"
    bash "$sdk_tree/platform/tools/setup-sdk.sh" "$sdk" "$sdk_revision" "$cache" >&2
    rm -rf -- "$sdk_tree"
fi
[[ -x $sdk/bin/prospero-lld && -d $sdk/target/include ]] || { echo "the pinned PS5 payload SDK is incomplete" >&2; exit 2; }
echo "$sdk"
