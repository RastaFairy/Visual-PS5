#!/usr/bin/env bash
# Build libcurl over mbedTLS for the PS5 as static archives, for EmulationStation's
# HTTP (es-core's HttpReq: the scraper and media downloads; docs/FRONTENDS.md).
#
# Both release archives are GitHub's, pinned by the digests GitHub publishes for
# them: mbedTLS 3.6.7 (the 3.6 long-term branch, 2026-07-07) and curl 8.22.0
# (2026-09-02). RetroArch's own mbedTLS is 2.6.0, too old for today's TLS. curl is
# HTTP and HTTPS only: no other protocols, compression, HTTP/2, IDN or
# certificate store (EmulationStation names its bundled certificates). The SDK
# declares pipe2, which the console's libc does not have: curl uses a socketpair.
#
# Output: .deps/native/curl-ps5 (lib/libcurl.a, lib/libmbed{tls,x509,crypto}.a,
# include/curl, include/mbedtls, include/psa), with the versions and this
# script's digest in .deps/native/curl-ps5/.stamp.
set -euo pipefail

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
cd "$root"
mbedtls_version=3.6.7
mbedtls_digest=a7e8bcbec0e6f761b4af24f25677626b35f762f68eef79c08677a363212d11f6
curl_version=8.22.0
curl_digest=5d956a6a22b3c279f50c421ee5d3c9e9d660cb6f115dcf881b579e952130549c
prefix="$root/.deps/native/curl-ps5"
stamp="$curl_version $mbedtls_version $(sha256sum "$0" | cut -c1-64)"
[[ -f $prefix/.stamp && $(<"$prefix/.stamp") == "$stamp" ]] && {
    echo "==> [curl] $curl_version over mbedTLS $mbedtls_version already built in $prefix"; exit 0; }

sdk="$root/.deps/native/ps5-payload-sdk"
[[ -x $sdk/bin/prospero-clang ]] || { echo "error: bootstrap this project's SDK first" >&2; exit 2; }
export PS5_PAYLOAD_SDK="$sdk" PS5_CLANG=${PS5_CLANG:-/usr/bin/clang}

mkdir -p "$root/.deps/downloads"
fetch() {
    local url=$1 file=$2 digest=$3
    [[ -f $file ]] || curl --fail --location --retry 3 "$url" -o "$file"
    printf '%s  %s\n' "$digest" "$file" | sha256sum --check --status || {
        echo "error: digest mismatch for $file" >&2; exit 1; }
}
mbedtls_archive="$root/.deps/downloads/mbedtls-$mbedtls_version.tar.bz2"
curl_archive="$root/.deps/downloads/curl-$curl_version.tar.bz2"
fetch "https://github.com/Mbed-TLS/mbedtls/releases/download/mbedtls-$mbedtls_version/mbedtls-$mbedtls_version.tar.bz2" \
    "$mbedtls_archive" "$mbedtls_digest"
fetch "https://github.com/curl/curl/releases/download/curl-${curl_version//./_}/curl-$curl_version.tar.bz2" \
    "$curl_archive" "$curl_digest"

build="$root/build/curl-ps5"
rm -rf -- "$build" "$prefix"
mkdir -p "$build/mbedtls" "$build/curl" "$prefix/lib" "$prefix/include" "$prefix/share/licenses/curl" \
    "$prefix/share/licenses/mbedtls"
tar -xjf "$mbedtls_archive" -C "$build/mbedtls" --strip-components=1
tar -xjf "$curl_archive" -C "$build/curl" --strip-components=1
cc="$sdk/bin/prospero-clang"
command -v ccache >/dev/null && cc="ccache $cc"
flags="-O2 -march=znver2 -fPIC -ffunction-sections -fdata-sections"

echo "==> [curl] mbedTLS $mbedtls_version"
# Thread-safe: curl shares one random generator (CTR-DRBG, prediction resistance on) among
# all its connections and counts on mbedTLS's own locks for it. Without them, the WebUI
# daemon's 32 scraper workers starting HTTPS handshakes together crashed it in
# mbedtls_entropy_func (2026-10-07, klog/webui-down.txt).
(cd "$build/mbedtls" && python3 scripts/config.py set MBEDTLS_THREADING_C &&
    python3 scripts/config.py set MBEDTLS_THREADING_PTHREAD)
make -C "$build/mbedtls/library" -j"${JOBS:-16}" CC="$cc" AR="$sdk/bin/prospero-ar" \
    CFLAGS="$flags" libmbedtls.a libmbedx509.a libmbedcrypto.a > "$build/mbedtls.log" 2>&1 ||
    { grep -E "error" "$build/mbedtls.log" | head -20 >&2; exit 1; }
cp "$build/mbedtls/library"/libmbed{tls,x509,crypto}.a "$prefix/lib/"
cp -r "$build/mbedtls/include/mbedtls" "$build/mbedtls/include/psa" "$prefix/include/"
cp "$build/mbedtls/LICENSE" "$prefix/share/licenses/mbedtls/LICENSE"

echo "==> [curl] curl $curl_version (HTTP and HTTPS over mbedTLS)"
(cd "$build/curl" && ./configure --host=x86_64-unknown-freebsd14 --prefix="$build/install" \
    CC="$cc" AR="$sdk/bin/prospero-ar" RANLIB="$sdk/bin/prospero-ranlib" CFLAGS="$flags" \
    CPPFLAGS="-I$prefix/include" LDFLAGS="-L$prefix/lib" \
    --enable-static --disable-shared --with-mbedtls="$prefix" --without-ssl-defaults \
    --without-zlib --without-brotli --without-zstd --without-libpsl --without-libidn2 \
    --without-nghttp2 --without-nghttp3 --without-ngtcp2 --without-libssh2 --without-librtmp \
    --without-ca-bundle --without-ca-path --without-ca-fallback \
    --disable-ldap --disable-ldaps --disable-rtsp --disable-dict --disable-telnet --disable-tftp \
    --disable-pop3 --disable-imap --disable-smtp --disable-gopher --disable-mqtt --disable-file \
    --disable-ftp --disable-smb --disable-ipfs --disable-manual --disable-docs --disable-ntlm \
    --disable-unix-sockets --disable-threaded-resolver --disable-dependency-tracking \
    ac_cv_func_pipe2=no \
    > "$build/curl-configure.log" 2>&1) ||
    { tail -30 "$build/curl-configure.log" >&2; exit 1; }
make -C "$build/curl/lib" -j"${JOBS:-16}" > "$build/curl-make.log" 2>&1 ||
    { grep -E "error" "$build/curl-make.log" | head -20 >&2; exit 1; }
cp "$build/curl/lib/.libs/libcurl.a" "$prefix/lib/"
cp -r "$build/curl/include/curl" "$prefix/include/"
cp "$build/curl/COPYING" "$prefix/share/licenses/curl/COPYING"
printf '%s\n' "$stamp" > "$prefix/.stamp"
printf '==> [curl] %s over mbedTLS %s: libcurl %s in %s\n' "$curl_version" "$mbedtls_version" \
    "$(du -h "$prefix/lib/libcurl.a" | cut -f1)" "$prefix"
