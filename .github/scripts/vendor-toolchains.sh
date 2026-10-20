#!/usr/bin/env bash
# Vendors source repositories into this repository so IDE users do not need
# those upstream GitHub accounts to remain available after this snapshot lands.
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"
mkdir -p toolchains
run_stamp="$(date -u +'%Y-%m-%dT%H:%M:%SZ')"
report_ndjson="${RUNNER_TEMP:-/tmp}/ps5hs-vendor-report.ndjson"
: > "$report_ndjson"

record() {
  python3 - "$report_ndjson" "$1" "$2" "$3" "$4" "$5" "$6" "$7" <<'PY'
import json, sys
path, folder, status, declared_repo, fetched_repo, ref, commit, detail = sys.argv[1:]
row = {
    "folder": folder,
    "status": status,
    "repository": declared_repo,
    "fetchedFrom": fetched_repo or None,
    "ref": ref,
    "commit": commit or None,
    "detail": detail,
}
with open(path, "a", encoding="utf-8") as f:
    f.write(json.dumps(row, ensure_ascii=False) + "\n")
PY
}

# folder | actual source repository | branch or exact commit | repository named by IDE
# Mirrors are used only where the catalog's old URL now redirects or returns 404.
while IFS='|' read -r folder actual_repo ref declared_repo; do
  [[ -n "$folder" ]] || continue
  dest="toolchains/$folder"

  if [[ -d "$dest" && -f "$dest/.ps5hs-source.json" && ( -f "$dest/README.md" || -f "$dest/readme.md" || -f "$dest/README" ) ]]; then
    if python3 - "$dest/.ps5hs-source.json" "$declared_repo" "$actual_repo" <<'PY'
import json, sys
path, declared, fetched = sys.argv[1:]
try:
    with open(path, encoding="utf-8") as f:
        marker = json.load(f)
except Exception:
    raise SystemExit(1)
repositories = {
    str(marker.get("repository", "")).lower(),
    str(marker.get("sourceRepository", "")).lower(),
    str(marker.get("mirrorRepository", "")).lower(),
}
raise SystemExit(0 if {declared.lower(), fetched.lower()} & repositories else 1)
PY
    then
      record "$folder" "already-present" "$declared_repo" "$actual_repo" "$ref" "" "El manifiesto existente coincide con la fuente; no se sobrescribe."
      continue
    fi
  fi
  if [[ -e "$dest" ]]; then
    record "$folder" "blocked-existing-path" "$declared_repo" "$actual_repo" "$ref" "" "Existe una ruta de destino sin un manifiesto verificable; no se modifica."
    continue
  fi

  src="${RUNNER_TEMP:-/tmp}/ps5hs-vendor-${folder//\//-}-$$"
  rm -rf -- "$src"
  url="https://github.com/$actual_repo.git"
  clone_ok=0
  source_only=false
  if [[ "$ref" =~ ^[0-9a-f]{40}$ ]]; then
    if git clone --depth 1 --no-checkout -- "$url" "$src" >/dev/null 2>&1 &&
       git -C "$src" fetch --depth 1 origin "$ref" >/dev/null 2>&1 &&
       git -C "$src" checkout --detach "$ref" >/dev/null 2>&1 &&
       git -C "$src" submodule update --init --recursive >/dev/null 2>&1; then
      clone_ok=1
    fi
  else
    if git clone --depth 1 --recurse-submodules --shallow-submodules --branch "$ref" -- "$url" "$src" >/dev/null 2>&1; then
      clone_ok=1
    elif [[ "$folder" == "ps5-fsr4" || "$folder" == "ps5-helixsr" ]]; then
      # Preserve the real source files; do not pretend the missing PS5 Vulkan
      # submodule is available or that this copy builds independently.
      rm -rf -- "$src"
      if git clone --depth 1 --branch "$ref" -- "$url" "$src" >/dev/null 2>&1; then
        clone_ok=1
        source_only=true
      fi
    fi
  fi

  if [[ "$clone_ok" -ne 1 ]]; then
    rm -rf -- "$src"
    record "$folder" "failed-to-fetch" "$declared_repo" "$actual_repo" "$ref" "" "No se pudo obtener el repositorio y sus submódulos; no se creó una copia parcial."
    continue
  fi

  readme=""
  for candidate in README.md readme.md README; do
    [[ -f "$src/$candidate" ]] && { readme="$candidate"; break; }
  done
  if [[ -z "$readme" ]]; then
    rm -rf -- "$src"
    record "$folder" "failed-validation" "$declared_repo" "$actual_repo" "$ref" "" "La raíz descargada no contiene README; no se considera una fuente válida."
    continue
  fi

  submodule_status="$(git -C "$src" submodule status --recursive 2>/dev/null || true)"
  unresolved_submodule=""
  if printf '%s\n' "$submodule_status" | grep -Eq '^[-+U]'; then
    expected_gitlink=""
    case "$folder" in
      ps5-fsr4) expected_gitlink="4bb0c8b1423698a7369efc22b829bf16a99e7128" ;;
      ps5-helixsr) expected_gitlink="6875f21438b7e51a1377a30f2d7f77b3e0154cd6" ;;
    esac
    if [[ ( "$folder" == "ps5-fsr4" || "$folder" == "ps5-helixsr" ) &&
          "$source_only" == true &&
          "$submodule_status" == "-$expected_gitlink external/ps5-vulkan" ]]; then
      unresolved_submodule="external/ps5-vulkan@$expected_gitlink"
    else
      rm -rf -- "$src"
      record "$folder" "failed-submodules" "$declared_repo" "$actual_repo" "$ref" "" "Hay submódulos ausentes o en revisión distinta; no se incorpora una copia parcial."
      continue
    fi
  fi

  oversized="$(find "$src" -type f -not -path '*/.git/*' -size +95M -print -quit)"
  if [[ -n "$oversized" ]]; then
    rm -rf -- "$src"
    record "$folder" "blocked-file-over-95MiB" "$declared_repo" "$actual_repo" "$ref" "" "El repositorio contiene un archivo individual mayor de 95 MiB ($oversized); se omite para no crear una copia inválida en GitHub."
    continue
  fi

  commit="$(git -C "$src" rev-parse HEAD)"
  mkdir -p "$dest"
  rsync -a --exclude='.git' "$src/" "$dest/"
  rm -rf -- "$src"

  python3 - "$dest/.ps5hs-source.json" "$declared_repo" "$actual_repo" "$ref" "$commit" "$run_stamp" "$unresolved_submodule" <<'PY'
