#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
python3 scripts/prepare-lexicons.py
python3 scripts/prepare-mixed-lexicon.py
python3 scripts/generate-rime-schemas.py
work=$(mktemp -d -t shika-rime-data)
trap 'rm -rf "$work"' EXIT
slice=Vendor/Rime/librime-static.xcframework/macos-arm64_x86_64
xcrun clang++ -std=c++17 -I "$slice/Headers" scripts/rime-deploy.cc "$slice/librime.a" -framework Foundation -liconv -o "$work/deploy"
mkdir "$work/user"
"$work/deploy" "$PWD/Vendor/RimeData" "$work/user"
mkdir -p ShikaKeyBoard/Resources/RimeData.bundle/build
cp "$work/user/build/"* ShikaKeyBoard/Resources/RimeData.bundle/build/
# The old dictionary remains an input fallback, but its compiled table is unused.
rm -f ShikaKeyBoard/Resources/RimeData.bundle/build/pinyin_simp.{table,reverse}.bin
cp Vendor/RimeData/default.yaml ShikaKeyBoard/Resources/RimeData.bundle/

python3 scripts/generate-correction-index.py
