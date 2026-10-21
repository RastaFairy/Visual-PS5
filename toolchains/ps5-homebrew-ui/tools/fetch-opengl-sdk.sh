#!/usr/bin/env bash
# ps5-homebrew-ui - Resolve the pinned ps5-opengl SDK, cached first.
# Copyright (C) 2026 BlackBearReloaded
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Reuses a verified SDK already under toolchains/. If none exists, it can seed
# one pinned official release archive (SHA-256 checked) into toolchains/ once.
# All other native build dependencies remain subject to local-only policy.

set -euo pipefail

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
version=1.0.2
archive_sha256=30d8e51dd062739b629346102be5932728ba714bc50b1bdcdf08306c8843d9a4
manifest_sha256=0d432edc9d648d6e0cccb4d5eb3db8484f10ba4b075b5ccf23edda3251b66360
archive_url="https://github.com/blackbearreloaded/ps5-opengl/releases/download/v${version}/ps5-opengl-sdk-${version}.tar.gz"

toolchains_root="${PS5HS_TOOLCHAINS_ROOT:-$(dirname "$root")}"
toolchains_root=$(cd -- "$toolchains_root" && pwd)
cache="$toolchains_root/ps5-opengl-sdk/.cache"
archive="$toolchains_root/ps5-opengl-sdk/ps5-opengl-sdk-$version.tar.gz"
extracted="$cache/ps5-opengl-sdk-$version"
prefix="$extracted/sdk"
mkdir -p "$cache" "$(dirname "$archive")"

verify_prefix() {
    local candidate=$1 actual
    [[ -f $candidate/manifest.sha256 ]] || return 1
    (cd "$candidate" && sha256sum --check --strict --quiet manifest.sha256) || return 1
    actual=$(sha256sum "$candidate/manifest.sha256" | cut -d' ' -f1)
    [[ $actual == "$manifest_sha256" ]]
}

# Existing extracted SDKs are accepted only if the files and manifest match the
# pinned release identity. No unverified directory is used as a compiler prefix.
local_prefixes=(
    "$prefix"
    "$toolchains_root/ps5-opengl-sdk/ps5-opengl-sdk-$version/sdk"
    "$toolchains_root/ps5-opengl-sdk/sdk"
    "$toolchains_root/ps5-opengl/build/sdk/ps5-opengl-gl46"
    "$toolchains_root/ps5-opengl-mihawk/build/sdk/ps5-opengl-gl46"
)
for candidate in "${local_prefixes[@]}"; do
    if verify_prefix "$candidate"; then
        printf '%s\n' "$candidate"
        exit 0
    fi
done

# An existing archive with the wrong hash is an explicit integrity failure;
# never replace or extract it silently.
if [[ -f $archive ]]; then
    if ! printf '%s  %s\n' "$archive_sha256" "$archive" | sha256sum --check --strict --status; then
        echo "ps5-opengl SDK archive checksum mismatch: $archive" >&2
        exit 2
    fi
else
    [[ ${PS5HS_ALLOW_PINNED_SDK_DOWNLOAD:-0} == 1 ]] || {
        echo "local-only: falta el tarball fijado o un SDK $version ya extraído y verificado dentro de toolchains/; la descarga del SDK oficial no está autorizada" >&2
        exit 2
    }
    download_tmp="$archive.download.$$"
    trap 'rm -f -- "$download_tmp"' EXIT
    echo "SDK OpenGL $version ausente localmente; recuperando release oficial con SHA-256 fijado." >&2
    if command -v curl >/dev/null 2>&1; then
        curl --fail --location --silent --show-error --retry 3 --connect-timeout 20 --max-time 1800 "$archive_url" --output "$download_tmp"
    elif command -v wget >/dev/null 2>&1; then
        wget --quiet --tries=3 --timeout=30 --output-document="$download_tmp" "$archive_url"
    else
        echo "No hay curl ni wget para obtener el SDK OpenGL fijado." >&2
        exit 2
    fi
    if ! printf '%s  %s\n' "$archive_sha256" "$download_tmp" | sha256sum --check --strict --status; then
        echo "ps5-opengl SDK downloaded archive checksum mismatch; it was discarded." >&2
        exit 2
    fi
    mv -- "$download_tmp" "$archive"
    trap - EXIT
fi

# Extract only the compiled SDK and its license/notice files into a shared local
# cache. The large verified archive is retained once under toolchains/ for reuse.
rm -rf -- "$extracted"
tar -xzf "$archive" -C "$cache" "ps5-opengl-sdk-$version/sdk" \
    "ps5-opengl-sdk-$version/LICENSE" "ps5-opengl-sdk-$version/LICENSES" \
    "ps5-opengl-sdk-$version/THIRD_PARTY_NOTICES.md"

verify_prefix "$prefix" || {
    echo "ps5-opengl SDK manifest verification failed: $prefix" >&2
    exit 2
}
printf '%s\n' "$prefix"
