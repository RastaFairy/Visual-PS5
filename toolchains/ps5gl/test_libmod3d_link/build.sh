#!/bin/bash
# Link-feasibility test: compiles most of libmod_3d's own .c files (see
# filelist.txt - everything except libmod_3d.c, which needs the BennuGD2
# module ABI, and the test_*.c dev harnesses) against PS5GL's compat layer,
# then runs them through ps5link's real linker. No signing, no packaging -
# this never needs to run on the console, only to link.
set -e
here=$(cd "$(dirname "$0")" && pwd)
out=$here/out
LIBMOD3D=${LIBMOD3D:-/home/ruben/BennuGD2/modules/libmod_3d}
SDLGPU_INC=${SDLGPU_INC:-/home/ruben/BennuGD2/vendor/sdl-gpu/include}
PS5GL=${PS5GL:-/home/ruben/Escritorio/PS5GL}
PS5_PAYLOAD_SDK=${PS5_PAYLOAD_SDK:-/home/ruben/ps5-payload-sdk-pacbrew}
PS5LINK=${PS5LINK:-/home/ruben/Escritorio/release/ps5link-sdk}

CC=$PS5_PAYLOAD_SDK/bin/prospero-clang
INC="-I$here -I$PS5GL/compat -I$PS5GL/compat/stb -I$PS5GL/include -I$PS5GL/backend -I$SDLGPU_INC -I$LIBMOD3D"
mkdir -p "$out"

echo ">>> compiling PS5GL"
$CC -c -O1 -w $INC -o "$out/ps5gl.o" "$PS5GL/src/ps5gl.c"
$CC -c -O1 -w $INC -o "$out/ps5gpu.o" "$PS5GL/backend/ps5gpu.c"
$CC -c -O1 -w $INC -o "$out/ps5gl_sdl_compat.o" "$PS5GL/src/ps5gl_sdl_compat.c"

echo ">>> compiling main"
$CC -c -O1 -w $INC -o "$out/main.o" "$here/main.c"

echo ">>> compiling libmod_3d (see filelist.txt), C files as C, the raw-string ones as C++"
objs="$out/ps5gl.o $out/ps5gpu.o $out/ps5gl_sdl_compat.o $out/main.o"
fail=0
while read -r f; do
    name=$(basename "$f" .c)
    case "$name" in
        libmod_3d_shader|libmod_3d_smaa|libmod_3d_fsr) lang="c++";;
        *) lang="c";;
    esac
    if $CC -c -O1 -w -x $lang $INC -o "$out/$name.o" "$LIBMOD3D/$f" -x none 2>"$out/$name.err"; then
        objs="$objs $out/$name.o"
    else
        echo "!! $f failed to compile:"
        tail -5 "$out/$name.err"
        fail=1
    fi
done < "$here/filelist.txt"

if [ "$fail" = "1" ]; then
    echo ">>> some files failed to compile, linking with what did"
fi

echo ">>> linking with link_real"
"$PS5LINK/linker/link_real" "$out/app.elf" "$PS5LINK/linker/crt1_ps5.o" $objs 2>&1 | tee "$out/link.log"
