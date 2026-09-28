#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/shika-special-checks.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
swiftc -module-cache-path "$WORK/module-cache" \
  "$ROOT/ShikaKeyBoard/Core/SKInputConfiguration.swift" \
  "$ROOT/ShikaKeyBoard/Core/SKInputEngine.swift" \
  "$ROOT/ShikaKeyBoard/Core/SKSpecialCandidates.swift" \
  "$ROOT/ShikaKeyBoard/Core/SKInputSession.swift" \
  "$ROOT/Tests/SpecialCandidatesChecks.swift" \
  -o "$WORK/checks"
"$WORK/checks" "$ROOT/ShikaKeyBoard/Resources/RimeData.bundle"

if [[ "${1:-}" == "--native" ]]; then
  SLICE="$ROOT/Vendor/Rime/librime-static.xcframework/macos-arm64_x86_64"
  xcrun clang -fobjc-arc -c "$ROOT/ShikaKeyBoard/Engine/SKRimeSession.m" \
    -I"$SLICE/Headers" -o "$WORK/bridge.o"
  swiftc -module-cache-path "$WORK/module-cache" \
    "$ROOT"/ShikaKeyBoard/Core/*.swift "$ROOT"/ShikaKeyBoard/Engine/*.swift \
    "$ROOT"/ShikaKeyBoard/Schemes/*/*Scheme.swift \
    "$ROOT/Tests/SpecialCandidatesRuntimeChecks.swift" "$WORK/bridge.o" "$SLICE/librime.a" \
    -import-objc-header "$ROOT/ShikaKeyBoard/Engine/SKRimeSession.h" \
    -framework Foundation -lc++ -liconv -o "$WORK/runtime-checks"
  "$WORK/runtime-checks" "$ROOT/ShikaKeyBoard/Resources/RimeData.bundle" "$WORK/user"
fi
