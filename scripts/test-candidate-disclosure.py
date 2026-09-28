#!/usr/bin/env python3
"""Check disclosure hit regions; optionally leave a host for real pointer gestures."""
import pathlib, plistlib, subprocess, sys, tempfile, time

root = pathlib.Path(__file__).resolve().parent.parent
if len(sys.argv) < 2:
    raise SystemExit('Usage: python3 scripts/test-candidate-disclosure.py <booted-simulator-UUID> [--interactive]')
device = sys.argv[1]
work = pathlib.Path(tempfile.mkdtemp(prefix='shika-disclosure-'))
app = work / 'DisclosureChecks.app'
app.mkdir()
sdk = subprocess.check_output(['xcrun', '--sdk', 'iphonesimulator', '--show-sdk-path'], text=True).strip()
sources = ['ShikaKeyBoard/Core/SKInputEngine.swift', 'ShikaKeyBoard/Core/SKInputConfiguration.swift',
           'ShikaKeyBoard/UI/Components/CandidateBarView.swift', 'Tests/CandidateDisclosureHitChecks.swift']
subprocess.run(['xcrun', '--sdk', 'iphonesimulator', 'swiftc', '-sdk', sdk,
                '-target', 'arm64-apple-ios26.2-simulator', '-module-cache-path', str(work / 'module-cache'),
                *[str(root / source) for source in sources], '-o', str(app / 'DisclosureChecks')], check=True)
bundle = 'local.shika.disclosure-checks'
(app / 'Info.plist').write_bytes(plistlib.dumps({
    'CFBundleIdentifier': bundle, 'CFBundleExecutable': 'DisclosureChecks', 'CFBundleName': 'DisclosureChecks',
    'CFBundlePackageType': 'APPL', 'CFBundleVersion': '1', 'CFBundleShortVersionString': '1.0',
    'MinimumOSVersion': '26.2', 'UIDeviceFamily': [1], 'UILaunchScreen': {}}))
subprocess.run(['xcrun', 'simctl', 'terminate', device, bundle], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
subprocess.run(['xcrun', 'simctl', 'install', device, str(app)], check=True)
container = pathlib.Path(subprocess.check_output(['xcrun', 'simctl', 'get_app_container', device, bundle, 'data'], text=True).strip())
result = container / 'Documents/result.txt'
result.unlink(missing_ok=True)
subprocess.run(['xcrun', 'simctl', 'launch', device, bundle], check=True)
deadline = time.monotonic() + 20
while not result.exists() and time.monotonic() < deadline:
    time.sleep(0.25)
if not result.exists():
    raise SystemExit('FAIL: disclosure checks did not finish')
report = result.read_text()
if not report.startswith('PASS '):
    raise SystemExit(report)
print(report)
print('Evidence:', result)
if '--interactive' in sys.argv:
    subprocess.run(['xcrun', 'simctl', 'terminate', device, bundle], check=True)
    subprocess.run(['xcrun', 'simctl', 'launch', device, bundle, 'interactive'], check=True)
