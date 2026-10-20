#!/usr/bin/env bash
# Recover exact Vulkan submodule trees and preserve the Wayback-era source snapshots.
# The copied repository content retains upstream licences; no proprietary DLLs are fetched.
set -Eeuo pipefail
trap 'status=$?; printf "ERROR: snapshot recovery failed at line %s (exit %s)\\n" "$LINENO" "$status" >&2; exit "$status"' ERR

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"
stamp="$(date -u +'%Y-%m-%dT%H:%M:%SZ')"
work="$(mktemp -d "${RUNNER_TEMP:-/tmp}/ps5hs-recovery.XXXXXX")"
trap 'rm -rf "$work"' EXIT
mkdir -p toolchains/archive

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

# Fetch a commit and verify both its full SHA and root Git tree SHA.
# If a historical commit cannot be fetched as a Git ref, use the immutable GitHub
# tarball and reconstruct its tree locally; reject a mismatching tree.
prepare_source() {
  local repo="$1" commit="$2" expected_tree="$3" label="$4"
  local src="$work/$label" archive="$work/$label.tar.gz" unpack="$work/$label-unpack"
  local got_commit="" got_tree="" top="" verify="$work/$label-verify"

  rm -rf "$src" "$unpack" "$verify"
  if git clone --quiet --filter=blob:none --no-checkout "https://github.com/$repo.git" "$src" 2>/dev/null &&
     git -C "$src" fetch --quiet --depth=1 origin "$commit" 2>/dev/null &&
     git -C "$src" checkout --quiet --detach "$commit" 2>/dev/null; then
    got_commit="$(git -C "$src" rev-parse HEAD)"
    got_tree="$(git -C "$src" rev-parse 'HEAD^{tree}')"
    [[ "$got_commit" == "$commit" ]] || fail "$repo: commit expected $commit, got $got_commit"
    [[ "$got_tree" == "$expected_tree" ]] || fail "$repo@$commit: unexpected tree $got_tree (expected $expected_tree)"
    printf '%s\n' "$src"
    return 0
  fi

  rm -rf "$src"
  curl -fLsS --retry 3 -H 'Accept: application/vnd.github+json' \
    "https://api.github.com/repos/$repo/tarball/$commit" -o "$archive" ||
    fail "Unable to retrieve $repo@$commit via Git or tarball."
  mkdir -p "$unpack"
  tar -xzf "$archive" -C "$unpack"
  top="$(find "$unpack" -mindepth 1 -maxdepth 1 -type d -print -quit)"
  [[ -n "$top" ]] || fail "The tarball for $repo@$commit has no repository root."

  mkdir -p "$verify"
  rsync -a --exclude='.git' "$top/" "$verify/"
  git -C "$verify" init -q
  git -C "$verify" config core.filemode true
  git -C "$verify" config core.autocrlf false
  git -C "$verify" add -f -A
  got_tree="$(git -C "$verify" write-tree)"
  [[ "$got_tree" == "$expected_tree" ]] ||
    fail "Tarball $repo@$commit does not reproduce the exact Git tree: $got_tree (expected $expected_tree)."
  printf '%s\n' "$top"
}

verify_plain_tree() {
  local folder="$1" expected_tree="$2" label="$3"
  local verify="$work/verify-$label" got_tree
  rm -rf "$verify"
  mkdir -p "$verify"
  rsync -a --exclude='.git' "$folder/" "$verify/"
  git -C "$verify" init -q
  git -C "$verify" config core.filemode true
  git -C "$verify" config core.autocrlf false
  git -C "$verify" add -f -A
  got_tree="$(git -C "$verify" write-tree)"
  [[ "$got_tree" == "$expected_tree" ]] ||
    fail "Materialized tree at $folder is $got_tree; expected $expected_tree."
}

