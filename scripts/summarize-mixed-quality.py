#!/usr/bin/env python3
"""Summarize immutable baseline/joint reports without dropping failed targets."""
import json,math,sys,pathlib,collections
p=pathlib.Path(sys.argv[1]); reports={name:json.loads((p/(name+'.json')).read_text()) for name in ['baseline','16']}
def summary(rows):
    durations=sorted(t for x in rows for t in x['keyMS']);n=len(rows)
    result={'cases':n}
    for k in [1,3,5,10]:result['top'+str(k)]=sum(0<x['rank']<=k for x in rows)/n if n else 0
    result['MRR10']=sum(1/x['rank'] for x in rows if 0<x['rank']<=10)/n if n else 0
    for k in [50,95,99]:result['keyP'+str(k)+'MS']=durations[min(len(durations)-1,math.ceil(len(durations)*k/100)-1)] if durations else 0
    result['peakFootprintMiB']=max((r['footprintBytes'] for r in rows),default=0)/2**20
    result['unexpectedCommits']=sum(bool(r['unexpectedCommit']) for r in rows)
    return result
out={}
for name,report in reports.items():
    rows=report['cases'];groups={'all':rows}
    for split in ['development','heldout']:groups[split]=[r for r in rows if r['split']==split]
    groups['heldout-mixed']=[r for r in rows if r['split']=='heldout' and not r['category'].startswith('pure-')]
    groups['heldout-pure']=[r for r in rows if r['split']=='heldout' and r['category'].startswith('pure-')]
    groups['long-vowels']=[r for r in rows if '-' in r['input']]
    for category in sorted(set(r['category'] for r in rows)):groups[category]=[r for r in rows if r['category']==category]
    out[name]={key:summary(items) for key,items in groups.items()}
    out[name]['behaviorFailures']=report['failed']
new=out['16'];out['gates']={'mixedTop5':new['heldout-mixed']['top5']>=.70,'mixedTop10':new['heldout-mixed']['top10']>=.80,'pureTop5':new['heldout-pure']['top5']>=.95,'noUnexpectedCommits':new['all']['unexpectedCommits']==0,'behavior':new['behaviorFailures']==0}
(p/'summary.json').write_text(json.dumps(out,ensure_ascii=False,indent=2)+'\n')
fail=[r for r in reports['16']['cases'] if r['rank']==0 or r['rank']>5]
(p/'failures.json').write_text(json.dumps(fail,ensure_ascii=False,indent=2)+'\n')
print(json.dumps({k:{g:out[k][g] for g in ['all','heldout-mixed','heldout-pure']} for k in reports},indent=2));print(out['gates'])

if not all(out["gates"].values()): sys.exit(1)
