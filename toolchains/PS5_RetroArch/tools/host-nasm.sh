# Sourced by the builds that assemble x86 code with NASM (Mupen64Plus's
# dynarec linkage, FFmpeg): builds the pinned NASM for the host once, with the
# host's compiler, into .deps/native/nasm-<version>, and sets $nasm.
host_nasm() {
    local version=2.16.03
    local digest=1412a1c760bbd05db026b6c0d1657affd6631cd0a63cddb6f73cc6d4aa616148
    nasm="$root/.deps/native/nasm-$version/bin/nasm"
    [[ -x $nasm ]] && return 0
    local archive="$root/.deps/downloads/nasm-$version.tar.xz"
    mkdir -p "$root/.deps/downloads"
    [[ -f $archive ]] || curl --fail --location --retry 3 \
        "https://www.nasm.us/pub/nasm/releasebuilds/$version/nasm-$version.tar.xz" -o "$archive"
    printf '%s  %s\n' "$digest" "$archive" | sha256sum --check --status || {
        echo "error: NASM archive digest mismatch" >&2; exit 1; }
    local source="$root/build/nasm-src"
    rm -rf -- "$source"
    mkdir -p "$source"
    tar -xJf "$archive" -C "$source" --strip-components=1
    # A host tool: the host's compiler, not the console's in CC.
    (cd "$source" && env -u CFLAGS -u LDFLAGS CC=cc ./configure -q > /dev/null &&
        make -s -j"${JOBS:-16}" CC=cc nasm > /dev/null)
    mkdir -p "$(dirname -- "$nasm")"
    cp -- "$source/nasm" "$nasm"
}
