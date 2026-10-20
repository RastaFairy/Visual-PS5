#!/usr/bin/env bash
# Ghostship for the PlayStation 5 - pack the built title folder as a release archive.
#
#   ps5/tools/package-release.sh VERSION      (through tools/vm.sh package-release 1.0)
#
# Writes dist/Mario64-PS5-vVERSION.zip: the title folder dist/<TITLE_ID>/ as the
# console takes it (eboot.bin, sce_sys/, sce_module/, ghostship.o2r, config.yml and
# assets/ for the ROM's conversion, licenses/), with SOURCE.txt beside eboot.bin naming
# the revision of every part the build linked and the licences it is offered under.
# No ROM, game archive, texture pack, save or setting goes in, and it refuses if one
# is in the folder.
#
# After the Dusklight port's package-release.sh.
# SPDX-License-Identifier: MIT
set -euo pipefail
version=${1:?usage: package-release.sh VERSION}
ps5=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
root=$(dirname "$ps5")
vulkan=$(cd -- "${PS5_VULKAN_DIR:-$root/../PS5_Vulkan}" && pwd)
game="$root/vendor/ghostship"
title_id=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["titleId"])' "$ps5/sce_sys/param.json")
app="$root/dist/$title_id"
for file in eboot.bin sce_sys/param.json sce_sys/icon0.png sce_sys/pic0.dds sce_sys/pic1.dds sce_module/libc.prx \
        ghostship.o2r config.yml assets/ymls licenses/Ghostship-LICENSE.md; do
    [[ -e $app/$file ]] || { echo "missing $app/$file: run build.sh and assets.sh first" >&2; exit 2; }
done
stray=$(find "$app" \( -iname '*.z64' -o -iname '*.n64' -o -iname '*.v64' -o -name 'sm64.o2r' -o -name userdata \
    -o -name mods -o -name 'env.txt' -o -name 'radv-shader-cache' -o -name 'devloop-*' \) -print -quit)
[[ -z $stray ]] || { echo "game data, a save or a setting in the title folder ($stray): a release never carries it" >&2; exit 2; }
# the title folder's art and name are this commit's
for file in param.json icon0.png pic0.dds pic1.dds; do
    cmp -s "$ps5/sce_sys/$file" "$app/sce_sys/$file" || { echo "dist's sce_sys/$file is not ps5/sce_sys/$file: run build.sh" >&2; exit 2; }
done
# the submodule's working tree carries the console's patches: that is not a change here
[[ -z $(git -C "$root" status --porcelain --ignore-submodules=dirty) ]] ||
    { echo "uncommitted changes: a release is built from a commit" >&2; exit 2; }
provenance="$vulkan/.deps/native/radv-release/PROVENANCE.txt"
cp "$root/licenses/GPL-3.0.txt" "$root/licenses/MIT.txt" "$root/licenses/Zlib.txt" "$app/licenses/"
cp "$root/LICENSING.md" "$app/licenses/LICENSING.md"
cp "$game/libultraship/LICENSE" "$app/licenses/libultraship-LICENSE.txt"
cp "$game/Torch/LICENSE" "$app/licenses/Torch-LICENSE.txt"
cp "$root/.deps/shaderc/LICENSE" "$app/licenses/shaderc-LICENSE.txt"
cat > "$app/SOURCE.txt" <<SOURCE
Mario 64 for PlayStation 5, version $version
An unofficial homebrew build of Ghostship, free of charge. Not affiliated with
HarbourMasters, Nintendo or Sony Interactive Entertainment.

This is a MODIFIED build of Ghostship: ps5/patches/ghostship.patch,
libultraship.patch and torch.patch are applied to it (the console's paths, its
Vulkan driver, a menu worked with the pad, a screenshot hook), and it is built
with SDL2 and this port's console drivers.

Licence. The title as built is under the GNU General Public License, version 3
(licenses/GPL-3.0.txt): it links the GPL-3.0 platform layer with MIT, Zlib,
Apache-2.0 and BSD parts. licenses/LICENSING.md lists them. All of its source
is at the revisions below.

The port (patches, SDL2 drivers, platform layer, build)
  $(git -C "$root" remote get-url origin 2>/dev/null || echo "this repository")
  $(git -C "$root" rev-parse HEAD)
The game's code: Ghostship (MIT), with ps5/patches/ghostship.patch
  https://github.com/HarbourMasters/Ghostship
  $(git -C "$game" rev-parse HEAD) ($(git -C "$game" describe --tags 2>/dev/null))
libultraship (MIT), with ps5/patches/libultraship.patch
  https://github.com/Kenix3/libultraship
  $(git -C "$game/libultraship" rev-parse HEAD)
Torch (MIT), with ps5/patches/torch.patch
  https://github.com/HarbourMasters/Torch
  $(git -C "$game/Torch" rev-parse HEAD)
SDL2 (Zlib), with ps5/patches/sdl.patch and the drivers in ps5/sdl
  https://github.com/libsdl-org/SDL
  $(sed -n 's/^tag=//p' "$ps5/tools/setup-sdl.sh")
shaderc with glslang and SPIRV-Tools (Apache-2.0 and BSD-3-Clause)
  https://github.com/google/shaderc
  $(sed -n 's/^tag=//p' "$ps5/tools/setup-shaderc.sh")
The Vulkan driver: RADV, from PS5_Mesa (MIT)
  https://github.com/mihawk-99/PS5_Mesa
  $(sed -n 's/^revision: //p' "$provenance")
The link recipe, CRT, libc.prx and packaging: PS5_Vulkan (GPL-3.0)
  https://github.com/mihawk-99/PS5_Vulkan
  $(git -C "$vulkan" rev-parse HEAD)
The platform layer and SDK: PS5_PayloadSDK (GPL-3.0), over ps5-payload-dev/sdk
  https://github.com/mihawk-99/PS5_PayloadSDK
  title: $(sed -n 's/^sdk_revision=//p' "$ps5/tools/setup-sdk.sh")
  RADV archive: $(sed -n 's/^sdk: //p' "$provenance")
The libraries Ghostship and libultraship fetch (Dear ImGui, libzip, spdlog,
nlohmann/json, tinyxml2, yaml-cpp, dr_libs, stb, Monocypher, prism and others)
are at the versions they name at the revisions above.
Compiler: $(${PS5_CLANG:-clang} --version | head -1)

No game data is included. Super Mario 64 belongs to Nintendo; this title does
nothing without a ROM from your own copy of the game (US or JP, .z64), placed
beside eboot.bin. ghostship.o2r holds Ghostship's own fonts, textures and
shaders. The pictures in sce_sys/ were made for this port and contain nothing
of Nintendo's.

eboot.bin sha256: $(sha256sum "$app/eboot.bin" | cut -d' ' -f1)
SOURCE
out="$root/dist/Mario64-PS5-v$version.zip"
rm -f "$out"
(cd "$root/dist" && zip -q -r -X "$out" "$title_id" -x '*/.DS_Store')
printf '==> %s (%s bytes)\n' "$out" "$(stat -c %s "$out")"
unzip -l "$out" | tail -n +4 | awk '{print "    " $1, $4}' | grep -v "/assets/" | head -30
