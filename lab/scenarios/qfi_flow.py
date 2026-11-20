#!/usr/bin/env python3
"""qfi_flow.py <pcap> <events.jsonl> <ue_ip> <outprefix> : per-flow QFI table from N3 GTP-U (inner dst/src, sizes, UE-side ports) + CSV + PNG.
Phase pre/on relative to n5_create t0. Only the UE under test is tabulated."""
import struct, sys, json, collections, csv
pc, evf, ueip, outp = sys.argv[1:5]
b = bytes(int(x) for x in ueip.split("."))
f = open(pc, 'rb'); gh = f.read(24); E = '<' if gh[:4] in (b'\xd4\xc3\xb2\xa1', b'\x4d\x3c\xb2\xa1') else '>'
nano = gh[:4] in (b'\x4d\x3c\xb2\xa1', b'\xa1\xb2\x3c\x4d'); link = struct.unpack(E + 'I', gh[20:24])[0]
pk = []
while True:
    ph = f.read(16)
    if len(ph) < 16: break
    s, us, incl, orig = struct.unpack(E + 'IIII', ph); p = f.read(incl); t = s + us / (1e9 if nano else 1e6)
    off = 14 if link == 1 else (16 if link == 113 else (4 if link == 0 else 0)); ip = p[off:]
    if len(ip) < 28 or ip[9] != 17: continue
    g = ip[(ip[0] & 15) * 4 + 8:]
    if len(g) < 8 or (g[0] >> 5) != 1 or g[1] != 0xff: continue
    pt = q = None; o = 8
    if g[0] & 0x07:
        nxt = g[11]; o = 12
        while nxt and o < len(g):
            ln = g[o] * 4
            if nxt == 0x85: pt = g[o + 1] >> 4; q = g[o + 2] & 0x3f
            nxt = g[o + ln - 1]; o += ln
    inner = g[o:]
    if len(inner) < 20 or inner[0] >> 4 != 4: continue
    pr = inner[9]; ii = (inner[0] & 15) * 4; sp = dp = 0
    if pr in (6, 17) and len(inner) >= ii + 4: sp, dp = struct.unpack('>HH', inner[ii:ii + 4])
    d = "DL" if pt == 0 else "UL"
    src, dst = bytes(inner[12:16]), bytes(inner[16:20])
    ue_side = (dst if d == "DL" else src)
    if ue_side != b: continue
    asip = ".".join(map(str, src if d == "DL" else dst)); asp = sp if d == "DL" else dp; uesp = dp if d == "DL" else sp
    pk.append((t, d, q, {1: "icmp", 6: "tcp", 17: "udp"}.get(pr, str(pr)), asip, asp if pr in (6, 17) else 0, uesp if pr in (6, 17) else 0, struct.unpack('>H', inner[2:4])[0]))
ev = [json.loads(l) for l in open(evf)]
tc = next((e['t0'] for e in ev if e['ev'] == 'n5_create'), None); td = next((e['t0'] for e in ev if e['ev'] == 'n5_delete'), None)
phase = lambda t: "pre" if (tc and t < tc) else ("post" if (td and t >= td) else "on")
agg = collections.defaultdict(lambda: [0, 0, 0, set()])
for t, d, q, pr, ai, ap, up, ln in pk:
    a = agg[(d, q, pr, ai, ap, phase(t))]; a[0] += 1; a[1] += ln; a[2] = max(a[2], ln); a[3].add(up)
rows = []
print("dir QFI proto AS_ip:port phase pkts bytes maxIPlen distinct_UE_ports")
for k in sorted(agg, key=lambda k: (k[3], k[4], k[0], k[5], str(k[1]))):
    a = agg[k]; line = (k[0], k[1], k[2], f"{k[3]}:{k[4]}", k[5], a[0], a[1], a[2], len(a[3])); rows.append(line); print(*line)
csv.writer(open(outp + "_flows.csv", "w")).writerows([("dir", "qfi", "proto", "as", "phase", "pkts", "bytes", "max_ip_len", "ue_ports")] + rows)
# latency of apply on target flow
tgt = [r for r in pk if r[5] == 18080]
res = {}
if tc:
    for d in ("DL", "UL"):
        t1 = next((t for t, dd, q, pr, ai, ap, up, ln in pk if t >= tc and dd == d and ap == 18080 and q not in (None, 1)), None)
        res[f"api_to_first_QFI2_{d}_ms"] = round((t1 - tc) * 1e3, 1) if t1 else None
    last_q1 = max((t for t, dd, q, pr, ai, ap, up, ln in tgt if q == 1), default=None)
    res["target_flow_last_QFI1_pkt_after_create_ms"] = round((last_q1 - tc) * 1e3, 1) if last_q1 else None
