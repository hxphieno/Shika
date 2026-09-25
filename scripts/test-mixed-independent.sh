#!/bin/bash
# Independent production-engine consumption/state tests and two-process learning.
set -euo pipefail
repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
work="$(mktemp -d "${TMPDIR:-/tmp}/shika-mixed-independent.XXXXXX")"
output="${1:-$work/results}"
mkdir -p "$output" "$work/sources"
slice="$repo_dir/Vendor/Rime/librime-static.xcframework/macos-arm64_x86_64"
cp "$repo_dir"/ShikaKeyBoard/Core/*.swift "$work/sources/"
cp "$repo_dir"/ShikaKeyBoard/Engine/*.swift "$work/sources/"
cp "$repo_dir"/ShikaKeyBoard/Engine/SKRimeSession.{h,m} "$work/sources/"
cp "$repo_dir"/ShikaKeyBoard/Schemes/*/*Scheme.swift "$work/sources/"
cp "$repo_dir/Tests/MixedIndependentChecks.swift" "$work/sources/"
cp -R "$repo_dir/ShikaKeyBoard/Resources/RimeData.bundle" "$work/resources.bundle"
shasum -a 256 "$work/sources/"* > "$output/source-hashes.txt"
xcrun clang -fobjc-arc -c "$work/sources/SKRimeSession.m" -I"$work/sources" -I"$slice/Headers" -o "$work/bridge.o"
xcrun swiftc -O -module-cache-path "$work/module-cache" -parse-as-library "$work"/sources/*.swift "$work/bridge.o" "$slice/librime.a" -import-objc-header "$work/sources/SKRimeSession.h" -framework Foundation -lc++ -liconv -o "$work/checks"
failed=0
"$work/checks" "$work/resources.bundle" "$work/behavior-user" "$output/behavior.json" behavior || failed=1
"$work/checks" "$work/resources.bundle" "$work/learning-user" "$output/learn.json" learn || failed=1
"$work/checks" "$work/resources.bundle" "$work/learning-user" "$output/probe.json" probe || failed=1
printf 'Independent mixed test artifacts: %s\n' "$work"
exit "$failed"
