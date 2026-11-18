#!/usr/bin/env python3
"""Flow UDP ber-rate tetap (pengganti iperf3 UDP; firewall lab hanya membuka UDP 4789, dan iperf3 butuh kontrol TCP di port yang sama).
server (vm-emu): udp-flow.py server --port 4789
client (netns UE): udp-flow.py dl|ul --host <emu> --port 4789 --kbps 5000 --dur 30 [--size 1200]
Output JSON: sent, recv, loss_pct, goodput_kbps (payload), jitter_ms (RFC3550-ish, dl saja)."""
import socket, struct, time, sys, json, argparse, threading
HDR = struct.Struct('>4sIdI')  # magic, seq, ts_send, total
def pace(sock, addr, kbps, dur, size, magic=b'DATA'):
    iv = size * 8 / (kbps * 1000.0); n = int(dur / iv); t0 = time.time(); pad = b'\0' * (size - HDR.size)
    for i in range(n):
        t = t0 + i * iv; d = t - time.time()
        if d > 0: time.sleep(d)
        sock.sendto(HDR.pack(magic, i, time.time(), n) + pad, addr)
    return n
def server(a):
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM); s.bind(('0.0.0.0', a.port)); ul = {}
    while True:
        b, addr = s.recvfrom(65535)
        if b[:2] == b'DL':
            _, kbps, dur, size = b.decode().split()
            def run(addr=addr, kbps=int(kbps), dur=float(dur), size=int(size)):
                n = pace(s, addr, kbps, dur, size)
                for _ in range(5): s.sendto(HDR.pack(b'END_', n, time.time(), n), addr); time.sleep(0.05)
            threading.Thread(target=run, daemon=True).start()
        elif b[:4] == b'DATA':
            m, seq, ts, tot = HDR.unpack(b[:HDR.size]); st = ul.setdefault(addr, {'recv': 0, 'bytes': 0, 'first': time.time(), 'last': 0})
            st['recv'] += 1; st['bytes'] += len(b); st['last'] = time.time()
        elif b[:4] == b'ULEN':
            st = ul.pop(addr, {'recv': 0, 'bytes': 0, 'first': 0, 'last': 0}); s.sendto(json.dumps(st).encode(), addr)
def client(a):
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM); s.settimeout(1.0); addr = (a.host, a.port)
    if a.mode == 'dl':
        s.sendto(f"DL {a.kbps} {a.dur} {a.size}".encode(), addr)
        recv = 0; byt = 0; first = last = None; tot = None; jit = 0.0; prev = None; end = time.time() + a.dur + 10
        while time.time() < end:
            try: b, _ = s.recvfrom(65535)
            except socket.timeout:
                if recv == 0: s.sendto(f"DL {a.kbps} {a.dur} {a.size}".encode(), addr)
                continue
            m, seq, ts, n = HDR.unpack(b[:HDR.size]); now = time.time()
            if m == b'END_': tot = n; break
            recv += 1; byt += len(b); first = first or now; last = now; tot = n
            tr = now - ts
            if prev is not None: jit += (abs(tr - prev) - jit) / 16
            prev = tr
        dt = (last - first) if recv > 1 else 1
        r = dict(mode='dl', kbps_target=a.kbps, dur=a.dur, sent=tot, recv=recv, loss_pct=round(100 * (1 - recv / tot), 3) if tot else None,
                 goodput_kbps=round(byt * 8 / dt / 1000, 1), jitter_ms=round(jit * 1000, 3))
    else:
        n = pace(s, addr, a.kbps, a.dur, a.size); st = None
        for _ in range(5):
            s.sendto(b'ULEND', addr)
            try: st = json.loads(s.recvfrom(65535)[0].decode()); break
            except socket.timeout: pass
        dt = (st['last'] - st['first']) if st and st['recv'] > 1 else 1
        r = dict(mode='ul', kbps_target=a.kbps, dur=a.dur, sent=n, recv=st and st['recv'], loss_pct=round(100 * (1 - st['recv'] / n), 3) if st else None,
                 goodput_kbps=round(st['bytes'] * 8 / dt / 1000, 1) if st else None)
    print(json.dumps(r))
ap = argparse.ArgumentParser(); ap.add_argument('mode', choices=['server', 'dl', 'ul']); ap.add_argument('--host'); ap.add_argument('--port', type=int, default=4789)
ap.add_argument('--kbps', type=int, default=5000); ap.add_argument('--dur', type=float, default=30); ap.add_argument('--size', type=int, default=1200)
a = ap.parse_args(); server(a) if a.mode == 'server' else client(a)
