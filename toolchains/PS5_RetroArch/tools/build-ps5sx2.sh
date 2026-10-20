#!/usr/bin/env bash
# Cross-build PS5SX2's emulator as a libretro core with this title's SDK.
#
# Output: build/cores/stage/{cores,info}/ps5sx2_libretro.{so,info} and PCSX2's game
# database in build/cores/stage/system/ps5sx2/resources; build-title.sh stages them.
#
# PS5SX2 (github.com/Swordpdf/PS5SX2) is PCSX2 made for the PS5: its recompilers,
# its Vulkan renderer on the console's driver, and its fixes. The source is my fork,
# ../Libretro_PS5SX2 (github.com/mihawk-99/Libretro_PS5SX2), branch main: the
# emulator without the app around it (shelf, notifications, disc drive, elevation),
# with ps5/libretro/ for the libretro side. An ordinary build clones the pinned
# revision below and builds it as it is; PS5SX2_DEV=1 builds the fork's working tree
# as it stands, which is how the port is edited: change ../Libretro_PS5SX2, build
# with PS5SX2_DEV=1, commit there, then move the pin. It is the title's PS2 core.
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
cd "$root"
source "$root/tools/core-stamp.sh"
[[ -z ${PS5SX2_DEV:-} ]] || rm -f -- "$core_stamp_dir/ps5sx2"
[[ -n ${PS5SX2_DEV:-} ]] || core_stamp_skip ps5sx2 \
    "$root/build/cores/stage/cores/ps5sx2_libretro.so" \
    "$root/build/cores/stage/info/ps5sx2_libretro.info" \
    "$root/build/cores/stage/system/ps5sx2/resources/GameIndex.yaml" \
    -- "$root/tools/build-ps5sx2.sh" "$root/tooling/ps5sx2"
