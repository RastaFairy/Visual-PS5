#!/usr/bin/env bash
# Ghostship for the PlayStation 5 - shaderc at a pinned release, with what it builds from.
#
#   ps5/tools/setup-shaderc.sh   fetch it into .deps/shaderc (once a release), print the path
#
# libultraship's Vulkan renderer writes its shaders as GLSL at run time and
# compiles them with shaderc. shaderc builds glslang, SPIRV-Tools and
# SPIRV-Headers from third_party/, at the revisions its DEPS file names.
#
# SPDX-License-Identifier: MIT
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
shaderc="$root/.deps/shaderc"
tag=v2026.3

if [[ ! -f $shaderc/.ps5-shaderc || $(<"$shaderc/.ps5-shaderc") != "$tag" ]]; then
    {
        [[ -d $shaderc/.git ]] || git clone -q --depth 1 -b "$tag" https://github.com/google/shaderc.git "$shaderc"
        (cd "$shaderc" && python3 utils/git-sync-deps)
    } >&2
    echo "$tag" > "$shaderc/.ps5-shaderc"
fi
echo "$shaderc"
