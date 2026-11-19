#!/usr/bin/env python3
"""Sesi D (netns ue1): deterministic QUIC wire traffic for per-packet tests, no app needed.
Each flow sends QUIC long-header Initial-sized datagrams (1200 B, reserved/grease version 0x?a?a?a?a) to a public QUIC server
on udp/443; the server answers with a Version Negotiation packet -> real QUIC packets in BOTH directions through UE->eNB->EPC.
Writes per-packet app-side RTT (send -> VN receive, same host clock as the Zeek taps) and a JSON summary.
usage: quic-gen.py --out <prefix> [--dur 120] [--pps 20] [--targets www.google.com,cloudflare-quic.com,www.youtube.com]"""
import argparse, json, os, random, select, socket, struct, time
ap = argparse.ArgumentParser(); ap.add_argument('--out', required=True); ap.add_argument('--dur', type=float, default=120)
ap.add_argument('--pps', type=float, default=20); ap.add_argument('--targets', default='www.google.com,cloudflare-quic.com,www.youtube.com')
a = ap.parse_args()
def dns(name):
    try: return socket.gethostbyname(name)
    except Exception: return None
flows = []
for i, n in enumerate(a.targets.split(',')):
    ip = dns(n)
    if not ip: continue
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM); s.connect((ip, 443)); s.setblocking(False)
    flows.append({'name': n, 'ip': ip, 'sock': s, 'sent': {}, 'rtt': [], 'tx': 0, 'rx': 0})
assert flows, 'no QUIC target resolvable'
def pkt(seq):
    ver = random.choice([0x1a1a1a1a, 0x2a2a2a2a, 0x3a3a3a3a])
    dcid, scid = os.urandom(8), os.urandom(8)
    hdr = bytes([0xc0]) + struct.pack('>I', ver) + bytes([8]) + dcid + bytes([8]) + scid
    return hdr + struct.pack('>I', seq) + os.urandom(1200 - len(hdr) - 4), dcid, scid
iv = 1.0 / a.pps; t0 = time.time(); nxt = t0; seq = 0; csv = open(a.out + '-rtt.csv', 'w'); csv.write('t_send,flow,seq,rtt_ms\n')
while time.time() - t0 < a.dur or time.time() - nxt < 1.0:
    now = time.time()
    if now >= nxt and now - t0 < a.dur:
        for f in flows:
            p, dcid, scid = pkt(seq); f['sock'].send(p); f['tx'] += 1; f['sent'][scid] = (seq, time.time())
        seq += 1; nxt += iv
    r, _, _ = select.select([f['sock'] for f in flows], [], [], max(0.0, min(0.01, nxt - time.time())))
    for f in flows:
        if f['sock'] in r:
            try: d = f['sock'].recv(4096)
            except BlockingIOError: continue
            tr = time.time(); f['rx'] += 1
            if len(d) > 6 and d[0] & 0x80 and d[1:5] == b'\0\0\0\0':     # Version Negotiation: DCID of reply = our SCID
                l = d[5]; k = d[6:6 + l]
                if k in f['sent']:
                    sq, ts = f['sent'].pop(k); rt = (tr - ts) * 1000; f['rtt'].append(rt); csv.write(f'{ts:.6f},{f["name"]},{sq},{rt:.3f}\n')
csv.close()
def q(v, p): v = sorted(v); return round(v[min(len(v) - 1, int(p * len(v)))], 2) if v else None
summ = {f['name']: {'ip': f['ip'], 'tx': f['tx'], 'rx': f['rx'], 'answered': len(f['rtt']), 'rtt_p50': q(f['rtt'], .5), 'rtt_p99': q(f['rtt'], .99)} for f in flows}
json.dump(summ, open(a.out + '-summary.json', 'w')); print(json.dumps(summ))
