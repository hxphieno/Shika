#!/usr/bin/env python3
"""Exercise real UIKit keyboard sizing with a deterministic engine fixture."""
import pathlib
import plistlib
import subprocess
import sys
import tempfile
import time

root = pathlib.Path(__file__).resolve().parent.parent
device = sys.argv[1] if len(sys.argv) > 1 else 'booted'
work = pathlib.Path(tempfile.mkdtemp(prefix='shika-height-'))
app = work / 'HeightChecks.app'
app.mkdir()
sdk = subprocess.check_output(['xcrun', '--sdk', 'iphonesimulator', '--show-sdk-path'], text=True).strip()
legacy = {'SKIMKeyButton.swift', 'SKIMKeyButtonWithoutPopUpView.swift', 'SKSeparatorLine.swift'}
sources = [str(p) for p in (root / 'ShikaKeyBoard').rglob('*.swift') if 'Engine' not in p.parts and p.name not in legacy]
sources += [str(p) for p in (root / 'Shared').glob('*.swift')]
sources += [str(root / 'Tests' / name) for name in ['KeyboardHeightChecks.swift', 'KeyboardHeightEngineFixture.swift']]
subprocess.run(['xcrun', '--sdk', 'iphonesimulator', 'swiftc', '-sdk', sdk,
                '-target', 'arm64-apple-ios26.2-simulator', '-module-cache-path', str(work / 'module-cache'),
                *sources, '-o', str(app / 'HeightChecks')], check=True)
bundle = 'local.shika.height-checks'
(app / 'Info.plist').write_bytes(plistlib.dumps({
    'CFBundleIdentifier': bundle, 'CFBundleExecutable': 'HeightChecks', 'CFBundleName': 'HeightChecks',
    'CFBundlePackageType': 'APPL', 'CFBundleVersion': '1', 'CFBundleShortVersionString': '1.0',
    'MinimumOSVersion': '26.2', 'UIDeviceFamily': [1], 'UILaunchScreen': {}}))
subprocess.run(['xcrun', 'simctl', 'terminate', device, bundle], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
subprocess.run(['xcrun', 'simctl', 'install', device, str(app)], check=True)
container = pathlib.Path(subprocess.check_output(['xcrun', 'simctl', 'get_app_container', device, bundle, 'data'], text=True).strip())
result = container / 'Documents/result.txt'
result.unlink(missing_ok=True)
subprocess.run(['xcrun', 'simctl', 'launch', device, bundle], check=True)
deadline = time.monotonic() + 30
while not result.exists() and time.monotonic() < deadline:
    time.sleep(0.25)
if not result.exists():
    raise SystemExit('FAIL: keyboard height checks did not finish')
report = result.read_text()
print(report)
print('Evidence:', result.parent)
if not report.startswith('PASS '):
    raise SystemExit(1)
