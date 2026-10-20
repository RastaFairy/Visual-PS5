#!/usr/bin/env bash
# Build FFmpeg for the PS5 as static archives, for RPCS3's media decoding
# (docs/RPCS3_PORT.md).
#
# RPCS3's own prebuilt archive (RPCS3/ffmpeg-core, FFmpeg 8.1.1) has no build for
# this console, so the same release is built from its signed source tarball,
# with the component list RPCS3 builds it with (ffmpeg-core's ffmpeg.patch):
# everything else disabled, no network, no programs or docs. Software decoding;
# the console's hardware decoder is a later option.
#
# Output: .deps/native/ffmpeg-ps5 (lib/*.a, include/), with the version and
# this script's digest in .deps/native/ffmpeg-ps5/.stamp.
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
cd "$root"

version=8.1.1
digest=b6863adde98898f42602017462871b5f6333e65aec803fdd7a6308639c52edf3
prefix="$root/.deps/native/ffmpeg-ps5"
stamp="$version $(sha256sum "$0" | cut -c1-64)"
[[ -f $prefix/.stamp && $(<"$prefix/.stamp") == "$stamp" ]] && {
    echo "==> [ffmpeg] $version already built in $prefix"; exit 0; }

sdk="$root/.deps/native/ps5-payload-sdk"
[[ -x $sdk/bin/prospero-clang ]] || { echo "error: bootstrap this project's SDK first" >&2; exit 2; }
export PS5_PAYLOAD_SDK="$sdk" PS5_CLANG=${PS5_CLANG:-/usr/bin/clang}
source "$root/tools/host-nasm.sh"
host_nasm

archive="$root/.deps/downloads/ffmpeg-$version.tar.xz"
mkdir -p "$root/.deps/downloads"
[[ -f $archive ]] || curl --fail --location --retry 3 \
    "https://ffmpeg.org/releases/ffmpeg-$version.tar.xz" -o "$archive"
printf '%s  %s\n' "$digest" "$archive" | sha256sum --check --status || {
    echo "error: FFmpeg archive digest mismatch" >&2; exit 1; }
build="$root/build/ffmpeg-ps5"
rm -rf -- "$build"
mkdir -p "$build/src" "$build/empty-libs"
tar -xJf "$archive" -C "$build/src" --strip-components=1
# FFmpeg links -lm; the math functions are the console's own libc.
"$sdk/bin/prospero-ar" rc "$build/empty-libs/libm.a"

cc="$sdk/bin/prospero-clang"
command -v ccache >/dev/null && cc="ccache $cc"
components=(
    --enable-decoder=aac --enable-decoder=aac_latm --enable-decoder=atrac3
    --enable-decoder=atrac3p --enable-decoder=atrac9 --enable-decoder=mp3
    --enable-decoder=pcm_s16le --enable-decoder=pcm_s8 --enable-decoder=mov
    --enable-decoder=h264 --enable-decoder=mpeg4 --enable-decoder=mpeg2video
    --enable-decoder=mjpeg --enable-decoder=mjpegb
    --enable-encoder=pcm_s16le --enable-encoder=mp3 --enable-encoder=ac3 --enable-encoder=aac
    --enable-encoder=ffv1 --enable-encoder=mpeg4 --enable-encoder=mjpeg --enable-encoder=h264
    --enable-muxer=avi --enable-muxer=h264 --enable-muxer=mjpeg --enable-muxer=mp4
    --enable-demuxer=h264 --enable-demuxer=m4v --enable-demuxer=mp3 --enable-demuxer=mpegvideo
    --enable-demuxer=mpegps --enable-demuxer=mjpeg --enable-demuxer=mov --enable-demuxer=avi
    --enable-demuxer=aac --enable-demuxer=pmp --enable-demuxer=oma --enable-demuxer=pcm_s16le
    --enable-demuxer=pcm_s8 --enable-demuxer=wav
    --enable-parser=h264 --enable-parser=mpeg4video --enable-parser=mpegaudio
    --enable-parser=mpegvideo --enable-parser=mjpeg --enable-parser=aac --enable-parser=aac_latm
    --enable-protocol=file --enable-bsf=mjpeg2jpeg
)
echo "==> [ffmpeg] configuring $version"
(cd "$build/src" && ./configure --prefix="$prefix" \
    --enable-cross-compile --target-os=freebsd --arch=x86_64 --cpu=znver2 \
    --cc="$cc" --cxx="$sdk/bin/prospero-clang++" --ar="$sdk/bin/prospero-ar" \
    --ranlib="$sdk/bin/prospero-ranlib" --nm="$sdk/bin/prospero-nm" \
    --x86asmexe="$nasm" --pkg-config=false \
    --enable-static --disable-shared --enable-pic --disable-programs --disable-doc \
    --disable-debug --disable-autodetect --disable-avdevice --disable-avfilter \
    --disable-everything --disable-network "${components[@]}" \
    --extra-ldflags="-L$build/empty-libs" > "$build/configure.log" 2>&1) ||
    { tail -30 "$build/configure.log" >&2; tail -40 "$build/src/ffbuild/config.log" >&2; exit 1; }
echo "==> [ffmpeg] building"
make -C "$build/src" -j"${JOBS:-16}" > "$build/make.log" 2>&1 || { tail -30 "$build/make.log" >&2; exit 1; }
rm -rf -- "$prefix"
make -C "$build/src" install > "$build/install.log" 2>&1
printf '%s\n' "$stamp" > "$prefix/.stamp"
printf '==> [ffmpeg] %s: %s of archives in %s\n' "$version" "$(du -sh "$prefix/lib" | cut -f1)" "$prefix"
