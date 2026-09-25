#!/usr/bin/env python3
"""Compare frozen complete-candidate rankings without selecting/training answers."""
import gzip, json, sys
from pathlib import Path
before, after, output = map(Path, sys.argv[1:4])
def read_report(path):
    return json.loads(gzip.decompress(path.read_bytes()) if path.suffix == '.gz' else path.read_bytes())
b = read_report(before); a = read_report(after)
baseline = {r['id']: r for r in b['results']}
assert len(baseline) == len(a['results']) == len(b['results'])
assert not a['rankingLearnsAnswers'] and not b['rankingLearnsAnswers']
rows = a['results']; metrics = []
for kind in sorted({r['kind'] for r in rows}):
    actual = [r for r in rows if r['kind'] == kind]; old = [baseline[r['id']] for r in actual]
    for r, previous in zip(actual, old):
        assert all(r[k] == previous[k] for k in ('input', 'target', 'kind', 'schema', 'split'))
    score = lambda values, n: sum(0 < v['rank'] <= n for v in values)
    metrics.append({'kind': kind, 'n': len(actual), 'before': {f'top{n}':score(old,n) for n in (1,3,5,8,10)},
                    'after': {f'top{n}':score(actual,n) for n in (1,3,5,8,10)}})
first = lambda r: r['candidates'][0]['text'] if r['candidates'] else ''
clean = [r for r in rows if r['kind']=='clean']
clean_changes = [r['id'] for r in clean if first(r)!=first(baseline[r['id']])]
clean_regressions = [r['id'] for r in clean if baseline[r['id']]['rank']==1 and r['rank']!=1]
errors = [m for m in metrics if m['kind'] not in ('clean','double-error')]
gain = sum(m['after']['top5']-m['before']['top5'] for m in errors)
n = sum(m['n'] for m in errors)
result = {'n':len(rows), 'metrics':metrics, 'singleErrorTop5NetGain':gain,
          'singleErrorTop5GainPercentagePoints':100*gain/n if n else 0,
          'cleanFirstChanges':clean_changes, 'cleanFirstRegressions':clean_regressions,
          'unexpectedCommits':[r['id'] for r in rows if r['unexpectedCommit']],
          'failures':[r['id'] for r in rows if not 0<r['rank']<=10],
          'top5Regressions':[r['id'] for r in rows if 0<baseline[r['id']]['rank']<=5 and not 0<r['rank']<=5],
          'timings':{tag:{k:v for k,v in d.items() if k!='results'} for tag,d in [('before',b),('after',a)]},
          'qualityGates':{'cleanTop5':sum(0<r['rank']<=5 for r in clean)>=sum(0<baseline[r['id']]['rank']<=5 for r in clean),
                          'cleanFirst':not clean_regressions, 'singleErrorGain':gain/n>=.05 if n else False,
                          'eachKind':all((m['after']['top5']-m['before']['top5'])/m['n']>=-.02 for m in errors)}}
result['performanceGates'] = {
    'p95Relative': a['keyP95MS'] <= b['keyP95MS'] * 1.25,
    'p95Absolute': a['keyP95MS'] <= 50,
    'p99Absolute': a['keyP99MS'] <= 100,
}
if len(sys.argv) > 4:
    fixture = {r['id']: r for r in json.loads(Path(sys.argv[4]).read_text())}
    groups = {}
    for row in rows:
        item = fixture[row['id']]
        length = len(item['target'])
        for group in ('category:' + item.get('category', 'unknown'),
                      'length:' + ('2-3' if length <= 3 else '4-6' if length <= 6 else '7+'),
                      'split:' + item['split']):
            groups.setdefault(group, []).append(row)
    def scores(values):
        ranks = [r['rank'] for r in values]
        return {'n': len(ranks), **{f'top{k}': sum(0 < r <= k for r in ranks) for k in (1, 3, 5, 8, 10)},
                'mrr10': sum(1/r for r in ranks if 0 < r <= 10) / len(ranks)}
    result['groups'] = {name: {'before': scores([baseline[r['id']] for r in values]),
                             'after': scores(values),
                             'missingTop10': [r['id'] for r in values if not 0 < r['rank'] <= 10]}
                        for name, values in sorted(groups.items())}
output.write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n')
for m in metrics: print(m['kind'],m['n'],m['before'],'->',m['after'])
print('Quality gates:',result['qualityGates'],'net single-error Top5 gain:',gain,'/',n)
print('P95/P99 ms:',b['keyP95MS'],b['keyP99MS'],'->',a['keyP95MS'],a['keyP99MS'])
