#!/bin/bash
set -euo pipefail
repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
output_dir="${1:?usage: test-mixed-engine.sh output_dir [baseline|16|32|64]}"
mode="${2:-16}"
work="$(mktemp -d "${TMPDIR:-/tmp}/shika-mixed.XXXXXX")"
mkdir -p "$output_dir"
slice="$repo_dir/Vendor/Rime/librime-static.xcframework/macos-arm64_x86_64"
xcrun clang -fobjc-arc -c "$repo_dir/ShikaKeyBoard/Engine/SKRimeSession.m" -I"$repo_dir/ShikaKeyBoard/Engine" -I"$slice/Headers" -o "$work/bridge.o"
xcrun swiftc -O -module-cache-path "$work/module-cache" -parse-as-library "$repo_dir"/ShikaKeyBoard/Core/*.swift "$repo_dir"/ShikaKeyBoard/Engine/*.swift "$repo_dir"/ShikaKeyBoard/Schemes/*/*Scheme.swift "$repo_dir/Tests/Support/SKLegacyMixedEngine.swift" "$repo_dir/Tests/MixedEngineChecks.swift" "$work/bridge.o" "$slice/librime.a" -import-objc-header "$repo_dir/ShikaKeyBoard/Engine/SKRimeSession.h" -framework Foundation -lc++ -liconv -o "$work/runner"
shasum -a 256 "$repo_dir"/ShikaKeyBoard/Engine/*.swift "$repo_dir/Tests/MixedEngineCases.json" > "$output_dir/source-hashes-$mode.txt"
"$work/runner" "$repo_dir/ShikaKeyBoard/Resources/RimeData.bundle" "$work/user" "$repo_dir/Tests/MixedEngineCases.json" "$output_dir/$mode.json" "$mode"
printf 'Mixed runner: %s\n' "$work"
