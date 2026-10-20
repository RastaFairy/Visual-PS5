#!/usr/bin/env bash
# Ghostship for the PlayStation 5 - upload your own game data to the console.
#
#   ps5/tools/console-files.sh       game/<TITLE_ID>/ (sm64.o2r, from tools/assets.sh ROM)
#                                    to /data/homebrew/<TITLE_ID>/ on the console
#
# The game's data is yours and is never part of dist/ or of a release: it goes
# up apart from the title, with PS5_Vulkan's console settings (its .env).
#
# SPDX-License-Identifier: MIT
set -euo pipefail
ps5=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
root=$(dirname "$ps5")
vulkan=$(cd -- "${PS5_VULKAN_DIR:-$root/../PS5_Vulkan}" && pwd)
title_id=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["titleId"])' "$ps5/sce_sys/param.json")
[[ -f $root/game/$title_id/sm64.o2r ]] || { echo "no game/$title_id/sm64.o2r: run ps5/tools/assets.sh ROM.z64 first" >&2; exit 2; }
exec python3 - "$vulkan/tools" "$root/game/$title_id" "$title_id" <<'PY'
import sys
from ftplib import FTP, error_perm
from pathlib import Path

sys.path.insert(0, sys.argv[1])
import ps5_console

folder, title = Path(sys.argv[2]), sys.argv[3]
settings = ps5_console.load_settings()
status = ps5_console.ps5vkctl_command(settings, "procs", timeout=20)
if " count=0 " not in status + " ":
    raise SystemExit(f"the console is running an application ({status.strip()}); not uploading")
with FTP() as ftp:
    ftp.connect(settings["host"], settings["ftp_port"], timeout=30)
    ftp.login(settings["ftp_user"], settings["ftp_password"] or "codex")
    ftp.voidcmd("TYPE I")
    for local in sorted(p for p in folder.iterdir() if p.is_file()):
        remote = f"/data/homebrew/{title}/{local.name}"
        try:
            if ftp.size(remote) == local.stat().st_size:
                print(f"  {local.name}  already there")
                continue
        except error_perm:
            pass
        # whole or not at all: under another name until it is complete
        with local.open("rb") as data:
            ftp.storbinary(f"STOR {remote}.upload", data)
        ftp.rename(f"{remote}.upload", remote)
        print(f"  {local.name}  {local.stat().st_size:,} bytes")
PY
