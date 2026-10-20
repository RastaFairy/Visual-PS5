#!/usr/bin/env bash
# PS5 OpenGL - OpenGL implementation for PlayStation 5.
# Copyright (C) 2026 BlackBearReloaded
# SPDX-License-Identifier: GPL-3.0-or-later

# Checks out the pinned native-app boilerplate (dependencies.json) below build/
# with its native toolchain, and prints its path. Reused when already present.

set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
template="$root/build/native-app-boilerplate"
read -r url revision < <(python3 -c 'import json, sys
pin = json.load(open(sys.argv[1]))["native_boilerplate"]
print(pin["url"], pin["revision"])' "$root/dependencies.json")

if [[ ! -d $template/.git ]]; then
    rm -rf -- "$template"
    git clone --quiet "$url" "$template" >&2
fi
if [[ $(git -C "$template" rev-parse HEAD) != "$revision" ]]; then
    git -C "$template" fetch --quiet origin "$revision" >&2 || true
    git -C "$template" checkout --quiet "$revision" >&2
fi
[[ $(git -C "$template" rev-parse HEAD) == "$revision" ]]
if [[ ! -x $template/.deps/native/ps5-payload-sdk/bin/prospero-clang ]]; then
    (cd "$template" && bash tools/setup-native-dependencies.sh >&2)
fi
printf '%s\n' "$template"
