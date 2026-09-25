#!/bin/bash
# Isolated parameter experiment: production working-tree sources are never edited.
set -euo pipefail
repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
output_dir="${1:?usage: test-lexicon-parameters.sh output_dir}"
work="$(mktemp -d "${TMPDIR:-/tmp}/shika-lexicon-parameters.XXXXXX")"
mkdir -p "$output_dir" "$work/base"
cp -R "$repo_dir/ShikaKeyBoard/Resources/RimeData.bundle" "$work/RimeData.bundle"
cp "$repo_dir/ShikaKeyBoard/Engine/SKRimeSession.m" "$repo_dir/ShikaKeyBoard/Engine/SKRimeSession.h" "$work/base/"
cp "$repo_dir"/ShikaKeyBoard/Core/*.swift "$repo_dir"/ShikaKeyBoard/Engine/*.swift "$repo_dir"/ShikaKeyBoard/Schemes/*/*Scheme.swift "$work/base/"
cp "$repo_dir/Tests/LexiconQualityChecks.swift" "$work/base/"
cp "$repo_dir/Tests/LexiconQualityCases.json" "$work/cases.json"
cp "$repo_dir/Tests/LexiconQualityAmbiguityCases.json" "$work/ambiguity.json"
shasum -a 256 "$work/cases.json" "$work/ambiguity.json" > "$output_dir/corpus-hashes.txt"
find "$work/RimeData.bundle" -type f -exec shasum -a 256 {} \; > "$output_dir/resource-hashes.txt"
slice="$repo_dir/Vendor/Rime/librime-static.xcframework/macos-arm64_x86_64"
xcrun clang -fobjc-arc -c "$work/base/SKRimeSession.m" -I"$work/base" -I"$slice/Headers" -o "$work/bridge.o"
for queries in 0 1 3; do
  mkdir -p "$work/q$queries" "$output_dir/query-$queries"
  cp "$work/base/"* "$work/q$queries/"
  python3 - "$work/q$queries/SKPinyinSegmentationCandidates.swift" "$queries" <<'PY'
import pathlib,re,sys
p=pathlib.Path(sys.argv[1]);s=p.read_text()
s,count=re.subn(r'(\}\)\.prefix\()[013](\) \{)',lambda m:m[1]+sys.argv[2]+m[2],s)
assert count==1, 'Expected exactly one query budget limit'
p.write_text(s)
PY
  shasum -a 256 "$work/q$queries/"* > "$output_dir/query-$queries/source-hashes.txt"
  xcrun swiftc -D SHIKA_HAS_CONVERSION_ENGINE -O -module-cache-path "$work/module-cache" -parse-as-library "$work"/q"$queries"/*.swift "$work/bridge.o" "$slice/librime.a" -import-objc-header "$work/q$queries/SKRimeSession.h" -framework Foundation -lc++ -liconv -o "$work/runner-$queries"
  for schema in shika_pinyin shika_flypy mixed; do
    "$work/runner-$queries" "$work/RimeData.bundle" "$work/user-$queries-$schema" "$work/cases.json" "$schema" ranking "$output_dir/query-$queries/$schema-ranking.json"
  done
  "$work/runner-$queries" "$work/RimeData.bundle" "$work/user-$queries-ambiguity" "$work/ambiguity.json" shika_pinyin ranking "$output_dir/query-$queries/ambiguity-ranking.json"
done
python3 - "$output_dir" <<'PY'
import pathlib,json,sys,math
p=pathlib.Path(sys.argv[1]);result={}
for q in [0,1,3]:
 out={}
 for schema in ['shika_pinyin','shika_flypy','mixed','ambiguity']:
  rows=json.loads((p/f'query-{q}/{schema}-ranking.json').read_text())['results'];r=[x['rank'] for x in rows];ds=sorted(d for x in rows for d in x['keyDurationsMS']);v={'count':len(r),**{f'top{k}':sum(0<n<=k for n in r)/len(r) for k in [1,5,10]},'MRR10':sum(1/n if n else 0 for n in r)/len(r),'p50MS':ds[math.ceil(len(ds)*.5)-1],'p95MS':ds[math.ceil(len(ds)*.95)-1],'peakRSSMiB':max(x['processPeakRSSBytes'] for x in rows)/1024**2}
  if schema=='ambiguity':v['pairsBothTop10']=sum(a>0 and b>0 for a,b in zip(r[::2],r[1::2]))
  out[schema]=v
 result[str(q)]=out
(p/'summary.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n');print(json.dumps(result,ensure_ascii=False,indent=2))
PY
printf 'Frozen parameter comparison: %s\n' "$work"
