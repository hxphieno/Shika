#!/bin/bash
set -euo pipefail
repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
output_dir="${1:?usage: test-lexicon-quality-japanese.sh output_dir}"
work="$(mktemp -d "${TMPDIR:-/tmp}/shika-japanese-quality.XXXXXX")"
mkdir -p "$output_dir" "$work/sources"
cp -R "$repo_dir/ShikaKeyBoard/Resources/RimeData.bundle" "$work/RimeData.bundle"
cp "$repo_dir/ShikaKeyBoard/Engine/SKRimeSession.m" "$repo_dir/ShikaKeyBoard/Engine/SKRimeSession.h" "$work/sources/"
cp "$repo_dir"/ShikaKeyBoard/Core/*.swift "$repo_dir"/ShikaKeyBoard/Engine/*.swift "$repo_dir"/ShikaKeyBoard/Schemes/*/*Scheme.swift "$work/sources/"
cp "$repo_dir/Tests/LexiconQualityJapaneseChecks.swift" "$work/sources/"
cp "$repo_dir/Tests/LexiconQualityJapaneseCases.json" "$work/cases.json"
shasum -a 256 "$work/sources/"* "$work/cases.json" > "$output_dir/source-hashes.txt"
find "$work/RimeData.bundle" -type f -exec shasum -a 256 {} \; > "$output_dir/resource-hashes.txt"
slice="$repo_dir/Vendor/Rime/librime-static.xcframework/macos-arm64_x86_64"
xcrun clang -fobjc-arc -c "$work/sources/SKRimeSession.m" -I"$work/sources" -I"$slice/Headers" -o "$work/bridge.o"
xcrun swiftc -O -module-cache-path "$work/module-cache" -parse-as-library "$work"/sources/*.swift "$work/bridge.o" "$slice/librime.a" -import-objc-header "$work/sources/SKRimeSession.h" -framework Foundation -lc++ -liconv -o "$work/runner"
for mode in ranking functional commit learning-write learning-read; do
  user_dir="$work/user-$mode"
  if [[ "$mode" == learning-* ]]; then user_dir="$work/user-learning"; fi
  "$work/runner" "$work/RimeData.bundle" "$user_dir" "$work/cases.json" "$mode" "$output_dir/$mode.json"
done
python3 - "$output_dir" <<'PY'
import pathlib,json,sys,math
p=pathlib.Path(sys.argv[1]);r=json.loads((p/'ranking.json').read_text())['results'];ds=sorted(d for x in r for d in x['keyDurationsMS']);ranks=[x['rank'] for x in r]
s={'cases':len(r),**{f'top{k}':sum(0<n<=k for n in ranks)/len(r) for k in [1,5,10]},'MRR10':sum(1/n if n else 0 for n in ranks)/len(r),'keyP50MS':ds[math.ceil(len(ds)*.5)-1],'keyP95MS':ds[math.ceil(len(ds)*.95)-1],'peakRSSMiB':max(x['peakRSSBytes'] for x in r)/1024**2,'failedChecks':sum(json.loads((p/f'{m}.json').read_text())['failed'] for m in ['functional','commit','learning-write','learning-read'])}
s['functionalMixedPeakRSSMiB']=json.loads((p/'functional.json').read_text())['processPeakRSSBytes']/1024**2
(p/'summary.json').write_text(json.dumps(s,ensure_ascii=False,indent=2)+'\n');print(json.dumps(s,ensure_ascii=False,indent=2))
PY
printf 'Japanese frozen runner: %s\n' "$work"
