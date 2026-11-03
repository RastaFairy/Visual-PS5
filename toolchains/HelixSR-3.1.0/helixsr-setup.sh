#!/usr/bin/env bash
# Copyright 2026 lonewolf0622. All rights reserved (HelixSR Freeware License).
#
# HelixSR 3.0 setup for Linux and Steam Deck, the only thing to run:
#   1. the first time (or with --rebuild): builds HelixSR's upscaling network (from NVIDIA's DLSS 310.7.0 DLL, downloaded
#      from NVIDIA after you agree) and HLX FSR 4's shaders (from AMD's FSR 4 driver file amdxcffx64.dll 2.4.0.4370,
#      read out of AMD's driver package downloaded from AMD after you agree) on this PC, into the folders next to this
#      script;
#   2. lists your games and installs HelixSR into the ones you pick (HelixSR Scaler, or the FSR drop-in HLX FSR 4 for
#      games with FSR 3.1 and games with anti-cheat), updates or removes it.
#
#   ./helixsr-setup.sh [GAME_FOLDER].. [--dlss nvngx_dlss.dll] [--rebuild] [--yes]
#
# A GAME_FOLDER adds a game the setup does not find by itself. --yes answers every question with its default.
# Needs Python 3 with numpy: the script uses the system's, installs them with your distro's package manager (asks
# first), or downloads a portable Python into ~/.local/share/HelixSR (read-only systems such as SteamOS, or if you say
# no). Shaders are compiled with Microsoft's DirectX Shader Compiler (downloaded once from Microsoft's GitHub) through
# Proton/Wine, which every Linux setup that runs HelixSR already has.
set -euo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
PKG="$HERE/setup"
OUT="$HERE/HelixSR"
DATA="${XDG_DATA_HOME:-$HOME/.local/share}/HelixSR"
PY_URL='https://github.com/astral-sh/python-build-standalone/releases/download/20261003/cpython-3.12.15%2B20261003-x86_64-unknown-linux-gnu-install_only.tar.gz'
PY_SHA='f937814031eab4698ca6d07ec606ede1825768f3f3e99af76d9db3900bee03c5'
DXCWIN_URL='https://github.com/microsoft/DirectXShaderCompiler/releases/download/v1.9.2607/dxc_2026_07_29.zip'
DXCWIN_SHA='a1dfb116ba3eeae6a1582291b53a8e7bf65ad760676bd3194685c8f7367cd241'
# HLX FSR 4's kernels were built with both releases (some on Windows with v1.9.2609): the setup rebuilds them with each
DXC9_URL='https://github.com/microsoft/DirectXShaderCompiler/releases/download/v1.9.2609/dxc_2026_09_29.zip'
DXC9_SHA='ad31b1fc8443175d204f77a611fdb3ef2ec42759bdc2f1167368de24a4a7e7f1'

say() { printf '[helixsr-setup] %s\n' "$*"; }
die() { printf '[helixsr-setup] error: %s\n' "$*" >&2; exit 1; }
ask() {   # ask "question" -> 0 for yes (default yes); --yes answers yes
    [ "$ASSUME_YES" = 1 ] && return 0
    local r; read -r -p "$1 [Y/n] " r || r=n
    case "$r" in ''|y|Y|yes|YES) return 0 ;; *) return 1 ;; esac
}
fetch() {   # fetch URL FILE SHA256
    say "downloading $(basename "$2")"
    if command -v curl >/dev/null; then curl -fL --retry 3 -o "$2" "$1"
    elif command -v wget >/dev/null; then wget -q -O "$2" "$1"
    else die "needs curl or wget"; fi
    echo "$3  $2" | sha256sum -c --status || { rm -f "$2"; die "$(basename "$2"): checksum mismatch"; }
}

# --- arguments ---
ASSUME_YES=0; PASS=(); REBUILD=0; NO_FG=0; INST=()
while [ $# -gt 0 ]; do
    case "$1" in
        --yes|-y) ASSUME_YES=1; PASS+=(--yes); INST+=(--yes) ;;
        --dlss) PASS+=(--dlss "$(realpath "$2")"); shift ;;
        --dlssg) PASS+=(--dlssg "$(realpath "$2")"); shift ;;
        --no-fg) NO_FG=1; PASS+=(--no-fg) ;;
        --rebuild) REBUILD=1 ;;
        -h|--help) sed -n '3,17p' "$0"; exit 0 ;;
        -*) die "unknown option: $1 (see --help)" ;;
        *) [ -d "$1" ] || die "not a folder: $1"; INST+=(--folder "$(realpath "$1")") ;;
    esac
    shift
