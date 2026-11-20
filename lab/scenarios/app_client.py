#!/usr/bin/env python3
# app_client.py <role target|bulk> <dur> <out.csv> : stand-in apps. target: UDP echo probes 50 pps to 10.45.0.1:18080 (RTT) + TCP segment fetch 1/s.
# bulk: TCP up 5201 (6 Mbit/s), TCP down 5202, UDP echo bulk 5203 (300 pps x 1000 B) to 10.45.0.2.
import socket, sys, time, threading, struct
role, dur, out = sys.argv[1], float(sys.argv[2]), sys.argv[3]
T, B = "10.45.0.1", "10.45.0.2"; rows = []; end = time.time() + dur; lk = threading.Lock()
def log(k, t, v):
    with lk: rows.append((k, t, v))
def udp_probe(ip, port, pps, size, kind):
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM); s.settimeout(0.001); n = 0; t0 = time.time(); pend = {}
    def rx():
        while time.time() < end + 1:
            try: d, _ = s.recvfrom(4096)
            except Exception: continue
            seq = struct.unpack(">I", d[:4])[0]
            if seq in pend: log(kind, pend.pop(seq), (time.time() - pend.get(seq, 0)) if False else None)
    # simple: blocking-ish rx loop in same thread
    while time.time() < end:
        ts = time.time(); s.sendto(struct.pack(">Id", n, ts) + b"x" * (size - 12), (ip, port)); pend[n] = ts; n += 1
        nxt = t0 + n / pps
        while time.time() < nxt:
            try: d, _ = s.recvfrom(4096)
            except Exception: continue
            q, ts0 = struct.unpack(">Id", d[:12]); log(kind, ts0, (time.time() - ts0) * 1e3); pend.pop(q, None)
    tend = time.time() + 1
    while time.time() < tend:
        try: d, _ = s.recvfrom(4096)
        except Exception: continue
        q, ts0 = struct.unpack(">Id", d[:12]); log(kind, ts0, (time.time() - ts0) * 1e3)
def seg_fetch():
    while time.time() < end:
        t = time.time()
        try:
            c = socket.create_connection((T, 18080), timeout=5); n = 0
            while True:
                d = c.recv(65536)
                if not d: break
                n += len(d)
            c.close(); log("tcp_seg_ms", t, (time.time() - t) * 1e3 if n >= 150000 else -1)
        except Exception: log("tcp_seg_ms", t, -1)
        time.sleep(max(0, t + 1 - time.time()))
def tcp_up():
    try:
        c = socket.create_connection((B, 5201), timeout=5); t0 = time.time(); n = 0; blk = b"u" * 1200
        while time.time() < end:
            c.sendall(blk); n += len(blk) * 8; dt = n / 6e6 - (time.time() - t0)
            if dt > 0: time.sleep(dt)
        c.close()
    except Exception as e: log("err", time.time(), str(e))
def tcp_down():
    try:
        c = socket.create_connection((B, 5202), timeout=5); n = 0
        while time.time() < end:
            d = c.recv(65536); n += len(d)
            if not d: break
        c.close(); log("bulk_down_bytes", time.time(), n)
    except Exception as e: log("err", time.time(), str(e))
th = []
if role == "target": th = [threading.Thread(target=udp_probe, args=(T, 18080, 50, 200, "udp_rtt_ms")), threading.Thread(target=seg_fetch)]
else: th = [threading.Thread(target=tcp_up), threading.Thread(target=tcp_down), threading.Thread(target=udp_probe, args=(B, 5203, 300, 1000, "bulkudp_rtt_ms"))]
for t in th: t.start()
for t in th: t.join()
with open(out, "w") as f:
    f.write("kind,t,value\n")
    for k, t, v in sorted(rows, key=lambda r: r[1]): f.write(f"{k},{t:.6f},{v}\n")
