#!/usr/bin/env bash
# PS5 OpenGL - OpenGL implementation for PlayStation 5.
# Copyright (C) 2026 BlackBearReloaded
# SPDX-License-Identifier: GPL-3.0-or-later

# Drive the in-process cts-runner title (PPSA99005 built with PS5_CTS_RUNNER=1)
# on one console. Results stream to /app0/cts-results/<run>/ (the title folder,
# so a full deploy removes them) and are read over FTP; no storage image is pulled.
#
#   cts-console-run.sh deploy <dist-dir>          verified sync of the title folder
#   cts-console-run.sh eboot <dist-dir>           replace only eboot.bin (verified)
#   cts-console-run.sh launch <run> <mode> [first] [last] [results-dir]
#       mode: official | sessions. Runs until the runner finishes, crashes or a
#       session log stops growing for CTS_HANG_SECONDS; then closes the title
#       and fetches the run directory into results-dir (default build/cts-runs/<run>).
#   cts-console-run.sh fetch <run> [results-dir]
#   cts-console-run.sh put <run> <local-file> <remote-name>
#
# The caller owns the console (see the console lock rules in docs/testing.md).

set -uo pipefail

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
host=${PS5_HOST:-192.168.4.40}
title=PPSA99005
ftp="ftp://$host:${FTP_PORT:-2121}"
protocol=${PS5_PROTOCOL:-$HOME/ps5-lab/ps5-homebrew-dev-protocol}
hang_seconds=${CTS_HANG_SECONDS:-900}
curl_ftp=(curl --globoff --fail --silent --show-error --disable-epsv --connect-timeout 5 --max-time 600)
remote_root=/data/homebrew/$title/cts-results

die() { printf '%s\n' "$*" >&2; exit 2; }

preflight() {
    local port
    for port in 2121 3232 9021; do
        nc -z -w 3 "$host" "$port" 2>/dev/null || die "preflight: $host port $port closed"
    done
}

# Plain names in a remote directory (this ftpsrv rejects NLST).
remote_names() {
    "${curl_ftp[@]}" "$ftp$1/" 2>/dev/null | tr -d '\r' |
        awk '$1 !~ /^d/ {print $5, $NF}'
}

remote_size() {
    "${curl_ftp[@]}" -I "$ftp$1" 2>/dev/null | tr -d '\r' |
        awk -F': ' 'tolower($1)=="content-length"{print $2}'
}

put_verified() {  # local remote [SELF]
    local local_file=$1 remote=$2 quote=() sum tmp
    [[ ${3:-} == SELF ]] && quote=(--quote SELF)
    sum=$(sha256sum "$local_file" | cut -d' ' -f1)
    tmp="$remote.upload-tmp"
    "${curl_ftp[@]}" --ftp-create-dirs -T "$local_file" "$ftp$tmp" || die "upload failed: $remote"
    [[ $("${curl_ftp[@]}" "${quote[@]}" "$ftp$tmp" | sha256sum | cut -d' ' -f1) == "$sum" ]] ||
        die "hash mismatch: $remote"
    "${curl_ftp[@]}" -Q "RNFR $tmp" -Q "RNTO $remote" "$ftp/data/" -o /dev/null ||
        die "promote failed: $remote"
}

fetch_run() {  # run results-dir
    local run=$1 out=$2 size name local_size
    mkdir -p "$out"
    while read -r size name; do
        [[ -n $name ]] || continue
        local_size=$(stat -c %s "$out/$name" 2>/dev/null || echo -1)
        [[ $local_size == "$size" ]] && continue
        "${curl_ftp[@]}" "$ftp$remote_root/$run/$name" -o "$out/$name" ||
            printf 'fetch failed: %s\n' "$name" >&2
    done < <(remote_names "$remote_root/$run")
    mkdir -p "$out/plan"
    while read -r size name; do
        [[ -n $name ]] || continue
        "${curl_ftp[@]}" "$ftp$remote_root/$run/plan/$name" -o "$out/plan/$name" || true
    done < <(remote_names "$remote_root/$run/plan")
}

controller() {
    bash "$protocol/scripts/send-controller.sh" "$1" "$title" "$host" 9021
}

