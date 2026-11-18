#!/usr/bin/env python3
"""AF Diameter Rx minimal (tanpa dependensi): CER -> AAR (Media-Component VIDEO) -> [hold] -> STR.
Usage: rx-af.py --pcrf 127.0.0.7 --ue 10.45.0.2 --remote 10.10.0.3 --port 9000 --hold 30 [--qod-url http://127.0.0.1:8090]
Tidak ada secret. Origin-Host af.localdomain harus terdaftar sebagai ConnectPeer di pcrf.conf freeDiameter."""
import socket, struct, time, os, argparse, json, urllib.request, sys
V3GPP = 10415; RX = 16777236
def avp(code, data, vendor=None, mand=True):
    flags = (0x40 if mand else 0) | (0x80 if vendor else 0)
    hl = 12 if vendor else 8
    h = struct.pack('>IB', code, flags) + (hl + len(data)).to_bytes(3, 'big')
    if vendor: h += struct.pack('>I', vendor)
    return h + data + b'\0' * ((4 - len(data) % 4) % 4)
u32 = lambda c, v, vd=None: avp(c, struct.pack('>I', v), vd)
s = lambda c, v, vd=None: avp(c, v.encode(), vd)
grp = lambda c, items, vd=None: avp(c, b''.join(items), vd)
def msg(cmd, app, avps, req=True, hbh=None, e2e=None, proxiable=True):
    body = b''.join(avps); flags = (0x80 if req else 0) | (0x40 if proxiable else 0)
    hbh = hbh or int.from_bytes(os.urandom(4), 'big'); e2e = e2e or int.from_bytes(os.urandom(4), 'big')
    return struct.pack('>B', 1) + (20 + len(body)).to_bytes(3, 'big') + struct.pack('>B', flags) + cmd.to_bytes(3, 'big') + struct.pack('>III', app, hbh, e2e) + body
def parse_avps(b):
    out = []; i = 0
    while i + 8 <= len(b):
        code, fl = struct.unpack('>IB', b[i:i+5]); ln = int.from_bytes(b[i+5:i+8], 'big'); hl = 12 if fl & 0x80 else 8
        out.append((code, b[i+hl:i+ln])); i += ln + ((4 - ln % 4) % 4)
    return out
def recv(sock):
    h = b''
    while len(h) < 20:
        c = sock.recv(20 - len(h))
        if not c: raise ConnectionError('peer closed')
        h += c
    ln = int.from_bytes(h[1:4], 'big'); b = b''
    while len(b) < ln - 20:
        c = sock.recv(ln - 20 - len(b))
        if not c: raise ConnectionError('peer closed')
        b += c
    flags = h[4]; cmd = int.from_bytes(h[5:8], 'big'); app, hbh, e2e = struct.unpack('>III', h[8:20])
    return dict(req=bool(flags & 0x80), prox=bool(flags & 0x40), cmd=cmd, app=app, hbh=hbh, e2e=e2e, avps=parse_avps(b))
def rc(m):
    for c, d in m['avps']:
        if c == 268: return struct.unpack('>I', d)[0]
        if c == 297:  # Experimental-Result
            for c2, d2 in parse_avps(d):
                if c2 == 298: return struct.unpack('>I', d2)[0]
    return None
OH, OR = 'af.localdomain', 'localdomain'
def base(): return [s(264, OH), s(296, OR)]
def answer_req(sock, m, log):
    sid = [avp(263, d) for c, d in m['avps'] if c == 263]
    sock.sendall(msg(m['cmd'], m['app'], sid + [u32(268, 2001)] + base(), req=False, hbh=m['hbh'], e2e=m['e2e'], proxiable=m['prox']))
    log(f"answered peer request cmd={m['cmd']} (2001)")
def wait_ans(sock, cmd, log):
    while True:
        m = recv(sock)
        if m['req']: answer_req(sock, m, log); continue
        if m['cmd'] == cmd: return m
