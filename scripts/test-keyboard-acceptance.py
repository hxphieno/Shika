#!/usr/bin/env python3
"""Independent UI checks, then verify saved language in a fresh app process."""
import os
import pathlib
import subprocess
import sys
import time

root = pathlib.Path(__file__).resolve().parent.parent
device = sys.argv[1] if len(sys.argv) > 1 else "booted"
env = dict(os.environ, SHIKA_SMOKE_SOURCE="Tests/KeyboardAcceptanceChecks.swift")
subprocess.run([sys.executable, str(root / "scripts/test-keyboard-simulator.py"), device], cwd=root, env=env, check=True)
container = pathlib.Path(subprocess.check_output(
    ["xcrun", "simctl", "get_app_container", device, "local.shika.integration", "data"], text=True).strip())
report = container / "Documents/keyboard-acceptance-persistence-result.txt"
report.unlink(missing_ok=True)
subprocess.run(["xcrun", "simctl", "terminate", device, "local.shika.integration"], check=True)
subprocess.run(["xcrun", "simctl", "launch", device, "local.shika.integration", "verify-persistence"], check=True)
deadline = time.monotonic() + 20
while not report.exists() and time.monotonic() < deadline:
    time.sleep(0.25)
if not report.exists():
    raise SystemExit("FAIL: independent persistence verification did not finish")
result = report.read_text()
print(result)
if not result.startswith("PASS "):
    raise SystemExit(1)
