#!/usr/bin/env python3
"""vm-core-ran dashboard collector (GUI session).
Every INTERVAL s builds status.json and serves it over HTTP on the INTERNAL IP only (default port 8099,
firewall: lab5g-allow-internal = 10.10.0.0/16). Never contains IMSI/KEY/OPC/passwords.
Sources: keepalive.log (UE ping 8.8.8.8), netns ue1 tun_srsue, /sys/class/net/ogstun counters,
watchdog.log, systemctl, /proc/stat + /proc/loadavg + /proc/uptime, proxy probe via gost (10.200.0.2:8080)."""
import json, os, re, subprocess, threading, time, socket
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

INTERVAL = float(os.environ.get("INTERVAL", "2"))
PORT = int(os.environ.get("PORT", "8099"))
PROXY_EVERY = float(os.environ.get("PROXY_EVERY", "10"))
L = "/var/log/lab5g"
UNITS = ["lab5g-enb", "lab5g-ue", "lab5g-keepalive", "lab5g-gost-ue", "open5gs-mmed", "open5gs-sgwcd",
         "open5gs-sgwud", "open5gs-smfd", "open5gs-upfd", "open5gs-hssd", "lab5g-watchdog.timer"]
REDACT = re.compile(r"\b\d{15}\b")
state = {"json": b"{}"}

def sh(cmd, t=5):
    try:
        return subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=t).stdout
    except Exception:
        return ""

def internal_ip():
    out = sh("ip -4 -o addr show ens4")
    m = re.search(r"inet (\d+\.\d+\.\d+\.\d+)", out)
    return m.group(1) if m else "127.0.0.1"

def tail(path, n):
    try:
        with open(path, "rb") as f:
            f.seek(0, 2); size = f.tell(); f.seek(max(0, size - 200 * n))
            return f.read().decode(errors="replace").splitlines()[-n:]
    except Exception:
        return []

def cpu_sample():
    with open("/proc/stat") as f:
        v = [int(x) for x in f.readline().split()[1:]]
    return v

def ping_stats():
    lines = tail(f"{L}/keepalive.log", 90)
    seqs, rtts = [], []
    for l in lines:
        m = re.search(r"icmp_seq=(\d+).*time=([\d.]+)", l)
        if m:
            seqs.append(int(m.group(1))); rtts.append(float(m.group(2)))
    loss = None
    if len(seqs) > 1:
        span = seqs[-1] - seqs[0] + 1
        loss = round(100.0 * (span - len(seqs)) / span, 2) if span > 0 else None
    last_ts = None
    for l in reversed(lines):
        m = re.match(r"\[(\d+\.\d+)\]", l)
        if m and "time=" in l:
            last_ts = float(m.group(1)); break
    return {"rtt_ms": rtts[-60:], "loss_pct_window": loss, "window_n": len(rtts),
            "last_reply_age_s": round(time.time() - last_ts, 1) if last_ts else None}

proxy = {"ttfb_ms": None, "code": None, "ts": 0}
def proxy_probe():
    while True:
        out = sh("curl -s -o /dev/null -m 8 -x http://10.200.0.2:8080 -w '%{http_code} %{time_starttransfer}' "
                 "https://www.google.com/generate_204", 10).split()
        if len(out) == 2:
            proxy.update(code=int(out[0]), ttfb_ms=round(float(out[1]) * 1000, 1), ts=time.time())
        else:
            proxy.update(code=0, ttfb_ms=None, ts=time.time())
        time.sleep(PROXY_EVERY)