if td:
    for d_ in ("DL", "UL"):
        t2 = next((t for t, dd, q, pr, ai, ap, up, ln in pk if t >= td and dd == d_ and ap == 18080 and q == 1), None)
        lq2 = max((t for t, dd, q, pr, ai, ap, up, ln in pk if dd == d_ and ap == 18080 and q not in (None, 1)), default=None)
        res[f"delete_to_first_QFI1_{d_}_ms"] = round((t2 - td) * 1e3, 1) if t2 else None
        res[f"delete_to_last_QFI2_{d_}_ms"] = round((lq2 - td) * 1e3, 1) if lq2 else None
# gate verdicts (only 'on' phase after first QFI2 apply counted as steady state: pkts at t>=create+1s)
steady = [r for r in pk if tc and r[0] >= tc + 1.0 and (not td or r[0] < td) and r[2] not in (None, 1)]
q2flows = collections.Counter((d, pr, ai, ap) for t, d, q, pr, ai, ap, up, ln in steady)
import os
ALLOW = {("10.45.0.1", 18080)} | {(a.split(':')[0], int(a.split(':')[1])) for a in os.environ.get('ALLOW', '').split(',') if a}
bulk_q2 = [(k, v) for k, v in q2flows.items() if (k[2], k[3]) not in ALLOW]
tg_steady = [r for r in pk if tc and r[0] >= tc + 1.0 and (not td or r[0] < td) and r[5] == 18080]
tg_q1 = sum(1 for r in tg_steady if r[2] == 1)
res.update(dict(QFI2_flows_steady={f"{k[0]}/{k[1]}/{k[2]}:{k[3]}": v for k, v in q2flows.items()}, non_target_pkts_on_QFI2=sum(v for k, v in bulk_q2),
                target_pkts_steady=len(tg_steady), target_pkts_steady_on_QFI1=tg_q1,
                GATE_DL_UL="PASS" if tc and not bulk_q2 and all(any(k[0] == d for k in q2flows if k[3] == 18080) for d in ("DL", "UL")) and tg_q1 == 0 else "FAIL"))
print(json.dumps(res, indent=1)); json.dump(res, open(outp + "_gate.json", "w"), indent=1)
# per-100 ms CSV + plot
import matplotlib; matplotlib.use("Agg"); import matplotlib.pyplot as plt
t0 = pk[0][0] if pk else 0
lab = lambda r: f"{r[1]} {r[3]} {r[4].split('.')[-1]}:{r[5]}" if r[3] != "icmp" else f"{r[1]} icmp (keepalive)"
labs = sorted({lab(r) for r in pk}); y = {l: i for i, l in enumerate(labs)}
fig, ax = plt.subplots(2, 1, figsize=(11, 6), sharex=True, gridspec_kw={"height_ratios": [3, 1]})
for qv, col in ((1, "tab:blue"), (2, "tab:red"), (None, "gray")):
    pts = [(r[0] - t0, y[lab(r)]) for r in pk if (r[2] == qv or (qv == 2 and r[2] not in (1, None)))]
    if pts: ax[0].scatter(*zip(*pts), s=3, c=col, label=f"QFI {qv}")
ax[0].set_yticks(range(len(labs))); ax[0].set_yticklabels(labs, fontsize=7); ax[0].legend(markerscale=4)
if tc: ax[0].axvline(tc - t0, c="k", ls="--"); ax[0].text(tc - t0, len(labs) - .5, " N5 Create", fontsize=8)
cnt = collections.Counter((int((r[0] - t0) * 10), r[2] if r[2] in (1, None) else 2) for r in pk)
for qv, col in ((1, "tab:blue"), (2, "tab:red")):
    xs = sorted(k[0] for k in cnt if k[1] == qv); ax[1].plot([x / 10 for x in xs], [cnt[(x, qv)] for x in xs], c=col, lw=.7)
ax[1].set_ylabel("pkts/100ms"); ax[1].set_xlabel("s since capture start"); ax[0].set_title(f"N3 per-flow QFI ({outp.split('/')[-1]})")
plt.tight_layout(); plt.savefig(outp + "_qfi.png", dpi=110)
with open(outp + "_bins.csv", "w") as fh:
    fh.write("t_rel_s,qfi,pkts\n")
    for (b_, q_), v in sorted(cnt.items()): fh.write(f"{b_/10},{q_},{v}\n")
