#!/usr/bin/env python3
import json,pathlib,sys,math
folder=pathlib.Path(sys.argv[1]); summary={}
def percentile(vals,p):
 vals=sorted(vals);return round(vals[min(len(vals)-1,max(0,math.ceil(len(vals)*p)-1))],3) if vals else None
for schema in ['shika_pinyin','shika_flypy']+(['mixed'] if (folder/'mixed-ranking.json').exists() else []):
 report=json.loads((folder/f'{schema}-ranking.json').read_text());rows=report['results']
 out={'count':len(rows),'startupMS':round(report['startupMS'],3),'groups':{}}
 for kind in ['all','word','phrase','sentence','ambiguity']:
  group=[r for r in rows if kind=='all' or r['kind']==kind]
  ranks=[r['rank'] for r in group];durations=[d for r in group for d in r['keyDurationsMS']]
  out['groups'][kind]={'count':len(group),**{f'top{k}':round(sum(0<r<=k for r in ranks)/len(group),4) for k in [1,5,10]},'MRR10':round(sum(1/r if r else 0 for r in ranks)/len(group),4),'keyP50MS':percentile(durations,.5),'keyP95MS':percentile(durations,.95),'peakRSSMiB':round(max(r['processPeakRSSBytes'] for r in group)/1024**2,2)}
 cover=json.loads((folder/f'{schema}-coverage.json').read_text())['results'];long=[r for r in cover if r['kind']=='sentence']
 out['sentenceCoverage']={'count':len(long),'topChoiceConsumesAllInput':sum(r.get('topChoiceConsumesAllInput',False) for r in long),'topChoiceExactOutput':sum(r.get('topChoiceExactOutput',False) for r in long),'note':'Each coverage case uses its own fresh process and userdir; no cross-case selection training.'}
 ambiguities=[r for r in rows if r['kind']=='ambiguity']
 out['ambiguityPairs']=[{'targets':[a['target'],b['target']],'inputs':[a['input'],b['input']],'bothInTop10':a['rank']>0 and b['rank']>0} for a,b in zip(ambiguities[::2],ambiguities[1::2])]
 out['unexpectedRankingCommits']=sum(bool(r['unexpectedCommit']) for r in rows)
 out['sihua']=next({'input':r['input'],'rank':r['rank'],'candidates':[c['text'] for c in r['candidates']]} for r in rows if r['target']=='丝滑')
 summary[schema]=out
(folder/'summary.json').write_text(json.dumps(summary,ensure_ascii=False,indent=2)+'\n')
print(json.dumps(summary,ensure_ascii=False,indent=2))
