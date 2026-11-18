#!/usr/bin/env python3
# Ringkas p50/p95/p99 ping RTT & HTTP TTFB + throughput bulk iperf3. Usage: p99-stats.py <dir> label...
import sys, re, json, os
def q(v, p):
    v = sorted(v); k = (len(v)-1)*p; f = int(k); c = min(f+1, len(v)-1); return v[f]+(v[c]-v[f])*(k-f)
def tp(fn):
    try: j = json.load(open(fn))
    except Exception: return None
    iv = j.get('intervals', [])
    if not iv: return None
    s = [x['sum']['bits_per_second'] for x in iv[2:] if 'sum' in x] or [iv[0]['sum']['bits_per_second']]
    return sum(s)/len(s)/1e6
d = sys.argv[1]; print("cond,metric,n,loss_or_fail,p50_ms,p95_ms,p99_ms,max_ms,bulk_dl_mbps,bulk_ul_mbps")
for L in sys.argv[2:]:
    dl, ul = tp(f"{d}/{L}-iperf-dl.json"), tp(f"{d}/{L}-iperf-ul.json")
    f = lambda x: f"{x:.2f}" if x is not None else "-"
    rtt = [float(m) for m in re.findall(r'time=([\d.]+) ms', open(f"{d}/{L}-ping.txt").read())]
    tx = re.search(r'(\d+) packets transmitted', open(f"{d}/{L}-ping.txt").read()); tx = int(tx.group(1)) if tx else len(rtt)
    if rtt: print(f"{L},ping_rtt,{len(rtt)},{tx-len(rtt)},{q(rtt,.5):.1f},{q(rtt,.95):.1f},{q(rtt,.99):.1f},{max(rtt):.1f},{f(dl)},{f(ul)}")
    rows = [r.strip().split(',') for r in open(f"{d}/{L}-http.csv") if r.count(',') >= 6]
    ok = [float(r[4])*1000 for r in rows if r[6] == '200']
    if ok: print(f"{L},http_ttfb,{len(ok)},{len(rows)-len(ok)},{q(ok,.5):.1f},{q(ok,.95):.1f},{q(ok,.99):.1f},{max(ok):.1f},{f(dl)},{f(ul)}")
