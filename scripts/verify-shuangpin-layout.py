#!/usr/bin/env python3
"""Audit current main codes against an independent, pinned Rime Flypy reference.

The upstream GPL schema is read only for testing, never copied into app resources.
Pass --reference /path/to/download.yaml to run offline. This cannot establish
which double-pinyin scheme iOS Gboard selects by default.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import urllib.request

ROOT = Path(__file__).resolve().parent.parent
COMMIT = '6e2e2262200a98496fd85327c9d3863a56897780'
URL = f'https://raw.githubusercontent.com/rime/rime-double-pinyin/{COMMIT}/double_pinyin_flypy.schema.yaml'
SHA256 = '6b522a7e9cb743474287a14678597460bd124369f32573dd63e8f04e7c41d4b9'
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--reference', type=Path)
args = parser.parse_args()
data = args.reference.read_bytes() if args.reference else urllib.request.urlopen(URL, timeout=30).read()
assert hashlib.sha256(data).hexdigest() == SHA256, 'Unexpected upstream reference bytes'
source = data.decode()
block = source.split('  algebra:\n', 1)[1].split('\ntranslator:', 1)[0]
rules = [line.strip()[2:] for line in block.splitlines() if line.strip().startswith('- ')]

def official_codes(syllable):
    forms = {syllable}
    for rule in rules:
        operation, pattern, replacement, *_ = rule.split('/')
        if operation == 'erase':
            forms = {value for value in forms if not re.search(pattern, value)}
        elif operation in ('derive', 'xform'):
            replacement = re.sub(r'\$(\d)', r'\\g<\1>', replacement)
            transformed = {re.sub(pattern, replacement, value) for value in forms}
            forms = forms | transformed if operation == 'derive' else transformed
        elif operation == 'xlit':
            forms = {value.translate(str.maketrans(pattern, replacement)) for value in forms}
        else:
            raise AssertionError(f'Unsupported reference operation {operation}')
    return forms

schema = (ROOT / 'Vendor/RimeData/shika_flypy.schema.yaml').read_text()
actual = {syllable: code.lower() for syllable, code in re.findall(r'xform/\^([a-z]+)\$/([A-Z]+)/', schema)}
assert len(actual) >= 400, f'Unexpectedly small main-code coverage: {len(actual)}'
mismatches = []
missing_aliases = []
for syllable, code in actual.items():
    expected = official_codes(syllable)
    if code not in expected:
        mismatches.append({'syllable': syllable, 'actual': code, 'expected': sorted(expected)})
    if expected - {code}:
        missing_aliases.append({'syllable': syllable, 'main': code, 'officialAdditionalCodes': sorted(expected - {code})})

layout = (ROOT / 'ShikaKeyBoard/Schemes/Shuangpin/SKShuangpinLayout.swift').read_text()
initials_block = layout.split('static let initials:', 1)[1].split('static let finals:', 1)[0]
finals_block = layout.split('static let finals:', 1)[1]
initials = dict(re.findall(r'"([a-z])": "([a-z]+)"', initials_block))
finals = dict(re.findall(r'"([a-z])": "([^"]+)"', finals_block))
assert len(finals) == 26, 'Missing keycap hint'
assert initials == {'u': 'sh', 'i': 'ch', 'v': 'zh'}, 'Incorrect retroflex initial labels'
# Verify every keycap final using an actual syllable from the current schema.
hints_checked = 0
for key, labels in finals.items():
    for label in labels.split(' / '):
        final = label.replace('ü', 'v')
        matching = []
        for syllable, code in actual.items():
            initial = next((value for value in ('zh', 'ch', 'sh') if syllable.startswith(value)), syllable[:1])
            ending = syllable[len(initial):]
            # Dictionaries spell j/q/x/y + ue without the umlaut.
            if ending == final or (final == 've' and ending == 'ue'):
                matching.append((syllable, code))
        assert matching, f'No syllable exercises {key}: {label}'
        assert all(code[-1] == key for _, code in matching), f'Keycap disagrees with encoding: {key}: {matching}'
        hints_checked += 1
print(json.dumps({'reference': URL, 'referenceSHA256': SHA256, 'mainCodes': len(actual),
                  'mismatches': mismatches, 'keycapFinalsChecked': hints_checked,
                  'additionalUpstreamAliases': missing_aliases,
                  'gboardDefaultVerified': False}, ensure_ascii=False, indent=2))
raise SystemExit(1 if mismatches else 0)