launch() {
    local run=$1 mode=$2 first=${3:-1} last=${4:-1000000}
    local out=${5:-$root/build/cts-runs/$run}
    local control klog_pid state=running current="" last_size=-1 stale=0 elapsed=0
    mkdir -p "$out"
    preflight
    control=$(mktemp)
    printf 'run=%s\nmode=%s\nfirst=%s\nlast=%s\nlogflush=%s\nonly_caselists=%s\nshader_sources=%s\ndump_nir=%s\ncompute_sync=%s\nlog_images=%s\nwatchdog=%s\n' \
        "$run" "$mode" "$first" "$last" "${CTS_LOG_FLUSH:-1}" "${CTS_ONLY_CASELISTS:-0}" \
        "${CTS_SHADER_SOURCES:-0}" "${CTS_DUMP_NIR:-0}" "${CTS_COMPUTE_SYNC:-0}" \
        "${CTS_LOG_IMAGES:-0}" "${CTS_WATCHDOG:-0}" > "$control"
    # CTS_ENV="NAME=value ...": driver environment variables for this launch.
    for variable in ${CTS_ENV:-}; do
        printf 'env=%s\n' "$variable" >> "$control"
    done
    put_verified "$control" "$remote_root/control.txt"
    rm -f "$control"

    local klog="$out/klog-$(date +%Y%m%dT%H%M%S).txt"
    nc "$host" 3232 > "$klog" 2>/dev/null &
    klog_pid=$!
    sleep 2
    controller launch > "$out/launch.txt" 2>&1 || { kill "$klog_pid"; die "launch failed"; }
    printf 'launched %s run=%s mode=%s sessions=%s-%s\n' "$title" "$run" "$mode" "$first" "$last"

    while :; do
        sleep 20
        elapsed=$((elapsed + 20))
        if grep -qaE '\[ps5-opengl-cts\] (sessions finished|official run finished)' "$klog"; then
            state=finished; break
        fi
        if grep -qaE '\[ps5-opengl-cts\] (runner fatal|finished state=fatal)' "$klog"; then
            state=fatal; break
        fi
        if grep -qaE "ProcessTerm\(\) big/mini app title_id = \[$title\]|LaunchFlowError.$title" "$klog"; then
            state=crashed; break
        fi
        current=$(grep -aoE '\[ps5-opengl-cts\] session [0-9]+/[0-9]+ start [^ ]+' "$klog" |
                  tail -n1 | awk '{print $NF}' | tr -d '\r')
        if [[ -n $current ]]; then
            # dEQP names each case in klog as it starts; silence means a hang.
            local size
            size=$(grep -ac "Test case '" "$klog")
            if [[ $size == "$last_size" ]]; then
                stale=$((stale + 20))
            else
                stale=0; last_size=$size
            fi
            if (( stale >= hang_seconds )); then
                state=hung; break
            fi
        fi
        if (( elapsed % 600 == 0 )); then
            grep -aoE '\[ps5-opengl-cts\] session [0-9]+/[0-9]+ done .*' "$klog" | tail -n1
        fi
    done
    # A crash can precede the first poll; take the session from klog.
    current=$(grep -aoE '\[ps5-opengl-cts\] session [0-9]+/[0-9]+ start [^ ]+' "$klog" |
              tail -n1 | awk '{print $NF}' | tr -d '\r')
    printf 'runner state=%s current=%s\n' "$state" "$current"
    if [[ $state != crashed ]]; then
        controller close > "$out/close.txt" 2>&1 || printf 'close failed\n' >&2
        sleep 8
    fi
    kill "$klog_pid" 2>/dev/null; wait "$klog_pid" 2>/dev/null
    fetch_run "$run" "$out"
    printf '%s %s\n' "$state" "$current" > "$out/last-state.txt"
    grep -aoE '\[ps5-opengl-cts\] session [0-9]+/[0-9]+ done .*' "$klog" | tr -d '\r' >> "$out/sessions.log"
    preflight
}

case ${1:-} in
    deploy)
        [[ -d ${2:-} ]] || die "usage: $0 deploy <dist-dir>"
        preflight
        PS5_HOST=$host TITLE_ID=$title bash "$HOME/ps5-lab/tools/ps5-sync.sh" "$2" \
            "$root/build/cts-runs/deploy-$(date +%Y%m%dT%H%M%S)"
        ;;
    eboot)
        [[ -f ${2:-}/eboot.bin ]] || die "usage: $0 eboot <dist-dir>"
        preflight
        put_verified "$2/eboot.bin" "/data/homebrew/$title/eboot.bin" SELF
        echo "eboot $(sha256sum "$2/eboot.bin" | cut -c1-16) installed"
        ;;
    launch) shift; launch "$@" ;;
    fetch) fetch_run "$2" "${3:-$root/build/cts-runs/$2}" ;;
    put) put_verified "$3" "$remote_root/$2/$4" ;;
    *) die "usage: $0 deploy|eboot|launch|fetch|put ..." ;;
esac
