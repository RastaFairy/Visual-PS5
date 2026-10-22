#!/usr/bin/env bash
# ps5-homebrew-ui - Resolve the locally packaged, hash-pinned PS5 OpenGL SDK.
# Copyright (C) 2026 BlackBearReloaded
# SPDX-License-Identifier: GPL-3.0-or-later
#
# This IDE package includes the SDK archive under toolchains/ps5-opengl-sdk/.
# The former upstream release URLs return 404; builds are intentionally local-only.

set -euo pipefail

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
version=1.0.2
archive_sha256=ca7d1f4bc1cc9ba22bb115ae10aaab9cee1072e5e5d157df7bc08c4cb56a99e0
manifest_sha256=700493a187604fa33b90b94416cb6faf702a4852de03e072eb79154faabd8d88

toolchains_root="${PS5HS_TOOLCHAINS_ROOT:-$(dirname "$root")}"
toolchains_root=$(cd -- "$toolchains_root" && pwd)
sdk_root="$toolchains_root/ps5-opengl-sdk"
cache="$sdk_root/.cache"
archive="$sdk_root/ps5-opengl-sdk-$version.tar.gz"
extracted="$cache/ps5-opengl-sdk-$version"
prefix="$extracted/sdk"
mkdir -p "$cache" "$sdk_root"

verify_prefix() {
    local candidate=$1 actual
    [[ -f $candidate/manifest.sha256 ]] || return 1
    (cd "$candidate" && sha256sum --check --strict --quiet manifest.sha256) || return 1
    actual=$(sha256sum "$candidate/manifest.sha256" | cut -d' ' -f1)
    [[ $actual == "$manifest_sha256" ]]
}

# Prefer a verified SDK directory; never use an unverified build cache.
local_prefixes=(
    "$prefix"
    "$root/.deps/ps5-opengl/ps5-opengl-sdk-$version/sdk"
    "$sdk_root/ps5-opengl-sdk-$version/sdk"
    "$sdk_root/sdk"
    "$toolchains_root/ps5-opengl/build/sdk/ps5-opengl-gl46"
    "$toolchains_root/ps5-opengl-mihawk/build/sdk/ps5-opengl-gl46"
)
for candidate in "${local_prefixes[@]}"; do
    if verify_prefix "$candidate"; then
        printf '%s\n' "$candidate"
        exit 0
    fi
done

# The self-contained IDE ZIP includes this file. Do not hit obsolete upstream
# release URLs or attempt a large source rebuild when the file is missing.
[[ -f $archive ]] || {
    echo "local-only: falta $archive. Usa el paquete del IDE que incluye el SDK OpenGL 1.0.2; No se consulta Internet." >&2
    exit 2
}
printf '%s  %s\n' "$archive_sha256" "$archive" | sha256sum --check --strict --status || {
    echo "ps5-opengl SDK archive checksum mismatch: $archive" >&2
    exit 2
}

rm -rf -- "$extracted"
tar -xzf "$archive" -C "$cache" "ps5-opengl-sdk-$version/sdk" \
    "ps5-opengl-sdk-$version/LICENSE" "ps5-opengl-sdk-$version/LICENSES" \
    "ps5-opengl-sdk-$version/THIRD_PARTY_NOTICES.md"

verify_prefix "$prefix" || {
    echo "ps5-opengl SDK manifest verification failed: $prefix" >&2
    exit 2
}
printf '%s\n' "$prefix"
