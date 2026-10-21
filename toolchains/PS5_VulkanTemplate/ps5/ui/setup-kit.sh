#!/usr/bin/env bash
# PS5 Vulkan Template - copy the pinned UI kit from this repository's toolchains/.
#
# The vendored PS5_VKHomebrewUI snapshot is intentionally stored without a nested
# .git directory. This script copies only its required local files and never
# clones, fetches or contacts GitHub.
#
# Copyright (C) 2026 Mihawk
# SPDX-License-Identifier: GPL-3.0-or-later
set -euo pipefail
root=$(cd -- "$(dirname -- "\${BASH_SOURCE[0]}")/../.." && pwd)
kit="$root/.deps/hui"
fork="\${PS5_VKHOMEBREWUI:-$root/../PS5_VKHomebrewUI}"
# SHA recorded in toolchains/REPOSITORY-VENDOR-REPORT.json for this local snapshot.
revision=2188642afbcc8d84d36149124f3d9e39dc1b1a05
stamp="$revision src assets/fonts assets/audio third_party/fonts"

if [[ ! -d $fork ]]; then
    echo "Local-only mode: PS5_VKHomebrewUI is missing under toolchains/: $fork" >&2
    exit 2
fi
if [[ ! -f $kit/.revision || $(<"$kit/.revision") != "$stamp" ]]; then
    for entry in src assets/fonts assets/audio third_party/fonts LICENSE THIRD_PARTY_NOTICES.md; do
        if [[ ! -e $fork/$entry ]]; then
            echo "Local-only mode: required UI kit path is missing from toolchains/: $fork/$entry" >&2
            exit 2
        fi
    done
    rm -rf -- "$kit"
    mkdir -p "$kit"
    for entry in src assets/fonts assets/audio third_party/fonts LICENSE THIRD_PARTY_NOTICES.md; do
        mkdir -p "$(dirname -- "$kit/$entry")"
        cp -R -- "$fork/$entry" "$kit/$entry"
    done
    echo "$stamp" > "$kit/.revision"
fi
echo "$kit"
