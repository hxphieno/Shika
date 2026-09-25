#!/bin/bash
# Focused independent checks; choose only the affected engine path.
set -euo pipefail
cd "$(dirname "$0")/.."
output="${1:?usage: test-engine-caches.sh output segmentation|japanese|unicode|mixed}"
mode="${2:?choose an engine check}"
case "$mode" in
  segmentation) test_name=ContinuousSegmentationCacheChecks ;;
  japanese) test_name=ContinuousJapaneseCacheChecks ;;
  unicode) test_name=ContinuousJapaneseUnicodeCacheChecks ;;
  mixed) test_name=ContinuousMixedLearningChecks ;;
  *) printf 'Unknown check: %s\n' "$mode" >&2; exit 2 ;;
esac
if [[ -e "$output" ]]; then
  printf 'Output path already exists; choose a fresh directory to isolate learning: %s\n' "$output" >&2
  exit 2
fi
mkdir -p "$output/sources"
cp ShikaKeyBoard/Core/*.swift ShikaKeyBoard/Engine/*.swift \
  ShikaKeyBoard/Engine/SKRimeSession.{h,m} ShikaKeyBoard/Schemes/*/*Scheme.swift \
  "Tests/$test_name.swift" "$output/sources/"
cp -R ShikaKeyBoard/Resources/RimeData.bundle "$output/resources.bundle"
shasum -a 256 "$output/sources/"* > "$output/source-hashes.txt"
slice="$PWD/Vendor/Rime/librime-static.xcframework/macos-arm64_x86_64"
xcrun clang -fobjc-arc -c "$output/sources/SKRimeSession.m" -I"$slice/Headers" -o "$output/bridge.o"
xcrun swiftc -O -whole-module-optimization -module-cache-path "$output/module-cache" -parse-as-library \
  "$output"/sources/*.swift "$output/bridge.o" "$slice/librime.a" \
  -import-objc-header "$output/sources/SKRimeSession.h" -framework Foundation -lc++ -liconv -o "$output/runner"
if [[ "$mode" == japanese || "$mode" == mixed ]]; then
  "$output/runner" "$output/resources.bundle" "$output/user" "$output/result.json"
  "$output/runner" "$output/resources.bundle" "$output/user" "$output/reload.json" reload "$output/result.json"
else
  "$output/runner" "$output/resources.bundle" "$output/result.json"
fi
