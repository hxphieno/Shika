#!/usr/bin/env python3
"""Replay each claimed complete hit in its own fresh native process/userdir."""
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
import gzip, json, subprocess, sys
runner, resources, cases, ranking, output = sys.argv[1:]
output = Path(output); output.mkdir(parents=True, exist_ok=True)
ranking_path = Path(ranking)
ranking_data = gzip.decompress(ranking_path.read_bytes()) if ranking_path.suffix == '.gz' else ranking_path.read_bytes()
rows = [r for r in json.loads(ranking_data)['results'] if r['rank'] > 0]
if not rows:
    raise SystemExit('No complete hits to replay; this is not a passing commit test')
def run(row):
    key = row['id']; result = output / (key + '.json'); user = output / (key + '-user')
    if user.exists(): raise RuntimeError(f'Refusing non-fresh user directory: {user}')
    subprocess.run([runner, resources, str(user), cases, str(result), 'all', key], check=True, stdout=subprocess.DEVNULL)
    observed = json.loads(result.read_text())['results']
    assert len(observed)==1
    r = observed[0]
    return {'id':key,'passed':r.get('selectionPassed',False), 'output':r.get('commit'), 'remaining':r.get('remaining'), 'rank':r['rank']}
with ThreadPoolExecutor(max_workers=3) as pool: results = list(pool.map(run, rows))
report={'freshProcessAndUserDirectoryPerCase':True,'count':len(results),'passed':sum(r['passed'] for r in results),'results':results}
(output/'summary.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
print('Isolated commits:',report['passed'],'/',report['count'])
raise SystemExit(0 if report['count']==report['passed'] else 1)