import json, sys
path, declared_repo, fetched_repo, ref, commit, stamp, unresolved_submodule = sys.argv[1:]
record = {
    "repository": declared_repo,
    "branch": ref if len(ref) != 40 else "pinned",
    "commit": commit,
    "sourceCommit": commit,
    "sourceRef": ref,
    "method": "vendored-snapshot",
    "vendoredSnapshot": True,
    "vendorRepository": "RastaFairy/Visual-PS5",
    "vendoredAt": stamp,
    "submodulesMaterialized": not bool(unresolved_submodule),
    "sourceOnly": bool(unresolved_submodule),
}
if fetched_repo.lower() != declared_repo.lower():
    record["mirrorRepository"] = fetched_repo
if unresolved_submodule:
    record["unresolvedSubmodules"] = [unresolved_submodule]
    record["buildableWithoutExternalRepo"] = False
with open(path, "w", encoding="utf-8", newline="\\n") as f:
    json.dump(record, f, ensure_ascii=False, indent=2)
    f.write("\\n")
PY
  if [[ -n "$unresolved_submodule" ]]; then
    record "$folder" "vendored-source-only" "$declared_repo" "$actual_repo" "$ref" "$commit" "Fuentes copiadas; falta el submódulo externo $unresolved_submodule. No se marca como compilación autónoma."
  else
    record "$folder" "vendored" "$declared_repo" "$actual_repo" "$ref" "$commit" "Fuentes y submódulos copiados a toolchains; sin .git anidado."
  fi
