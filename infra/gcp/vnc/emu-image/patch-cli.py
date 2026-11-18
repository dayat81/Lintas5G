#!/usr/bin/env python3
"""Patch budtmo docker-android CLI (cli/src/device/emulator.py) for the Lab5G image. Idempotent; fails loudly if a
pattern is not found (so an upstream change breaks the build instead of silently changing behaviour).
1. API_LEVEL map: add 15.0/16.0/17.0.
2. -writable-system opt-in (EMULATOR_WRITABLE_SYSTEM=1); Play Store images do not support it.
3. EMULATOR_LAUNCH_PREFIX (e.g. "vglrun -d egl0" for the GPU path).
4. is_initialized(): match hw.device.name case-insensitively and in avdmanager id form (Pixel C == pixel_c).
   Upstream compares 'Pixel C' against 'hw.device.name=pixel_c' -> always False -> avdmanager -f recreates the AVD and
   -wipe-data on EVERY container start, which destroys a restored user session (lab test 18 Nov 2026 14:27 WIB)."""
import sys
p = sys.argv[1]; s = open(p).read()
R = [
 ('"14.0": "34"', '"14.0": "34",\n        "15.0": "35",\n        "16.0": "36",\n        "17.0": "37"', '"16.0": "36"'),
 ('basic_args = f"-gpu {self.gpu} -accel on -writable-system -verbose"',
  'basic_args = f"-gpu {self.gpu} -accel on {\'-writable-system\' if os.getenv(\'EMULATOR_WRITABLE_SYSTEM\') == \'1\' else \'\'} -verbose"',
  "EMULATOR_WRITABLE_SYSTEM"),
 ('basic_cmd = "emulator @{n}".format(n=self.name)',
  'basic_cmd = (os.getenv("EMULATOR_LAUNCH_PREFIX", "") + " emulator @{n}").strip().format(n=self.name)',
  "EMULATOR_LAUNCH_PREFIX"),
 ("if any(re.match(r'hw\\.device\\.name ?= ?{}'.format(self.device), line) for line in f):",
  "if any(re.match(r'hw\\.device\\.name ?= ?({}|{})\\s*$'.format(re.escape(self.device), re.escape(self.device.lower().replace(' ', '_'))), line, re.I) for line in f):",
  "re.escape(self.device)"),
]
for old, new, marker in R:
    if marker in s: continue
    if old not in s: sys.exit(f"patch-cli: pattern not found: {old[:60]}")
    s = s.replace(old, new, 1)
open(p, "w").write(s); print("patch-cli: ok")
