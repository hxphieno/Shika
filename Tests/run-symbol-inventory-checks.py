#!/usr/bin/env python3
"""Run symbol UI checks in an explicitly selected booted iOS simulator."""
import os, pathlib, plistlib, shutil, subprocess, tempfile, sys, time
root=pathlib.Path(__file__).resolve().parents[1]
if len(sys.argv) != 2:
    raise SystemExit('Usage: python3 Tests/run-symbol-inventory-checks.py <booted-simulator-UUID>')
os.chdir(root)
work=pathlib.Path(tempfile.mkdtemp(prefix='shika-integration-'))
app=work/'ShikaSmoke.app';app.mkdir()
sdk=subprocess.check_output(['xcrun','--sdk','iphonesimulator','--show-sdk-path'],text=True).strip()
optimization = ['-O'] if os.environ.get('SHIKA_SMOKE_OPTIMIZED') == '1' else []
files = ['ShikaKeyBoard/UI/Components/SKMainKeyButton.swift', 'ShikaKeyBoard/UI/Components/SKSymbolKeyButton.swift', 'ShikaKeyBoard/UI/Components/SKKeyboardScrollView.swift', 'ShikaKeyBoard/UI/Components/SKDeleteKeyInteraction.swift', 'ShikaKeyBoard/UI/Layouts/SKMainKeyboardSurface.swift', 'ShikaKeyBoard/UI/Layouts/SKKeyboardFooterView.swift', 'ShikaKeyBoard/UI/Layouts/SKNumberInputView.swift', 'ShikaKeyBoard/UI/Layouts/SKSymbolLayout.swift', 'ShikaKeyBoard/UI/Layouts/SKSymbolMemory.swift', 'ShikaKeyBoard/UI/Theme/SKMainKeyboardMetrics.swift', 'ShikaKeyBoard/Core/SKKeyboardEventHandler.swift']
snapshot = work/'Sources'; snapshot.mkdir()
for source in files: shutil.copy2(source, snapshot/pathlib.Path(source).name)
files = [str(p) for p in snapshot.glob('*.swift')]
subprocess.run(['xcrun','--sdk','iphonesimulator','swiftc','-sdk',sdk,'-target','arm64-apple-ios26.2-simulator','-module-name','ShikaSmoke']+optimization+files+['Tests/SymbolInventoryChecks.swift','-o',str(app/'ShikaSmoke')],check=True)
(app/'Info.plist').write_bytes(plistlib.dumps({'CFBundleIdentifier':'local.shika.symbol-badges','CFBundleExecutable':'ShikaSmoke','CFBundleName':'ShikaSmoke','CFBundlePackageType':'APPL','CFBundleVersion':'1','CFBundleShortVersionString':'1.0','MinimumOSVersion':'26.2','UIDeviceFamily':[1],'UILaunchScreen':{}}))
fixture = root/'docs/validation/symbol-inventory/ios26-symbols.json'
shutil.copy2(fixture, app/fixture.name)
device=sys.argv[1]
subprocess.run(['xcrun','simctl','terminate',device,'local.shika.symbol-badges'],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
subprocess.run(['xcrun','simctl','install',device,str(app)],check=True)
container=pathlib.Path(subprocess.check_output(['xcrun','simctl','get_app_container',device,'local.shika.symbol-badges','data'],text=True).strip())
result=container/'Documents/result.txt'
result.unlink(missing_ok=True)
subprocess.run(['xcrun','simctl','launch',device,'local.shika.symbol-badges'],check=True)
print('Build:',app)
deadline=time.monotonic()+float(os.environ.get('SHIKA_SMOKE_TIMEOUT','20'))
while not result.exists() and time.monotonic()<deadline:
    time.sleep(0.25)
if not result.exists():
    raise SystemExit('FAIL: test app did not finish; inspect simulator crash logs')
report=result.read_text()
if not report.startswith('PASS '):
    raise SystemExit(report)
print(report)
print('Evidence:',container/'Documents')