write_parent_manifest() {
  local parent="$1" driver_commit="$2" driver_tree="$3" label="$4"
  python3 - "$parent/.ps5hs-source.json" "$driver_commit" "$driver_tree" "$label" "$stamp" <<'PY'
import json, sys
path, commit, tree, label, stamp = sys.argv[1:]
with open(path, encoding="utf-8") as f:
    data = json.load(f)
entry = {
    "path": "external/ps5-vulkan",
    "repository": "mpereiraesaa/ps5-vulkan",
    "sourceUrl": "https://github.com/mpereiraesaa/ps5-vulkan",
    "commit": commit,
    "tree": tree,
    "materializedAsFiles": True,
}
items = [x for x in data.get("materializedSubmodules", []) if x.get("path") != entry["path"]]
items.append(entry)
data["materializedSubmodules"] = items
unresolved = [
    x for x in data.get("unresolvedSubmodules", [])
    if not (str(x).startswith("external/ps5-vulkan@") and str(x).endswith(commit))
]
if unresolved:
    data["unresolvedSubmodules"] = unresolved
    data["submodulesMaterialized"] = False
    data["sourceOnly"] = True
    data["buildableWithoutExternalRepo"] = False
else:
    data.pop("unresolvedSubmodules", None)
    data["submodulesMaterialized"] = True
    data["sourceOnly"] = False
    # This means the declared external/ps5-vulkan Gitlink is included locally.
    # Generic build inputs and user-supplied proprietary DLLs remain separate.
    data["buildableWithoutExternalRepo"] = True
data["submoduleRecovery"] = {
    "status": "verified",
    "method": "vendored-tree",
    "completedAt": stamp,
    "note": "The declared Vulkan Gitlink was replaced with the exact verified tree as ordinary files."
}
with open(path, "w", encoding="utf-8", newline="\n") as f:
    json.dump(data, f, ensure_ascii=False, indent=2)
    f.write("\n")
PY
}

materialize_module() {
  local parent="$1" driver_commit="$2" driver_tree="$3" label="$4"
  local dest="$parent/external/ps5-vulkan" source marker_ok=""

  [[ -f "$parent/.ps5hs-source.json" ]] || fail "$parent: missing parent source manifest."
  source="$(prepare_source "mpereiraesaa/ps5-vulkan" "$driver_commit" "$driver_tree" "driver-$label")"
  [[ -f "$source/README.md" && -f "$source/Makefile" ]] ||
    fail "The pinned tree mpereiraesaa/ps5-vulkan@$driver_commit failed structural validation."

  marker_ok="$(python3 - "$parent/.ps5hs-source.json" "$driver_commit" <<'PY'
import json, sys
try:
    with open(sys.argv[1], encoding="utf-8") as f:
        d = json.load(f)
except Exception:
    print("invalid")
    raise SystemExit
expected = sys.argv[2]
for item in d.get("materializedSubmodules", []):
    if item.get("path") == "external/ps5-vulkan" and item.get("commit") == expected:
        print("previously-materialized")
        raise SystemExit
for item in d.get("unresolvedSubmodules", []):
    if str(item) == "external/ps5-vulkan@" + expected:
        print("expected-unresolved")
        raise SystemExit
if d.get("sourceOnly") is True and not d.get("materializedSubmodules"):
    print("source-only")
else:
    print("unexpected")
PY
)"
  if [[ -d "$dest" && -f "$dest/README.md" && "$marker_ok" == "previously-materialized" ]]; then
    if verify_plain_tree "$dest" "$driver_tree" "$label-existing" 2>/dev/null; then
      echo "==> $parent: external/ps5-vulkan already complete and verified."
      return 0
    fi
    # The source is pinned and verified above. A mismatching local tree can be
    # a partial earlier snapshot where nested upstream .gitignore rules caused
    # tracked source files to be omitted from the parent repository's index.
    # Rebuild only this declared Gitlink from the pinned mirror; never switch pins.
    echo "==> $dest: incomplete materialization detected; rebuilding from verified pin $driver_commit."
    marker_ok="previously-materialized-incomplete"
  fi

  [[ "$marker_ok" == "expected-unresolved" || "$marker_ok" == "source-only" || "$marker_ok" == "previously-materialized-incomplete" ]] ||
    fail "$dest exists or the manifest does not prove the missing Gitlink; refusing to overwrite."

  # Stage and verify before replacing the current copy. This keeps the old
  # directory intact if the mirror content ever fails the exact tree check.
  local staged_dest="${dest}.recovery-stage-$"
  rm -rf -- "$staged_dest"
  mkdir -p "$staged_dest"
  rsync -a --delete --exclude='.git' "$source/" "$staged_dest/"
  verify_plain_tree "$staged_dest" "$driver_tree" "$label"
  rm -rf -- "$dest"
  mv -- "$staged_dest" "$dest"
  write_parent_manifest "$parent" "$driver_commit" "$driver_tree" "$label"
  echo "==> $parent: recovered external/ps5-vulkan@$driver_commit; verified tree $driver_tree."
}

