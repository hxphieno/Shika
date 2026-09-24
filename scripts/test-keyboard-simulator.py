#!/usr/bin/env python3
"""Build a temporary test host using the real keyboard views, engine and proxy calls."""
import os, pathlib, plistlib, shutil, subprocess, tempfile, sys, time
root=pathlib.Path(__file__).resolve().parent.parent
os.chdir(root)
work=pathlib.Path(tempfile.mkdtemp(prefix='shika-integration-'))
app=work/'ShikaSmoke.app';app.mkdir()
sdk=subprocess.check_output(['xcrun','--sdk','iphonesimulator','--show-sdk-path'],text=True).strip()
slice=root/'Vendor/Rime/librime-static.xcframework/ios-arm64_x86_64-simulator'
subprocess.run(['xcrun','clang','-fobjc-arc','-target','arm64-apple-ios26.2-simulator','-isysroot',sdk,'-I',str(slice/'Headers'),'-c','ShikaKeyBoard/Engine/SKRimeSession.m','-o',str(work/'bridge.o')],check=True)
files=[str(p) for p in pathlib.Path('ShikaKeyBoard').rglob('*.swift')]
subprocess.run(['xcrun','--sdk','iphonesimulator','swiftc','-sdk',sdk,'-target','arm64-apple-ios26.2-simulator','-module-name','ShikaSmoke','-import-objc-header','ShikaKeyBoard/Engine/ShikaKeyBoard-Bridging-Header.h']+files+[os.environ.get('SHIKA_SMOKE_SOURCE','Tests/KeyboardIntegrationSmoke.swift'),str(work/'bridge.o'),str(slice/'librime.a'),'-lc++','-liconv','-o',str(app/'ShikaSmoke')],check=True)
(app/'Info.plist').write_bytes(plistlib.dumps({'CFBundleIdentifier':'local.shika.integration','CFBundleExecutable':'ShikaSmoke','CFBundleName':'ShikaSmoke','CFBundlePackageType':'APPL','CFBundleVersion':'1','CFBundleShortVersionString':'1.0','MinimumOSVersion':'26.2','UIDeviceFamily':[1],'UILaunchScreen':{}}))
shutil.copytree('ShikaKeyBoard/Resources/RimeData.bundle',app/'RimeData.bundle')
device=sys.argv[1] if len(sys.argv)>1 else 'booted'
subprocess.run(['xcrun','simctl','terminate',device,'local.shika.integration'],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
subprocess.run(['xcrun','simctl','install',device,str(app)],check=True)
container=pathlib.Path(subprocess.check_output(['xcrun','simctl','get_app_container',device,'local.shika.integration','data'],text=True).strip())
result=container/'Documents/result.txt'
result.unlink(missing_ok=True)
subprocess.run(['xcrun','simctl','launch',device,'local.shika.integration'],check=True)
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
