#!/bin/bash
# First real-module boot test on PS5: bgdrtm+bgdi core (proven working) plus
# libmod_misc statically linked in via a hand-written fake_dl.h, running a
# DCB that does `IMPORT "libmod_misc"` and calls STRLEN("hello"). Proves the
# static module-loading path (dlibopen -> __fake_dl lookup -> functions_exports
# -> sysproc_add) works end to end and a real module function executes.
set -e
here=$(cd "$(dirname "$0")" && pwd)
out=$here/out
TITLE_ID=${TITLE_ID:-PPSA00100}
TITLE_NAME=${TITLE_NAME:-bgdi libmod_misc test}

PS5_PAYLOAD_SDK=${PS5_PAYLOAD_SDK:-/home/ruben/ps5-payload-sdk-pacbrew}
PS5LINK=${PS5LINK:-/home/ruben/Escritorio/release/ps5link-sdk}
SHARPPROSPERO=${SHARPPROSPERO:-/home/ruben/Escritorio/SharpProspero}
SM64=${SM64:-/home/ruben/Escritorio/release/sm64-ps5/ps5}
LIBC_PRX=${LIBC_PRX:-/home/ruben/Escritorio/SM64_PS5/ps5gpu/package/sce_module/libc.prx}
DOTNET_HOME=${DOTNET_HOME:-/home/ruben/.dotnet}
export PATH="$DOTNET_HOME:$PATH"

BENNUGD2=${BENNUGD2:-/home/ruben/BennuGD2}
PS5GL=${PS5GL:-/home/ruben/Escritorio/PS5GL}
SDLGPU_INC=${SDLGPU_INC:-$BENNUGD2/vendor/sdl-gpu/include}
CC=$PS5_PAYLOAD_SDK/bin/prospero-clang
INC="-I$here/include -I$BENNUGD2/core/include -I$BENNUGD2/core/bgdrtm -I$BENNUGD2/core/bgdi -I$BENNUGD2/core/common -I$PS5GL/compat -I$PS5GL/compat/stb -I$PS5GL/include -I$PS5GL/backend -I$SDLGPU_INC -I$BENNUGD2/modules/libmod_misc"
ZLIB_INC="-I$PS5_PAYLOAD_SDK/target/user/homebrew/include"
ZLIB_LIB=$PS5_PAYLOAD_SDK/target/user/homebrew/lib/libz.a
DEFS="-D__BGDI__ -D__STATIC__ -D__PROSPERO__ -DVERSION=\"2.0.0\""

mkdir -p "$out" "$out/zlib_objs"

echo ">>> compile bgdrtm+bgdi+common"
srcs="$BENNUGD2/core/bgdrtm/*.c $BENNUGD2/core/bgdi/main.c $BENNUGD2/core/common/files.c $BENNUGD2/core/common/xctype.c $BENNUGD2/core/common/b_crypt.c $here/../test_bgdi_core/stub_debug.c"
for f in $srcs; do
    name=$(basename "$f" .c)
    eval $CC -c -O1 -w $DEFS $INC $ZLIB_INC -o "$out/$name.o" "$f"
done

echo ">>> compile PS5GL"
for f in "$PS5GL/src/ps5gl.c" "$PS5GL/backend/ps5gpu.c" "$PS5GL/src/ps5gl_sdl_compat.c"; do
    name=$(basename "$f" .c)
    eval $CC -c -O1 -w $DEFS $INC -o "$out/$name.o" "$f"
done

echo ">>> compile libmod_misc"
for f in "$BENNUGD2/modules/libmod_misc"/*.c; do
    name=$(basename "$f" .c)
    eval $CC -c -O1 -w $DEFS $INC -o "$out/$name.o" "$f"
done

echo ">>> extract zlib objects"
[ -f "$out/zlib_objs/adler32.o" ] || (cd "$out/zlib_objs" && ar x "$ZLIB_LIB")

echo ">>> link"
objs=$(ls "$out"/*.o)
zobjs=$(ls "$out"/zlib_objs/*.o)
"$PS5LINK/linker/link_real" "$out/app.elf" "$PS5LINK/linker/crt1_ps5.o" $objs $zobjs | tail -10

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
