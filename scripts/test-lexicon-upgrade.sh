#!/bin/bash
# Learn with the pre-upgrade bundle, then reuse the same user database after upgrade.
set -euo pipefail
cd "$(dirname "$0")/.."
work=$(mktemp -d -t shika-lexicon-upgrade)
mkdir "$work/old"
revision=$(cat docs/evidence/lexicon-quality/baseline/revision.txt)
git archive "$revision" ShikaKeyBoard/Resources/RimeData.bundle | tar -x -C "$work/old"
slice=Vendor/Rime/librime-static.xcframework/macos-arm64_x86_64
xcrun clang -fobjc-arc Tests/RimeLearningChecks.m ShikaKeyBoard/Engine/SKRimeSession.m \
 -IShikaKeyBoard/Engine -I"$slice/Headers" "$slice/librime.a" -framework Foundation -lc++ -liconv -o "$work/learning"
"$work/learning" "$work/old/ShikaKeyBoard/Resources/RimeData.bundle" "$work/user" learn
"$work/learning" "$PWD/ShikaKeyBoard/Resources/RimeData.bundle" "$work/user" probe
printf 'Upgrade test artifacts: %s\n' "$work"
