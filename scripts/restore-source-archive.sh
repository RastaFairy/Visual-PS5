#!/usr/bin/env sh
set -eu
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
REPO_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
SEGMENTS="$REPO_ROOT/release/source-archive"
OUTPUT="$REPO_ROOT/PS5-Homebrew-Studio-v1.0.1.tar.xz"
EXPECTED='f6aa6aae6d5d58a1e5e2e3582d168f0e97f67e1d105938ed6039ba963b329d13'

command -v base64 >/dev/null 2>&1 || { echo 'base64 utility is required.' >&2; exit 1; }
cat "$SEGMENTS"/part*.b64 | base64 --decode > "$OUTPUT"
ACTUAL=$(sha256sum "$OUTPUT" | awk '{print $1}')
if [ "$ACTUAL" != "$EXPECTED" ]; then
  rm -f "$OUTPUT"
  echo "SHA-256 mismatch: expected $EXPECTED, got $ACTUAL" >&2
  exit 1
fi
tar -tJf "$OUTPUT" >/dev/null
tar -xJf "$OUTPUT" -C "$REPO_ROOT"
printf 'Source restored and verified under %s/PS5-Homebrew-Studio\n' "$REPO_ROOT"
