#!/usr/bin/env bash
set -euo pipefail

root="/"
source_user=""
stage_id=""
lock_file=""
apply=false

usage() {
    echo "usage: prepare-image.sh [--root fixture-root --source-user NAME] [--stage-id GUID] [--lock-file PATH] [--apply]" >&2
}

while (($#)); do
    case "$1" in
        --root) (($# >= 2)) || { usage; exit 2; }; root=$2; shift 2 ;;
        --source-user) (($# >= 2)) || { usage; exit 2; }; source_user=$2; shift 2 ;;
        --stage-id) (($# >= 2)) || { usage; exit 2; }; stage_id=$2; shift 2 ;;
        --lock-file) (($# >= 2)) || { usage; exit 2; }; lock_file=$2; shift 2 ;;
        --apply) apply=true; shift ;;
        -h|--help) usage; exit 0 ;;
        *) echo "unknown option: $1" >&2; usage; exit 2 ;;
    esac
done

root=$(realpath -e -- "$root")
if [[ "$root" == "/" ]]; then
    [[ -n "$stage_id" && -f /etc/ps5hs-offline-image-stage-id ]] || {
        echo "refusing to inspect or clean the active distro: staging marker is missing" >&2
        exit 3
    }
    recorded_stage_id=$(< /etc/ps5hs-offline-image-stage-id)
    [[ "$recorded_stage_id" == "$stage_id" ]] || {
        echo "staging marker does not match the requested operation" >&2
        exit 3
    }
    [[ -n "$lock_file" && -f "$lock_file" ]] || {
        echo "the image lock file is required for a real image" >&2
        exit 3
    }
    source_user=${source_user:-$(awk -F= 'BEGIN{section=""} /^\[/{section=$0} section=="[user]" && $1 ~ /^[[:space:]]*default[[:space:]]*$/ {gsub(/[[:space:]]/,"",$2); print $2; exit}' /etc/wsl.conf)}
else
    [[ -f "$root/.ps5hs-offline-image-test-root" ]] || {
        echo "fixture root lacks the safety marker: $root" >&2
        exit 3
    }
    source_user=${source_user:-rasta}
fi

[[ "$source_user" =~ ^[a-z_][a-z0-9_-]*[$]?$ ]] || {
    echo "invalid source user name" >&2
    exit 2
}
[[ "$source_user" != "root" && "$source_user" != "visualps5" ]] || {
    echo "source user must be the existing non-root account, not '$source_user'" >&2
    exit 2
}

source_home="$root/home/$source_user"
target_home="$root/home/visualps5"
[[ -d "$source_home" && ! -L "$source_home" ]] || {
    echo "source home is missing or is a symbolic link: $source_home" >&2
    exit 4
}
[[ ! -e "$target_home" ]] || {
    echo "target home already exists; refusing to overwrite: $target_home" >&2
    exit 4
}

echo "Image sanitation plan:"
echo "  remove personal/project home: $source_home"
echo "  create generic home: $target_home"
echo "  preserve the installed SDK tree: $root/opt/ps5-payload-sdk"
echo "  preserve the installed package database: $root/var/lib/dpkg"
echo "  mode: $([[ "$apply" == true ]] && echo apply || echo dry-run)"

if [[ "$apply" != true ]]; then
    exit 0
fi

if [[ "$root" == "/" ]]; then
    old_uid=$(id -u "$source_user")
    old_gid=$(id -g "$source_user")
    old_home=$(getent passwd "$source_user" | cut -d: -f6)
    [[ "$old_uid" -ge 1000 && "$old_home" == "/home/$source_user" ]] || {
        echo "the source account is outside the expected user/home layout; manual review required" >&2
        exit 4
    }
    if pgrep -u "$old_uid" >/dev/null 2>&1; then
        echo "the source user still has running processes; refusing to replace it" >&2
        exit 4
    fi
    group_name=$(getent group "$old_gid" | cut -d: -f1)
    userdel --remove "$source_user"
    if [[ "$group_name" == "$source_user" ]] && getent group "$group_name" >/dev/null; then
        groupdel "$group_name"
    fi
    useradd --create-home --uid "$old_uid" --shell /bin/bash --user-group visualps5
    usermod --password '!' visualps5
    chown -R visualps5:visualps5 "$target_home"

    if [[ -f /etc/wsl.conf ]]; then
        tmp=$(mktemp /etc/wsl.conf.ps5hs.XXXXXX)
        awk '
            BEGIN { in_user=0; found_user=0; wrote_default=0 }
            /^\[/ {
                if (in_user && !wrote_default) print "default=visualps5"
                in_user=($0 ~ /^\[user\][[:space:]]*$/)
                if (in_user) found_user=1
                print
                next
            }
            in_user && /^[[:space:]]*default[[:space:]]*=/ {
                if (!wrote_default) print "default=visualps5"
                wrote_default=1
                next
            }
            { print }
            END {
                if (in_user && !wrote_default) print "default=visualps5"
                if (!found_user) print "\n[user]\ndefault=visualps5"
            }
        ' /etc/wsl.conf > "$tmp"
        cat "$tmp" > /etc/wsl.conf
        rm -f -- "$tmp"
    else
        printf '[user]\ndefault=visualps5\n' > /etc/wsl.conf
    fi
    chmod 0644 /etc/wsl.conf

    [[ -x /opt/ps5-payload-sdk/bin/prospero-lld ]] || {
        echo "required installed SDK is missing: /opt/ps5-payload-sdk/bin/prospero-lld" >&2
        exit 5
    }
    python3 - "$lock_file" /etc/ps5hs-image-identity.json <<'PY'
import json
import hashlib
import os
import platform
import shutil
import subprocess
import sys
from datetime import datetime, timezone

lock_path, output_path = sys.argv[1:]
with open(lock_path, "r", encoding="utf-8") as stream:
    lock = json.load(stream)
with open("/etc/os-release", "r", encoding="utf-8") as stream:
    release = {}
    for line in stream:
        if "=" in line:
            key, value = line.rstrip().split("=", 1)
            release[key] = value.strip().strip('"')
architecture = subprocess.check_output(["dpkg", "--print-architecture"], text=True).strip()
if release.get("ID") != lock["ubuntu"]["id"] or release.get("VERSION_ID") != lock["ubuntu"]["versionId"]:
    raise SystemExit("Ubuntu release does not match image-lock.json")
if architecture != lock["ubuntu"]["architecture"]:
    raise SystemExit("image architecture does not match image-lock.json")
missing_commands = [name for name in lock["requiredCommands"] if not shutil.which(name)]
missing_paths = [path for path in lock["requiredPaths"] if not os.path.isfile(path) or not os.access(path, os.X_OK)]
if missing_commands or missing_paths:
    raise SystemExit("required image inputs missing: commands=" + repr(missing_commands) + ", paths=" + repr(missing_paths))
pacbrew = lock.get("pacbrew", {})
pacbrew_prefix = os.path.join("/", str(pacbrew.get("targetPrefix", "")).lstrip("/"))
pacbrew_manifest_path = os.path.join(pacbrew_prefix, ".ps5hs-pacbrew-install.json")
required_pacbrew_files = pacbrew.get("requiredFiles", [])
try:
    with open(pacbrew_manifest_path, "r", encoding="utf-8") as stream:
        pacbrew_manifest = json.load(stream)
except (OSError, json.JSONDecodeError) as exc:
    raise SystemExit("PacBrew installation manifest is missing or invalid: " + str(exc))
if (
    pacbrew_manifest.get("schema") != "ps5hs-pacbrew-homebrew"
    or pacbrew_manifest.get("version") != pacbrew.get("version")
    or pacbrew_manifest.get("archiveSha256") != pacbrew.get("sha256")
):
    raise SystemExit("PacBrew installation does not match image-lock.json")
recorded_pacbrew_files = {
    item.get("path"): item.get("sha256")
    for item in pacbrew_manifest.get("files", [])
    if isinstance(item, dict)
}
verified_pacbrew_files = {}
for relative_path in required_pacbrew_files:
    file_path = os.path.join(pacbrew_prefix, relative_path)
    if os.path.islink(file_path) or not os.path.isfile(file_path):
        raise SystemExit("required PS5 homebrew file is missing or linked: " + file_path)
    digest = hashlib.sha256()
    with open(file_path, "rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    actual_hash = digest.hexdigest()
    if actual_hash != recorded_pacbrew_files.get(relative_path):
        raise SystemExit("required PS5 homebrew file differs from its PacBrew manifest: " + file_path)
    verified_pacbrew_files[relative_path] = actual_hash
packages_raw = subprocess.check_output(
    ["dpkg-query", "-W", "-f=${binary:Package}\t${Version}\n"], text=True, stderr=subprocess.DEVNULL
)
packages = {}
for line in packages_raw.splitlines():
    fields = line.split("\t", 1)
    if len(fields) == 2:
        packages[fields[0]] = fields[1]
tools = {}
for name in lock.get("requiredCommands", []) + lock.get("optionalCommands", []):
    path = shutil.which(name)
    if path:
        completed = subprocess.run([name, "--version"], text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        first_line = (completed.stdout or "").splitlines()
        tools[name] = {"path": path, "version": first_line[0] if first_line else "available"}
    else:
        tools[name] = {"path": None, "version": None}
identity = {
    "schema": "ps5hs-wsl-image",
    "schemaVersion": lock["version"],
    "generatedAt": datetime.now(timezone.utc).isoformat(),
    "ubuntu": {key: release.get(key) for key in ("ID", "VERSION_ID", "VERSION", "VERSION_CODENAME", "PRETTY_NAME")},
    "architecture": architecture,
    "defaultUser": lock["ubuntu"]["defaultUser"],
    "packages": packages,
    "tools": tools,
    "sdkPaths": lock["requiredPaths"],
    "pacbrew": {
        "version": pacbrew["version"],
        "archiveSha256": pacbrew["sha256"],
        "targetPrefix": pacbrew["targetPrefix"],
        "requiredFiles": required_pacbrew_files,
        "verifiedFiles": verified_pacbrew_files,
    },
}
with open(output_path, "w", encoding="utf-8") as stream:
    json.dump(identity, stream, ensure_ascii=False, indent=2, sort_keys=True)
    stream.write("\n")
PY
    rm -f -- /etc/ps5hs-offline-image-stage-id
else
    rm -rf -- "$source_home"
    install -d -m 0755 "$target_home"
    if [[ -d "$root/etc/skel" ]]; then
        cp -a "$root/etc/skel/." "$target_home/"
    fi
    chown -R "$(id -u):$(id -g)" "$target_home" 2>/dev/null || true
fi

echo "Image sanitation completed."
