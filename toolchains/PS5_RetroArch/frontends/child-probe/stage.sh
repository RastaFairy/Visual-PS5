# PS5 RetroArch - the local-process probe's headless child (frontends/child-probe-helper).
# Sourced by tools/build-frontend.sh (child-probe) after the probe is signed, with
# $root, $app, $sdk, $tool and $work set. Built as ../PS5_Proton builds its proven
# helper: freestanding C, ordinary libkernel its only dependency, the native tool's
# standard layout, and the libc-only preload mask in its process parameters
# (--preload-prx-flags 0x8000000000000002), signed into es-de/child-helper.bin.
# shellcheck shell=bash
helper_work="$work/helper"
mkdir -p "$helper_work"
env PS5_PAYLOAD_SDK="$sdk" sh "$root/tooling/prospero-clang18" -std=c11 -O2 -fPIC -ffreestanding -fno-builtin \
    -fno-omit-frame-pointer -funwind-tables -c "$root/frontends/child-probe-helper/helper.c" -o "$helper_work/helper.o"
"$sdk/bin/prospero-lld" -pie --eh-frame-hdr -T "$root/tooling/native/ps5-pie.ld" \
    --version-script "$root/tooling/native/app-symbols.map" -e _start -o "$helper_work/helper.elf" \
    "$helper_work/helper.o" "$sdk/target/lib/libkernel.so"
helper_needed=$(llvm-readelf -d "$helper_work/helper.elf" 2>/dev/null | grep -c '(NEEDED)' || true)
[[ $helper_needed == 1 ]] && llvm-readelf -d "$helper_work/helper.elf" | grep -q 'libkernel' ||
    { echo "error: the headless helper must need ordinary libkernel only" >&2; exit 1; }
"$tool" link --in "$helper_work/helper.elf" --out "$helper_work/helper.module.elf" --stub-dir "$sdk/target/lib" \
    --module-sdk 0x02000009 --companion-sdk 0x08050001 --file-name child-helper.bin \
    --preload-prx-flags 0x8000000000000002 > /dev/null
"$tool" self --sign --in "$helper_work/helper.module.elf" --out "$app/es-de/child-helper.bin" --magic 0x1D3D154F > /dev/null
printf '==> [frontend] child-probe: headless helper es-de/child-helper.bin, %s bytes\n' \
    "$(stat -c %s "$app/es-de/child-helper.bin")"
