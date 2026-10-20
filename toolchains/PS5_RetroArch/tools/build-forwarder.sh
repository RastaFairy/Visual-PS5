#!/usr/bin/env bash
# PS5 RetroArch - build the Game Forwarder's two programs (forwarder/): the app every home
# screen tile runs (eboot.bin, linked as tools/build.sh links the title's, with nothing of
# RetroArch in it) and the launch payload a tile sends to the console's ELF loader
# (launch.elf, built with the payload SDK as the WebUI's daemon is). The WebUI copies both
# into each tile it makes. Run after the title's build, whose native tool this uses.
# Prints the folder holding them.
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
sdk="$root/.deps/native/ps5-payload-sdk"
native="$root/tooling/native"
tool="$root/build/host/ps5-native-tool"
out="$root/build/forwarder"
[[ -x $sdk/bin/prospero-clang ]] || { echo "error: no SDK at $sdk" >&2; exit 2; }
[[ -x $tool ]] || { echo "error: no $tool; build the title first (tools/build.sh)" >&2; exit 2; }
target=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["titleId"])' "$root/sce_sys/param.json")
[[ $target =~ ^[A-Z]{4}[0-9]{5}$ ]] || { echo "error: no title id in sce_sys/param.json" >&2; exit 2; }
rm -rf -- "$out"
mkdir -p "$out/obj"

# The launch payload: what it starts is this title.
PS5_PAYLOAD_SDK="$sdk" PS5_CLANG=${PS5_CLANG:-clang} "$sdk/bin/prospero-clang" -std=c11 -O2 -Wall -Wextra -Werror \
    -DFORWARDER_TARGET="\"$target\"" -o "$out/launch.elf" "$root/forwarder/launch.c" \
    -lSceSystemService -lSceUserService
grep -q "PS5RA-FORWARDER-TILE-ID-SLOT" "$out/launch.elf" ||
    { echo "error: launch.elf has no slot for a tile's title id" >&2; exit 1; }

# The tile's app.
cc() { PS5_PAYLOAD_SDK="$sdk" sh "$root/tooling/prospero-clang18" "$@"; }
cc -std=c11 -O2 -Wall -Wextra -Werror -ffunction-sections -fdata-sections \
    -c "$root/forwarder/tile.c" -o "$out/obj/tile.o"
for part in app_crt app_cpp_runtime; do
    cc -std=c++20 -O2 -Wall -Wextra -fno-exceptions -fno-rtti -ffunction-sections -fdata-sections \
        -c "$native/$part.cpp" -o "$out/obj/$part.o"
done
"$sdk/bin/prospero-lld" -T "$native/ps5-pie.ld" -L "$native" --eh-frame-hdr --error-limit=0 \
    --version-script "$native/app-symbols.map" --exclude-libs=ALL -e _start -o "$out/tile.elf" \
    "$out/obj/app_crt.o" "$out/obj/app_cpp_runtime.o" "$out/obj/tile.o" --as-needed "$sdk"/target/lib/*.so
# As tools/build.sh: an import only libkernel_sys or libScePosixForWebKit defines is null at
# run time (the spike's tile called sceLncUtilLaunchApp, null for a title, and faulted at 0).
mapfile -t null_imports < <(comm -23 \
    <("$sdk/bin/llvm-nm" -D --undefined-only "$out/tile.elf" | awk '$1 == "U" { sub(/@.*/, "", $2); print $2 }' |
        sort -u) \
    <(for stub in "$sdk"/target/lib/*.so; do
        case $(basename "$stub") in libkernel_sys.so | libScePosixForWebKit.so) continue ;; esac
        "$sdk/bin/llvm-nm" -D --defined-only "$stub" 2>/dev/null | awk '{ print $NF }'
    done | sort -u))
((${#null_imports[@]} == 0)) || { echo "error: the tile imports what no module exports: ${null_imports[*]}" >&2; exit 1; }
"$tool" link --in "$out/tile.elf" --out "$out/tile.module.elf" --stub-dir "$sdk/target/lib" \
    --module-sdk 0x02000009 --companion-sdk 0x08050001 --file-name eboot.elf >&2
"$tool" self --sign --in "$out/tile.module.elf" --out "$out/eboot.bin" --magic 0x1D3D154F >&2
printf '==> [forwarder] tile app %s bytes, launch payload %s bytes (starts %s)\n' \
    "$(stat -c %s "$out/eboot.bin")" "$(stat -c %s "$out/launch.elf")" "$target" >&2
printf '%s\n' "$out"
