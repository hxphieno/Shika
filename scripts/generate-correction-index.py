#!/usr/bin/env python3
"""Compile a compact, read-only typo index from Shika's existing Apache-2.0 dictionary.
No test vocabulary, external corpus, or mutable user data is part of this index.
"""
from pathlib import Path
import re, struct, json, itertools
root = Path(__file__).resolve().parent.parent
source = root / 'Vendor/RimeData'
out = root / 'ShikaKeyBoard/Resources/RimeData.bundle'
# Apply the actual full-pinyin schema's spelling aliases per syllable. Avoid
# substitutions across a syllable boundary (lu + er is not lue + r).
pinyin_schema = (source/'shika_pinyin.schema.yaml').read_text()
pinyin_aliases = []
for pattern, replacement in re.findall(r'derive/([^/]+)/([^/]+)/', pinyin_schema):
    pinyin_aliases.append((re.compile(pattern), re.sub(r'\$(\d)', r'\\g<\1>', replacement)))
def full_codes(syllables):
    options = []
    for syllable in syllables:
        variants = {syllable}
        for pattern, replacement in pinyin_aliases:
            variants.update(pattern.sub(replacement, v) for v in list(variants))
        options.append(sorted(variants))
    return {''.join(parts) for parts in itertools.product(*options)}

mapping = {a:b.lower() for a,b in re.findall(r'xform/\^([a-z]+)\$/([A-Z]+)', (source/'shika_flypy.schema.yaml').read_text())}
(out/'correction-syllables.json').write_text(json.dumps(mapping,sort_keys=True,separators=(',',':'))+'\n')
for scheme in ('shika_pinyin','shika_flypy'):
    entries = {}
    for line in (source/'pinyin_simp.dict.yaml').read_text().splitlines():
        fields = line.split('\t')
        if len(fields)<3: continue
        text,pinyin,weight = fields[:3]
        syllables=pinyin.split()
        # Single-character correction is too ambiguous on a mobile keyboard.
        if len(syllables)<2: continue
        if scheme=='shika_flypy' and any(s not in mapping for s in syllables): continue
        codes={''.join(mapping[s] for s in syllables)} if scheme=='shika_flypy' else full_codes(syllables)
        frequency=int(weight)
        for code in codes:
            if not code.isascii() or not code.isalpha() or len(code)>48: continue
            if code not in entries or frequency>entries[code][1]: entries[code]=(text,frequency)
    pool=bytearray();records=bytearray()
    for code,(text,frequency) in sorted(entries.items()):
        c=code.encode();t=text.encode();co=len(pool);pool.extend(c);to=len(pool);pool.extend(t)
        records.extend(struct.pack('<IHHII',co,len(c),len(t),to,frequency))
    data=b'SKC1'+struct.pack('<I',len(entries))+records+pool
    (out/(scheme+'.correction.bin')).write_bytes(data)
    print(scheme,len(entries),'codes',len(data),'bytes')
