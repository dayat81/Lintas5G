#!/usr/bin/env python3
# AS-side servers (run inside mq-lab). T=10.45.0.1 (target AS): UDP echo :18080, TCP :18080 sends 150 KB per connect.
# B=10.45.0.2 (bulk AS): TCP sink :5201, TCP source :5202 (rate-capped), UDP echo :5203.
import socket, threading, time, sys
T, B = "10.45.0.1", "10.45.0.2"; RATE = float(sys.argv[1]) if len(sys.argv) > 1 else 6e6
def udp_echo(ip, port):
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM); s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1); s.bind((ip, port))
    while True:
        d, a = s.recvfrom(4096); s.sendto(d, a)
def tcp_srv(ip, port, handler):
    s = socket.socket(); s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1); s.bind((ip, port)); s.listen(16)
    while True:
        c, a = s.accept(); threading.Thread(target=handler, args=(c,), daemon=True).start()
def seg(c):
    try:
        c.settimeout(5); c.sendall(b"v" * 150000); c.shutdown(socket.SHUT_WR); c.recv(10)
    except Exception: pass
    c.close()
def sink(c):
    try:
        while c.recv(65536): pass
    except Exception: pass
    c.close()
def src(c):
    try:
        t0 = time.time(); n = 0; blk = b"b" * 1200
        while True:
            c.sendall(blk); n += len(blk)*8
            dt = n / RATE - (time.time() - t0)
            if dt > 0: time.sleep(dt)
    except Exception: pass
    c.close()
for f, a in ((udp_echo, (T, 18080)), (udp_echo, (B, 5203)), (udp_echo, ("10.45.0.3", 9000)), (tcp_srv, (T, 18080, seg)), (tcp_srv, (B, 5201, sink)), (tcp_srv, (B, 5202, src))):
    threading.Thread(target=f, args=a, daemon=True).start()
print("as up", flush=True); time.sleep(3600)
