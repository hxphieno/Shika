#!/usr/bin/env python3
"""Summarize independently frozen correction cases without hiding misses."""
from pathlib import Path
import argparse
import hashlib
import json
import statistics

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('results', type=Path)
args = parser.parse_args()
root = Path(__file__).resolve().parent.parent
baseline = json.loads((args.results/'baseline-ranking.json').read_text())['results']
corrected = json.loads((args.results/'corrected-ranking.json').read_text())['results']
commits = json.loads((args.results/'corrected-commit.json').read_text())['results']
key = lambda item: (item['schema'], item['kind'], item['input'], item['target'])
by_key = {key(item): item for item in baseline}
assert len(by_key) == len(baseline) == len(corrected) == len(commits) == 400
assert set(by_key) == {key(item) for item in corrected} == {key(item) for item in commits}
first = lambda item: item['candidates'][0]['text'] if item['candidates'] else ''
rows = []
for schema in ('shika_pinyin', 'shika_flypy'):
    for kind in ('clean', 'substitution', 'omission', 'insertion', 'transposition'):
        tests = [item for item in corrected if item['schema'] == schema and item['kind'] == kind]
        bases = [by_key[key(item)] for item in tests]
        measure = lambda items, limit: sum(0 < item['targetRank'] <= limit for item in items)
        rows.append(dict(schema=schema, kind=kind, count=len(tests),
            baselineTop1=measure(bases, 1), correctedTop1=measure(tests, 1),
            baselineTop3=measure(bases, 3), correctedTop3=measure(tests, 3),
            baselineTop8=measure(bases, 8), correctedTop8=measure(tests, 8)))
clean_changes = [item for item in corrected if item['kind']=='clean' and first(item)!=first(by_key[key(item)])]
clean_regressions = [item for item in clean_changes if first(by_key[key(item)])==item['target'] and first(item)!=item['target']]
spurious = [item for item in corrected if item['unexpectedOutputBeforeSelection']]
selection_failures = [item for item in commits if not item.get('selectionUnavailable') and not(item.get('selectedExactlyOnce') and item.get('selectionCleared'))]
space_failures = [item for item in commits if not item['spaceMatchesDisplayedTop']]
durations = sorted(value for item in corrected for value in item['keyDurationsMS'])
percentile = lambda p: durations[min(len(durations)-1, int((len(durations)-1)*p))]
summary = dict(datasetSHA256=hashlib.sha256((root/'Tests/AutocorrectionIndependentHeldout.json').read_bytes()).hexdigest(),
    cases=400, metrics=rows, cleanFirstCandidateChanges=clean_changes, cleanTargetRegressions=clean_regressions,
    unexpectedCommitsWhileTyping=spurious, selectedCandidateCommitFailures=selection_failures,
    spaceCommitFailures=space_failures, selectionUnavailable=sum(bool(i.get('selectionUnavailable')) for i in commits),
    keyLatencyMS=dict(p50=percentile(.5), p95=percentile(.95), p99=percentile(.99), max=max(durations)))
(args.results/'summary.json').write_text(json.dumps(summary,ensure_ascii=False,indent=2)+'\n')
print('| Scheme | Error | N | Top1 baseline→corrected | Top3 baseline→corrected | Top8 baseline→corrected |')
print('|---|---|---:|---:|---:|---:|')
for row in rows:
    print(f"| {row['schema']} | {row['kind']} | {row['count']} | {row['baselineTop1']}→{row['correctedTop1']} | {row['baselineTop3']}→{row['correctedTop3']} | {row['baselineTop8']}→{row['correctedTop8']} |")
print('Clean first changes:',len(clean_changes),'clean target regressions:',len(clean_regressions))
print('Unexpected typing commits:',len(spurious),'target select failures:',len(selection_failures),'space failures:',len(space_failures))
print('Mac latency:',summary['keyLatencyMS'])
# Quality percentages remain explicit measurements; state-corruption and exact
# clean-input regressions are hard test failures rather than a successful exit.
raise SystemExit(1 if clean_regressions or spurious or selection_failures or space_failures else 0)