create_historical_snapshot() {
  local folder="$1" repo="$2" root_commit="$3" root_tree="$4"
  local driver_commit="$5" driver_tree="$6" archive_url="$7" capture_time="$8" label="$9"
  local dest="toolchains/archive/$folder" source marker_status

  if [[ -e "$dest" ]]; then
    [[ -f "$dest/.ps5hs-source.json" ]] ||
      fail "$dest already exists without a verifiable manifest; refusing to overwrite."
    marker_status="$(python3 - "$dest/.ps5hs-source.json" "$root_commit" <<'PY'
import json, sys
try:
    with open(sys.argv[1], encoding="utf-8") as f:
        d = json.load(f)
    print("ok" if (d.get("sourceCommit") or d.get("commit")) == sys.argv[2] else "different")
except Exception:
    print("invalid")
PY
)"
    [[ "$marker_status" == "ok" ]] || fail "$dest points at a different revision; refusing to overwrite."
  else
    source="$(prepare_source "$repo" "$root_commit" "$root_tree" "root-$label")"
    mkdir -p "$dest"
    rsync -a --exclude='.git' "$source/" "$dest/"
    python3 - "$dest/.ps5hs-source.json" "$repo" "$root_commit" "$root_tree" "$driver_commit" "$archive_url" "$capture_time" "$stamp" <<'PY'
import json, sys
path, repo, commit, tree, driver_commit, archive_url, capture_time, stamp = sys.argv[1:]
owner, name = repo.split("/", 1)
data = {
    "repository": "blackbearreloaded/" + name,
    "mirrorRepository": repo,
    "branch": "archived",
    "commit": commit,
    "sourceCommit": commit,
    "sourceTree": tree,
    "sourceRef": commit,
    "method": "vendored-snapshot",
    "vendoredSnapshot": True,
    "vendorRepository": "RastaFairy/Visual-PS5",
    "vendoredAt": stamp,
    "historicalSnapshot": True,
    "webArchiveSnapshot": archive_url,
    "archiveCapturedAt": capture_time,
    "submodulesMaterialized": False,
    "sourceOnly": True,
    "unresolvedSubmodules": ["external/ps5-vulkan@" + driver_commit],
    "buildableWithoutExternalRepo": False,
    "materializedSubmodules": [],
}
with open(path, "w", encoding="utf-8", newline="\n") as f:
    json.dump(data, f, ensure_ascii=False, indent=2)
    f.write("\n")
PY
  fi

  materialize_module "$dest" "$driver_commit" "$driver_tree" "$label"
  echo "==> Archived snapshot: $dest (root $root_commit; captured $capture_time)."
}

# Current vendored roots: restore each root revision's own submodule pin.
materialize_module "toolchains/ps5-fsr4" \
  "4bb0c8b1423698a7369efc22b829bf16a99e7128" "90bc4a136c6830fdb28fd4fbdade33c1ad7b97f2" "fsr4-current"
materialize_module "toolchains/ps5-helixsr" \
  "6875f21438b7e51a1377a30f2d7f77b3e0154cd6" "de24817f1fb6d1afb0dd86e07301820fee4a9e9b" "helixsr-current"

