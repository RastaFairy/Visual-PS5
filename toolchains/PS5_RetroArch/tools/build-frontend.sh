#!/usr/bin/env bash
# PS5 RetroArch - build an SDL2/OpenGL frontend executable beside eboot.bin.
#
#   tools/build-frontend.sh sdl-probe     frontends/sdl-probe -> dist/<TITLE>/es-de/sdl-probe.bin
#
# Why a second executable. EmulationStation draws with OpenGL, which on this
# console is ../PS5_OpenGL's stack: Mesa, as RADV is, so the two cannot share
# one image. LoadExec starts another executable of the title with its arguments
# (evidence/loadexec-second-image/), so a frontend is its own program in /app0,
# built the way ../PS5_OpenGL builds its SDL2 consumers
# (integration/SDL2/folder.py there): its runtime shims and heap, its linker
# script over this project's base layout, a 256 MiB libc heap, SDL2 from its
# bridge (integration/SDL2/build.py native) and the OpenGL SDK's static archive
# and AGC import stubs. The C runtime, the native module tool and the payload
# SDK are this project's, so the executable and eboot.bin share one libc.prx.
#
# Inputs, overridable:
#   PS5_OPENGL      ../PS5_OpenGL                       the bridge and native-app sources
#   PS5_OPENGL_SDK  $PS5_OPENGL/build/sdk/ps5-opengl-gl46
#   PS5_SDL2        the newest $PS5_OPENGL/build/sdl2-retroarch-*/sdk
# Run after tools/build-title.sh: the title folder it writes is where this goes.
set -euo pipefail

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
program=${1:?usage: tools/build-frontend.sh <program in frontends/>}
[[ $program =~ ^[a-z0-9-]+$ && -d $root/frontends/$program ]] ||
    { echo "no frontend program frontends/$program" >&2; exit 2; }

opengl=${PS5_OPENGL:-$root/../PS5_OpenGL}
gl_sdk=${PS5_OPENGL_SDK:-$opengl/build/sdk/ps5-opengl-gl46}
sdl=${PS5_SDL2:-$(ls -d "$opengl"/build/sdl2-retroarch-*/sdk 2>/dev/null | sort | tail -1)}
sdk="$root/.deps/native/ps5-payload-sdk"
native="$root/tooling/native"
tool="$root/build/host/ps5-native-tool"
title_id=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["titleId"])' "$root/sce_sys/param.json")
app="$root/dist/$title_id"
work="$root/build/frontend/$program"

for input in "$gl_sdk/lib/libPS5OpenGLCore33.a" "$gl_sdk/lib/libSceAgc.so" "$gl_sdk/lib/libSceAgcDriver.so" \
    "$sdl/lib/libSDL2.a" "$opengl/native-app/runtime_shims.c" "$opengl/native-app/app_heap.c" \
    "$opengl/native-app/ps5-pie.ld" "$opengl/native-app/app-symbols.map" "$tool" "$app/eboot.bin"; do
    [[ -e $input ]] || { echo "missing input: $input (build the title, the GL SDK and SDL2 first)" >&2; exit 2; }
done

# A program's own inputs beyond SDL2 and OpenGL: frontends/<program>/link.sh, when
# there is one, builds them and sets extra_includes, extra_system_includes,
# extra_archives and extra_link_flags.
extra_includes=() extra_system_includes=() extra_archives=() extra_link_flags=()
# shellcheck source=/dev/null
[[ ! -f $root/frontends/$program/link.sh ]] || source "$root/frontends/$program/link.sh"
for input in "${extra_archives[@]}"; do
    [[ -f $input ]] || { echo "missing archive: $input (frontends/$program/link.sh)" >&2; exit 2; }
done
includes=(-I"$sdl/include" -I"$sdl/include/SDL2" -I"$gl_sdk/include" -I"$root/src")
for include in "${extra_includes[@]}"; do includes+=(-I"$include"); done
for include in "${extra_system_includes[@]}"; do includes+=(-isystem "$include"); done

rm -rf "$work"
mkdir -p "$work/obj" "$work/tooling/native"
cc=(env PS5_PAYLOAD_SDK="$sdk" sh "$root/tooling/prospero-clang18")
common=(-O2 -Wall -Wextra -ffunction-sections -fdata-sections)
"${cc[@]}" -std=c++20 "${common[@]}" -fno-exceptions -fno-rtti -c "$native/app_crt.cpp" -o "$work/obj/app_crt.o"
"${cc[@]}" -std=c++20 "${common[@]}" -fno-exceptions -fno-rtti -c "$native/app_cpp_runtime.cpp" \
    -o "$work/obj/app_cpp_runtime.o"
for shim in runtime_shims app_heap; do
    "${cc[@]}" -std=c11 "${common[@]}" -c "$opengl/native-app/$shim.c" -o "$work/obj/$shim.o"
