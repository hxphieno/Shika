#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
work=$(mktemp -d -t shika-correction-interactions)
slice=Vendor/Rime/librime-static.xcframework/macos-arm64_x86_64
xcrun clang -fobjc-arc -c ShikaKeyBoard/Engine/SKRimeSession.m -I"$slice/Headers" -o "$work/bridge.o"
xcrun swiftc -O -module-cache-path "$work/module-cache" -parse-as-library \
 Tests/AutocorrectionInteractionChecks.swift ShikaKeyBoard/Engine/SKInputEngine.swift ShikaKeyBoard/Engine/SKSpellingCorrector.swift ShikaKeyBoard/Core/SKInputSession.swift \
 "$work/bridge.o" "$slice/librime.a" -import-objc-header ShikaKeyBoard/Engine/SKRimeSession.h \
 -framework Foundation -lc++ -liconv -o "$work/runner"
"$work/runner" "$PWD/ShikaKeyBoard/Resources/RimeData.bundle" "$work/user"
printf 'Interaction evidence: %s\n' "$work"
