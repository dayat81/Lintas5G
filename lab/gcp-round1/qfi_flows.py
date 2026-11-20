#!/usr/bin/env python3
"""qfi_flows.py <n3.pcap> <boost_from> <boost_to> [t_bulk_on]: GTP-U packets per phase x dir x peer class x proto/port x QFI. No UE IP printed."""
import struct, sys, collections
sys.path.insert(0, "/opt/booster/qod")
from qod_adapter.n3watch import parse
P, B0, B1 = sys.argv[1], float(sys.argv[2]), float(sys.argv[3]); L = float(sys.argv[4]) if len(sys.argv) > 4 else 0
def cls(peer, pr, port):
    ip = ".".join(str(b) for b in peer) if isinstance(peer, (bytes, bytearray)) else str(peer)
    if ip == "10.99.9.20": return "reflector:%s" % port if port in (443, 9000, 9001) else "backend:%s" % port
    if ip == "10.45.0.1": return "bulk/core:%s" % port
    if ip in ("8.8.8.8",): return "dns/keepalive"
    return "internet:%s" % port
f = open(P, "rb"); gh = f.read(24); E = "<" if gh[:4] in (b"\xd4\xc3\xb2\xa1", b"\x4d\x3c\xb2\xa1") else ">"
nano = gh[:4] in (b"\x4d\x3c\xb2\xa1", b"\xa1\xb2\x3c\x4d"); link = struct.unpack(E + "I", gh[20:24])[0]; off = {1: 14, 113: 16, 0: 4}.get(link, 0)
c = collections.Counter(); first = {}
while True:
    h = f.read(16)
    if len(h) < 16: break
    s, us, incl, _ = struct.unpack(E + "IIII", h); p = f.read(incl); r = parse(p, off)
    if not r: continue
    t = s + us / (1e9 if nano else 1e6); d, q, ue, peer, pr, port = r
    ph = ("boost" if B0 <= t < B1 else "noboost") + ("+load" if L and t >= L else "")
    k = (ph, d, cls(peer, pr, port), {1: "icmp", 6: "tcp", 17: "udp"}.get(pr, str(pr)), q); c[k] += 1
    if q not in (1, None, -1) and (d, k[2]) not in first: first[(d, k[2])] = round(t - B0, 3)
for k in sorted(c, key=lambda k: (k[0], k[1], k[2], k[3], str(k[4]))):
    if c[k] >= 20 or (k[4] not in (1, None, -1)): print(*k, c[k], sep="\t")
print("first_qfi!=1_rel_boost_s", first)
