#!/usr/bin/env bash
# Build FreeType for the PS5 as a static archive, for EmulationStation's text
# (frontends/es-de; docs/FRONTENDS.md) and HarfBuzz under it.
#
# The release archive is pinned by digest: the same bytes from savannah.gnu.org and
# sourceforge.net (2026-10-04). Static, without the optional zlib, bzip2, PNG,
# Brotli and HarfBuzz back-ends: fonts are plain TrueType/OpenType files.
#
# Output: .deps/native/freetype-ps5 (lib/libfreetype.a, include/freetype2), with
# the version and this script's digest in .deps/native/freetype-ps5/.stamp.
set -euo pipefail

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
cd "$root"
version=2.13.3
digest=0550350666d427c74daeb85d5ac7bb353acba5f76956395995311a9c6f063289
prefix="$root/.deps/native/freetype-ps5"
stamp="$version $(sha256sum "$0" | cut -c1-64)"
[[ -f $prefix/.stamp && $(<"$prefix/.stamp") == "$stamp" ]] && {
    echo "==> [freetype] $version already built in $prefix"; exit 0; }

sdk="$root/.deps/native/ps5-payload-sdk"
[[ -x $sdk/bin/prospero-clang ]] || { echo "error: bootstrap this project's SDK first" >&2; exit 2; }
export PS5_PAYLOAD_SDK="$sdk" PS5_CLANG=${PS5_CLANG:-/usr/bin/clang}

archive="$root/.deps/downloads/freetype-$version.tar.xz"
mkdir -p "$root/.deps/downloads"
[[ -f $archive ]] || curl --fail --location --retry 3 \
    "https://download.savannah.gnu.org/releases/freetype/freetype-$version.tar.xz" -o "$archive"
printf '%s  %s\n' "$digest" "$archive" | sha256sum --check --status || {
    echo "error: FreeType archive digest mismatch" >&2; exit 1; }

build="$root/build/freetype-ps5"
rm -rf -- "$build"
mkdir -p "$build/src"
tar -xJf "$archive" -C "$build/src" --strip-components=1
cc="$sdk/bin/prospero-clang"
command -v ccache >/dev/null && cc="ccache $cc"
echo "==> [freetype] configuring $version"
(cd "$build/src" && ./configure --prefix="$prefix" --host=x86_64-unknown-freebsd14 \
    CC="$cc" AR="$sdk/bin/prospero-ar" RANLIB="$sdk/bin/prospero-ranlib" \
    CFLAGS="-O2 -march=znver2 -fPIC -ffunction-sections -fdata-sections" \
    --enable-static --disable-shared --without-zlib --without-bzip2 --without-png \
    --without-harfbuzz --without-brotli > "$build/configure.log" 2>&1) ||
    { tail -30 "$build/configure.log" >&2; exit 1; }
echo "==> [freetype] building"
make -C "$build/src" -j"${JOBS:-16}" > "$build/make.log" 2>&1 ||
    { tail -30 "$build/make.log" >&2; exit 1; }
rm -rf -- "$prefix"
make -C "$build/src" install > "$build/install.log" 2>&1 ||
    { tail -30 "$build/install.log" >&2; exit 1; }
rm -rf -- "$prefix/lib/pkgconfig" "$prefix/share/man" "$prefix/share/aclocal"
mkdir -p "$prefix/share/licenses/freetype"
cp "$build/src/LICENSE.TXT" "$build/src/docs/FTL.TXT" "$build/src/docs/GPLv2.TXT" "$prefix/share/licenses/freetype/"
printf '%s\n' "$stamp" > "$prefix/.stamp"
printf '==> [freetype] %s: %s in %s\n' "$version" "$(du -h "$prefix/lib/libfreetype.a" | cut -f1)" "$prefix"