def main():
    ap = argparse.ArgumentParser(); ap.add_argument('--pcrf', default='127.0.0.7'); ap.add_argument('--pcrf-port', type=int, default=3868)
    ap.add_argument('--ue', required=True); ap.add_argument('--remote', required=True); ap.add_argument('--port', default='9000')
    ap.add_argument('--hold', type=float, default=30); ap.add_argument('--bw', type=int, default=5000000)
    ap.add_argument('--qod-url', default=''); a = ap.parse_args()
    t0 = time.time(); log = lambda x: print(f"[{time.time()-t0:7.3f}s] {x}", flush=True)
    sock = socket.create_connection((a.pcrf, a.pcrf_port), timeout=10); sock.settimeout(15)
    hip = avp(257, struct.pack('>H', 1) + socket.inet_aton(sock.getsockname()[0]))
    cer = msg(257, 0, base() + [hip, u32(266, 0), s(269, 'lab5g-rx-af'), u32(265, V3GPP),
                              grp(260, [u32(266, V3GPP), u32(258, RX)]), u32(258, RX)], proxiable=False)
    sock.sendall(cer); m = wait_ans(sock, 257, log)
    log(f"CEA Result-Code={rc(m)} peer={[d.decode(errors='ignore') for c, d in m['avps'] if c == 264]}")
    if rc(m) != 2001: sys.exit(2)
    sid = f"{OH};{int(time.time())};{os.getpid()}"
    msc = grp(519, [u32(509, 1, V3GPP),
        s(507, f"permit out 6 from {a.remote} {a.port} to {a.ue}", V3GPP),
        s(507, f"permit out 6 from {a.ue} to {a.remote} {a.port}", V3GPP), u32(512, 0, V3GPP)], V3GPP)
    mcd = grp(517, [u32(518, 1, V3GPP), msc, u32(520, 1, V3GPP),  # Media-Type VIDEO -> QCI 2
        u32(515, a.bw, V3GPP), u32(516, a.bw, V3GPP), u32(511, 2, V3GPP)], V3GPP)
    aar = msg(265, RX, [s(263, sid), u32(258, RX)] + base() + [s(283, 'localdomain'),
        avp(8, socket.inet_aton(a.ue)), s(504, 'lab5g-qod', V3GPP), mcd])
    ts = time.time(); sock.sendall(aar); m = wait_ans(sock, 265, log); ms = (time.time() - ts) * 1000
    log(f"AAA Result-Code={rc(m)} latency_ms={ms:.1f} session={sid}")
    ok = rc(m) == 2001; qid = None
    if ok and a.qod_url:
        body = json.dumps({"ueIpv4": a.ue, "remote": a.remote, "port": int(a.port), "source": "rx-aaa", "sessionId": sid}).encode()
        r = urllib.request.urlopen(urllib.request.Request(a.qod_url + '/qod', body, {'Content-Type': 'application/json'}), timeout=5)
        qid = json.loads(r.read().decode()); log(f"qod-adapter POST -> {qid}")
    end = time.time() + a.hold
    sock.settimeout(1)
    while time.time() < end:
        try:
            m = recv(sock)
            if m['req']: answer_req(sock, m, log)
        except socket.timeout: pass
    sock.settimeout(15)
    st = msg(275, RX, [s(263, sid)] + base() + [s(283, 'localdomain'), u32(258, RX), u32(295, 1)])
    ts = time.time(); sock.sendall(st); m = wait_ans(sock, 275, log)
    log(f"STA Result-Code={rc(m)} latency_ms={(time.time()-ts)*1000:.1f}")
    if qid:
        r = urllib.request.urlopen(urllib.request.Request(a.qod_url + '/qod/' + qid['id'], method='DELETE'), timeout=5)
        log(f"qod-adapter DELETE -> {r.read().decode()}")
    sock.sendall(msg(282, 0, base() + [u32(273, 0)], proxiable=False))  # DPR
    try: wait_ans(sock, 282, log)
    except Exception: pass
    sys.exit(0 if ok else 1)
main()