done <<'REPOSITORIES'
PS5_VKHomebrewUI|mihawk-99/PS5_VKHomebrewUI|main|mihawk-99/PS5_VKHomebrewUI
ps5-vulkan-alt|mpereiraesaa/ps5-vulkan|main|mpereiraesaa/ps5-vulkan
ProsperoLight|LedyBacer/ProsperoLight|main|blackbearreloaded/ProsperoLight
ProsperoEden0|Tiang-88/ProsperoEden0|main|Tiang-88/ProsperoEden0
unofficial-stremio-ps5-port|Sp9nky/unofficial-stremio-ps5-port|main|Sp9nky/unofficial-stremio-ps5-port
Nativehbl|Rufidj/Nativehbl|main|Rufidj/Nativehbl
ps5gl|Rufidj/ps5gl|master|Rufidj/ps5gl
ps5-opengl-mihawk|mihawk-99/ps5-opengl|main|mihawk-99/ps5-opengl
ps5-fsr4|manoma080/ps5-fsr4|main|blackbearreloaded/ps5-fsr4
ps5-helixsr|manoma080/ps5-helixsr|main|blackbearreloaded/ps5-helixsr
PS5_Sunshine|griches/PS5_Sunshine|main|griches/PS5_Sunshine
PS5_SwitchWaker|griches/PS5_SwitchWaker|main|griches/PS5_SwitchWaker
PS5_Dusklight|griches/PS5_Dusklight|main|griches/PS5_Dusklight
PS5_Ghostship|griches/PS5_Ghostship|main|griches/PS5_Ghostship
Porpoise-Dolphin-Emulator-for-PS5|elripalda/Porpoise-Dolphin-Emulator-for-PS5|Main|elripalda/Porpoise-Dolphin-Emulator-for-PS5
PS5X360|BrinooTk/PS5X360|main|BrinooTk/PS5X360
syobon-action-ps5|kvaps/syobon-action-ps5|main|kvaps/syobon-action-ps5
aurora|encounter/aurora|main|encounter/aurora
PS5_Quake3e|griches/PS5_Quake3e|main|griches/PS5_Quake3e
PS5_RetroArch|mihawk-99/PS5_RetroArch|main|mihawk-99/PS5_RetroArch
X360PS5-AI-Prototype|polarco/X360PS5|master|polarco/X360PS5
PS5_PayloadSDK-pinned-b83202be|mihawk-99/PS5_PayloadSDK|b83202be73e930050e00de0f1b4d9ec46c0391bf|mihawk-99/PS5_PayloadSDK
REPOSITORIES

# Normalize provenance for existing source trees already included in this repository.
# Empty upstream commit fields remain explicitly unknown; never invent a source revision.
for marker in toolchains/*/.ps5hs-source.json; do
  [[ -f "$marker" ]] || continue
  python3 - "$marker" "$run_stamp" <<'PY'
import json, os, sys
path, stamp = sys.argv[1:]
try:
    with open(path, encoding="utf-8") as f:
        item = json.load(f)
except Exception:
    raise SystemExit(0)
old_method = item.get("method")
item["vendorRepository"] = "RastaFairy/Visual-PS5"
item["vendoredSnapshot"] = True
item["vendoredAt"] = item.get("vendoredAt") or stamp
item["originalMethod"] = item.get("originalMethod") or old_method
if item.get("commit"):
    item.setdefault("sourceCommit", item["commit"])
    item["sourceRevisionRecorded"] = True
else:
    item["sourceRevisionRecorded"] = False
item["method"] = "vendored-snapshot"
with open(path, "w", encoding="utf-8", newline="\n") as f:
    json.dump(item, f, ensure_ascii=False, indent=2)
    f.write("\n")
PY
done

python3 - "$report_ndjson" toolchains/REPOSITORY-VENDOR-REPORT.json "$run_stamp" <<'PY'
import json, sys
src, dest, stamp = sys.argv[1:]
rows = []
with open(src, encoding="utf-8") as f:
    for line in f:
        if line.strip():
            rows.append(json.loads(line))
result = {
    "schemaVersion": 1,
    "repository": "RastaFairy/Visual-PS5",
    "generatedAt": stamp,
    "policy": "Vendor source code and initialized submodules into this repository. Keep original license files. Do not rely on upstream .git folders at runtime.",
    "entries": rows,
}
with open(dest, "w", encoding="utf-8", newline="\n") as f:
    json.dump(result, f, ensure_ascii=False, indent=2)
    f.write("\n")
PY

echo "Resultado de vendorización:"
python3 - <<'PY'
import json
with open("toolchains/REPOSITORY-VENDOR-REPORT.json", encoding="utf-8") as f:
    report = json.load(f)
for row in report["entries"]:
    print(f'{row["status"]:28} {row["folder"]:40} {row["repository"]}')
PY
