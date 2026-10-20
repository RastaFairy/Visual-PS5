#!/usr/bin/env bash
# PS5 OpenGL - OpenGL implementation for PlayStation 5.
# Copyright (C) 2026 BlackBearReloaded
# SPDX-License-Identifier: GPL-3.0-or-later

# Packages the built showcase demo app as
# <destination>/ps5-opengl-showcase-<version>-PPSA99005.zip plus its .sha256.

set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
version=${1:?usage: package-demo-app.sh <version> [destination]}
destination=$(realpath -m -- "${2:-$root/build/demo}")
dist="$root/build/native-app/PPSA99005/dist"
[[ $(tr -d '\r\n' < "$root/build/native-app/PPSA99005/selected-test.txt") == \
   egl_public_gl46_showcase.o ]] || {
    echo 'the last native app build is not the showcase; run make demo' >&2
    exit 2
}
name="ps5-opengl-showcase-$version-PPSA99005"
mkdir -p "$destination"
rm -f -- "$destination/$name.zip" "$destination/$name.zip.sha256"
(cd "$dist" && python3 -m zipfile -c "$destination/$name.zip" PPSA99005)
# The console only starts an app whose files are open to all (CE-107750-0 otherwise),
# and some tools keep a ZIP's permissions when unpacking: store every entry as 0777.
python3 "$root/tools/zip-open-modes.py" "$destination/$name.zip"
cd "$destination"
python3 -m zipfile -t "$name.zip" >/dev/null
python3 - "$name.zip" "$version" <<'PY'
import json
import re
import sys
import zipfile

with zipfile.ZipFile(sys.argv[1]) as archive:
    names = set(archive.namelist())
    assert all(n.startswith("PPSA99005/") for n in names), "entries outside the app folder"
    wrong = [i.filename for i in archive.infolist() if (i.external_attr >> 16) & 0o777 != 0o777]
    assert not wrong, f"entries not stored as 0777: {wrong[:3]}"
    for required in ("eboot.bin", "sce_module/libc.prx", "sce_sys/param.json",
                     "sce_sys/icon0.png", "sce_sys/pic0.dds", "sce_sys/pic1.dds",
                     "sce_sys/snd0.at9"):
        assert "PPSA99005/" + required in names, required
    metadata = json.loads(archive.read("PPSA99005/sce_sys/param.json"))
assert metadata["titleId"] == "PPSA99005"
assert metadata["localizedParameters"]["en-US"]["titleName"] == "PS5 OpenGL Showcase"
# A release X.Y.Z carries content version 0X.00Y.00Z (examples/core46-showcase/sce_sys/param.json):
# a console tells a newer release by it, so a release that forgot to raise it is refused here.
release = re.fullmatch(r"(\d{1,2})\.(\d{1,3})\.(\d{1,3})(-.+)?", sys.argv[2])
if release:
    expected = "%02d.%03d.%03d" % tuple(int(part) for part in release.groups()[:3])
    assert metadata["contentVersion"] == expected, (
        f"contentVersion {metadata['contentVersion']} is not {expected}: "
        "raise it in examples/core46-showcase/sce_sys/param.json")
PY
sha256sum "$name.zip" > "$name.zip.sha256"
printf 'Demo app: %s\n' "$destination/$name.zip"