done
# a package without frame generation (no setup/fg) builds the network only
HAS_FG=1; [ -f "$PKG/fg/fg_setup.py" ] || { HAS_FG=0; NO_FG=1; }
[ "$(uname -m)" = x86_64 ] || die "x86-64 Linux only"
[ -f "$OUT/helixsr.dll" ] || die "$OUT/helixsr.dll is missing: extract the whole ZIP and run the setup there"
mkdir -p "$DATA"

# --- distro ---
ID=unknown; ID_LIKE=""
[ -r /etc/os-release ] && . /etc/os-release
FAMILY=unknown
case " $ID $ID_LIKE " in
    *" arch "*|*" cachyos "*|*" manjaro "*|*" endeavouros "*) FAMILY=arch ;;
    *" debian "*|*" ubuntu "*) FAMILY=debian ;;
    *" fedora "*|*" rhel "*|*" centos "*) FAMILY=fedora ;;
    *" suse "*|*" opensuse "*) FAMILY=suse ;;
esac
IMMUTABLE=0   # SteamOS and ostree systems (Bazzite, Silverblue, Kinoite): no package installs
{ [ "$ID" = steamos ] || [ -e /run/ostree-booted ]; } && IMMUTABLE=1
say "system: ${PRETTY_NAME:-$ID} (family: $FAMILY$([ $IMMUTABLE = 1 ] && echo ', read-only system'))"

# --- Python 3 with numpy ---
has_numpy() { "$1" -c 'import numpy, sys; sys.exit(0 if sys.version_info >= (3, 8) else 1)' 2>/dev/null; }
PY=""
# (HELIXSR_FORCE_PORTABLE=1: test switch for the portable-Python path)
[ "${HELIXSR_FORCE_PORTABLE:-0}" = 1 ] && CANDIDATES=("$DATA/python/bin/python3") || CANDIDATES=("$DATA/python/bin/python3" python3)
for c in "${CANDIDATES[@]}"; do
    if command -v "$c" >/dev/null 2>&1 && has_numpy "$c"; then PY=$(command -v "$c"); break; fi
done
if [ -z "$PY" ] && [ "${HELIXSR_FORCE_PORTABLE:-0}" != 1 ] && [ $IMMUTABLE = 0 ] && [ $FAMILY != unknown ] && command -v sudo >/dev/null; then
    case $FAMILY in
        arch)   CMD="sudo pacman -S --needed --noconfirm python python-numpy" ;;
        debian) CMD="sudo apt-get install -y python3 python3-numpy" ;;
        fedora) CMD="sudo dnf install -y python3 python3-numpy" ;;
        suse)   CMD="sudo zypper --non-interactive install python3 python3-numpy" ;;
    esac
    if ask "Install Python 3 + numpy with your package manager ($CMD)?"; then
        if $CMD && has_numpy python3; then PY=$(command -v python3); fi
    fi
fi
if [ -z "$PY" ]; then
    say "using a portable Python in $DATA/python (one-time download, ~67 MB)"
    if [ ! -x "$DATA/python/bin/python3" ]; then
        fetch "$PY_URL" "$DATA/python.tar.gz" "$PY_SHA"
        tar -C "$DATA" -xzf "$DATA/python.tar.gz" && rm -f "$DATA/python.tar.gz"
    fi
    "$DATA/python/bin/python3" -m pip install --quiet --disable-pip-version-check numpy || die "numpy install failed"
    PY="$DATA/python/bin/python3"
fi
say "python: $PY"
# NVIDIA's NGX core comes out of a zstd-compressed package: Python 3.14 reads it, older ones need the zstd program
if [ $NO_FG = 0 ] && ! "$PY" -c 'import compression.zstd' 2>/dev/null && ! command -v zstd >/dev/null; then
    say "note: frame generation needs the zstd program with this Python (install zstd with your package manager)"
fi

# --- what is built already: the network inside HelixSR's DLL, frame generation in helixsr-fg ---
STATUS=$("$PY" "$PKG/helixsr_setup.py" "$OUT" --status)
NET=0; FG=0; HLX=0
case "$STATUS" in *network=1*) NET=1 ;; esac
case "$STATUS" in *fg=1*) FG=1 ;; esac
case "$STATUS" in *hlx=1*) HLX=1 ;; esac
[ $NO_FG = 1 ] && FG=1
if [ "$REBUILD" = 0 ] && [ $NET = 1 ] && [ $FG = 1 ] && [ $HLX = 1 ]; then
    say "already built (--rebuild builds it again): $OUT"
