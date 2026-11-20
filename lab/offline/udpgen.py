#!/usr/bin/env python3
# udpgen.py <bind_ip> <bind_port> <dst_ip> <dst_port> <pps> <seconds> [rxlog]: constant-rate UDP (200 B) for QFI timeline.
# Optional rxlog: also log every datagram received on the bound socket as "<epoch> <src_ip>" (delivery check).
import socket, sys, time, select
b, bp, d, dp, pps, dur = sys.argv[1], int(sys.argv[2]), sys.argv[3], int(sys.argv[4]), float(sys.argv[5]), float(sys.argv[6])
rx = open(sys.argv[7], 'w', buffering=1) if len(sys.argv) > 7 else None
s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM); s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1); s.bind((b, bp))
t0 = time.time(); n = 0; pl = b"x" * 200
while time.time() - t0 < dur:
    s.sendto(pl, (d, dp)); n += 1
    while True:
        w = t0 + n / pps - time.time()
        if w <= 0: break
        if rx is None: time.sleep(w); break
        r, _, _ = select.select([s], [], [], w)
        if r:
            _, a = s.recvfrom(4096); rx.write(f"{time.time():.4f} {a[0]}\n")
if rx:
    end = time.time() + 1.0
    s.settimeout(0.1)
    while time.time() < end:
        try: _, a = s.recvfrom(4096); rx.write(f"{time.time():.4f} {a[0]}\n")
        except socket.timeout: pass
