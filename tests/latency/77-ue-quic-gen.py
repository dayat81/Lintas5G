#!/usr/bin/env python3
"""poc-phase3 v2.1: generator QUIC sisi UE (netns l5g-ue, jam VM) utk validasi pktlat v2.1 TANPA emulator.
Kirim paket QUIC long-header (versi 0x1a1a1a1a, 1200 B; server membalas Version Negotiation) per flow ke tujuan internet UDP 443
lewat LTE -> CGNAT, catat t_ue UL (sebelum send) dan DL (setelah recv), hash md5(payload[0:64])[0:8], lalu kirim probe MGLT v2.1
(mode hash, flags bit1) ke PROBE_SINK:PROBE_PORT (env) seperti app v0.9.1 (tick 25 ms / 32 record, kirim ulang 1x).
t_ue ditulis = t_vm - skew_s supaya rumus Zeek (ts - t_ue - skew) = latency nyata (UE dan Zeek sama2 jam VM).
Pakai: 77-ue-quic-gen.py <skew_s> <out.json> [flows=6] [pkts=20] [gap_ms=50]"""
import socket, struct, os, time, hashlib, json, sys, threading, random, select
PROBE_SINK = os.environ.get("PROBE_SINK", "192.0.2.20")  # GANTI: IP sink probe MGLT di sisi SGi (contoh RFC 5737)
PROBE_PORT = int(os.environ.get("PROBE_PORT", "9001"))
DNS_SERVER = os.environ.get("DNS_SERVER", "8.8.8.8")
UE_PRIV_IP = os.environ.get("UE_PRIV_IP", "10.0.0.2")  # alamat tun app (hanya label di probe)
SKEW = float(sys.argv[1]); OUT = sys.argv[2]
NF = int(sys.argv[3]) if len(sys.argv) > 3 else 6; NP = int(sys.argv[4]) if len(sys.argv) > 4 else 20
GAP = (float(sys.argv[5]) if len(sys.argv) > 5 else 50) / 1000
def crc32c(b):
    c = 0xffffffff
    for x in b:
        c ^= x
        for _ in range(8): c = (c >> 1) ^ (0x82F63B78 if c & 1 else 0)
    return c ^ 0xffffffff
def dns(name):
    q = struct.pack(">HHHHHH", random.randrange(65536), 0x0100, 1, 0, 0, 0) + b"".join(bytes([len(p)]) + p.encode() for p in name.split(".")) + b"\0" + struct.pack(">HH", 1, 1)
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM); s.settimeout(4); s.sendto(q, (DNS_SERVER, 53)); d, _ = s.recvfrom(2000)
    an = struct.unpack(">H", d[6:8])[0]; i = len(q); ips = []
    for _ in range(an):
        i += 2 if d[i] & 0xc0 == 0xc0 else d.index(b"\0", i) + 1 - i
        typ, cls, ttl, rl = struct.unpack(">HHIH", d[i:i + 10]); i += 10
        if typ == 1 and rl == 4: ips.append(socket.inet_ntoa(d[i:i + 4]))
        i += rl
    return ips
def tns(): return time.time_ns() - int(SKEW * 1e9)
H = lambda p: hashlib.md5(p[:64]).digest()[:8]
probe = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
lock = threading.Lock(); stats = {"probes": 0, "probe_bytes": 0, "ul": 0, "dl": 0, "ul_bytes": 0, "dl_bytes": 0}
class Fl:
    def __init__(s, fid, ip):
        s.fid = fid; s.ip = ip; s.sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM); s.sock.connect((ip, 443))
        s.neu = []; s.prev = []; s.pseq = 0; s.tconn = tns(); s.recs = []
    def rec(s, typ, h, n, t):
        with lock:
            s.neu.append((typ, h, n, t)); s.recs.append({"t": typ, "h": h.hex(), "len": n, "t_ue": t})
            if len(s.neu) >= 32: s.send()
    def send(s):
        n = len(s.neu) + len(s.prev)
        if n == 0: return
        sp = s.sock.getsockname()[1]
        b = bytearray(b"MGLT" + bytes([2, 0x02]) + struct.pack(">HIIQQ", 52, s.fid, s.pseq, tns(), s.tconn) + bytes([17, n, 20, 0])
                      + socket.inet_aton(UE_PRIV_IP) + struct.pack(">H", sp) + socket.inet_aton(s.ip) + struct.pack(">H", 443))
        b += struct.pack(">I", crc32c(bytes(b[:48])))
        for pas, lst in ((0, s.neu), (1, s.prev)):
            for typ, h, ln, t in lst: b += struct.pack(">BBH", typ, pas, ln) + h + struct.pack(">Q", t)
        probe.sendto(bytes(b), (PROBE_SINK, PROBE_PORT)); stats["probes"] += 1; stats["probe_bytes"] += len(b)
        s.pseq += 1; s.prev = s.neu; s.neu = []
targets = []
for h in ("www.google.com", "www.youtube.com", "cloudflare-quic.com"):
    try: targets += [(h, ip) for ip in dns(h)[:2]]
    except Exception as e: print("dns", h, e)
flows = [Fl(random.getrandbits(32), targets[i % len(targets)][1]) for i in range(NF)]
run = True
def ticker():
    while run:
        time.sleep(0.025)
        with lock:
            for f in flows: f.send()
def rx():
    m = {f.sock.fileno(): f for f in flows}
    while run:
        r, _, _ = select.select(list(m), [], [], 0.2)
        for fd in r:
            f = m[fd]; d = f.sock.recv(4096); t = tns(); stats["dl"] += 1; stats["dl_bytes"] += len(d); f.rec(2, H(d), len(d), t)
threading.Thread(target=ticker, daemon=True).start(); threading.Thread(target=rx, daemon=True).start()
for k in range(NP):
    for f in flows:
        p = bytes([0xc0]) + bytes.fromhex("1a1a1a1a") + bytes([8]) + os.urandom(8) + bytes([8]) + os.urandom(8) + os.urandom(1200 - 23)
        t = tns(); f.sock.send(p); stats["ul"] += 1; stats["ul_bytes"] += len(p); f.rec(1, H(p), len(p), t)
    time.sleep(GAP)
time.sleep(1.5); run = False; time.sleep(0.1)
with lock:
    for f in flows: f.send(); f.send()
json.dump({"skew": SKEW, "stats": stats, "targets": targets, "flows": [{"fid": "%08x" % f.fid, "dst": f.ip, "recs": f.recs} for f in flows]}, open(OUT, "w"))
print(json.dumps(stats), "flows", len(flows), "targets", targets)
