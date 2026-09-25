#!/bin/bash
# Compile a frozen source snapshot once; reuse its runner for separate fresh-user runs.
set -euo pipefail
cd "$(dirname "$0")/.."
output="${1:?usage: test-shuangpin-optimization.sh output [frozen-sources]}"
mkdir -p "$output/sources"
if [[ -n "${2:-}" ]]; then
  cp "$2"/* "$output/sources/"
else
  cp ShikaKeyBoard/Core/*.swift ShikaKeyBoard/Engine/*.swift ShikaKeyBoard/Engine/SKRimeSession.{h,m} ShikaKeyBoard/Schemes/*/*Scheme.swift "$output/sources/"
fi
cp Tests/ShuangpinOptimizationChecks.swift "$output/sources/"
slice="$PWD/Vendor/Rime/librime-static.xcframework/macos-arm64_x86_64"
shasum -a 256 "$output/sources/"* > "$output/source-hashes.txt"
xcrun clang -fobjc-arc -c "$output/sources/SKRimeSession.m" -I"$slice/Headers" -o "$output/bridge.o"
xcrun swiftc -O -whole-module-optimization -module-cache-path "$output/module-cache" -parse-as-library "$output"/sources/*.swift "$output/bridge.o" "$slice/librime.a" -import-objc-header "$output/sources/SKRimeSession.h" -framework Foundation -lc++ -liconv -o "$output/runner"
printf 'Frozen runner: %s/runner\n' "$output"
