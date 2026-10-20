#!/usr/bin/env bash
# Build libwebp's decoder for the PS5 as a static archive, for EmulationStation's
# images (frontends/es-de/ps5/freeimage_stb.cpp): ES-DE's default theme draws its
# system art from WebP files, which stb_image does not read.
#
# The release archive is the WebM project's own (libwebp 1.6.0), pinned
# by its digest here; its src/ is the v1.6.0 tag's apart from the generated
# Makefile.in and config.h.in. Only the decoder is built (webpdecoder: still
# images, no threads), with the SDK's toolchain through libwebp's CMake.
#
# Output: .deps/native/libwebp-ps5 (lib/libwebpdecoder.a, include/webp/decode.h,
# include/webp/types.h), with the version and this script's digest in .stamp.
set -euo pipefail

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
cd "$root"
version=1.6.0
digest=e4ab7009bf0629fd11982d4c2aa83964cf244cffba7347ecd39019a9e38c4564
prefix="$root/.deps/native/libwebp-ps5"
stamp="$version $(sha256sum "$0" | cut -c1-64)"
[[ -f $prefix/.stamp && $(<"$prefix/.stamp") == "$stamp" ]] && {
    echo "==> [libwebp] $version already built in $prefix"; exit 0; }

sdk="$root/.deps/native/ps5-payload-sdk"
[[ -x $sdk/bin/prospero-clang ]] || { echo "error: bootstrap this project's SDK first" >&2; exit 2; }
export PS5_PAYLOAD_SDK="$sdk" PS5_CLANG=${PS5_CLANG:-/usr/bin/clang}

archive="$root/.deps/downloads/libwebp-$version.tar.gz"
mkdir -p "$root/.deps/downloads"
[[ -f $archive ]] || curl --fail --location --retry 3 \
    "https://storage.googleapis.com/downloads.webmproject.org/releases/webp/libwebp-$version.tar.gz" -o "$archive"
printf '%s  %s\n' "$digest" "$archive" | sha256sum --check --status || {
    echo "error: libwebp archive digest mismatch" >&2; exit 1; }

build="$root/build/libwebp-ps5"
rm -rf -- "$build"
mkdir -p "$build/src"
tar -xzf "$archive" -C "$build/src" --strip-components=1
cmake -S "$build/src" -B "$build/cmake" -G Ninja -DCMAKE_TOOLCHAIN_FILE="$sdk/toolchain/prospero.cmake" \
    -DCMAKE_BUILD_TYPE=Release -DCMAKE_C_FLAGS="-march=znver2 -ffunction-sections -fdata-sections" \
    -DBUILD_SHARED_LIBS=OFF -DWEBP_USE_THREAD=OFF -DWEBP_BUILD_ANIM_UTILS=OFF -DWEBP_BUILD_CWEBP=OFF \
    -DWEBP_BUILD_DWEBP=OFF -DWEBP_BUILD_GIF2WEBP=OFF -DWEBP_BUILD_IMG2WEBP=OFF -DWEBP_BUILD_VWEBP=OFF \
    -DWEBP_BUILD_WEBPINFO=OFF -DWEBP_BUILD_WEBPMUX=OFF -DWEBP_BUILD_EXTRAS=OFF -DWEBP_BUILD_LIBWEBPMUX=OFF \
    > "$build/configure.log" 2>&1 || { tail -30 "$build/configure.log" >&2; exit 1; }
ninja -C "$build/cmake" webpdecoder > "$build/build.log" 2>&1 ||
    { grep -E "error" "$build/build.log" | head -20 >&2; exit 1; }
rm -rf -- "$prefix"
mkdir -p "$prefix/lib" "$prefix/include/webp" "$prefix/share/licenses/libwebp"
cp "$build/cmake/libwebpdecoder.a" "$prefix/lib/"
cp "$build/src/src/webp/decode.h" "$build/src/src/webp/types.h" "$prefix/include/webp/"
cp "$build/src/COPYING" "$build/src/PATENTS" "$prefix/share/licenses/libwebp/"
printf '%s\n' "$stamp" > "$prefix/.stamp"
printf '==> [libwebp] %s: %s in %s\n' "$version" "$(du -h "$prefix/lib/libwebpdecoder.a" | cut -f1)" "$prefix"
