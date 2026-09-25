#!/bin/bash
# Compile production Swift + real Rime. No expected strings enter the engine.
set -euo pipefail
cd "$(dirname "$0")/.."
work=${SHIKA_CORRECTION_TEST_DIR:-$(mktemp -d -t shika-correction-checks)}
mkdir -p "$work"
slice=Vendor/Rime/librime-static.xcframework/macos-arm64_x86_64
xcrun clang -fobjc-arc -c ShikaKeyBoard/Engine/SKRimeSession.m -I"$slice/Headers" -o "$work/bridge.o"
xcrun swiftc -O -module-cache-path "$work/module-cache" -parse-as-library \
 Tests/AutocorrectionChecks.swift ShikaKeyBoard/Core/*.swift ShikaKeyBoard/Engine/*.swift ShikaKeyBoard/Schemes/*/*Scheme.swift \
 "$work/bridge.o" "$slice/librime.a" -import-objc-header ShikaKeyBoard/Engine/SKRimeSession.h \
 -framework Foundation -lc++ -liconv -o "$work/runner"
resources="$PWD/ShikaKeyBoard/Resources/RimeData.bundle"
cases=${1:-Tests/AutocorrectionCases.json}
"$work/runner" "$resources" "$work/baseline-user" "$cases" "$work/baseline.json" baseline
"$work/runner" "$resources" "$work/correction-user" "$cases" "$work/correction.json"
printf 'Evidence: %s\n' "$work"
