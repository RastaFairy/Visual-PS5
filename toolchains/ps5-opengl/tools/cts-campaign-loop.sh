#!/usr/bin/env bash
# PS5 OpenGL - OpenGL implementation for PlayStation 5.
# Copyright (C) 2026 BlackBearReloaded
# SPDX-License-Identifier: GPL-3.0-or-later

# Run a sessions-mode cts-runner triage run to the end: after a crash or hang,
# record the case, resume the session after it and relaunch.
#   cts-campaign-loop.sh <run> <app-dist-dir> [first] [last]

set -uo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
run=$1 dist=$2 first=${3:-1} last=${4:-1000000}
out=$root/build/cts-runs/$run
for attempt in $(seq 1 200); do
    bash "$root/tools/cts-console-run.sh" launch "$run" sessions "$first" "$last" "$out" || exit 1
    read -r state current < "$out/last-state.txt"
    case $state in
        finished) echo "run $run finished after $attempt launches"; exit 0 ;;
        crashed|hung)
            # The session named in the last start marker is the one to resume.
            [[ -n $current ]] || { echo "no current session after $state"; exit 1; }
            name=${current%.resume}
            # dEQP announces each case on stdout (klog) before running it.
            klog=$(ls -t "$out"/klog-*.txt | head -n1)
            crashed=$(grep -aoE "Test case '[^']+'" "$klog" | tail -n1 | cut -d"'" -f2)
            python3 "$root/tools/cts-runner-results.py" resume "$out" "$name" --mustpass "$dist" \
                ${crashed:+--crashed "$crashed"} || exit 1
            bash "$root/tools/cts-console-run.sh" put "$run" "$out/$name.caselist" "$name.caselist" || exit 1
            ;;
        *) echo "runner state $state; stopping"; exit 1 ;;
    esac
done
