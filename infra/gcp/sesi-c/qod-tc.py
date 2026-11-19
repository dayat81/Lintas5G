#!/usr/bin/env python3
"""Adapter QoD minimal -> tc HTB (USULAN PoC). Penegakan di SGi (ogstun), bukan di UPF (Sesi A: UPF 2.8.0 tidak menegakkan MBR QER).
  DL = egress ogstun (paket menuju UE). UL = ingress ogstun -> mirred -> ifb0.
  HTB: 1:1 (bottleneck R) -> 1:10 prio0 (QoD, pfifo 100) + 1:20 prio1 default (bulk, pfifo DEPTH).
  setup:  qod-tc.py setup --dl 15mbit --ul 8mbit --depth 300
  serve:  qod-tc.py serve --listen 127.0.0.1:8090 --dl 15mbit --ul 8mbit  (POST /qod {ueIpv4,remote,port,gbrKbps} ; DELETE /qod/<id> ; GET /qod)
  Sesi C: filter juga UDP (proto 17) di port flow; reservasi GBR: rate kelas 1:10 = max(30% R, sum gbrKbps aktif), maks 80% R;
  kelas bulk 1:20 = R - rate QoD. gbrKbps=0 -> perilaku Sesi B (rate statis 30%).
  clear:  qod-tc.py clear
Trigger: curl manual (AF), atau rx-af.py setelah AAA Rx 2001. Latency apply/remove dicatat di /var/log/lab5g/tc/adapter.log."""
import sys, json, time, subprocess, argparse, threading, os
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
IF, IFB = 'ogstun', 'ifb0'; LOG = '/var/log/lab5g/tc/adapter.log'
def sh(cmd, check=True):
    r = subprocess.run(cmd, shell=True, capture_output=True, text=True)
    if check and r.returncode: raise RuntimeError(f"{cmd}: {r.stderr.strip()}")
    return r.stdout
def log(o):
    os.makedirs(os.path.dirname(LOG), exist_ok=True)
    o['ts'] = time.strftime('%F %T') + f".{int(time.time()*1000)%1000:03d}"
    open(LOG, 'a').write(json.dumps(o) + '\n'); print(json.dumps(o), flush=True)
def htb(dev, rate, depth):
    sh(f"tc qdisc replace dev {dev} root handle 1: htb default 20 r2q 10")
    sh(f"tc class replace dev {dev} parent 1: classid 1:1 htb rate {rate} ceil {rate}")
    sh(f"tc class replace dev {dev} parent 1:1 classid 1:10 htb rate {pct(rate,.3)} ceil {rate} prio 0")
    sh(f"tc class replace dev {dev} parent 1:1 classid 1:20 htb rate {pct(rate,.7)} ceil {rate} prio 1")
    sh(f"tc qdisc replace dev {dev} parent 1:10 handle 10: pfifo limit 100")
    sh(f"tc qdisc replace dev {dev} parent 1:20 handle 20: pfifo limit {depth}")
def pct(rate, f):
    n = float(rate.rstrip('mbit')); return f"{n*f:.2f}mbit"
def setup(a):
    clear(None)
    sh("modprobe ifb numifbs=1"); sh(f"ip link add {IFB} type ifb", check=False); sh(f"ip link set {IFB} up")
    htb(IF, a.dl, a.depth)
    sh(f"tc qdisc replace dev {IF} handle ffff: ingress")
    sh(f"tc filter replace dev {IF} parent ffff: protocol ip prio 1 u32 match u32 0 0 action mirred egress redirect dev {IFB}")
    htb(IFB, a.ul, a.depth)
    log({"event": "setup", "dl": a.dl, "ul": a.ul, "depth": a.depth})
def clear(a):
    for d in (IF, IFB): sh(f"tc qdisc del dev {d} root", check=False)
    sh(f"tc qdisc del dev {IF} ingress", check=False)
SESS = {}; LOCK = threading.Lock(); NEXT = [100]; RATES = {}; HEADROOM = float(os.environ.get("QOD_GBR_HEADROOM", "1.1"))  # overhead IP/UDP/TCP di atas goodput GBR
def mbit(r): return float(r.rstrip('mbit'))
def reserve():
    tot = sum(int(x.get('gbrKbps', 0) or 0) for x in SESS.values())
    out = {}
    for dev, R in ((IF, RATES.get('dl', '15mbit')), (IFB, RATES.get('ul', '8mbit'))):
        rk = int(mbit(R) * 1000); q = min(max(int(tot * HEADROOM), int(rk * .3)), int(rk * .8))
        sh(f"tc class change dev {dev} parent 1:1 classid 1:10 htb rate {q}kbit ceil {R} prio 0")
        sh(f"tc class change dev {dev} parent 1:1 classid 1:20 htb rate {rk-q}kbit ceil {R} prio 1")
        out[dev] = q
    return out
