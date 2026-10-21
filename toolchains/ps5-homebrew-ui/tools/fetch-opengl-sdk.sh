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
    direct_url="https://github.com/blackbearreloaded/ps5-opengl/releases/download/v$version/ps5-opengl-sdk-$version.tar.gz"
    verified=false

    # Prefer the deterministic, pinned release URL. The GitHub API endpoint has
    # returned 404 in some environments even while release/CDN links are indexed;
    # resolve the known archive first, then verify bytes before using them.
    echo "SDK OpenGL $version ausente localmente; intentando el asset fijado del release oficial." >&2
    rm -f -- "$download_tmp"
    if command -v curl >/dev/null 2>&1; then
        if curl --fail --location --silent --show-error --retry 2 --connect-timeout 20 --max-time 1800 \
            "$direct_url" --output "$download_tmp"; then
            if printf '%s  %s\\n' "$archive_sha256" "$download_tmp" | sha256sum --check --strict --status; then
                mv -- "$download_tmp" "$archive"
                verified=true
            else
                echo "El asset de URL fija no coincide con el SHA-256 esperado; se descarta." >&2
                rm -f -- "$download_tmp"
            fi
        else
            rm -f -- "$download_tmp"
            echo "El asset de URL fija no respondió correctamente; se probará la API del release como alternativa." >&2
        fi
    elif command -v wget >/dev/null 2>&1; then
        if wget --quiet --tries=2 --timeout=30 --output-document="$download_tmp" "$direct_url"; then
            if printf '%s  %s\\n' "$archive_sha256" "$download_tmp" | sha256sum --check --strict --status; then
                mv -- "$download_tmp" "$archive"
                verified=true
            else
                echo "El asset de URL fija no coincide con el SHA-256 esperado; se descarta." >&2
                rm -f -- "$download_tmp"
            fi
        else
            rm -f -- "$download_tmp"
            echo "El asset de URL fija no respondió correctamente; se probará la API del release como alternativa." >&2
        fi
    else
        echo "No hay curl ni wget para descargar el SDK OpenGL fijado." >&2
        exit 2
    fi

    # Some deployments or mirrors may rename the archive; only then use the API
    # to discover the release asset URL. The downloaded file must still match the
    # exact SHA-256 pin, so a different/renamed release is never accepted.
    if [[ $verified != true ]]; then
        echo "Consultando API de GitHub para enumerar los assets del release v$version." >&2
        release_api="https://api.github.com/repos/blackbearreloaded/ps5-opengl/releases/tags/v$version"
        release_json="$cache/release-v$version.json"
        if command -v curl >/dev/null 2>&1; then
            if ! curl --fail --location --silent --show-error --retry 2 --connect-timeout 20 --max-time 90 \
                -H 'Accept: application/vnd.github+json' "$release_api" --output "$release_json"; then
                echo "La API del release no está disponible; la URL fija tampoco entregó el SDK." >&2
            fi
        elif command -v wget >/dev/null 2>&1; then
            if ! wget --quiet --tries=2 --timeout=30 --output-document="$release_json" "$release_api"; then
                echo "La API del release no está disponible; la URL fija tampoco entregó el SDK." >&2
            fi
        fi
        if [[ -s $release_json ]]; then
            mapfile -t archive_urls < <(python3 - "$release_json" <<'PY'
import json, sys
with open(sys.argv[1], encoding="utf-8") as source:
    release = json.load(source)
for asset in release.get("assets", []):
    name = asset.get("name", "")
    url = asset.get("browser_download_url", "")
    if name.startswith("ps5-opengl-sdk-") and name.endswith(".tar.gz") and url:
        print(url)
PY
)
            if (( ${#archive_urls[@]} == 0 )); then
                echo "El release v$version no publica ningún asset ps5-opengl-sdk-*.tar.gz." >&2
                python3 - "$release_json" >&2 <<'PY'
import json, sys
with open(sys.argv[1], encoding="utf-8") as source:
    release = json.load(source)
print("Assets disponibles: " + ", ".join(a.get("name", "<sin nombre>") for a in release.get("assets", [])))
PY
            fi
            for asset_url in "${archive_urls[@]}"; do
                rm -f -- "$download_tmp"
                echo "Verificando asset oficial alternativo: ${asset_url##*/}" >&2
                if command -v curl >/dev/null 2>&1; then
                    curl --fail --location --silent --show-error --retry 2 --connect-timeout 20 --max-time 1800 \
                        "$asset_url" --output "$download_tmp" || continue
                else
                    wget --quiet --tries=2 --timeout=30 --output-document="$download_tmp" "$asset_url" || continue
                fi
                if printf '%s  %s\\n' "$archive_sha256" "$download_tmp" | sha256sum --check --strict --status; then
                    mv -- "$download_tmp" "$archive"
                    verified=true
                    break
                fi
                echo "SHA-256 distinto; se descarta este asset sin extraerlo." >&2
            done
        fi
    fi

    if [[ $verified != true ]]; then
        echo "No se pudo obtener ningún asset del release v$version con SHA-256 $archive_sha256." >&2
        rm -f -- "$download_tmp"
        exit 2
    fi
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
