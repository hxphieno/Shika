#!/usr/bin/env python3
"""Transcribe the frozen double-pinyin targets and apply protocol-v1 typos.

These are shared targets, not a second independent vocabulary sample.
Only the spelling/input/edit metadata changes; no engine output is consulted.
"""
import hashlib
import json
from pathlib import Path

root = Path(__file__).resolve().parent.parent
rows = json.loads((root / 'Tests/ShuangpinOptimizationCases.json').read_text())
targets = list(dict.fromkeys(r['target'] for r in rows))

def neighbor(c):
    row = next(r for r in ('qwertyuiop', 'asdfghjkl', 'zxcvbnm') if c in r)
    i = row.index(c)
    return row[i + 1] if i + 1 < len(row) else row[i - 1]

output = []
for row in rows:
    code = ''.join(row['syllables'])
    n = len(code)
    positions = list(range(2, n - 2)) if n >= 16 else list(range(n))
    position = positions[int(hashlib.sha256(row['target'].encode()).hexdigest()[:8], 16) % len(positions)]
    kind = row['kind']
    edits = []
    if kind == 'substitution':
        edits = [(position, code[position], neighbor(code[position]))]
    elif kind == 'omission':
        edits = [(position, code[position], '')]
    elif kind == 'insertion':
        edits = [(position, '', neighbor(code[position]))]
    elif kind == 'transposition':
        choices = [j for j in (range(2, n - 3) if n >= 16 else range(n - 1)) if code[j] != code[j + 1]]
        j = choices[targets.index(row['target']) % len(choices)]
        edits = [(j, code[j:j + 2], code[j:j + 2][::-1])]
    elif kind == 'double-error':
        edits = [(j, code[j], neighbor(code[j])) for j in (max(0, n // 3 - 1), min(n - 1, 2 * n // 3 + 1))]
    value = code
    for position, before, after in sorted(edits, reverse=True):
        assert value[position:position + len(before)] == before
        value = value[:position] + after + value[position + len(before):]
    output.append({**row, 'id': 'full-' + row['id'], 'schema': 'shika_pinyin', 'correct': code,
                   'input': value, 'sourceDoublePinyinID': row['id'],
                   'edits': [{'position': p, 'from': a, 'to': b} for p, a, b in edits],
                   'derivation': 'Shared targets from double-pinyin fixture; protocol-v1 mutations on full pinyin. Not independent vocabulary.'})
destination = root / 'Tests/FullPinyinOptimizationCases.json'
destination.write_text(json.dumps(output, ensure_ascii=False, indent=2) + '\n')
print(len(output), hashlib.sha256(destination.read_bytes()).hexdigest())
