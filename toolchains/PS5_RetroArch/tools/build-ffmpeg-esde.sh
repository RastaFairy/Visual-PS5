#!/usr/bin/env bash
# Build FFmpeg for EmulationStation on the PS5 as static archives (its video
# player, es-core's VideoFFmpegComponent; docs/FRONTENDS.md).
#
# The same signed release tools/build-ffmpeg.sh builds for RPCS3 (8.1.1, the same
# digest), with the components EmulationStation uses instead: its filter graphs
# (buffer, buffersink, abuffer, abuffersink, scale, fps, format, aresample,
# aformat) and the formats theme and scraped videos come in (MP4, Matroska/WebM,
# AVI, Ogg; H.264, HEVC, VP8, VP9, MPEG-4, MPEG-2; AAC, MP3, Vorbis, Opus, FLAC,
# PCM). No network, no programs or docs; software decoding.
#
# Output: .deps/native/ffmpeg-esde-ps5 (lib/*.a, include/), with the version and
# this script's digest in .stamp.
set -euo pipefail

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
cd "$root"
version=8.1.1
digest=b6863adde98898f42602017462871b5f6333e65aec803fdd7a6308639c52edf3
prefix="$root/.deps/native/ffmpeg-esde-ps5"
stamp="$version $(sha256sum "$0" | cut -c1-64)"
[[ -f $prefix/.stamp && $(<"$prefix/.stamp") == "$stamp" ]] && {
    echo "==> [ffmpeg-esde] $version already built in $prefix"; exit 0; }

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

build="$root/build/ffmpeg-esde-ps5"
rm -rf -- "$build"
mkdir -p "$build/src" "$build/empty-libs"
tar -xJf "$archive" -C "$build/src" --strip-components=1
# FFmpeg links -lm; the math functions are the console's own libc.
"$sdk/bin/prospero-ar" rc "$build/empty-libs/libm.a"
cc="$sdk/bin/prospero-clang"
command -v ccache >/dev/null && cc="ccache $cc"
components=(
    --enable-avfilter
    --enable-filter=buffer --enable-filter=buffersink --enable-filter=abuffer --enable-filter=abuffersink
    --enable-filter=scale --enable-filter=fps --enable-filter=format --enable-filter=aresample
    --enable-filter=aformat --enable-filter=null --enable-filter=anull
    # es-core's VideoFFmpegComponent ends its audio graph with asetnsamples; without it the
    # graph fails ("Couldn't add graph filter: Filter not found") and videos stay black.
    --enable-filter=asetnsamples
    --enable-decoder=h264 --enable-decoder=hevc --enable-decoder=vp8 --enable-decoder=vp9
    --enable-decoder=mpeg4 --enable-decoder=mpeg2video --enable-decoder=mpeg1video --enable-decoder=mjpeg
    --enable-decoder=aac --enable-decoder=aac_latm --enable-decoder=mp3 --enable-decoder=mp3float
    --enable-decoder=vorbis --enable-decoder=opus --enable-decoder=flac
    --enable-decoder=pcm_s16le --enable-decoder=pcm_s16be --enable-decoder=pcm_s24le --enable-decoder=pcm_f32le
    --enable-demuxer=mov --enable-demuxer=matroska --enable-demuxer=avi --enable-demuxer=ogg
    --enable-demuxer=mp3 --enable-demuxer=flac --enable-demuxer=wav --enable-demuxer=mpegps
    --enable-demuxer=mpegts --enable-demuxer=h264 --enable-demuxer=hevc --enable-demuxer=aac
    --enable-parser=h264 --enable-parser=hevc --enable-parser=vp8 --enable-parser=vp9
    --enable-parser=mpeg4video --enable-parser=mpegvideo --enable-parser=aac --enable-parser=mpegaudio
    --enable-parser=vorbis --enable-parser=opus --enable-parser=flac
    --enable-protocol=file --enable-swscale --enable-swresample
)
echo "==> [ffmpeg-esde] configuring $version"
(cd "$build/src" && ./configure --prefix="$prefix" \
    --enable-cross-compile --target-os=freebsd --arch=x86_64 --cpu=znver2 \
    --cc="$cc" --cxx="$sdk/bin/prospero-clang++" --ar="$sdk/bin/prospero-ar" \
    --ranlib="$sdk/bin/prospero-ranlib" --nm="$sdk/bin/prospero-nm" \
    --x86asmexe="$nasm" --pkg-config=false \
    --enable-static --disable-shared --enable-pic --disable-programs --disable-doc \
    --disable-debug --disable-autodetect --disable-avdevice \
    --disable-everything --disable-network "${components[@]}" \
    --extra-ldflags="-L$build/empty-libs" > "$build/configure.log" 2>&1) ||
    { tail -30 "$build/configure.log" >&2; tail -40 "$build/src/ffbuild/config.log" >&2; exit 1; }
echo "==> [ffmpeg-esde] building"
make -C "$build/src" -j"${JOBS:-16}" > "$build/make.log" 2>&1 || { tail -30 "$build/make.log" >&2; exit 1; }
rm -rf -- "$prefix"
make -C "$build/src" install > "$build/install.log" 2>&1
mkdir -p "$prefix/share/licenses/ffmpeg"
cp "$build/src/COPYING.LGPLv2.1" "$build/src/LICENSE.md" "$prefix/share/licenses/ffmpeg/"
printf '%s\n' "$stamp" > "$prefix/.stamp"
printf '==> [ffmpeg-esde] %s: %s of archives in %s\n' "$version" "$(du -sh "$prefix/lib" | cut -f1)" "$prefix"
