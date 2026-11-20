#!/usr/bin/env python3
"""Stand-in for v0.10.2 Mglt.java: MGLT v1 60 B marker per flow event (syn/est/data/fin; udp) as a SEPARATE UDP datagram to the
reflector (default 10.45.0.3:9000 = stand-in for 10.99.9.20:9000), sent from a socket that bypasses the TUN (protect()+bind).
Triggered by FLOW lines of the relay log (= flows of the allowed apps in the examine TUN). Writes RTT CSV. Layout per Mglt.java header."""
import socket, struct, sys, time, re, threading, zlib
log, out, dur, refhost = sys.argv[1], sys.argv[2], float(sys.argv[3]), (sys.argv[4] if len(sys.argv) > 4 else "10.45.0.3")
def crc32c(b):
    c = 0xFFFFFFFF
    for x in b:
        c ^= x
        for _ in range(8): c = (c >> 1) ^ (0x82F63B78 if c & 1 else 0)
    return (~c) & 0xFFFFFFFF
s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM); s.connect((refhost, 9000)); s.settimeout(0.002)
end = time.time() + dur; rows = []; fid = [0]; lk = threading.Lock(); pend = {}
def send(proto, ev, dip, dport, flow, seq):
    t = time.time(); b = bytearray(60); b[0:4] = b"MGLT"; b[4] = 1; b[5] = 0x20; b[6] = 60
    struct.pack_into(">II", b, 8, flow, seq); struct.pack_into(">QI", b, 16, int(t * 1e9), int(time.monotonic() * 1e6) & 0xffffffff)
    struct.pack_into(">I", b, 28, crc32c(bytes(b[:28]))); b[32] = 1; b[33] = proto; b[34] = ev
    b[42:46] = socket.inet_aton(dip); struct.pack_into(">H", b, 46, dport)
    with lk: pend[(flow, seq)] = t
    s.send(bytes(b)); return t
def life(proto, dip, dport, flow):
    evs = [(0, 1), (0.02, 2), (0.1, 3), (0.9, 4)] if proto == 6 else [(0, 5), (1.0, 3), (2.0, 3)]
    for i, (dt, ev) in enumerate(evs):
        time.sleep(dt if i == 0 else dt - evs[i - 1][0]); send(proto, ev, dip, dport, flow, i)
def rx():
    while time.time() < end + 1:
        try: d = s.recv(2048)
        except Exception: continue
        flow, seq = struct.unpack(">II", d[8:16])
        with lk: t0 = pend.pop((flow, seq), None)
        if t0: rows.append((t0, (time.time() - t0) * 1e3))
threading.Thread(target=rx, daemon=True).start()
seen = 0; pos = 0
while time.time() < end:
    with open(log) as f: lines = f.readlines()
    for l in lines[pos:]:
        m = re.match(r"FLOW t=([\d.]+) proto=(\w+) dst=([\d.]+):(\d+)", l)
        if m:
            fid[0] += 1; threading.Thread(target=life, args=(6 if m[2] == "tcp" else 17, m[3], int(m[4]), fid[0]), daemon=True).start()
    pos = len(lines); time.sleep(0.05)
time.sleep(1.5)
with open(out, "w") as f:
    f.write("kind,t,value\n")
    for t, v in sorted(rows): f.write(f"marker_rtt_ms,{t:.6f},{v:.3f}\n")
