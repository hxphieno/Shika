#!/usr/bin/env python3
"""Retain frozen targets/edit positions and re-encode their inputs as Ziranma."""
import json
import re
from pathlib import Path
ROOT = Path(__file__).resolve().parent.parent
schema = (ROOT / 'Vendor/RimeData/shika_flypy.schema.yaml').read_text()
mapping = {s: c.lower() for s, c in re.findall(r'xform/\^([a-z]+)\$/([A-Z]+)/', schema)}
def neighbor(c):
    row = next(row for row in ('qwertyuiop', 'asdfghjkl', 'zxcvbnm') if c in row)
    i = row.index(c)
    return row[i + 1] if i + 1 < len(row) else row[i - 1]
for filename in ('ShuangpinOptimizationCases.json', 'ShuangpinOptimizationConfirmationCases.json'):
    path = ROOT / 'Tests' / filename
    rows = json.loads(path.read_text())
    for row in rows:
        code = ''.join(mapping[s] for s in row['syllables'])
        edits = []
        for edit in row['edits']:
            i, op = edit['index'], edit['operation']
            if op == 'transpose':
                if code[i] == code[i + 1]:
                    i = next(j for j in range(len(code) - 1) if code[j] != code[j + 1])
                before, after = code[i:i + 2], code[i:i + 2][::-1]
            else:
                before = '' if op == 'insert' else code[i]
                after = '' if op == 'delete' else neighbor(code[i])
            edits.append(dict(operation=op, index=i, old=before, new=after))
        value = code
        for e in sorted(edits, key=lambda e: e['index'], reverse=True):
            i = e['index']
            assert value[i:i + len(e['old'])] == e['old']
            value = value[:i] + e['new'] + value[i + len(e['old']):]
        row.update(correct=code, input=value, edits=edits)
    path.write_text(json.dumps(rows, ensure_ascii=False, indent=2) + '\n')
    print(filename, len(rows))
