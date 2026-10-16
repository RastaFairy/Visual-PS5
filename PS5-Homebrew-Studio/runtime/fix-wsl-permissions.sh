#!/usr/bin/env bash
set -euo pipefail

CONF="${WSL_CONF_PATH:-/etc/wsl.conf}"
if [[ "$EUID" -ne 0 ]]; then
  echo "Este ajuste modifica /etc/wsl.conf. Ejecuta: sudo bash \"$0\"" >&2
  exit 2
fi
if ! command -v python3 >/dev/null 2>&1; then
  echo "Se necesita python3 para actualizar wsl.conf sin eliminar otras opciones." >&2
  exit 3
fi

BACKUP=""
if [[ -f "$CONF" ]]; then
  BACKUP="$CONF.backup.$(date +%Y%m%d-%H%M%S)"
  cp -p "$CONF" "$BACKUP"
fi

python3 - "$CONF" <<'PY'
from pathlib import Path
import os
import re
import stat
import sys
import tempfile

path = Path(sys.argv[1])
mode = stat.S_IMODE(path.stat().st_mode) if path.exists() else 0o644
with path.open("r", encoding="utf-8", newline="") as source if path.exists() else __import__("contextlib").nullcontext("") as handle:
    text = handle.read()
lines = text.splitlines(keepends=True)
newline = "\r\n" if "\r\n" in text else "\n"
section_match = re.compile(r"^\s*\[([^\]]+)\]\s*(?:[#;].*)?$")
section_start = None
section_end = len(lines)
for idx, line in enumerate(lines):
    match = section_match.match(line.rstrip("\r\n"))
    if not match:
        continue
    if match.group(1).strip().lower() == "automount" and section_start is None:
        section_start = idx
        continue
    if section_start is not None:
        section_end = idx
        break

if section_start is None:
    if lines and not lines[-1].endswith(("\n", "\r")):
        lines[-1] += newline
    if lines and lines[-1].strip():
        lines.append(newline)
    lines.extend(["[automount]" + newline, 'options = "metadata"' + newline])
else:
    option_idx = None
    for idx in range(section_start + 1, section_end):
        line = lines[idx].rstrip("\r\n")
        if re.match(r"^\s*options\s*=", line, re.IGNORECASE):
            option_idx = idx
            break
    if option_idx is None:
        lines.insert(section_start + 1, 'options = "metadata"' + newline)
    else:
        original = lines[option_idx]
        eol = "\r\n" if original.endswith("\r\n") else ("\n" if original.endswith("\n") else "")
        body = original[:-len(eol)] if eol else original
        prefix, value = body.split("=", 1)
        value = value.strip()
        quote = value[0] if value.startswith(("'", '"')) else ""
        trailing = ""
        if quote:
            end = value.find(quote, 1)
            if end < 0:
                raise SystemExit("La opción automount/options tiene comillas sin cerrar; no se modificó el archivo.")
            option_text = value[1:end]
            trailing = value[end + 1:]
        else:
            option_text, marker, comment = value.partition("#")
            trailing = ((" #" + comment) if marker else "")
            option_text = option_text.strip()
        options = [item.strip() for item in option_text.split(",") if item.strip()]
        if not any(item.lower() == "metadata" for item in options):
            options.append("metadata")
        wrapped = quote if quote else ""
        lines[option_idx] = prefix + "= " + wrapped + ",".join(options) + wrapped + trailing + eol

new_text = "".join(lines)
path.parent.mkdir(parents=True, exist_ok=True)
fd, temp_name = tempfile.mkstemp(prefix="wsl.conf.", dir=str(path.parent))
try:
    with os.fdopen(fd, "w", encoding="utf-8", newline="") as out:
        out.write(new_text)
    os.chmod(temp_name, mode)
    os.replace(temp_name, path)
finally:
    if os.path.exists(temp_name):
        os.unlink(temp_name)
print("Configuración actualizada: [automount] options incluye metadata.")
PY

if [[ -n "$BACKUP" ]]; then
  echo "Copia de seguridad: $BACKUP"
else
  echo "Se creó /etc/wsl.conf (no existía una configuración anterior)."
fi
echo
echo "Ahora cierra esta distribución. Desde PowerShell de Windows ejecuta:"
echo "  wsl --shutdown"
echo "Inicia WSL otra vez y vuelve a compilar en PS5 Homebrew Studio."
