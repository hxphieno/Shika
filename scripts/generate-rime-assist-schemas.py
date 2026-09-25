#!/usr/bin/env python3
"""Derive an internal correction schema from the already compiled main schema.

The helper shares the same prism, dictionary and user dictionary. It is never
listed in default.yaml and never receives typing/commit/selection events.
No deploy, downloads, or configuration writes happen inside the extension.
"""
from pathlib import Path
import argparse
p = argparse.ArgumentParser(description=__doc__)
p.add_argument('--check', action='store_true')
a = p.parse_args()
root = Path(__file__).resolve().parent.parent / 'ShikaKeyBoard/Resources/RimeData.bundle/build'
for schema in ('shika_flypy',):
    source = (root / f'{schema}.schema.yaml').read_text()
    # Build timestamps belong to the source schema, not to this derived file.
    source = source[source.index('engine:\n'):]
    assert source.count(f'  schema_id: {schema}\n') == 1
    assert source.count('translator:\n') == 1
    result = source.replace(f'  schema_id: {schema}\n', f'  schema_id: {schema}_assist\n')
    result = result.replace('translator:\n', 'translator:\n  enable_correction: true\n')
    destination = root / f'{schema}_assist.schema.yaml'
    if a.check:
        assert destination.read_text() == result, f'Stale helper: {destination}'
    else:
        destination.write_text(result)
print('Verified' if a.check else 'Generated', 'isolated Rime correction schema')
