#!/usr/bin/env python3
# qfi_timeline.py <pcap> <events.jsonl> <ue1_ip> <ue2_ip>: per-flow QFI over time from N3 GTP-U (lo pcap), apply/remove latency.
import struct, sys, json, collections, os
TU = os.environ.get("TARGET_UE", "ue1")
pc, evf, ue1, ue2 = sys.argv[1:5]
ip2b = lambda s: bytes(int(x) for x in s.split('.'))
U = {ip2b(ue1): "ue1", ip2b(ue2): "ue2"}
f = open(pc, 'rb'); gh = f.read(24); E = '<' if gh[:4] in (b'\xd4\xc3\xb2\xa1', b'\x4d\x3c\xb2\xa1') else '>'
nano = gh[:4] in (b'\x4d\x3c\xb2\xa1', b'\xa1\xb2\x3c\x4d'); link = struct.unpack(E + 'I', gh[20:24])[0]
pk = []
while True:
    ph = f.read(16)
    if len(ph) < 16: break
    s, us, incl, orig = struct.unpack(E + 'IIII', ph); p = f.read(incl); t = s + us / (1e9 if nano else 1e6)
    off = 14 if link == 1 else (16 if link == 113 else (4 if link == 0 else 0)); ip = p[off:]
    if len(ip) < 28 or ip[9] != 17: continue
    g = ip[(ip[0] & 15) * 4 + 8:]
    if len(g) < 8 or (g[0] >> 5) != 1 or g[1] != 0xff: continue
    pt = q = None; o = 8
    if g[0] & 0x07:
        nxt = g[11]; o = 12
        while nxt and o < len(g):
            ln = g[o] * 4
            if nxt == 0x85: pt = g[o + 1] >> 4; q = g[o + 2] & 0x3f
            nxt = g[o + ln - 1]; o += ln
    inner = g[o:]
    if len(inner) < 20 or inner[0] >> 4 != 4: continue
    pr = inner[9]; ii = (inner[0] & 15) * 4; sp = dp = 0
    if pr in (6, 17) and len(inner) >= ii + 4: sp, dp = struct.unpack('>HH', inner[ii:ii + 4])
    d = "DL" if pt == 0 else "UL"
    ue = U.get(bytes(inner[16:20] if d == "DL" else inner[12:16]), "?")
    asport = sp if d == "DL" else dp
    pk.append((t, d, q, {1: "icmp", 6: "tcp", 17: "udp"}.get(pr, pr), asport if pr in (6, 17) else 0, ue))
ev = [json.loads(l) for l in open(evf)]
tc = next((e['t0'] for e in ev if e['ev'] == 'n5_create'), None); td = next((e['t0'] for e in ev if e['ev'] == 'n5_delete'), None)
c = collections.Counter((d, q, pr, port, ue, "pre" if tc and t < tc else ("on" if td and t < td else "post")) for t, d, q, pr, port, ue in pk)
print("dir QFI proto as_port ue phase pkts")
for k, v in sorted(c.items(), key=lambda x: (x[0][4], x[0][3], x[0][0], x[0][5], str(x[0][1])) ): print(*k, v)
def first(cond, after):
    return next((t for t, *r in pk if t >= after and cond(*r)), None)
res = {}
if tc:
    for d in ("DL", "UL"):
        for pr in ("udp", "tcp"):
            t1 = first(lambda dd, q, ppr, port, ue: dd == d and ppr == pr and port == 18080 and ue == TU and q not in (None, 1), tc)
            res[f"apply_{d}_{pr}_ms"] = round((t1 - tc) * 1e3, 1) if t1 else None
if td:
    for d in ("DL", "UL"):
        for pr in ("udp", "tcp"):
            last = max((t for t, dd, q, ppr, port, ue in pk if dd == d and ppr == pr and port == 18080 and ue == TU and q not in (None, 1)), default=None)
            t2 = first(lambda dd, q, ppr, port, ue: dd == d and ppr == pr and port == 18080 and ue == TU and q == 1, td)
            res[f"remove_{d}_{pr}_ms(last_newQFI,first_QFI1)"] = (round((last - td) * 1e3, 1) if last else None, round((t2 - td) * 1e3, 1) if t2 else None)
print(json.dumps(res, indent=1))
