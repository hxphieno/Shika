#!/usr/bin/env python3
"""Audit Ziranma codes and keycap hints against the user-supplied 2026-09-26 chart.

The expected table is deliberately independent of the generator's JSON input.
Zero initials use doubled single vowels, literal two-letter syllables, ah/eg.
No network or upstream schema is required.
"""
import json
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parent.parent
EXPECTED = dict(zip('qwertyuiopasdfghjklzxcvbnm', [
    ['iu'], ['ia', 'ua'], ['e'], ['uan', 'van'], ['ve', 'ue'], ['uai', 'ing'],
    ['u'], ['i'], ['o', 'uo'], ['vn', 'un'], ['a'], ['ong', 'iong'],
    ['iang', 'uang'], ['en'], ['eng'], ['ang'], ['an'], ['ao'], ['ai'],
    ['ei'], ['ie'], ['iao'], ['ui', 'v'], ['ou'], ['in'], ['ian'],
]))
ZERO = dict(a='aa', o='oo', e='ee', ai='ai', ei='ei', ao='ao', ou='ou',
            an='an', en='en', ang='ah', eng='eg', er='er')
INITIALS = {'sh': 'u', 'ch': 'i', 'zh': 'v'}
FINALS = {final: key for key, finals in EXPECTED.items() for final in finals}
layout = json.loads((ROOT / 'Vendor/RimeData/shuangpin-layout.json').read_text())
assert {entry['key']: entry['finals'] for entry in layout['keys']} == EXPECTED
assert layout['zeroInitials'] == ZERO
assert layout['initials'] == {key: value for value, key in INITIALS.items()}
assert layout['rows'] == ['qwertyuiop', 'asdfghjkl', 'zxcvbnm']

def expected_code(syllable):
    if syllable in ZERO:
        return ZERO[syllable]
    initial = next((v for v in INITIALS if syllable.startswith(v)), syllable[:1])
    final = syllable[len(initial):]
    return INITIALS.get(initial, initial) + FINALS.get(final, final)

schema = (ROOT / 'Vendor/RimeData/shika_flypy.schema.yaml').read_text()
assert 'name: 自然码双拼' in schema
actual = {s: c.lower() for s, c in re.findall(r'xform/\^([a-z]+)\$/([A-Z]+)/', schema)}
assert len(actual) >= 400
for syllable, code in actual.items():
    assert code == expected_code(syllable), (syllable, code, expected_code(syllable))
syllables = set()
for line in (ROOT / 'Vendor/RimeData/shika_chinese.dict.yaml').read_text().splitlines():
    fields = line.split('\t')
    if len(fields) > 1:
        syllables.update(fields[1].split())
for syllable in syllables:
    code = expected_code(syllable)
    if len(code) == 2:
        assert actual.get(syllable) == code, ('missing syllable', syllable)

swift = (ROOT / 'ShikaKeyBoard/Schemes/Shuangpin/SKShuangpinLayout.swift').read_text()
initials_block, finals_block = swift.split('static let finals:', 1)
assert dict(re.findall(r'"([a-z])": "([a-z]+)"', initials_block)) == layout['initials']
expected_hints = {key: ' / '.join(dict.fromkeys(f.replace('ue', 've').replace('v', 'ü') for f in finals))
                  for key, finals in EXPECTED.items()}
assert dict(re.findall(r'"([a-z])": "([^"]+)"', finals_block)) == expected_hints
bundle = ROOT / 'ShikaKeyBoard/Resources/RimeData.bundle'
assert json.loads((bundle / 'correction-syllables.json').read_text()) == actual
compiled = (bundle / 'build/shika_flypy.schema.yaml').read_text()
assert {s: c.lower() for s, c in re.findall(r'xform/\^([a-z]+)\$/([A-Z]+)/', compiled)} == actual
print(f'PASS: Ziranma chart, {len(actual)} main codes, 26 keycaps, zero initials, compiled schema and correction syllables')
