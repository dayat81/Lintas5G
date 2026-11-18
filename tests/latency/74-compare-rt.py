#!/usr/bin/env python3
"""poc-phase3: bandingkan pktlat.log waktu nyata (pktlat2.zeek) dgn hasil offline 63-analyze-pktlat.py (pkt-ul.csv / pkt-dl.csv).
Pakai: 74-compare-rt.py <run-dir> [pktlat.log] [pktlat_stats.log]   (run-dir sudah dianalisis 63)"""
import json, csv, sys, os, collections, statistics as st
D = sys.argv[1]; RT = sys.argv[2] if len(sys.argv) > 2 else os.path.join(D, 'zeek-pktlat-rt.log')
STATS = sys.argv[3] if len(sys.argv) > 3 else os.path.join(D, 'zeek-pktlat-stats.log')
out = []; P = lambda *a: out.append(' '.join(str(x) for x in a))
def S(v):
    v = sorted(v); n = len(v)
    if not n: return 'n=0'
    q = lambda p: v[min(n - 1, int(p * n))]
    return f"n={n:4} p50={st.median(v):7.2f} p90={q(.9):7.2f} max={v[-1]:8.2f}"
rt = [json.loads(l) for l in open(RT) if l.startswith('{')]
P(f"pktlat.log waktu nyata: baris={len(rt)} status={dict(collections.Counter((r['dir'], r['status'].split(':')[0]) for r in rt))}"
  f" resend_dipakai={sum(r['resend'] for r in rt)}")
TAP = {'s1u(gtp)': 'ow_s1u', 's5s8(gtp)': 'ow_s5s8', 'sgi': 'ow_sgi'}
off_ul = {}; off_dl = {}
for r in csv.DictReader(open(os.path.join(D, 'pkt-ul.csv'))):
    if r['tap'] in TAP: off_ul[(r['fid'], int(r['off']), r['tap'])] = float(r['lat_last_ms'])
for r in csv.DictReader(open(os.path.join(D, 'pkt-dl.csv'))):
    if r['tap'] in TAP: off_dl[(r['fid'], int(r['off']), r['tap'])] = float(r['lat_read_ms'])
for dirn, ref in (('UL', off_ul), ('DL', off_dl)):
    P(f"{dirn}:")
    for tap, fld in TAP.items():
        rtv = {(r['fid'].lstrip('0') or '0', r['off']): r[fld] for r in rt if r['dir'] == dirn and fld in r}
        refv = {(k[0].lstrip('0') or '0', k[1]): v for k, v in ref.items() if k[2] == tap}
        both = [k for k in refv if k in rtv]
        diff = [rtv[k] - refv[k] for k in both]
        P(f"  {tap:10} offline {S(list(refv.values()))}")
        P(f"  {'':10} rt      {S(list(rtv.values()))}")
        if diff:
            P(f"  {'':10} cakupan rt/offline {len(both)}/{len(refv)} ({100*len(both)/max(1,len(refv)):.1f}%)  |selisih| per paket p50={st.median([abs(x) for x in diff]):.3f} max={max(abs(x) for x in diff):.3f} ms"
              f"  selisih p50 {st.median([rtv[k] for k in both]) - st.median([refv[k] for k in both]):+.3f} p90 {sorted(rtv[k] for k in both)[int(.9*len(both))] - sorted(refv[k] for k in both)[int(.9*len(both))]:+.3f} ms")
if os.path.exists(STATS):
    s = [json.loads(l) for l in open(STATS) if l.startswith('{')]
    if s: P("pktlat_stats terakhir: " + json.dumps(s[-1]))
open(os.path.join(D, 'compare-rt.txt'), 'w').write('\n'.join(out) + '\n'); print('\n'.join(out))
