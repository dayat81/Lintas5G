#!/usr/bin/env python3
"""vm-emu dashboard collector: every INTERVAL s writes OUT (served by caddy under basic auth as /api/emu.json).
Sources: /proc/stat, /proc/loadavg, /proc/uptime, docker/adb (container state, boot_completed, Android proxy),
proxy probe from vm-emu through vm-core-ran:18080 (the emulator's path). No passwords/IMSI."""
import json, os, re, subprocess, threading, time
INTERVAL = float(os.environ.get("INTERVAL", "2")); OUT = os.environ.get("OUT", "/opt/lab5g/dash/api/emu.json")
PROXY = os.environ.get("CORE_PROXY", "http://10.10.0.3:18080"); PROXY_EVERY = float(os.environ.get("PROXY_EVERY", "10"))
COST = float(os.environ.get("COST_PER_HOUR", "0.80"))
def sh(c, t=5):
    try: return subprocess.run(c, shell=True, capture_output=True, text=True, timeout=t).stdout.strip()
    except Exception: return ""
def cpu():
    with open("/proc/stat") as f: return [int(x) for x in f.readline().split()[1:]]
probe = {"ttfb_ms": None, "code": None, "ts": 0, "ok": 0, "n": 0}
emu = {"container": None, "boot_completed": None, "android_proxy": None, "android": None, "sdk": None, "abilist": None}
EGRESS = os.environ.get("EMU_EGRESS", "ue-l3")
gpu = {"name": None, "driver": None, "util_pct": None, "mem_used_mib": None, "temp_c": None, "mode": None, "renderer": None}
def slow_loop():
    while True:
        o = sh(f"curl -s -o /dev/null -m 8 -x {PROXY} -w '%{{http_code}} %{{time_starttransfer}}' https://www.google.com/generate_204", 10).split()
        probe["n"] += 1
        if len(o) == 2 and o[0] in ("200", "204"):
            probe.update(code=int(o[0]), ttfb_ms=round(float(o[1]) * 1000, 1), ts=time.time()); probe["ok"] += 1
        else:
            probe.update(code=int(o[0]) if o and o[0].isdigit() else 0, ttfb_ms=None, ts=time.time())
        emu["container"] = sh("docker inspect -f '{{.State.Status}}' android-emu") or "absent"
        emu["boot_completed"] = sh("docker exec android-emu adb shell getprop sys.boot_completed", 8) == "1"
        emu["android_proxy"] = sh("docker exec android-emu adb shell settings get global http_proxy", 8) or None
        if emu["boot_completed"] and not emu["sdk"]:
            emu["android"] = sh("docker exec android-emu adb shell getprop ro.build.version.release", 8) or None
            emu["sdk"] = sh("docker exec android-emu adb shell getprop ro.build.version.sdk", 8) or None
            emu["abilist"] = sh("docker exec android-emu adb shell getprop ro.product.cpu.abilist", 8) or None
        q = sh("nvidia-smi --query-gpu=name,driver_version,utilization.gpu,memory.used,temperature.gpu --format=csv,noheader,nounits", 5)
        if q:
            f = [x.strip() for x in q.splitlines()[0].split(",")]
            if len(f) == 5:
                gpu.update(name=f[0], driver=f[1], util_pct=float(f[2]), mem_used_mib=float(f[3]), temp_c=float(f[4]))
        gpu["mode"] = sh("docker inspect -f '{{range .Config.Env}}{{println .}}{{end}}' android-emu | sed -n 's/^EMULATOR_GPU=//p'") or None
        if emu["boot_completed"] and not gpu["renderer"]:
            r = sh("docker exec android-emu adb shell dumpsys SurfaceFlinger | grep -m1 -i 'GLES:'", 10)
            gpu["renderer"] = r.split("GLES:", 1)[-1].strip()[:160] if r else None
        time.sleep(PROXY_EVERY)
def main():
    threading.Thread(target=slow_loop, daemon=True).start()
    prev = cpu(); os.makedirs(os.path.dirname(OUT), exist_ok=True); gprev = None
    while True:
        time.sleep(INTERVAL)
        c = cpu(); d = [a - b for a, b in zip(c, prev)]; prev = c; tot = sum(d) or 1
        up = float(open("/proc/uptime").read().split()[0]); now = time.time()
        try:
            g = (int(open("/sys/class/net/gre-core/statistics/tx_bytes").read()), int(open("/sys/class/net/gre-core/statistics/rx_bytes").read()))
        except Exception:
            g = None
        gre = {"up": g is not None, "ul_mbps": None, "dl_mbps": None}
        if g and gprev:
            gre.update(ul_mbps=round((g[0] - gprev[0]) * 8 / INTERVAL / 1e6, 3), dl_mbps=round((g[1] - gprev[1]) * 8 / INTERVAL / 1e6, 3))
        gprev = g
        st = {"ts": now, "host": "vm-emu", "interval_s": INTERVAL, "boot_epoch": round(now - up), "uptime_s": round(up),
              "cost_per_hour_usd": COST, "cost_so_far_usd_est": round(up / 3600 * COST, 2),
              "cpu": {"busy_pct": round(100.0 * (tot - d[3] - d[4]) / tot, 1), "steal_pct": round(100.0 * d[7] / tot, 1)},
              "load": os.getloadavg(), "emulator": emu, "gpu": gpu, "egress_mode": EGRESS, "gre_core": gre,
              "proxy_probe": dict(probe, age_s=round(now - probe["ts"], 1) if probe["ts"] else None)}
        tmp = OUT + ".tmp"
        with open(tmp, "w") as f: json.dump(st, f)
        os.chmod(tmp, 0o644); os.replace(tmp, OUT)
if __name__ == "__main__": main()
