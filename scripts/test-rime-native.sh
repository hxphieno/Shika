#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
work=$(mktemp -d -t shika-rime-test)
trap 'rm -rf "$work"' EXIT
slice=Vendor/Rime/librime-static.xcframework/macos-arm64_x86_64
xcrun clang -fobjc-arc -I ShikaKeyBoard/Engine -I "$slice/Headers" scripts/rime-smoke.m ShikaKeyBoard/Engine/SKRimeSession.m "$slice/librime.a" -framework Foundation -lc++ -liconv -o "$work/test"
"$work/test" "$PWD/ShikaKeyBoard/Resources/RimeData.bundle" "$work/user"
