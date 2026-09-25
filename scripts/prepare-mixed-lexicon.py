#!/usr/bin/env python3
"""Build a mapped Chinese word lattice index from the same attributed Rime corpus.
No evaluation sentences or answers are inputs. Existing Rime resources are unchanged.
"""
from pathlib import Path
import json, math, struct, hashlib
root=Path(__file__).resolve().parent.parent
source=root/'Vendor/RimeData/shika_chinese.dict.yaml'
if not source.exists():
    raise SystemExit('Run python3 scripts/prepare-lexicons.py --language chinese first')
entries={}
for line in source.open():
    f=line.rstrip('\n').split('\t')
    if len(f)!=3 or not f[2].isdigit(): continue
    text,reading,freq=f; code=reading.replace(' ','')
    if not code.isascii() or not code.isalpha() or len(code)>64: continue
    words=entries.setdefault(code,{})
    words[text]=max(words.get(text,0),int(freq))
keys=bytearray(); tokens=bytearray(); pool=bytearray(); count=0
for code,words in sorted(entries.items()):
    raw=code.encode(); offset=len(pool); pool.extend(raw)
    # Homophones stay selectable; bound per-key fan-out rather than loading Python
    # or Swift dictionaries into the extension. Pure Rime retains the full corpus.
    words=sorted(words.items(),key=lambda v:(-v[1],v[0]))[:12]
    keys.extend(struct.pack('<IHHI',offset,len(raw),len(words),count))
    for text,freq in words:
        raw=text.encode(); offset=len(pool); pool.extend(raw)
        tokens.extend(struct.pack('<IHHI',offset,len(raw),len(text),freq)); count+=1
out=root/'ShikaKeyBoard/Resources/RimeData.bundle/mixed-chinese.bin'
data=b'SKM1'+struct.pack('<III',len(entries),count,16+len(keys)+len(tokens))+keys+tokens+pool
out.write_bytes(data)
metadata={'source':'Wanxiang; same pinned snapshot as lexicon-metadata.json','readings':len(entries),'entries':count,'bytes':len(data),'sha256':hashlib.sha256(data).hexdigest(),'maxHomophones':12,'maxCodeLength':64}
(out.parent/'mixed-lexicon-metadata.json').write_text(json.dumps(metadata,indent=2)+'\n')
print(metadata)
