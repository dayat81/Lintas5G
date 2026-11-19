#!/usr/bin/env python3
# qfi.py <pcap>: count GTP-U packets by (direction pdu_type, QFI, inner proto/port class, inner UE addr hash). Ethernet/lo pcap.
import struct, sys, collections, hashlib
f = open(sys.argv[1], 'rb'); gh = f.read(24)
le = gh[:4] == b'\xd4\xc3\xb2\xa1'; E = '<' if le else '>'
link = struct.unpack(E + 'I', gh[20:24])[0]
cnt = collections.Counter(); byt = collections.Counter()
def h(a): return hashlib.md5(a).hexdigest()[:6]
while True:
    ph = f.read(16)
    if len(ph) < 16: break
    _, _, incl, orig = struct.unpack(E + 'IIII', ph); p = f.read(incl)
    off = 14 if link == 1 else (16 if link == 113 else 0)
    ip = p[off:]; ihl = (ip[0] & 15) * 4
    if ip[9] != 17: continue
    udp = ip[ihl:]; g = udp[8:]
    if len(g) < 8 or (g[0] >> 5) != 1 or g[1] != 0xff: continue
    pt, q = None, None; o = 8
    if g[0] & 0x07:
        nxt = g[11]; o = 12
        while nxt:
            ln = g[o] * 4
            if nxt == 0x85: pt = g[o + 1] >> 4; q = g[o + 2] & 0x3f
            nxt = g[o + ln - 1]; o += ln
    inner = g[o:]
    if len(inner) < 20 or inner[0] >> 4 != 4: continue
    pr = inner[9]; ii = (inner[0] & 15) * 4; sp = dp = 0
    if pr in (6, 17) and len(inner) >= ii + 4: sp, dp = struct.unpack('>HH', inner[ii:ii + 4])
    ue = inner[16:20] if pt == 0 else inner[12:16]
    key = ("DL" if pt == 0 else "UL" if pt == 1 else "?", q, {1: "icmp", 6: "tcp", 17: "udp"}.get(pr, pr), min(sp, dp) if pr in (6, 17) else 0, h(ue))
    cnt[key] += 1; byt[key] += orig
print("dir QFI proto port(min) ue_hash  pkts  MB(orig)")
for k, v in sorted(cnt.items(), key=lambda x: (x[0][4], x[0][0], str(x[0][1]))):
    print(*k, v, round(byt[k] / 1e6, 2))
