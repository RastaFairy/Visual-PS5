#!/usr/bin/env bash
# Reuse pinned zlib/minizip and RetroArch's bundled SHA-256 implementation.
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
mode=${1:-ps5}
build="$root/build/webui-update-$mode"
zlib="$root/.deps/native/zlib/zlib-1.3.2"
mbed="$root/vendor/retroarch/deps/mbedtls"
mkdir -p "$build"
if [[ $mode == ps5 ]]; then
    cc="$root/.deps/native/ps5-payload-sdk/bin/prospero-clang"
    ar="$root/.deps/native/ps5-payload-sdk/bin/prospero-ar"
else
    cc=cc; ar=ar
fi
for source in "$zlib/contrib/minizip/ioapi.c" "$zlib/contrib/minizip/unzip.c" "$mbed/sha256.c"; do
    "$cc" -O2 -fPIC -DUSE_FILE32API -DNOUNCRYPT -I"$zlib" -I"$mbed" -c "$source" -o "$build/$(basename "$source" .c).o"
done
"$ar" rcs "$build/libupdate.a" "$build/ioapi.o" "$build/unzip.o" "$build/sha256.o"
printf '%s\n' "$build/libupdate.a"
