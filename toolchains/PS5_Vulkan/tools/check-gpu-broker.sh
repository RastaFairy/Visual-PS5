#!/usr/bin/env bash
# Copyright (C) 2026 Mihawk-99
# SPDX-License-Identifier: LGPL-2.1-or-later
# Bounds, descriptor transfer, full packets and truncation cleanup; no PS5 required.
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
out=${1:-$root/build/gpu-broker-host}
mkdir -p "$out"
"${CC:-cc}" -std=gnu11 -O2 -g -Wall -Wextra -Werror -fsanitize=address,undefined \
    "$root/tooling/gpu-broker/test_transport.c" "$root/tooling/gpu-broker/packet_io.c" -o "$out/test_transport"
"$out/test_transport"
