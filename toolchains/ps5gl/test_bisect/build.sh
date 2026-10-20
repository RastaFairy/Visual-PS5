#!/bin/bash
set -e
here=$(cd "$(dirname "$0")" && pwd)
out=$here/out
TITLE_ID=${TITLE_ID:-PPSA00098}
TITLE_NAME=${TITLE_NAME:-PS5GL bisect}

PS5_PAYLOAD_SDK=${PS5_PAYLOAD_SDK:-/home/ruben/ps5-payload-sdk-pacbrew}
PS5LINK=${PS5LINK:-/home/ruben/Escritorio/release/ps5link-sdk}
SHARPPROSPERO=${SHARPPROSPERO:-/home/ruben/Escritorio/SharpProspero}
SM64=${SM64:-/home/ruben/Escritorio/release/sm64-ps5/ps5}
LIBC_PRX=${LIBC_PRX:-/home/ruben/Escritorio/SM64_PS5/ps5gpu/package/sce_module/libc.prx}
DOTNET_HOME=${DOTNET_HOME:-/home/ruben/.dotnet}
export PATH="$DOTNET_HOME:$PATH"

CC=$PS5_PAYLOAD_SDK/bin/prospero-clang
mkdir -p "$out"

echo ">>> compile"
$CC -c -O1 -Wall -Wextra -I"$here" -o "$out/main.o" "$here/main_isolated.c"
$CC -c -O1 -Wall -Wextra -I"$here" -o "$out/ps5gl.o" "$here/ps5gl.c"
$CC -c -O1 -Wall -Wextra -I"$here" -o "$out/ps5gpu.o" "$here/ps5gpu.c"

echo ">>> link"
"$PS5LINK/linker/link_real" "$out/app.elf" "$PS5LINK/linker/crt1_ps5.o" "$out/main.o" "$out/ps5gl.o" "$out/ps5gpu.o" | tail -1

echo ">>> sign"
rm -f "$out/eboot.bin"
(cd "$SHARPPROSPERO/tools/SharpProspero.Bindings.Generator" &&
    dotnet run -c Release -- self --sign --in "$out/app.elf" --out "$out/eboot.bin") > "$out/sign.log" 2>&1 || true
[ -s "$out/eboot.bin" ] || { tail -20 "$out/sign.log"; echo "signing failed"; exit 1; }

echo ">>> package"
pkg=$out/$TITLE_ID
rm -rf "$pkg"
mkdir -p "$pkg/sce_sys" "$pkg/sce_module" "$pkg/data"
cp "$out/eboot.bin" "$pkg/"
cp "$SM64/package/sce_sys/icon0.png" "$pkg/sce_sys/"
sed -e "s/@TITLE_ID@/$TITLE_ID/g" -e "s/@TITLE_NAME@/$TITLE_NAME/g" "$SM64/package/sce_sys/param.json" > "$pkg/sce_sys/param.json"
cp "$LIBC_PRX" "$pkg/sce_module/libc.prx"
echo "done: $pkg"
