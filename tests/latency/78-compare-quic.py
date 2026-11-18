#!/usr/bin/env python3
"""poc-phase3 v2.1: bandingkan record yg dikirim generator/app (JSON 77) dgn pktlat.log waktu nyata (proto=quic).
Pakai: 78-compare-quic.py <gen.json> <pktlat.log...>  -> cakupan UL/DL, p50/p90 per tap, overhead probe."""
import json, sys, collections
G = json.load(open(sys.argv[1])); rows = []
for fn in sys.argv[2:]:
    for l in open(fn):
        if l.startswith('{'):
            j = json.loads(l)
            if j.get('proto') == 'quic': rows.append(j)
fids = {f['fid'] for f in G['flows']}
got = {(r['fid'], 1 if r['dir'] == 'UL' else 2, r.get('qhash')): r for r in rows if r['fid'] in fids}
def pct(v, q): v = sorted(v); return v[min(len(v) - 1, int(q * len(v)))] if v else float('nan')
for typ, d in ((1, 'UL'), (2, 'DL')):
    sent = [(f['fid'], r['h']) for f in G['flows'] for r in f['recs'] if r['t'] == typ]
    m = [got.get((fid, typ, h)) for fid, h in sent]; ok = [x for x in m if x and x['status'] == 'ok']
    st = collections.Counter(x['status'] if x else 'tidak-ada-baris' for x in m)
    print(f"{d}: record app={len(sent)} baris pktlat={sum(1 for x in m if x)} ok={len(ok)} cakupan={100*len(ok)/max(1,len(sent)):.1f}% status={dict(st)}")
    for t in ('ow_s1u', 'ow_s5s8', 'ow_sgi', 'ow_cgnat', 'one_way'):
        v = [x[t] for x in ok if t in x]
        if v: print(f"   {t:9s} n={len(v):4d} p50={pct(v,.5):8.2f} p90={pct(v,.9):8.2f} min={min(v):7.2f} max={max(v):8.2f} ms")
s = G['stats']; q = s['ul_bytes'] + s['dl_bytes']
print(f"overhead probe: {s['probes']} probe, {s['probe_bytes']} B payload (+28 B IP/UDP/probe = {s['probe_bytes']+28*s['probes']} B) "
      f"vs QUIC UL {s['ul_bytes']} B / DL {s['dl_bytes']} B -> {100*s['probe_bytes']/max(1,s['ul_bytes']):.1f}% UL, {100*s['probe_bytes']/max(1,q):.1f}% UL+DL")
print("contoh baris:", json.dumps(next((r for r in rows if r['fid'] in fids and r['status'] == 'ok' and r['dir'] == 'DL'), {}))[:900])
