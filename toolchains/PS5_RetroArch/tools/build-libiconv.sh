#!/usr/bin/env bash
# Build GNU libiconv for the PS5 as a static archive, for RPCS3's cellL10n (the
# PS3's character-set conversions; docs/RPCS3_PORT.md).
#
# The console's libc has no iconv, so the release is built from its signed
# source tarball (GNU, Bruno Haible's key 9001B85AF9E1B83DF1BDA942F5BE8B267C6A406D;
# the digest below is of the verified archive), static, without NLS.
#
# Output: .deps/native/libiconv-ps5 (lib/libiconv.a, include/iconv.h), with the
# version and this script's digest in .deps/native/libiconv-ps5/.stamp.
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
cd "$root"

version=1.18
digest=3b08f5f4f9b4eb82f151a7040bfd6fe6c6fb922efe4b1659c66ea933276965e8
prefix="$root/.deps/native/libiconv-ps5"
stamp="$version $(sha256sum "$0" | cut -c1-64)"
[[ -f $prefix/.stamp && $(<"$prefix/.stamp") == "$stamp" ]] && {
    echo "==> [libiconv] $version already built in $prefix"; exit 0; }

sdk="$root/.deps/native/ps5-payload-sdk"
[[ -x $sdk/bin/prospero-clang ]] || { echo "error: bootstrap this project's SDK first" >&2; exit 2; }
export PS5_PAYLOAD_SDK="$sdk" PS5_CLANG=${PS5_CLANG:-/usr/bin/clang}

archive="$root/.deps/downloads/libiconv-$version.tar.gz"
mkdir -p "$root/.deps/downloads"
[[ -f $archive ]] || curl --fail --location --retry 3 \
    "https://ftp.gnu.org/pub/gnu/libiconv/libiconv-$version.tar.gz" -o "$archive"
printf '%s  %s\n' "$digest" "$archive" | sha256sum --check --status || {
    echo "error: libiconv archive digest mismatch" >&2; exit 1; }
build="$root/build/libiconv-ps5"
rm -rf -- "$build"
mkdir -p "$build/src"
tar -xzf "$archive" -C "$build/src" --strip-components=1

cc="$sdk/bin/prospero-clang"
command -v ccache >/dev/null && cc="ccache $cc"
echo "==> [libiconv] configuring $version"
(cd "$build/src" && ./configure --prefix="$prefix" --host=x86_64-unknown-freebsd14 \
    CC="$cc" AR="$sdk/bin/prospero-ar" RANLIB="$sdk/bin/prospero-ranlib" \
    CFLAGS="-O2 -march=znver2 -fPIC" \
    --enable-static --disable-shared --disable-nls --disable-dependency-tracking \
    > "$build/configure.log" 2>&1) ||
    { tail -30 "$build/configure.log" >&2; tail -40 "$build/src/config.log" >&2; exit 1; }
echo "==> [libiconv] building"
# libcharset first: the library includes its localcharset.h, which the
# top-level Makefile copies into lib/.
make -C "$build/src/libcharset" -j"${JOBS:-16}" > "$build/make.log" 2>&1 &&
    make -C "$build/src" lib/localcharset.h >> "$build/make.log" 2>&1 &&
    make -C "$build/src/lib" -j"${JOBS:-16}" >> "$build/make.log" 2>&1 ||
    { tail -30 "$build/make.log" >&2; exit 1; }
rm -rf -- "$prefix"
mkdir -p "$prefix/lib" "$prefix/include"
# The library and its header; no programs, which link like executables.
cp "$build/src/lib/.libs/libiconv.a" "$prefix/lib/"
cp "$build/src/include/iconv.h.inst" "$prefix/include/iconv.h"
printf '%s\n' "$stamp" > "$prefix/.stamp"
printf '==> [libiconv] %s: %s in %s\n' "$version" "$(du -h "$prefix/lib/libiconv.a" | cut -f1)" "$prefix"
