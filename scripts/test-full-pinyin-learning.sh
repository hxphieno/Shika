#!/bin/bash
# Real Rime learning, cross-process typo recovery and bounded metadata checks.
set -euo pipefail
cd "$(dirname "$0")/.."
output="${1:?usage: test-full-pinyin-learning.sh output-directory}"
mkdir -p "$output"
work=$(mktemp -d "${TMPDIR:-/tmp}/shika-full-learning.XXXXXX")
mkdir -p "$work/sources"
cp ShikaKeyBoard/Core/*.swift ShikaKeyBoard/Engine/*.swift ShikaKeyBoard/Engine/SKRimeSession.{h,m} ShikaKeyBoard/Schemes/*/*Scheme.swift Tests/BackendRound2LearningChecks.swift "$work/sources/"
cp -R ShikaKeyBoard/Resources/RimeData.bundle "$work/resources.bundle"
cp Tests/BackendRound2LearnedPhrases.json "$work/phrases.json"
shasum -a 256 "$work/sources/"* "$work/phrases.json" > "$output/source-hashes.txt"
slice="$PWD/Vendor/Rime/librime-static.xcframework/macos-arm64_x86_64"
xcrun clang -fobjc-arc -c "$work/sources/SKRimeSession.m" -I"$slice/Headers" -o "$work/bridge.o"
xcrun swiftc -O -whole-module-optimization -module-cache-path "$work/module-cache" -parse-as-library "$work"/sources/*.swift "$work/bridge.o" "$slice/librime.a" -import-objc-header "$work/sources/SKRimeSession.h" -framework Foundation -lc++ -liconv -o "$work/runner"
failed=0
for mode in learn probe disabled index; do
    user="$work/user-$mode"
    if [[ "$mode" == learn || "$mode" == probe ]]; then user="$work/user-learning"; fi
    "$work/runner" "$work/resources.bundle" "$user" "$work/phrases.json" "$output/$mode.json" "$mode" || failed=1
done
printf 'Frozen full-pinyin learning runner: %s/runner\n' "$work"
exit "$failed"
