#!/usr/bin/env python3
"""Box: hitung kriteria Fase 0 Sesi C dari salinan log (nf/). Output: criteria-sesi-c.csv, reps-sesi-c.csv, cv-sesi-c.csv
Usage: analyze.py <nf_dir> <out_dir>"""
import sys, re, json, os, glob, statistics as st, csv
nf, out = sys.argv[1], sys.argv[2]; os.makedirs(out, exist_ok=True)
def q(v, p):
    v = sorted(v); k = (len(v)-1)*p; f = int(k); c = min(f+1, len(v)-1); return v[f]+(v[c]-v[f])*(k-f)
def ping(l):
    t = open(f"{nf}/{l}-ping.txt").read(); r = [float(x) for x in re.findall(r'time=([\d.]+) ms', t)]
    tx = int(re.search(r'(\d+) packets transmitted', t).group(1)); return r, tx
def http(l):
    rows = [x.strip().split(',') for x in open(f"{nf}/{l}-http.csv") if x.count(',') >= 6]
    return [float(x[4])*1000 for x in rows if x[6] == '200'], len(rows)
def tp(fn):
    try: j = json.load(open(fn))
    except Exception: return None
    s = [x['sum']['bits_per_second'] for x in j.get('intervals', [])[2:]]; return sum(s)/len(s)/1e6 if s else None
R = sorted({int(m) for m in re.findall(r'-r(\d+)-ping', ' '.join(os.listdir(nf)))})
reps = []
for r in R:
    for c in ('c1-idle', 'c2-load', 'c3-load-qod'):
        l = f"{c}-r{r}"; pr, tx = ping(l); hr, hn = http(l)
        reps.append(dict(rep=r, cond=c, n_ping=len(pr), ping_loss=tx-len(pr), ping_p50=q(pr,.5), ping_p95=q(pr,.95), ping_p99=q(pr,.99),
                         n_http=len(hr), http_fail=hn-len(hr), http_p50=q(hr,.5), http_p95=q(hr,.95), http_p99=q(hr,.99),
                         dl=tp(f"{nf}/{l}-iperf-dl.json"), ul=tp(f"{nf}/{l}-iperf-ul.json")))
f = lambda x: '' if x is None else (f"{x:.2f}" if isinstance(x, float) else x)
with open(f"{out}/reps-sesi-c.csv", 'w', newline='') as fh:
    w = csv.writer(fh); k = list(reps[0]); w.writerow(k); [w.writerow([f(x[i]) for i in k]) for x in reps]
cv = []
for c in ('c1-idle', 'c2-load', 'c3-load-qod'):
    for m in ('ping_p50', 'ping_p99', 'http_p50', 'http_p99'):
        v = [x[m] for x in reps if x['cond'] == c]; cv.append(dict(cond=c, metric=m, mean=st.mean(v), sd=st.pstdev(v), cv_pct=100*st.pstdev(v)/st.mean(v), vals='/'.join(f"{a:.1f}" for a in v)))
with open(f"{out}/cv-sesi-c.csv", 'w', newline='') as fh:
    w = csv.writer(fh); k = list(cv[0]); w.writerow(k); [w.writerow([f(x[i]) for i in k]) for x in cv]
g = lambda r, c: next(x for x in reps if x['rep'] == r and x['cond'] == c)
crit = []
for r in R:
    i, l, qd = g(r, 'c1-idle'), g(r, 'c2-load'), g(r, 'c3-load-qod')
    crit += [dict(rep=r, k='ping_p99_reduction_pct', v=100*(1-qd['ping_p99']/l['ping_p99'])), dict(rep=r, k='http_p99_reduction_pct', v=100*(1-qd['http_p99']/l['http_p99'])),
             dict(rep=r, k='ping_p50_qod_over_idle', v=qd['ping_p50']/i['ping_p50']), dict(rep=r, k='http_p50_qod_over_idle', v=qd['http_p50']/i['http_p50']),
             dict(rep=r, k='ping_loss_qod_pct', v=100*qd['ping_loss']/(qd['n_ping']+qd['ping_loss'])), dict(rep=r, k='http_fail_qod', v=qd['http_fail']),
             dict(rep=r, k='bulk_dl_qod_over_load', v=(qd['dl'] or 0)/(l['dl'] or 1)), dict(rep=r, k='bulk_ul_qod_over_load', v=(qd['ul'] or 0)/(l['ul'] or 1))]
for lbl in ('s1-load-qod', 's2-load-after-str', 'r1-load-qod', 'r2-load-after-delete'):
    if os.path.exists(f"{nf}/{lbl}-ping.txt") and os.path.exists(f"{nf}/{lbl}-http.csv"):
        pr, tx = ping(lbl); hr, hn = http(lbl)
        crit += [dict(rep='str', k=f'{lbl}_ping_n', v=len(pr)), dict(rep='str', k=f'{lbl}_ping_p50', v=q(pr,.5)), dict(rep='str', k=f'{lbl}_ping_p99', v=q(pr,.99)),
                 dict(rep='str', k=f'{lbl}_ping_loss', v=tx-len(pr)), dict(rep='str', k=f'{lbl}_http_n', v=len(hr)), dict(rep='str', k=f'{lbl}_http_p50', v=q(hr,.5)), dict(rep='str', k=f'{lbl}_http_p99', v=q(hr,.99))]
for fn in sorted(glob.glob(f"{nf}/*-udp-*.json")):
    try: j = json.loads(open(fn).read().strip().splitlines()[-1])
    except Exception: continue
    b = os.path.basename(fn)[:-5]; crit += [dict(rep='gbr', k=f'{b}_goodput_kbps', v=j.get('goodput_kbps')), dict(rep='gbr', k=f'{b}_loss_pct', v=j.get('loss_pct'))]
for fn in sorted(glob.glob(f"{nf}/c-gbr-tcp-*.json")):
    try: j = json.load(open(fn)); e = j['end']
    except Exception: continue
    b = os.path.basename(fn)[:-5]; crit += [dict(rep='gbr', k=f'{b}_recv_kbps', v=e['sum_received']['bits_per_second']/1000), dict(rep='gbr', k=f'{b}_retrans', v=e['sum_sent'].get('retransmits'))]
with open(f"{out}/criteria-sesi-c.csv", 'w', newline='') as fh:
    w = csv.writer(fh); w.writerow(['rep', 'key', 'value']); [w.writerow([x['rep'], x['k'], f(float(x['v'])) if x['v'] is not None else '']) for x in crit]
for fn in ('reps-sesi-c.csv', 'cv-sesi-c.csv', 'criteria-sesi-c.csv'): print(open(f"{out}/{fn}").read())
