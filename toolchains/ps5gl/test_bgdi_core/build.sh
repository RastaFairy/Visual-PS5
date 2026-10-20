#!/bin/bash
# First hardware test of the BennuGD2 interpreter core (bgdrtm+bgdi+common,
# statically linked, zero dlopen) on PS5. Runs game.dcb, a trivial
# `PROCESS MAIN() BEGIN RETURN; END` program with zero module imports -
# this only proves the interpreter loop itself boots, loads a DCB and
# executes an instance to completion on real hardware. No graphics/input/
# sound modules involved yet; those come once this boots clean.
set -e
here=$(cd "$(dirname "$0")" && pwd)
out=$here/out
TITLE_ID=${TITLE_ID:-PPSA00100}
TITLE_NAME=${TITLE_NAME:-bgdi core boot test}

PS5_PAYLOAD_SDK=${PS5_PAYLOAD_SDK:-/home/ruben/ps5-payload-sdk-pacbrew}
PS5LINK=${PS5LINK:-/home/ruben/Escritorio/release/ps5link-sdk}
SHARPPROSPERO=${SHARPPROSPERO:-/home/ruben/Escritorio/SharpProspero}
SM64=${SM64:-/home/ruben/Escritorio/release/sm64-ps5/ps5}
LIBC_PRX=${LIBC_PRX:-/home/ruben/Escritorio/SM64_PS5/ps5gpu/package/sce_module/libc.prx}
DOTNET_HOME=${DOTNET_HOME:-/home/ruben/.dotnet}
export PATH="$DOTNET_HOME:$PATH"

BENNUGD2=${BENNUGD2:-/home/ruben/BennuGD2}
CC=$PS5_PAYLOAD_SDK/bin/prospero-clang
INC="-I$here/include -I$BENNUGD2/core/include -I$BENNUGD2/core/bgdrtm -I$BENNUGD2/core/bgdi -I$BENNUGD2/core/common"
ZLIB_INC="-I$PS5_PAYLOAD_SDK/target/user/homebrew/include"
ZLIB_LIB=$PS5_PAYLOAD_SDK/target/user/homebrew/lib/libz.a
DEFS="-D__BGDI__ -D__STATIC__ -D__PROSPERO__ -DVERSION=\"2.0.0\""

mkdir -p "$out" "$out/zlib_objs"

echo ">>> compile bgdrtm+bgdi+common"
srcs="$BENNUGD2/core/bgdrtm/*.c $BENNUGD2/core/bgdi/main.c $BENNUGD2/core/common/files.c $BENNUGD2/core/common/xctype.c $BENNUGD2/core/common/b_crypt.c $here/stub_debug.c"
for f in $srcs; do
    name=$(basename "$f" .c)
    eval $CC -c -O1 -w $DEFS $INC $ZLIB_INC -o "$out/$name.o" "$f"
done

echo ">>> extract zlib objects"
(cd "$out/zlib_objs" && ar x "$ZLIB_LIB")

echo ">>> link"
objs=$(ls "$out"/*.o)
zobjs=$(ls "$out"/zlib_objs/*.o)
"$PS5LINK/linker/link_real" "$out/app.elf" "$PS5LINK/linker/crt1_ps5.o" $objs $zobjs | tail -5

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
cp "$here/game.dcb" "$pkg/data/game.dcb"
echo "done: $pkg"
