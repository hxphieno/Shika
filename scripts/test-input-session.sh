#!/bin/bash
# Real Rime + production Swift policy checks; no mock candidate engine.
set -euo pipefail
repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
test_dir="$(mktemp -d "${TMPDIR:-/tmp}/shika-session-checks.XXXXXX")"
slice="$repo_dir/Vendor/Rime/librime-static.xcframework/macos-arm64_x86_64"
resources="$repo_dir/ShikaKeyBoard/Resources/RimeData.bundle"

# The session and its contracts must compile without UIKit, Objective-C or Rime.
xcrun swiftc -module-cache-path "$test_dir/module-cache" -parse-as-library \
    -emit-module -module-name ShikaInputCore \
    "$repo_dir/ShikaKeyBoard/Core/SKInputEngine.swift" \
    "$repo_dir/ShikaKeyBoard/Core/SKInputConfiguration.swift" \
    "$repo_dir/ShikaKeyBoard/Core/SKInputSession.swift" \
    -emit-module-path "$test_dir/ShikaInputCore.swiftmodule"

xcrun clang -fobjc-arc -c "$repo_dir/ShikaKeyBoard/Engine/SKRimeSession.m" \
    -I"$repo_dir/ShikaKeyBoard/Engine" -I"$slice/Headers" -o "$test_dir/bridge.o"
xcrun swiftc -module-cache-path "$test_dir/module-cache" -parse-as-library \
    "$repo_dir/Tests/RimeSessionChecks.swift" \
    "$repo_dir"/ShikaKeyBoard/Core/*.swift \
    "$repo_dir"/ShikaKeyBoard/Engine/*.swift \
    "$repo_dir"/ShikaKeyBoard/Schemes/*/*Scheme.swift \
    "$test_dir/bridge.o" "$slice/librime.a" \
    -import-objc-header "$repo_dir/ShikaKeyBoard/Engine/SKRimeSession.h" \
    -framework Foundation -lc++ -liconv -o "$test_dir/session-checks"
"$test_dir/session-checks" "$resources" "$test_dir/session-user"

xcrun clang -fobjc-arc "$repo_dir/Tests/RimeLearningChecks.m" \
    "$test_dir/bridge.o" -I"$repo_dir/ShikaKeyBoard/Engine" "$slice/librime.a" \
    -framework Foundation -lc++ -liconv -o "$test_dir/learning-checks"
"$test_dir/learning-checks" "$resources" "$test_dir/learning-user" learn
"$test_dir/learning-checks" "$resources" "$test_dir/learning-user" probe
xcrun clang -fobjc-arc "$repo_dir/Tests/RimeRuntimeChecks.m" \
    "$test_dir/bridge.o" -I"$repo_dir/ShikaKeyBoard/Engine" "$slice/librime.a" \
    -framework Foundation -lc++ -liconv -o "$test_dir/runtime-checks"
"$test_dir/runtime-checks" "$resources" "$test_dir/runtime-user"
printf 'Test artifacts: %s\n' "$test_dir"
