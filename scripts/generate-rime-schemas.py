#!/usr/bin/env python3
"""Generate our schemas from phonetic mappings; no upstream GPL schema is copied."""
from pathlib import Path
root = Path(__file__).resolve().parent.parent / 'Vendor/RimeData'
common = '''schema:
  schema_id: {schema}
  name: {name}
  version: '1.0'
engine:
  processors: [speller, selector, navigator, express_editor]
  segmentors: [abc_segmentor, fallback_segmentor]
  translators: [script_translator]
menu:
  page_size: 8
speller:
  alphabet: abcdefghijklmnopqrstuvwxyz
  delimiter: " '"
  algebra:
{algebra}
translator:
  dictionary: pinyin_simp
  prism: {schema}
  enable_user_dict: true
  enable_sentence: true
  enable_completion: true
'''
(root/'shika_pinyin.schema.yaml').write_text(common.format(schema='shika_pinyin',name='中文全拼',algebra='    - derive/^([nl])ue$/$1ve/\n    - abbrev/^([a-z]).+$/$1/'))
finals = {'iu':'q','ei':'w','uan':'r','ue':'t','ve':'t','un':'y','uo':'o','ie':'p','ong':'s','iong':'s','ing':'k','uai':'k','ai':'d','en':'f','eng':'g','iang':'l','uang':'l','ang':'h','ian':'m','an':'j','ou':'z','ia':'x','ua':'x','iao':'n','ao':'c','ui':'v','in':'b'}
zero = {'a':'aa','o':'oo','e':'ee','ai':'ai','ei':'ei','ao':'ao','ou':'ou','an':'an','en':'en','ang':'ah','eng':'eg','er':'er'}
syllables=set()
for line in (root/'pinyin_simp.dict.yaml').read_text().splitlines():
    fields=line.split('\t')
    if len(fields)>1: syllables.update(fields[1].split())
rules=[]
for syllable in sorted(syllables):
    if syllable in zero: code=zero[syllable]
    else:
        initial=next((s for s in ['zh','ch','sh'] if syllable.startswith(s)),syllable[:1])
        final=syllable[len(initial):]
        if not final: continue
        code={'zh':'v','ch':'i','sh':'u'}.get(initial,initial)+finals.get(final,final)
    if len(code)==2: rules.append(f'    - xform/^{syllable}$/{code.upper()}/')
rules += ['    - xlit/ABCDEFGHIJKLMNOPQRSTUVWXYZ/abcdefghijklmnopqrstuvwxyz/']
(root/'shika_flypy.schema.yaml').write_text(common.format(schema='shika_flypy',name='小鹤双拼',algebra='\n'.join(rules)))
(root/'default.yaml').write_text('config_version: "1.0"\nschema_list:\n  - schema: shika_pinyin\n  - schema: shika_flypy\n')
print(f'Generated {len(rules)-1} Xiaohe syllable mappings')