[[ $# == 0 ]] || { echo "usage: ${0##*/}" >&2; exit 2; }
sdk="$root/.deps/native/ps5-payload-sdk"
[[ -x $sdk/bin/prospero-clang ]] || { echo "error: bootstrap this project's SDK first" >&2; exit 2; }
export PS5_PAYLOAD_SDK="$sdk"

revision=dba9ef4a9e01f930781cbc5eb177cf325e0af502  # ../Libretro_PS5SX2 main
# The emulator's own dependencies, at the revisions PS5SX2's app builds with.
ryml_revision=0cd25a10e0b83e4e1c11ad74048f4817f45b9763      # rapidyaml, c4core in ext/
glslang_revision=275822a6261ee689aadb1da5f09a0ec2f058685c   # glslang
shaderc_revision=d5f08ae5c5a9a45165578445cbd0f9adf0223448   # shaderc v2026.2 (headers only)

deps="$root/.deps/ps5sx2"
mkdir -p "$deps"
fetch() { # fetch NAME URL REVISION
    local dir="$deps/$1"
    if [[ ! -d $dir/.git ]]; then
        echo "==> [ps5sx2] fetching $1 $3"
        rm -rf -- "$dir"
        git clone --quiet --no-checkout "$2" "$dir"
    fi
    git -C "$dir" cat-file -e "$3^{commit}" 2>/dev/null || git -C "$dir" fetch --quiet origin "$3"
    git -C "$dir" checkout --force --quiet "$3"
    [[ $(git -C "$dir" rev-parse HEAD) == "$3" ]] || { echo "error: $1 is not at $3" >&2; exit 2; }
}
fetch ryml https://github.com/biojppm/rapidyaml.git "$ryml_revision"
fetch glslang https://github.com/KhronosGroup/glslang.git "$glslang_revision"
fetch shaderc https://github.com/google/shaderc.git "$shaderc_revision"

# glslang as static libraries for the console (the GS compiles its shaders at run time).
glslang_build="$deps/glslang/build-ps5"
if [[ ! -f $glslang_build/glslang/libglslang.a || ! -f $glslang_build/.revision ||
        $(<"$glslang_build/.revision") != "$glslang_revision" ]]; then
    echo "==> [ps5sx2] building glslang"
    rm -rf -- "$glslang_build"
    cmake -S "$deps/glslang" -B "$glslang_build" \
        -DCMAKE_TOOLCHAIN_FILE="$sdk/toolchain/prospero.cmake" -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_POSITION_INDEPENDENT_CODE=ON -DBUILD_SHARED_LIBS=OFF -DENABLE_OPT=OFF \
        -DENABLE_HLSL=OFF -DENABLE_GLSLANG_BINARIES=OFF -DENABLE_GLSLANG_JS=OFF \
        -DENABLE_EXCEPTIONS=OFF -DENABLE_RTTI=OFF -DGLSLANG_TESTS=OFF \
        -DALLOW_EXTERNAL_SPIRV_TOOLS=OFF > "$deps/glslang-configure.log" ||
        { tail -30 "$deps/glslang-configure.log" >&2; exit 1; }
    cmake --build "$glslang_build" --target glslang glslang-default-resource-limits \
        --parallel "${JOBS:-4}" > "$deps/glslang-build.log" ||
        { tail -30 "$deps/glslang-build.log" >&2; exit 1; }
    printf '%s\n' "$glslang_revision" > "$glslang_build/.revision"
fi

fork="$root/../Libretro_PS5SX2"
if [[ -n ${PS5SX2_DEV:-} ]]; then
    [[ -d $fork/.git ]] || { echo "error: PS5SX2_DEV needs the fork at $fork" >&2; exit 2; }
    source_dir=$(cd -- "$fork" && pwd)
    echo "==> [ps5sx2] PS5SX2_DEV: building $source_dir as it stands"
else
    source_dir="$root/.deps/ps5sx2-src"
    if [[ ! -d $source_dir/.git ]]; then
        origin=https://github.com/mihawk-99/Libretro_PS5SX2.git
        [[ -d $fork/.git ]] && origin=$(cd -- "$fork" && pwd)
        echo "==> [ps5sx2] fetching $revision from $origin"
        rm -rf -- "$source_dir"
        git clone --quiet --no-checkout "$origin" "$source_dir"
    fi
    git -C "$source_dir" cat-file -e "$revision^{commit}" 2>/dev/null ||
        git -C "$source_dir" fetch --quiet origin "$revision"
    echo "==> [ps5sx2] resetting the pinned tree"
    git -C "$source_dir" checkout --force --quiet "$revision"
    got=$(git -C "$source_dir" rev-parse HEAD)
    [[ $got == "$revision" ]] || { echo "error: the tree is at $got, wanted $revision" >&2; exit 2; }
fi
source_date_epoch=$(git -C "$source_dir" show -s --format=%ct HEAD)
export SOURCE_DATE_EPOCH="$source_date_epoch"

# Linked into the core itself: the core-local destructor registry the native loader
# runs before unmapping the module.
build="$root/build/cores/ps5sx2"
mkdir -p "$build" "$root/build/cores/stage/cores" "$root/build/cores/stage/info"
"$sdk/bin/prospero-clang++" -std=c++11 -fPIC -fno-exceptions -fno-rtti \
    -c "$root/tooling/native/core_cxx_runtime.cpp" -o "$build/core_cxx_runtime.o"

# The fork's own make files: ps5/libretro/Makefile.libretro includes the app's
# ps5/coreorbis/Makefile.vk for PCSX2's sources and leaves the app out. The pinned
# tree's objects go to build/cores/ps5sx2/obj; a PS5SX2_DEV build keeps the fork's own
# (ps5/coreorbis/obj-libretro, ignored there), so editing the fork rebuilds only what
# changed.
objdir="$build/obj"
[[ -z ${PS5SX2_DEV:-} ]] || objdir="$source_dir/ps5/coreorbis/obj-libretro"
echo "==> [ps5sx2] building the core"
nice -n 10 make -C "$source_dir/ps5/coreorbis" -f ../libretro/Makefile.libretro \
    --jobs="${JOBS:-4}" OBJDIR="$objdir" \
    PS5_PAYLOAD_SDK="$sdk" RYML="$deps/ryml" GLSLANG="$deps/glslang" GLSLANG_BUILD="$glslang_build" \
    SHADERC_INCLUDE="$deps/shaderc/libshaderc/include" \
    CORE_LDSCRIPT="$root/tooling/native/ps5-core.ld" CORE_LINK_INPUTS="$build/core_cxx_runtime.o" \
    > "$build/make.log" 2>&1 || { grep -E "error|Error" "$build/make.log" | head -30 >&2; exit 1; }
core="$objdir/ps5sx2_libretro.so"
[[ -f $core ]] || { echo "error: no ps5sx2_libretro.so was produced" >&2; exit 2; }
cp -- "$core" "$build/ps5sx2_libretro.so"
python3 tools/check-core.py "$build/ps5sx2_libretro.so" --report "$build/abi.json"
cp -- "$build/ps5sx2_libretro.so" "$root/build/cores/stage/cores/ps5sx2_libretro.so"
cp -- "$root/tooling/ps5sx2/ps5sx2_libretro.info" "$root/build/cores/stage/info/ps5sx2_libretro.info"

# PCSX2's game database (per-game fixes the emulator applies by serial), read from
# <system>/ps5sx2/resources.
resources="$root/build/cores/stage/system/ps5sx2/resources"
rm -rf -- "$root/build/cores/stage/system/ps5sx2"
mkdir -p "$resources"
cp -- "$source_dir/bin/resources/GameIndex.yaml" "$resources/GameIndex.yaml"

python3 - "$build" "$revision" "$source_date_epoch" "${PS5SX2_DEV:+dev}" <<'PY'
import hashlib, json, pathlib, sys
build = pathlib.Path(sys.argv[1])
revision, epoch, dev = sys.argv[2], sys.argv[3], sys.argv[4]
def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()
report = json.loads((build / 'abi.json').read_text())
report.update(source_revision='working tree' if dev else revision, source_date_epoch=int(epoch))
report['port_inputs_sha256'] = {name: sha(pathlib.Path(name)) for name in
    ['tools/build-ps5sx2.sh', 'tooling/ps5sx2/ps5sx2_libretro.info',
     'tooling/native/core_cxx_runtime.cpp', 'tooling/native/ps5-core.ld']}
(build / 'build.json').write_text(json.dumps(report, indent=2) + '\n')
PY
[[ -n ${PS5SX2_DEV:-} ]] || core_stamp_write
what="revision $revision"
[[ -z ${PS5SX2_DEV:-} ]] || what="the working tree"
printf '==> [ps5sx2] built and ABI-checked %s; console loading is a separate gate\n' "$what"
