#!/usr/bin/env bash
# Build ICU's common library and a filtered data library for the PS5, for
# EmulationStation's case conversion and title case (es-core's StringUtil:
# icu::UnicodeString::toLower/toUpper and a word BreakIterator; docs/FRONTENDS.md).
#
# Both archives are the GitHub release's, pinned by the digests GitHub publishes
# for them (release-78.3, 2026-03-17). ICU cross-builds from a host build of the
# same release, which supplies the data tools. The data is rebuilt from source
# with a filter (build/icu-data-filter.json, written below): English and root
# only, and none of the collation, transliteration, conversion tables, time zones,
# names of languages, regions, currencies or units, nor the break dictionaries
# (CJK and South-East Asian words), which ES-DE does not ask for. Case mapping
# is compiled into libicuuc and needs no data. Static, without the i18n, io and
# tools libraries.
#
# Output: .deps/native/icu-ps5 (lib/libicuuc.a, lib/libicudata.a, include/unicode),
# with the version and this script's digest in .deps/native/icu-ps5/.stamp.
set -euo pipefail

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
cd "$root"
version=78.3
sources_digest=3a2e7a47604ba702f345878308e6fefeca612ee895cf4a5f222e7955fabfe0c0
data_digest=9d8b3899096aeb83e4e21ef8a40fec9e03b28db18c48452efac882ce25a91e27
prefix="$root/.deps/native/icu-ps5"
stamp="$version $(sha256sum "$0" | cut -c1-64)"
[[ -f $prefix/.stamp && $(<"$prefix/.stamp") == "$stamp" ]] && {
    echo "==> [icu] $version already built in $prefix"; exit 0; }

sdk="$root/.deps/native/ps5-payload-sdk"
[[ -x $sdk/bin/prospero-clang ]] || { echo "error: bootstrap this project's SDK first" >&2; exit 2; }
export PS5_PAYLOAD_SDK="$sdk" PS5_CLANG=${PS5_CLANG:-/usr/bin/clang}

mkdir -p "$root/.deps/downloads"
release="https://github.com/unicode-org/icu/releases/download/release-$version"
for pair in "sources.tgz:$sources_digest" "data.zip:$data_digest"; do
    name=${pair%%:*} digest=${pair#*:}
    archive="$root/.deps/downloads/icu4c-$version-$name"
    [[ -f $archive ]] || curl --fail --location --retry 3 "$release/icu4c-$version-$name" -o "$archive"
    printf '%s  %s\n' "$digest" "$archive" | sha256sum --check --status || {
        echo "error: ICU $name digest mismatch" >&2; exit 1; }
done

build="$root/build/icu-ps5"
rm -rf -- "$build"
mkdir -p "$build/src" "$build/host" "$build/target"
tar -xzf "$root/.deps/downloads/icu4c-$version-sources.tgz" -C "$build/src" --strip-components=1
# The data from source, so the filter applies (the sources archive carries it prebuilt).
rm -rf -- "$build/src/source/data"
(cd "$build/src/source" && unzip -q "$root/.deps/downloads/icu4c-$version-data.zip")
[[ -d $build/src/source/data/brkitr ]] || { echo "error: ICU data sources missing after unzip" >&2; exit 1; }

cat > "$build/icu-data-filter.json" <<'JSON'
{
  "localeFilter": {
    "filterType": "language",
    "includelist": ["en", "root"]
  },
  "featureFilters": {
    "brkitr_dictionaries": "exclude",
    "coll_tree": "exclude",
    "coll_ucadata": "exclude",
    "confusables": "exclude",
    "conversion_mappings": "exclude",
    "curr_tree": "exclude",
    "lang_tree": "exclude",
    "rbnf_tree": "exclude",
    "region_tree": "exclude",
    "stringprep": "exclude",
    "translit": "exclude",
    "unit_tree": "exclude",
    "zone_tree": "exclude",
    "zoneinfo64": "exclude"
  }
}
JSON

echo "==> [icu] host build $version (data tools)"
(cd "$build/host" && ICU_DATA_FILTER_FILE="$build/icu-data-filter.json" "$build/src/source/configure" \
    --disable-tests --disable-samples --disable-extras --disable-icuio --disable-layoutex \
    > configure.log 2>&1 && make -j"${JOBS:-16}" > make.log 2>&1) ||
    { tail -30 "$build/host/configure.log" "$build/host/make.log" >&2; exit 1; }

cc="$sdk/bin/prospero-clang" cxx="$sdk/bin/prospero-clang++"
command -v ccache >/dev/null && { cc="ccache $cc"; cxx="ccache $cxx"; }
# U_STATIC_IMPLEMENTATION: this compiler takes __declspec(dllexport), which ICU's
# U_EXPORT otherwise becomes, and refuses it on members of an exported class. A
# static library exports nothing; users of the headers define it too.
flags="-O2 -march=znver2 -fPIC -ffunction-sections -fdata-sections -DU_STATIC_IMPLEMENTATION"
echo "==> [icu] PS5 build $version (common and data, static)"
(cd "$build/target" && ICU_DATA_FILTER_FILE="$build/icu-data-filter.json" "$build/src/source/configure" \
    --host=x86_64-unknown-freebsd14 --with-cross-build="$build/host" --prefix="$prefix" \
    CC="$cc" CXX="$cxx" AR="$sdk/bin/prospero-ar" RANLIB="$sdk/bin/prospero-ranlib" \
    CFLAGS="$flags" CXXFLAGS="$flags -std=c++17" \
    --enable-static --disable-shared --disable-tools --disable-tests --disable-samples --disable-extras \
    --disable-icuio --disable-layoutex --with-data-packaging=static > configure.log 2>&1) ||
    { tail -40 "$build/target/configure.log" >&2; exit 1; }
(cd "$build/target" && make -j"${JOBS:-16}" > make.log 2>&1) ||
    { grep -E "error|Error" "$build/target/make.log" | head -20 >&2; tail -20 "$build/target/make.log" >&2; exit 1; }

rm -rf -- "$prefix"
mkdir -p "$prefix/lib" "$prefix/include" "$prefix/share/licenses/icu"
cp "$build/target/lib/libicuuc.a" "$build/target/lib/libicudata.a" "$prefix/lib/"
cp -r "$build/src/source/common/unicode" "$prefix/include/unicode"
cp "$build/src/LICENSE" "$prefix/share/licenses/icu/LICENSE"
cp "$build/icu-data-filter.json" "$prefix/share/licenses/icu/data-filter.json"
printf '%s\n' "$stamp" > "$prefix/.stamp"
printf '==> [icu] %s: libicuuc %s, libicudata %s in %s\n' "$version" \
    "$(du -h "$prefix/lib/libicuuc.a" | cut -f1)" "$(du -h "$prefix/lib/libicudata.a" | cut -f1)" "$prefix"
