#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
version=1.17.0-pack.9.0.3
expected=abdd6240e740043933b9241bd6e1d1be1ce0c06d457c6c65931e06c0ccaec37e
work=$(mktemp -d -t shika-rime)
archive="$work/librime.zip"
trap 'rm -rf "$work"' EXIT
curl --fail --location --retry 3 "https://github.com/ghostflyby/librime-xcframework/releases/download/$version/librime-static.xcframework.zip" -o "$archive"
printf '%s  %s\n' "$expected" "$archive" | shasum -a 256 -c -
mkdir -p Vendor/Rime
unzip -oq "$archive" -d Vendor/Rime
printf 'Rime %s ready (device, simulator and macOS).\n' "$version"
