#!/usr/bin/env python3
"""Check the built app contains the exact offline resources and required notices."""
import hashlib
import pathlib
import plistlib
import sys

if len(sys.argv) != 2:
    raise SystemExit('Usage: python3 scripts/check-rime-bundle.py /path/to/Shika.app')
root = pathlib.Path(sys.argv[1])
extension = root / 'PlugIns/ShikaKeyBoard.appex'
info = plistlib.loads((extension / 'Info.plist').read_bytes())
assert info['NSExtension']['NSExtensionAttributes']['RequestsOpenAccess'] is False
source = pathlib.Path(__file__).resolve().parent.parent / 'ShikaKeyBoard/Resources/RimeData.bundle'
for resource in source.rglob('*'):
    if resource.is_file() and resource.name != 'Info.plist':
        target = extension / 'RimeData.bundle' / resource.relative_to(source)
        assert target.is_file(), f'Missing resource: {target}'
        assert hashlib.sha256(resource.read_bytes()).digest() == hashlib.sha256(target.read_bytes()).digest(), str(target)
assert (extension / 'PrivacyInfo.xcprivacy').is_file()
assert (extension / 'ThirdPartyNotices.txt').is_file()
assert (root / 'ThirdPartyNotices.txt').is_file()
assert not list(root.rglob('librime*.dylib'))
print('PASS: exact offline resources, full access disabled, privacy and notices bundled, static Rime')