else
# --- shader compiler: Microsoft's DXC (Windows build) through Proton/Wine ---
WINE=""
# official Proton first, then custom Proton builds, then a system Wine
for p in "$HOME"/.local/share/Steam/steamapps/common/Proton*/files/bin/wine \
         "$HOME"/.steam/steam/steamapps/common/Proton*/files/bin/wine \
         "$HOME"/.local/share/Steam/compatibilitytools.d/*/files/bin/wine \
         "$HOME"/.steam/root/compatibilitytools.d/*/files/bin/wine; do
    if [ -x "$p" ]; then WINE="$p"; break; fi
done
[ -z "$WINE" ] && command -v wine >/dev/null && WINE=$(command -v wine)
[ -n "$WINE" ] || die "no Proton or Wine found (needed to run the shader compiler); install Proton in Steam or Wine"
unpack_dxc() {   # unpack_dxc ZIP DIR (the zip stores Windows paths: bin\x64\dxc.exe)
    "$PY" -c 'import os, sys, zipfile
z = zipfile.ZipFile(sys.argv[1]); n_out = 0
for n in z.namelist():
    t = n.replace(chr(92), "/")
    if t.startswith("bin/x64/") and not t.endswith("/"):
        p = os.path.join(sys.argv[2], t); os.makedirs(os.path.dirname(p), exist_ok=True)
        open(p, "wb").write(z.read(n)); n_out += 1
sys.exit(0 if n_out else 1)' "$1" "$2" || die "could not unpack the shader compiler"
    rm -f "$1"
}
if [ ! -f "$DATA/dxc-win/bin/x64/dxc.exe" ]; then
    fetch "$DXCWIN_URL" "$DATA/dxc-win.zip" "$DXCWIN_SHA"; unpack_dxc "$DATA/dxc-win.zip" "$DATA/dxc-win"
fi
if [ -d "$PKG/hlxfsr4" ] && [ ! -f "$DATA/dxc-win-2609/bin/x64/dxc.exe" ]; then
    fetch "$DXC9_URL" "$DATA/dxc-win-2609.zip" "$DXC9_SHA"; unpack_dxc "$DATA/dxc-win-2609.zip" "$DATA/dxc-win-2609"
fi
DXC="$DATA/dxc-wine.sh"
cat > "$DXC" <<EOS
#!/usr/bin/env bash
# DXC through Wine: absolute Linux paths become Z:\\ paths
args=()
for a in "\$@"; do case "\$a" in /*) args+=("Z:\$(printf '%s' "\$a" | tr / '\\\\')") ;; *) args+=("\$a") ;; esac; done
WINEPREFIX="$DATA/wineprefix" WINEDEBUG=-all exec "$WINE" "$DATA/dxc-win/bin/x64/dxc.exe" "\${args[@]}"
EOS
chmod +x "$DXC"
say "shader compiler: Windows DXC through $(dirname "$(dirname "$(dirname "$WINE")")")"

# --- build (HLX FSR 4 and frame generation only when the network is there already) ---
ONLY=(); [ "$REBUILD" = 0 ] && [ $NET = 1 ] && ONLY=(--fg-only)
rc=0
"$PY" "$PKG/helixsr_setup.py" "$OUT" --dxc "$DXC" "${ONLY[@]}" "${PASS[@]}" \
    --dxc-dir "$DATA/dxc-win/bin/x64" --dxc2609-dir "$DATA/dxc-win-2609/bin/x64" --wine "$WINE" --wineprefix "$DATA/wineprefix" || rc=$?
rm -rf "$DATA/wineprefix"   # the Wine compiler's temporary prefix
[ $rc = 0 ] || [ $rc = 3 ] || [ $rc = 4 ] || [ $rc = 1 -a ${#ONLY[@]} = 1 ] || die "the setup stopped (exit $rc)"
fi

STATUS=$("$PY" "$PKG/helixsr_setup.py" "$OUT" --status)
case "$STATUS" in *network=1*) ;; *) die "the network is not built" ;; esac
say "done: $OUT"
case "$HAS_FG$STATUS" in
    0*) say "  upscaling is ready" ;;
    *fg=1*) say "  upscaling and DLSS frame generation are ready" ;;
    *) say "  upscaling is ready; DLSS frame generation is not (run the setup again to retry)" ;;
esac
if [ -d "$PKG/hlxfsr4" ]; then
    case "$STATUS" in
        *hlx=1*) say "  HLX FSR 4 is ready (HLX-FSR4/ and helixsr-scaler/OptiScaler/)" ;;
        *) say "  HLX FSR 4 is not built (the reason is above; run the setup again to retry)" ;;
    esac
fi
say "The HelixSR folder contains files built from NVIDIA's software: it is for this PC only, do not share or upload it."
[ -d "$PKG/hlxfsr4" ] && say "HLX FSR 4's DLLs contain data built from AMD's software: they are for this PC only too."

# --- games ---
echo
exec "$PY" "$PKG/helixsr_install.py" "$HERE" "${INST[@]}"
