#!/usr/bin/env python3
# probe.py <srv> <port> <secs> <pps> <out.json>: app-level UDP RTT probe (seq + send time, 64 B), p50/p90/p99/max, loss.
# Late replies (> 5 s) count as lost.
import socket, sys, time, json, struct, threading
srv, port, secs, pps, out = sys.argv[1], int(sys.argv[2]), float(sys.argv[3]), int(sys.argv[4]), sys.argv[5]
s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM); s.settimeout(0.5)
sent = {}; rtt = []; stop = [False]
def rx():
    while not stop[0]:
        try: d, _ = s.recvfrom(2048)
        except socket.timeout: continue
        q, t = struct.unpack('!Id', d[:12]); r = time.monotonic() - t
        if q in sent and r < 5: rtt.append(r * 1000); sent.pop(q, None)
th = threading.Thread(target=rx, daemon=True); th.start()
n = int(secs * pps); t0 = time.monotonic()
for q in range(n):
    tgt = t0 + q / pps; dt = tgt - time.monotonic()
    if dt > 0: time.sleep(dt)
    sent[q] = 1; s.sendto(struct.pack('!Id', q, time.monotonic()) + b'x' * 52, (srv, port))
time.sleep(5.5); stop[0] = True; th.join(1)
rtt.sort()
def pct(p): return round(rtt[min(len(rtt) - 1, int(p / 100 * len(rtt)))], 2) if rtt else None
json.dump({"port": port, "sent": n, "recv": len(rtt), "loss_pct": round(100 * (n - len(rtt)) / max(n, 1), 2),
           "p50_ms": pct(50), "p90_ms": pct(90), "p99_ms": pct(99), "max_ms": round(rtt[-1], 2) if rtt else None}, open(out, "w"))
