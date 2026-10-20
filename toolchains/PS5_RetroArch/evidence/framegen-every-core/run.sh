#!/usr/bin/env bash
# Frame generation on every core: one run each with its pad script (two recordings), its
# optional extra RetroArch argument. bash <this> <games-all.tsv> <out dir>
# The run tool's capture stamp ties the run to klog/retroarch-<stamp>.log and klog/pad-<stamp>/.
set -u
games=$1 out=$2
mkdir -p "$out"
while IFS=$'\t' read -r core path pad extra; do
    [[ $path == - ]] && path=""
    [[ $extra == - ]] && extra=""
    log="$out/$core.log"
    args=(--no-build --no-deploy "--game=$core:$path" "--pad-script=$pad" --watch ${WATCH:-95})
    [[ -n $extra ]] && args+=("$extra")
    timeout 360 bash tools/run-title.sh "${args[@]}" > "$log" 2>&1
    echo "$core: $(grep -o 'klog/pad-[0-9]*' "$log" | head -1) $(grep -c 'crash: signal' "$log") crash"
done < "$games"
echo finished