def collect():
    prev_cpu = cpu_sample(); prev_net = None; prev_t = time.time()
    while True:
        time.sleep(INTERVAL)
        now = time.time(); dt = now - prev_t; prev_t = now
        c = cpu_sample(); d = [a - b for a, b in zip(c, prev_cpu)]; prev_cpu = c; tot = sum(d) or 1
        cpu = {"busy_pct": round(100.0 * (tot - d[3] - d[4]) / tot, 1), "steal_pct": round(100.0 * d[7] / tot, 1),
               "iowait_pct": round(100.0 * d[4] / tot, 1)}
        try:
            rx = int(open("/sys/class/net/ogstun/statistics/rx_bytes").read())
            tx = int(open("/sys/class/net/ogstun/statistics/tx_bytes").read())
        except Exception:
            rx = tx = None
        thr = {"dl_mbps": None, "ul_mbps": None}
        try:
            grx = int(open("/sys/class/net/gre-emu/statistics/rx_bytes").read()); gtx = int(open("/sys/class/net/gre-emu/statistics/tx_bytes").read())
        except Exception:
            grx = gtx = None
        if rx is not None and prev_net:
            thr = {"dl_mbps": round((tx - prev_net[1]) * 8 / dt / 1e6, 3), "ul_mbps": round((rx - prev_net[0]) * 8 / dt / 1e6, 3)}
        prev_net = (rx, tx) if rx is not None else None
        gre = {"up": grx is not None, "emu_to_ue_mbps": None, "ue_to_emu_mbps": None}
        if grx is not None and state.get("gre_prev"):
            gre.update(emu_to_ue_mbps=round((grx - state["gre_prev"][0]) * 8 / dt / 1e6, 3), ue_to_emu_mbps=round((gtx - state["gre_prev"][1]) * 8 / dt / 1e6, 3))
        state["gre_prev"] = (grx, gtx) if grx is not None else None
        ue = sh("ip netns exec ue1 ip -4 -br addr show tun_srsue")
        m = re.search(r"(10\.45\.\d+\.\d+)", ue)
        mtu = re.search(r"mtu (\d+)", sh("ip netns exec ue1 ip link show tun_srsue"))
        units = {}
        for u in UNITS:
            units[u] = sh(f"systemctl is-active {u}").strip() or "unknown"
        wd = [REDACT.sub("IMSI_REDACTED", re.sub(r"IMSI\[[^\]]*\]", "IMSI[REDACTED]", l)) for l in tail(f"{L}/watchdog.log", 8)]
        reattach = sum(1 for l in tail(f"{L}/watchdog.log", 2000) if "REATTACH mulai" in l)
        qdisc = sh("tc qdisc show dev ogstun").split("\n")[0][:80]
        up = float(open("/proc/uptime").read().split()[0])
        try:
            phase = open("/run/lab5g-phase").read().strip()
        except Exception:
            phase = "unknown"
        st = {"ts": now, "host": "vm-core-ran", "phase": phase, "interval_s": INTERVAL,
              "boot_epoch": round(now - up), "uptime_s": round(up),
              "ue": {"attached": bool(m), "ip": m.group(1) if m else None, "tun_mtu": int(mtu.group(1)) if mtu else None},
              "ping": ping_stats(), "throughput_ogstun": thr, "gre_emu": gre, "units": units,
              "watchdog": {"recent": wd, "reattach_total": reattach},
              "proxy": dict(proxy, age_s=round(now - proxy["ts"], 1) if proxy["ts"] else None),
              "cpu": cpu, "load": os.getloadavg(), "ogstun_qdisc": qdisc}
        state["json"] = json.dumps(st).encode()

class H(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path.split("?")[0] not in ("/status.json", "/"):
            self.send_error(404); return
        b = state["json"]
        self.send_response(200); self.send_header("Content-Type", "application/json")
        self.send_header("Cache-Control", "no-store"); self.send_header("Content-Length", str(len(b)))
        self.end_headers(); self.wfile.write(b)
    def log_message(self, *a):
        pass

if __name__ == "__main__":
    threading.Thread(target=collect, daemon=True).start()
    threading.Thread(target=proxy_probe, daemon=True).start()
    ThreadingHTTPServer((os.environ.get("BIND", internal_ip()), PORT), H).serve_forever()