done
objects=()
while IFS= read -r -d '' source; do
    object="$work/obj/$(basename "${source%.*}").o"
    case $source in
        *.c) "${cc[@]}" -std=c11 "${common[@]}" "${includes[@]}" -c "$source" -o "$object" ;;
        *) "${cc[@]}" -std=c++17 "${common[@]}" "${includes[@]}" -c "$source" -o "$object" ;;
    esac
    objects+=("$object")
done < <(find "$root/frontends/$program" "$root/frontends/common" -type f \( -name '*.c' -o -name '*.cpp' \) \
    -print0 | sort -z)
# The contracts every frontend shares with eboot.bin, the same files it is built with:
# game mode (src/ps5_game.h), how a frontend starts a game, and the game library
# (src/ps5_library.h), what a frontend shows, read from RetroArch's playlists.
for contract in ps5_game ps5_library ps5_webui_qr; do
    "${cc[@]}" -std=c11 "${common[@]}" "${includes[@]}" -I"$root/third_party" -c "$root/src/$contract.c" -o "$work/obj/$contract.o"
    objects+=("$work/obj/$contract.o")
done
# The link that keeps the WebUI's daemon up while the frontend shows (src/webui_link.h).
"${cc[@]}" -std=c++17 "${common[@]}" "${includes[@]}" -c "$root/src/webui_link.cpp" -o "$work/obj/webui_link.o"
objects+=("$work/obj/webui_link.o")

# ../PS5_OpenGL's linker script includes this project's base layout by that path.
cp "$native/ps5-pie.ld" "$work/tooling/native/ps5-pie-base.ld"
cp "$opengl/native-app/ps5-pie.ld" "$opengl/native-app/app-symbols.map" "$work/tooling/native/"
# The platform layer's libc (ps5platform/libc.h in the SDK): functions the console
# has not, or refuses to a title (access, the directory functions), and FreeBSD's
# locale variants libc++ calls, bound by name as ../PS5_Vulkan's tools/radv-link.sh
# binds them for eboot.bin, so a frontend sees the files RetroArch sees. Only names
# the platform defines are bound, and not the ones ../PS5_OpenGL's shims define
# (mkstemps, openlog, popen, pclose); the version script keeps every one local.
# (iswctype_l was frontends/common's until the platform answered FreeBSD's masks
# itself: PS5_PayloadSDK b5efad5.)
#
# That list is eboot.bin's. A frontend imports more of the functions the platform
# replaces (ES-DE's first start called readlink, which no module exports to a title,
# through a null import: klog/run-PPSA99169-155300.log), so after each link every
# import the platform has a ps5_ version of is bound too, and the program linked
# again, until none is left. Only imports are added: --defsym silently replaces a
# definition, and an imported name has none in the program. The platform's
# pthread_exit is in its threads object, which wraps pthread_create, _join and
# _detach (a thread asking for no stack size gets the main thread's 2 MiB): the
# link wraps them as eboot.bin's does (../PS5_Vulkan's tools/radv-link.sh).
platform="$sdk/target/lib/libps5platform.a"
mapfile -t replaced < <("$sdk/bin/llvm-nm" --defined-only "$platform" 2>/dev/null |
    awk '$2 ~ /^[TDR]$/ && $3 ~ /^ps5_/ { print substr($3, 5) }' | sort -u)
declare -A is_replaced=()
for name in "${replaced[@]}"; do is_replaced[$name]=1; done
own=" mkstemps openlog popen pclose "
bindings=()
bind() { [[ $own == *" $1 "* ]] || bindings+=("--defsym=$1=ps5_$1"); }
for name in qsort_r __xuname __assert regcomp regexec regfree regerror localtime_r newlocale freelocale \
        strtod_l strtof_l dladdr utimensat localeconv_l strtoll_l strtoull_l strtold_l snprintf_l sscanf_l \
        asprintf_l strcoll_l strxfrm_l strftime_l wcscoll_l wcsxfrm_l btowc_l wctob_l iswctype_l mbrlen_l \
        mbrtowc_l mbsrtowcs_l mbsnrtowcs_l wcrtomb_l wcsnrtombs_l mbtowc_l ___mb_cur_max_l ___runetype_l \
        ___tolower_l ___toupper_l __runes_for_locale catopen catgets catclose __cxa_thread_atexit_impl \
        localeconv arc4random arc4random_buf arc4random_uniform gmtime_r statvfs fstatvfs futimens \
        clock_nanosleep getaddrinfo freeaddrinfo if_nameindex if_freenameindex if_nametoindex opendir \
        fdopendir readdir rewinddir dirfd closedir nl_langinfo nl_langinfo_l getpwuid_r posix_fallocate \
        access openat unlinkat fchmodat fstatat mkdirat renameat memfd_create; do
    [[ -z ${is_replaced[$name]:-} ]] || bind "$name"
