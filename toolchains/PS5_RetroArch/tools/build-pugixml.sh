#!/usr/bin/env bash
# Build pugixml for the PS5 as a static archive, for EmulationStation's XML (its
# settings, systems and game lists; docs/FRONTENDS.md).
#
# The release archive is GitHub's, pinned by the digest GitHub publishes for it
# (v1.16, 2026-06-16): one source file, compiled as it is.
#
# Output: .deps/native/pugixml-ps5 (lib/libpugixml.a, include/pugixml.hpp,
# include/pugiconfig.hpp), with the version and this script's digest in .stamp.
set -euo pipefail

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
cd "$root"
version=1.16
digest=4cee1ca4aad395170f4c7a07824f3bdd41f28316c6e1e1090a1425b278ec0b4b
prefix="$root/.deps/native/pugixml-ps5"
stamp="$version $(sha256sum "$0" | cut -c1-64)"
[[ -f $prefix/.stamp && $(<"$prefix/.stamp") == "$stamp" ]] && {
    echo "==> [pugixml] $version already built in $prefix"; exit 0; }

sdk="$root/.deps/native/ps5-payload-sdk"
[[ -x $sdk/bin/prospero-clang ]] || { echo "error: bootstrap this project's SDK first" >&2; exit 2; }
export PS5_PAYLOAD_SDK="$sdk" PS5_CLANG=${PS5_CLANG:-/usr/bin/clang}

archive="$root/.deps/downloads/pugixml-$version.tar.gz"
mkdir -p "$root/.deps/downloads"
[[ -f $archive ]] || curl --fail --location --retry 3 \
    "https://github.com/zeux/pugixml/releases/download/v$version/pugixml-$version.tar.gz" -o "$archive"
printf '%s  %s\n' "$digest" "$archive" | sha256sum --check --status || {
    echo "error: pugixml archive digest mismatch" >&2; exit 1; }

build="$root/build/pugixml-ps5"
rm -rf -- "$build"
mkdir -p "$build/src"
tar -xzf "$archive" -C "$build/src" --strip-components=1
cxx="$sdk/bin/prospero-clang++"
command -v ccache >/dev/null && cxx="ccache $cxx"
$cxx -std=c++17 -O2 -march=znver2 -fPIC -ffunction-sections -fdata-sections \
    -c "$build/src/src/pugixml.cpp" -o "$build/pugixml.o" > "$build/compile.log" 2>&1 ||
    { tail -20 "$build/compile.log" >&2; exit 1; }
rm -rf -- "$prefix"
mkdir -p "$prefix/lib" "$prefix/include" "$prefix/share/licenses/pugixml"
"$sdk/bin/prospero-ar" rcs "$prefix/lib/libpugixml.a" "$build/pugixml.o"
cp "$build/src/src/pugixml.hpp" "$build/src/src/pugiconfig.hpp" "$prefix/include/"
cp "$build/src/LICENSE.md" "$prefix/share/licenses/pugixml/LICENSE.md"
printf '%s\n' "$stamp" > "$prefix/.stamp"
printf '==> [pugixml] %s: %s in %s\n' "$version" "$(du -h "$prefix/lib/libpugixml.a" | cut -f1)" "$prefix"