# Archive-aligned snapshots: the Web Archive captures map to these exact source commits.
# Historical FSR4 used 6a0228; current FSR4 uses the later pin 4bb0c8.
create_historical_snapshot "ps5-fsr4-2026-09-28" \
  "manoma080/ps5-fsr4" "3789980ceba27568f2910a561483aa1cee383342" "4819a0aac0bc4ef59a8ff5ad0dfe2a039b2b6000" \
  "6a0228bedebef949fd2dd90643eae4a5b711c23f" "e09c15f888cd622cd658599598a6d3cd8bee3154" \
  "https://web.archive.org/web/20260928200623/https://github.com/blackbearreloaded/ps5-fsr4" \
  "2026-09-28T20:06:23Z" "fsr4-archive"
create_historical_snapshot "ps5-helixsr-2026-10-09" \
  "manoma080/ps5-helixsr" "028fcd7f737a95183cf688ee4bca8a9e48fe0c40" "962689603b7c85360347a038cff7525337b00624" \
  "6875f21438b7e51a1377a30f2d7f77b3e0154cd6" "de24817f1fb6d1afb0dd86e07301820fee4a9e9b" \
  "https://web.archive.org/web/20261009031258/https://github.com/blackbearreloaded/ps5-helixsr" \
  "2026-10-09T03:12:58Z" "helixsr-archive"

# Store links to historical source in the current manifests without changing current root commits.
python3 - "$stamp" <<'PY'
import json, sys
items = {
    "toolchains/ps5-fsr4/.ps5hs-source.json": {
        "archiveCapturedAt": "2026-09-28T20:06:23Z",
        "waybackSnapshot": "https://web.archive.org/web/20260928200623/https://github.com/blackbearreloaded/ps5-fsr4",
        "rootCommit": "3789980ceba27568f2910a561483aa1cee383342",
        "submoduleCommit": "6a0228bedebef949fd2dd90643eae4a5b711c23f",
        "archivedPath": "toolchains/archive/ps5-fsr4-2026-09-28",
    },
    "toolchains/ps5-helixsr/.ps5hs-source.json": {
        "archiveCapturedAt": "2026-10-09T03:12:58Z",
        "waybackSnapshot": "https://web.archive.org/web/20261009031258/https://github.com/blackbearreloaded/ps5-helixsr",
        "rootCommit": "028fcd7f737a95183cf688ee4bca8a9e48fe0c40",
        "submoduleCommit": "6875f21438b7e51a1377a30f2d7f77b3e0154cd6",
        "archivedPath": "toolchains/archive/ps5-helixsr-2026-10-09",
    },
}
for path, archived in items.items():
    with open(path, encoding="utf-8") as f:
        data = json.load(f)
    history = [x for x in data.get("historicalSnapshots", []) if x.get("archiveCapturedAt") != archived["archiveCapturedAt"]]
    history.append(archived)
    data["historicalSnapshots"] = history
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
        f.write("\n")
PY

cat > toolchains/archive/README.md <<'EOF'
# Historical snapshots recovered from Web Archive

These directories preserve the repository states corresponding to the dated Web Archive captures. They are recovery snapshots, not additional entries in the IDE's toolchain catalogue.

- ps5-fsr4-2026-09-28: upstream root 3789980ceba27568f2910a561483aa1cee383342, Vulkan submodule 6a0228bedebef949fd2dd90643eae4a5b711c23f.
- ps5-helixsr-2026-10-09: upstream root 028fcd7f737a95183cf688ee4bca8a9e48fe0c40, Vulkan submodule 6875f21438b7e51a1377a30f2d7f77b3e0154cd6.

Root source is restored from mirrors that retain the historical commits. Each Vulkan submodule is recovered from mpereiraesaa/ps5-vulkan at its exact SHA. The synchronizer verifies the commit and Git tree SHA before copying and records provenance in .ps5hs-source.json.

The current toolchain paths toolchains/ps5-fsr4 and toolchains/ps5-helixsr remain on later/current root revisions: FSR4 uses pin 4bb0c8b1423698a7369efc22b829bf16a99e7128; HelixSR uses 6875f21438b7e51a1377a30f2d7f77b3e0154cd6. Do not substitute one version's pin into another without updating its manifest.

