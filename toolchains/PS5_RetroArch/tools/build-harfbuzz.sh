#!/usr/bin/env bash
# Build HarfBuzz for the PS5 as a static archive, for EmulationStation's text
# shaping (es-core's Font; docs/FRONTENDS.md), over tools/build-freetype.sh's
# FreeType.
#
# The release archive is GitHub's, pinned by the digest GitHub publishes for it
# (14.5.1, 2026-09-30). HarfBuzz is built the way its README allows for embedding:
# the amalgamated src/harfbuzz.cc as one translation unit, with FreeType and
# without GLib, ICU or Graphite (it carries its own Unicode data).
#
# Output: .deps/native/harfbuzz-ps5 (lib/libharfbuzz.a, include/harfbuzz), with
# the version and this script's digest in .deps/native/harfbuzz-ps5/.stamp.
set -euo pipefail

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
cd "$root"
version=14.5.1
digest=7e2fa4e8c7c98e8d8140671f5772542afaaa6acccfbd746506886b6d85f7f8d6
prefix="$root/.deps/native/harfbuzz-ps5"
freetype="$root/.deps/native/freetype-ps5"
stamp="$version $(sha256sum "$0" | cut -c1-64) $(cat "$freetype/.stamp" 2>/dev/null)"
[[ -f $prefix/.stamp && $(<"$prefix/.stamp") == "$stamp" ]] && {
    echo "==> [harfbuzz] $version already built in $prefix"; exit 0; }
[[ -f $freetype/lib/libfreetype.a ]] || { echo "error: run tools/build-freetype.sh first" >&2; exit 2; }

sdk="$root/.deps/native/ps5-payload-sdk"
[[ -x $sdk/bin/prospero-clang ]] || { echo "error: bootstrap this project's SDK first" >&2; exit 2; }
export PS5_PAYLOAD_SDK="$sdk" PS5_CLANG=${PS5_CLANG:-/usr/bin/clang}

archive="$root/.deps/downloads/harfbuzz-$version.tar.xz"
mkdir -p "$root/.deps/downloads"
[[ -f $archive ]] || curl --fail --location --retry 3 \
    "https://github.com/harfbuzz/harfbuzz/releases/download/$version/harfbuzz-$version.tar.xz" -o "$archive"
printf '%s  %s\n' "$digest" "$archive" | sha256sum --check --status || {
    echo "error: HarfBuzz archive digest mismatch" >&2; exit 1; }

build="$root/build/harfbuzz-ps5"
rm -rf -- "$build"
mkdir -p "$build/src"
tar -xJf "$archive" -C "$build/src" --strip-components=1
cxx="$sdk/bin/prospero-clang++"
command -v ccache >/dev/null && cxx="ccache $cxx"
echo "==> [harfbuzz] building $version (one translation unit)"
$cxx -std=c++17 -O2 -march=znver2 -fPIC -ffunction-sections -fdata-sections -fno-exceptions -fno-rtti \
    -DHAVE_FREETYPE=1 -I"$freetype/include/freetype2" -c "$build/src/src/harfbuzz.cc" \
    -o "$build/harfbuzz.o" > "$build/compile.log" 2>&1 || { tail -30 "$build/compile.log" >&2; exit 1; }
rm -rf -- "$prefix"
mkdir -p "$prefix/lib" "$prefix/include/harfbuzz" "$prefix/share/licenses/harfbuzz"
"$sdk/bin/prospero-ar" rcs "$prefix/lib/libharfbuzz.a" "$build/harfbuzz.o"
# The public headers: hb.h and what it and hb-ft.h include.
for header in "$build/src/src"/hb.h "$build/src/src"/hb-*.h; do
    case $(basename "$header") in
        hb-*-private.h | hb-*.hh) ;;
        *) cp "$header" "$prefix/include/harfbuzz/" ;;
    esac
done
cp "$build/src/COPYING" "$prefix/share/licenses/harfbuzz/COPYING"
printf '%s\n' "$stamp" > "$prefix/.stamp"
printf '==> [harfbuzz] %s: %s in %s\n' "$version" "$(du -h "$prefix/lib/libharfbuzz.a" | cut -f1)" "$prefix"
