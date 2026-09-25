#!/bin/bash
# Independent frozen heldout; does not tune the engine or change app resources.
set -euo pipefail
repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
test_dir="$(mktemp -d "${TMPDIR:-/tmp}/shika-correction-independent.XXXXXX")"
slice="$repo_dir/Vendor/Rime/librime-static.xcframework/macos-arm64_x86_64"
resources="$test_dir/RimeData.bundle"
cp -R "$repo_dir/ShikaKeyBoard/Resources/RimeData.bundle" "$resources"
cases="$repo_dir/Tests/AutocorrectionIndependentHeldout.json"
output_dir="${1:-$test_dir/results}"
mkdir -p "$output_dir" "$test_dir/sources"
# Freeze sources before compilation; other agents may continue unrelated work.
cp "$repo_dir/ShikaKeyBoard/Engine/SKRimeSession.m" "$test_dir/sources/"
cp "$repo_dir/ShikaKeyBoard/Engine/SKRimeSession.h" "$test_dir/sources/"
cp "$repo_dir"/ShikaKeyBoard/Core/*.swift "$test_dir/sources/"
cp "$repo_dir"/ShikaKeyBoard/Engine/*.swift "$test_dir/sources/"
cp "$repo_dir"/ShikaKeyBoard/Schemes/*/*Scheme.swift "$test_dir/sources/"
cp "$repo_dir/Tests/AutocorrectionIndependentChecks.swift" "$test_dir/sources/"
shasum -a 256 "$test_dir/sources/"* > "$output_dir/source-hashes.txt"
xcrun clang -fobjc-arc -c "$test_dir/sources/SKRimeSession.m" \
    -I"$test_dir/sources" -I"$slice/Headers" -o "$test_dir/bridge.o"
xcrun swiftc -O -module-cache-path "$test_dir/module-cache" -parse-as-library \
    "$test_dir"/sources/*.swift \
    "$test_dir/bridge.o" "$slice/librime.a" \
    -import-objc-header "$test_dir/sources/SKRimeSession.h" \
    -framework Foundation -lc++ -liconv -o "$test_dir/independent-checks"
"$test_dir/independent-checks" "$resources" "$test_dir/baseline-user" "$cases" disabled ranking "$output_dir/baseline-ranking.json"
"$test_dir/independent-checks" "$resources" "$test_dir/corrected-user" "$cases" enabled ranking "$output_dir/corrected-ranking.json"
"$test_dir/independent-checks" "$resources" "$test_dir/commit-user" "$cases" enabled commit "$output_dir/corrected-commit.json"
printf 'Independent test artifacts: %s\n' "$test_dir"
