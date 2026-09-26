#!/bin/bash
# Focused sentence/prefix acceptance, with isolated learning and frozen sources.
set -euo pipefail
cd "$(dirname "$0")/.."
output="${1:?usage: test-sentence-limit.sh fresh-output-directory}"
if [[ -e "$output" ]]; then
  printf 'Choose a fresh output directory to isolate learning: %s\n' "$output" >&2
  exit 2
fi
mkdir -p "$output/sources"
output="$(cd "$output" && pwd)"
cp ShikaKeyBoard/Core/*.swift ShikaKeyBoard/Engine/*.swift ShikaKeyBoard/Platform/*.swift \
  ShikaKeyBoard/Engine/SKRimeSession.{h,m} ShikaKeyBoard/Schemes/*/*Scheme.swift \
  Tests/SentenceLimitIndependentChecks.swift "$output/sources/"
shasum -a 256 "$output/sources/"* > "$output/source-hashes.txt"
slice="$PWD/Vendor/Rime/librime-static.xcframework/macos-arm64_x86_64"
xcrun clang -fobjc-arc -c "$output/sources/SKRimeSession.m" -I"$slice/Headers" -o "$output/bridge.o"
xcrun swiftc -O -whole-module-optimization -module-cache-path "$output/module-cache" -parse-as-library \
  "$output"/sources/*.swift "$output/bridge.o" "$slice/librime.a" \
  -import-objc-header "$output/sources/SKRimeSession.h" -framework Foundation -framework CoreText -lc++ -liconv -o "$output/runner"
"$output/runner" "$PWD/ShikaKeyBoard/Resources/RimeData.bundle" "$output/results"
