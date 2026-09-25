#!/bin/bash
# Independent production-engine behavior, persistence and bounded-index checks.
set -euo pipefail
cd "$(dirname "$0")/.."
output="${1:?usage: test-shuangpin-behavior.sh output-directory}"
mkdir -p "$output"
work=$(mktemp -d "${TMPDIR:-/tmp}/shika-shuangpin-behavior.XXXXXX")
mkdir -p "$work/sources"
cp ShikaKeyBoard/Core/*.swift ShikaKeyBoard/Engine/*.swift ShikaKeyBoard/Engine/SKRimeSession.{h,m} ShikaKeyBoard/Schemes/*/*Scheme.swift Tests/ShuangpinOptimizationBehaviorChecks.swift "$work/sources/"
cp -R ShikaKeyBoard/Resources/RimeData.bundle "$work/resources.bundle"
shasum -a 256 "$work/sources/"* > "$output/source-hashes.txt"
slice="$PWD/Vendor/Rime/librime-static.xcframework/macos-arm64_x86_64"
xcrun clang -fobjc-arc -c "$work/sources/SKRimeSession.m" -I"$slice/Headers" -o "$work/bridge.o"
xcrun swiftc -O -whole-module-optimization -module-cache-path "$work/module-cache" -parse-as-library "$work"/sources/*.swift "$work/bridge.o" "$slice/librime.a" -import-objc-header "$work/sources/SKRimeSession.h" -framework Foundation -lc++ -liconv -o "$work/runner"
failed=0
for mode in behavior learn probe index; do
    user="$work/user-$mode"
    if [[ "$mode" == learn || "$mode" == probe ]]; then user="$work/user-learning"; fi
    "$work/runner" "$work/resources.bundle" "$user" "$output/$mode.json" "$mode" || failed=1
done
printf 'Frozen behavior runner: %s/runner\n' "$work"
exit "$failed"
