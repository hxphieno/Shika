#!/bin/bash
# Native real-engine benchmark. Baseline can use a pre-edit frozen snapshot.
set -euo pipefail
repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
output_dir="${1:?usage: test-lexicon-quality.sh output_dir [frozen_dir]}"
work="$(mktemp -d "${TMPDIR:-/tmp}/shika-lexicon-quality.XXXXXX")"
mkdir -p "$output_dir" "$work/sources"
if [[ -n "${2:-}" ]]; then
  cp -R "$2/resources/RimeData.bundle" "$work/RimeData.bundle"
  cp "$2/sources/"* "$work/sources/"
  cp "$2/revision.txt" "$output_dir/revision.txt"
else
  cp -R "$repo_dir/ShikaKeyBoard/Resources/RimeData.bundle" "$work/RimeData.bundle"
  cp "$repo_dir/ShikaKeyBoard/Engine/SKRimeSession.m" "$repo_dir/ShikaKeyBoard/Engine/SKRimeSession.h" "$work/sources/"
  cp "$repo_dir"/ShikaKeyBoard/Core/*.swift "$repo_dir"/ShikaKeyBoard/Engine/*.swift "$repo_dir"/ShikaKeyBoard/Schemes/*/*Scheme.swift "$work/sources/"
  git -C "$repo_dir" rev-parse HEAD > "$output_dir/revision.txt"
fi
cp "$repo_dir/Tests/LexiconQualityChecks.swift" "$work/sources/"
cp "$repo_dir/Tests/LexiconQualityCases.json" "$work/cases.json"
shasum -a 256 "$work/sources/"* "$work/cases.json" > "$output_dir/source-hashes.txt"
find "$work/RimeData.bundle" -type f -exec shasum -a 256 {} \; > "$output_dir/resource-hashes.txt"
slice="$repo_dir/Vendor/Rime/librime-static.xcframework/macos-arm64_x86_64"
xcrun clang -fobjc-arc -c "$work/sources/SKRimeSession.m" -I"$work/sources" -I"$slice/Headers" -o "$work/bridge.o"
swift_flags=(-D SHIKA_LEGACY_ENGINE)
schemas=(shika_pinyin shika_flypy)
if [[ -f "$work/sources/SKConversionEngine.swift" ]]; then
  swift_flags=(-D SHIKA_HAS_CONVERSION_ENGINE)
  schemas+=(mixed)
fi
xcrun swiftc "${swift_flags[@]}" -O -module-cache-path "$work/module-cache" -parse-as-library "$work"/sources/*.swift "$work/bridge.o" "$slice/librime.a" -import-objc-header "$work/sources/SKRimeSession.h" -framework Foundation -lc++ -liconv -o "$work/runner"
for schema in "${schemas[@]}"; do
  "$work/runner" "$work/RimeData.bundle" "$work/user-$schema-ranking" "$work/cases.json" "$schema" ranking "$output_dir/$schema-ranking.json"
  for case_id in $(python3 -c 'import json,sys;print(" ".join(x["id"] for x in json.load(open(sys.argv[1]))["cases"] if x["kind"]=="sentence"))' "$work/cases.json"); do
    "$work/runner" "$work/RimeData.bundle" "$work/user-$schema-$case_id" "$work/cases.json" "$schema" "coverage:$case_id" "$work/$schema-$case_id.json"
  done
  python3 - "$work" "$schema" "$output_dir" <<'PYMERGE'
import json,pathlib,sys
work,schema,out=pathlib.Path(sys.argv[1]),sys.argv[2],pathlib.Path(sys.argv[3]);rows=[]
for file in sorted(work.glob(f'{schema}-sentence-*.json')):rows.extend(json.loads(file.read_text())['results'])
(out/f'{schema}-coverage.json').write_text(json.dumps({'schema':schema,'mode':'coverage','freshProcessAndUserdirPerCase':True,'results':rows},ensure_ascii=False,indent=2)+'\n')
PYMERGE
done
python3 "$repo_dir/scripts/test-lexicon-quality-summary.py" "$output_dir"
printf 'Frozen runtime artifacts: %s\n' "$work"