def add(req):
    t0 = time.perf_counter()
    ue, rem, port = req['ueIpv4'], req['remote'], int(req.get('port', 9000))
    with LOCK: pref = NEXT[0]; NEXT[0] += 1
    # DL (ogstun egress): remote -> UE ; UL (ifb0): UE -> remote. TCP port app + ICMP (probe ping).
    # remote: IPv4 (/32), CIDR, or "any" (Sesi D: QUIC udp/443 to any internet server)
    rc = None if rem in ("any", "0.0.0.0/0") else (rem if "/" in rem else f"{rem}/32")
    for dev, m in ((IF, (f"match ip src {rc} " if rc else "") + f"match ip dst {ue}/32"), (IFB, f"match ip src {ue}/32" + (f" match ip dst {rc}" if rc else ""))):
        pm = "sport" if dev == IF else "dport"
        sh(f"tc filter add dev {dev} parent 1: protocol ip prio {pref} u32 {m} match ip protocol 6 0xff match ip {pm} {port} 0xffff flowid 1:10")
        sh(f"tc filter add dev {dev} parent 1: protocol ip prio {pref} u32 {m} match ip protocol 17 0xff match ip {pm} {port} 0xffff flowid 1:10")
        sh(f"tc filter add dev {dev} parent 1: protocol ip prio {pref} u32 {m} match ip protocol 1 0xff flowid 1:10")
    ms = (time.perf_counter() - t0) * 1000
    sid = f"qod-{pref}"; SESS[sid] = dict(req, pref=pref, applied=time.time())
    t1 = time.perf_counter(); rs = reserve(); rms = (time.perf_counter() - t1) * 1000
    log({"event": "apply", "id": sid, "source": req.get("source", "manual"), "ue": ue, "remote": rem, "port": port, "gbr_kbps": int(req.get('gbrKbps', 0) or 0), "qod_rate_kbit": rs, "apply_ms": round(ms, 2), "reserve_ms": round(rms, 2)})
    return {"id": sid, "apply_ms": round(ms, 2), "reserve_ms": round(rms, 2), "qod_rate_kbit": rs}
def rem(sid):
    t0 = time.perf_counter(); s = SESS.pop(sid)
    for dev in (IF, IFB): sh(f"tc filter del dev {dev} parent 1: protocol ip prio {s['pref']}")
    ms = (time.perf_counter() - t0) * 1000; rs = reserve()
    log({"event": "remove", "id": sid, "source": s.get("source", "manual"), "remove_ms": round(ms, 2), "held_s": round(time.time() - s['applied'], 1), "qod_rate_kbit": rs})
    return {"id": sid, "remove_ms": round(ms, 2)}
class H(BaseHTTPRequestHandler):
    def _j(self, code, o):
        b = json.dumps(o).encode(); self.send_response(code); self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(b))); self.end_headers(); self.wfile.write(b)
    def do_POST(self):
        try: self._j(201, add(json.loads(self.rfile.read(int(self.headers['Content-Length'])))))
        except Exception as e: self._j(400, {"error": str(e)})
    def do_DELETE(self):
        sid = self.path.rsplit('/', 1)[-1]
        if sid == 'qod':
            self._j(200, [rem(k) for k in list(SESS)]); return
        self._j(200, rem(sid)) if sid in SESS else self._j(404, {"error": "not found"})
    def do_GET(self): self._j(200, SESS)
    def log_message(self, *a): pass
def serve(a):
    RATES['dl'], RATES['ul'] = a.dl, a.ul
    h, p = a.listen.split(':'); ThreadingHTTPServer((h, int(p)), H).serve_forever()
ap = argparse.ArgumentParser(); sp = ap.add_subparsers(dest='cmd', required=True)
s1 = sp.add_parser('setup'); s1.add_argument('--dl', default='15mbit'); s1.add_argument('--ul', default='8mbit'); s1.add_argument('--depth', type=int, default=300)
s2 = sp.add_parser('serve'); s2.add_argument('--listen', default='127.0.0.1:8090'); s2.add_argument('--dl', default='15mbit'); s2.add_argument('--ul', default='8mbit'); sp.add_parser('clear')
a = ap.parse_args(); {'setup': setup, 'serve': serve, 'clear': clear}[a.cmd](a)
