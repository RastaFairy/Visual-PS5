#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT="${1:-$ROOT/bin/ps5-at9-converter}"
mkdir -p "$(dirname "$OUTPUT")"
CXX="${CXX:-g++}"
"$CXX" -std=c++17 -O2 -Wall -Wextra -Wpedantic -pthread -static \
  -I "$ROOT/src/lib/at9" \
  "$ROOT/cli.cpp" \
  "$ROOT/src/lib/at9/at9_decode.cpp" \
  "$ROOT/src/lib/at9/at9_encoder.cpp" \
  "$ROOT/src/lib/at9/at9_snd0.cpp" \
  "$ROOT/src/lib/at9/at9_tables.cpp" \
  -o "$OUTPUT"
chmod 755 "$OUTPUT"
printf 'Built static ATRAC9 converter: %s\n' "$OUTPUT"