The external/ps5-vulkan folders are ordinary tracked files, not nested Git submodules. No proprietary DLLs, firmware, keys, games, ROMs, or BIOS are included. Build dependencies and the legitimate user-supplied DLL that HelixSR requires remain separate.
EOF

# Keep the report explicit about restored dependencies and historical states.
python3 - "$stamp" <<'PY'
import json, os, sys
stamp = sys.argv[1]
report_path = "toolchains/REPOSITORY-VENDOR-REPORT.json"
if os.path.isfile(report_path):
    with open(report_path, encoding="utf-8") as f:
        report = json.load(f)
else:
    report = {"schemaVersion": 1, "repository": "RastaFairy/Visual-PS5", "entries": []}
for folder, root_commit, driver_commit, tree in [
    ("ps5-fsr4", "4f931d8926cc25b2fdd78898cf08ee5c1999ea68", "4bb0c8b1423698a7369efc22b829bf16a99e7128", "90bc4a136c6830fdb28fd4fbdade33c1ad7b97f2"),
    ("ps5-helixsr", "0673d91561c761b054449d30f2c2036fb6e0cf99", "6875f21438b7e51a1377a30f2d7f77b3e0154cd6", "de24817f1fb6d1afb0dd86e07301820fee4a9e9b"),
]:
    found = False
    for row in report.get("entries", []):
        if row.get("folder") == folder:
            row["status"] = "vendored-with-materialized-submodule"
            row["commit"] = root_commit
            row["detail"] = f"Root {root_commit}; external/ps5-vulkan materialized and verified at {driver_commit} (tree {tree})."
            found = True
    if not found:
        report.setdefault("entries", []).append({
            "folder": folder,
            "status": "vendored-with-materialized-submodule",
            "repository": "blackbearreloaded/" + folder,
            "fetchedFrom": "manoma080/" + folder,
            "ref": root_commit,
            "commit": root_commit,
            "detail": f"Root {root_commit}; external/ps5-vulkan materialized and verified at {driver_commit} (tree {tree}).",
        })
report["generatedAt"] = stamp
report["recoveredSubmodules"] = [
    {"path": "toolchains/ps5-fsr4/external/ps5-vulkan", "repository": "mpereiraesaa/ps5-vulkan", "commit": "4bb0c8b1423698a7369efc22b829bf16a99e7128", "tree": "90bc4a136c6830fdb28fd4fbdade33c1ad7b97f2", "verified": True},
    {"path": "toolchains/ps5-helixsr/external/ps5-vulkan", "repository": "mpereiraesaa/ps5-vulkan", "commit": "6875f21438b7e51a1377a30f2d7f77b3e0154cd6", "tree": "de24817f1fb6d1afb0dd86e07301820fee4a9e9b", "verified": True},
]
report["historicalSnapshots"] = [
    {"path": "toolchains/archive/ps5-fsr4-2026-09-28", "repository": "manoma080/ps5-fsr4", "rootCommit": "3789980ceba27568f2910a561483aa1cee383342", "vulkanCommit": "6a0228bedebef949fd2dd90643eae4a5b711c23f", "webArchive": "https://web.archive.org/web/20260928200623/https://github.com/blackbearreloaded/ps5-fsr4"},
    {"path": "toolchains/archive/ps5-helixsr-2026-10-09", "repository": "manoma080/ps5-helixsr", "rootCommit": "028fcd7f737a95183cf688ee4bca8a9e48fe0c40", "vulkanCommit": "6875f21438b7e51a1377a30f2d7f77b3e0154cd6", "webArchive": "https://web.archive.org/web/20261009031258/https://github.com/blackbearreloaded/ps5-helixsr"},
]
with open(report_path, "w", encoding="utf-8", newline="\n") as f:
    json.dump(report, f, ensure_ascii=False, indent=2)
    f.write("\n")
PY
