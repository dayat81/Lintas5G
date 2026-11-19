#!/usr/bin/env python3
"""Clock offset core <-> Android GUEST with streaming + minimum-delay filter (replaces the ssh/adb bracket).

Why: the old bracket `a=date; r=$(ssh emu docker exec adb shell date); b=date` has rtt ~300 ms and the guest clock is read
late in that chain, so mid-point estimation was biased by ~120 ms (v0.10.2 recheck: runner skew 218.6 ms vs 338 ms calibrated).

Stage 1 (runs on the emu host):  `skew-guest.py emu <container>`
  streams guest `date +%s.%N` through `docker exec <c> adb shell` and stamps every line on arrival with the emu-HOST clock
  (line g, host receive h; h - g_host = true_offset_gh + small stream delay) -> prints  G <max(g-h)>  (min-delay filter),
  then prints  T <host_time>  lines (one per ~20 ms) so stage 2 can bracket host vs core with a stream too.
Stage 2 (runs on the core): `skew-guest.py core -- <command that runs stage 1 on the emu host>`
  stamps every T line with the CORE clock on arrival -> off_hc = max(host_ts - core_recv).
Result: off_gc = (guest - core) = off_gh + off_hc ;  skew_s (PKTLAT2, = core - guest) = -off_gc.
Everything is read-only (no clock is changed). Output: one JSON line.
"""
from __future__ import annotations

import json, subprocess, sys, time


def best_offset(pairs):
    """pairs of (remote_ts, local_recv_ts). remote - local = offset - delay (delay >= 0) -> take the max."""
    return max(r - l for r, l in pairs) if pairs else None


def combine(off_gh, off_hc):
    """off_gh = guest - host, off_hc = host - core -> skew_s = core - guest."""
    return -(off_gh + off_hc)


def stage_emu(container: str, n: int = 40) -> int:
    loop = f"i=0; while [ $i -lt {n} ]; do date +%s.%N; i=$((i+1)); done"
    p = subprocess.Popen(["docker", "exec", container, "adb", "shell", loop], stdout=subprocess.PIPE, text=True, bufsize=1)
    pairs = []
    for line in p.stdout:
        h = time.time()
        try:
            pairs.append((float(line.strip()), h))
        except ValueError:
            continue
    p.wait()
    og = best_offset(pairs)
    if og is None:
        print("ERR no-guest-samples", flush=True)
        return 1
    print(f"G {og:.6f} n={len(pairs)}", flush=True)
    for _ in range(60):
        print(f"T {time.time():.6f}", flush=True)
        time.sleep(0.02)
    return 0


def stage_core(cmd) -> int:
    p = subprocess.Popen(cmd, stdout=subprocess.PIPE, text=True, bufsize=1)
    off_gh = None
    pairs = []
    for line in p.stdout:
        c = time.time()
        f = line.split()
        if len(f) >= 2 and f[0] == "G":
            off_gh = float(f[1])
        elif len(f) == 2 and f[0] == "T":
            pairs.append((float(f[1]), c))
    p.wait()
    off_hc = best_offset(pairs)
    if off_gh is None or off_hc is None:
        print(json.dumps({"ok": False, "off_gh": off_gh, "n_host": len(pairs)}))
        return 1
    print(json.dumps({"ok": True, "off_gh_s": round(off_gh, 6), "off_hc_s": round(off_hc, 6),
                      "skew_s": round(combine(off_gh, off_hc), 6), "n_host": len(pairs)}))
    return 0


if __name__ == "__main__":
    if len(sys.argv) >= 3 and sys.argv[1] == "emu":
        sys.exit(stage_emu(sys.argv[2]))
    if len(sys.argv) >= 4 and sys.argv[1] == "core" and sys.argv[2] == "--":
        sys.exit(stage_core(sys.argv[3:]))
    print(__doc__)
    sys.exit(2)
