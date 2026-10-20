#!/usr/bin/env bash
# Dusklight for the PlayStation 5 - move to upstream Dusklight's latest revision.
#
#   ps5/tools/update-dusklight.sh [REVISION]     default: origin/main
#
# Takes the console's patches off vendor/dusklight (and its Aurora and Borealis),
# checks out the revision with the Aurora and Borealis it pins, and puts the
# patches back (tools/setup-source.sh). The new revision is staged in this
# repository; commit it once the game builds and runs. If a patch no longer
# applies, it says which and leaves the tree on the new revision for the patch
# to be redone (re-export it with git diff once the change is made by hand).
#
# Dawn and SDL3 follow on their own: tools/setup-dawn.sh and setup-sdl.sh read
# the revisions Aurora pins. tools/check-patches.sh tells whether their patches
# still apply.
#
# The scheduled workflow .github/workflows/track-dusklight.yml runs this daily.
#
# SPDX-License-Identifier: MIT
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
dusklight="$root/vendor/dusklight"
revision=${1:-origin/main}

[[ -f $dusklight/CMakeLists.txt ]] || git -C "$root" submodule update --init vendor/dusklight
unapply() {
    local tree=$1 patch="$root/ps5/patches/$2"
    [[ -d $tree ]] || return 0
    if git -C "$tree" apply --reverse --check "$patch" 2>/dev/null; then
        git -C "$tree" apply --reverse --whitespace=nowarn "$patch"
    fi
}
unapply "$dusklight/extern/aurora" aurora.patch
unapply "$dusklight/extern/borealis" borealis.patch
unapply "$dusklight" dusklight.patch

before=$(git -C "$dusklight" rev-parse HEAD)
git -C "$dusklight" fetch -q origin
git -C "$dusklight" checkout -q --detach "$revision"
git -C "$dusklight" submodule update -q --init extern/aurora extern/borealis
after=$(git -C "$dusklight" rev-parse HEAD)

bash "$root/ps5/tools/setup-source.sh"
git -C "$root" add vendor/dusklight
if [[ $before == "$after" ]]; then
    echo "Dusklight is already at ${after:0:10}"
else
    echo "Dusklight ${before:0:10} -> ${after:0:10} ($(git -C "$dusklight" log --oneline "$before..$after" | wc -l | tr -d ' ') commits)"
fi
