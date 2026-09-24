#!/usr/bin/env python3
from pathlib import Path
root=Path(__file__).resolve().parent.parent
files=[root/'Vendor/Rime/LICENSE.txt',root/'Vendor/Rime/LICENSE-librime.txt',root/'Vendor/Rime/THIRD_PARTY_NOTICES.md',root/'Vendor/RimeData/LICENSE-pinyin.txt']+sorted((root/'Vendor/Rime/third-party-notices').rglob('*.txt'))
text='Shika third-party notices\n\nRime 1.17.0: https://github.com/rime/librime\nApple static packaging: https://github.com/ghostflyby/librime-xcframework\nSimplified dictionary: https://github.com/rime/rime-pinyin-simp (derived from AOSP PinyinIME)\n\n'
for p in files:
    data=p.read_bytes()
    try: contents=data.decode('utf-8')
    except UnicodeDecodeError: contents=data.decode('latin-1')
    text+='\n\n===== '+str(p.relative_to(root))+' =====\n\n'+contents
for destination in ['Shika/ThirdPartyNotices.txt','ShikaKeyBoard/Resources/ThirdPartyNotices.txt']:
    (root/destination).write_text(text)