done
builtins="$(clang --print-resource-dir)/lib/linux/libclang_rt.builtins-x86_64.a"
[[ -f $builtins ]] || { echo "no compiler builtins at $builtins" >&2; exit 2; }
link_program() (
    cd "$work"
    "$sdk/bin/prospero-lld" -T tooling/native/ps5-pie.ld -L tooling/native --eh-frame-hdr --error-limit=0 \
        --wrap=malloc --wrap=calloc --wrap=realloc --wrap=free --wrap=posix_memalign --wrap=malloc_usable_size \
        --wrap=pthread_create --wrap=pthread_join --wrap=pthread_detach "${bindings[@]}" "${extra_link_flags[@]}" \
        --Map="$work/$program.map" --version-script tooling/native/app-symbols.map --exclude-libs=ALL \
        -e _start -o "$work/$program.elf" obj/app_crt.o obj/app_cpp_runtime.o obj/runtime_shims.o obj/app_heap.o \
        "${objects[@]}" -L "$sdk/target/lib" -L "$gl_sdk/lib" \
        --start-group "${extra_archives[@]}" "$sdl/lib/libSDL2.a" "$gl_sdk/lib/libPS5OpenGLCore33.a" \
        "$sdk/target/lib/libunwind.a" "$sdk/target/lib/libc++abi.a" "$sdk/target/lib/libc++.a" "$platform" "$builtins" \
        --end-group --as-needed "$sdk"/target/lib/*.so "$gl_sdk/lib/libSceAgc.so" "$gl_sdk/lib/libSceAgcDriver.so"
)
# The imports the platform replaces that are not bound yet, apart from the
# program's own (which are defined, so never imports).
unbound_imports() {
    comm -12 <("$sdk/bin/llvm-nm" -D --undefined-only "$work/$program.elf" | awk '{ sub(/@.*/, "", $2); print $2 }' |
        sort -u) <(printf '%s\n' "${replaced[@]}") |
        while read -r name; do
            [[ " ${bindings[*]} " == *" --defsym=$name=ps5_$name "* || $own == *" $name "* ]] || echo "$name"
        done
}
link_program
added=()
for pass in 1 2 3; do
    mapfile -t more < <(unbound_imports)
    ((${#more[@]})) || break
    for name in "${more[@]}"; do bind "$name"; added+=("$name"); done
    link_program
done
mapfile -t more < <(unbound_imports)
((${#more[@]} == 0)) || { echo "error: imports the platform replaces are still unbound: ${more[*]}" >&2; exit 1; }
# A title loads libkernel, not libkernel_sys: an import only libkernel_sys's stub
# defines is null at run time (pathconf was, for libc++'s current_path).
mapfile -t sys_only < <(comm -23 \
    <("$sdk/bin/llvm-nm" -D --undefined-only "$work/$program.elf" | awk '{ sub(/@.*/, "", $2); print $2 }' | sort -u) \
    <(for stub in "$sdk"/target/lib/*.so "$gl_sdk/lib/libSceAgc.so" "$gl_sdk/lib/libSceAgcDriver.so"; do
        [[ $(basename "$stub") == libkernel_sys.so ]] ||
            "$sdk/bin/llvm-nm" -D --defined-only "$stub" 2>/dev/null | awk '{ print $NF }'
    done | sort -u))
((${#sys_only[@]} == 0)) ||
    { echo "error: imports no module a title loads exports (only libkernel_sys): ${sys_only[*]}" >&2; exit 1; }
printf '==> [frontend] %s: %s platform functions bound (imported beyond eboot.bin'"'"'s list: %s)\n' "$program" \
    "${#bindings[@]}" "${added[*]:-none}"
"$tool" link --in "$work/$program.elf" --out "$work/$program.module.elf" --stub-dir "$sdk/target/lib" \
    --stub "$gl_sdk/lib/libSceAgc.so" --stub "$gl_sdk/lib/libSceAgcDriver.so" \
    --module-sdk 0x02000009 --companion-sdk 0x08050001 --file-name "$program.elf" --libc-heap-size 0x10000000
mkdir -p "$app/es-de"
"$tool" self --sign --in "$work/$program.module.elf" --out "$app/es-de/$program.bin" --magic 0x1D3D154F
printf '==> [frontend] %s: %s bytes at es-de/%s.bin (SDL2 %s, GL SDK %s)\n' "$program" \
    "$(stat -c %s "$app/es-de/$program.bin")" "$program" "${sdl#"$opengl/"}" "${gl_sdk#"$opengl/"}"
# What the program reads beside it: frontends/<program>/stage.sh, when there is one.
# shellcheck source=/dev/null
[[ ! -f $root/frontends/$program/stage.sh ]] || source "$root/frontends/$program/stage.sh"
