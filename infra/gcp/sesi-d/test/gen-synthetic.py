#!/usr/bin/env python3
"""Synthetic pcaps for offline tests of pkthash.zeek + the ClickHouse join (no real traffic, no secrets).
Writes ue.pcap (raw IP, tun_srsue), n3.pcap (Ethernet on lo, GTP-U with PDU Session Container), n6.pcap (raw IP, ogstun)
and expected.json with the ground-truth per-segment delays. usage: gen-synthetic.py <outdir> [n_per_cond]"""
import json, os, random, sys
from scapy.all import IP, UDP, TCP, Ether, Raw, wrpcap, conf
from scapy.contrib.gtp import GTP_U_Header, GTPPDUSessionContainer

out = sys.argv[1]; N = int(sys.argv[2]) if len(sys.argv) > 2 else 200
os.makedirs(out, exist_ok=True); random.seed(7)
UE, SRV, ENB, SGW = "10.45.0.2", "142.250.4.100", "127.0.1.1", "127.0.0.7"
T0 = 1_700_000_000.0
conds = [("idle", 12.0, 0.25), ("load", 160.0, 40.0), ("load+qod", 18.0, 2.0)]  # (cond, ue->n3 mean ms, n3->n6 mean ms) UL
ue, n3, n6, exp = [], [], [], {}
t = T0
def gtp(inner, teid, qfi, dl):
    g = GTP_U_Header(teid=teid, E=1, next_ex=0x85) / GTPPDUSessionContainer(type=0 if dl else 1, QFI=qfi, ExtHdrLen=1)
    return Ether() / IP(src=SGW if dl else ENB, dst=ENB if dl else SGW) / UDP(sport=2152, dport=2152) / g / inner
for ci, (cond, a_ms, b_ms) in enumerate(conds):
    e = exp.setdefault(cond, {"UL_ue_n3": [], "UL_n3_n6": [], "DL_n6_n3": [], "DL_n3_ue": [], "t0": t})
    for i in range(N):
        pl = os.urandom(random.randint(60, 1250))
        qfi = 2 if cond == "load+qod" else 1
        a = max(0.5, random.gauss(a_ms, a_ms / 5)) / 1000; b = max(0.05, random.gauss(b_ms, b_ms / 5 + 0.01)) / 1000
        inner = IP(src=UE, dst=SRV) / UDP(sport=50000 + ci, dport=443) / Raw(pl)
        p = inner.copy(); p.time = t; ue.append(p)
        q = gtp(inner, 0x1001, qfi, False); q.time = t + a; n3.append(q)
        if i % 50 != 49:                                   # 2% UL loss between n3 and n6 (miss counted, not matched)
            r = inner.copy(); r.time = t + a + b; n6.append(r); e["UL_n3_n6"].append(round(b * 1000, 3))
        e["UL_ue_n3"].append(round(a * 1000, 3))
        # DL echo
        pl2 = os.urandom(random.randint(60, 1250))
        inner2 = IP(src=SRV, dst=UE) / UDP(sport=443, dport=50000 + ci) / Raw(pl2)
        c = max(0.05, random.gauss(b_ms, b_ms / 5 + 0.01)) / 1000; d = max(0.5, random.gauss(a_ms / 2, a_ms / 10)) / 1000
        t2 = t + 0.030
        r2 = inner2.copy(); r2.time = t2; n6.append(r2)
        q2 = gtp(inner2, 0x2002, qfi, True); q2.time = t2 + c; n3.append(q2)
        p2 = inner2.copy(); p2.time = t2 + c + d; ue.append(p2)
        e["DL_n6_n3"].append(round(c * 1000, 3)); e["DL_n3_ue"].append(round(d * 1000, 3))
        t += 0.05
    e["t1"] = t; t += 5
for name, pk, link in (("ue", ue, 101), ("n3", n3, 1), ("n6", n6, 101)):
    pk.sort(key=lambda p: p.time)
    wrpcap(f"{out}/{name}.pcap", pk, linktype=link)
json.dump(exp, open(f"{out}/expected.json", "w"))
with open(f"{out}/phases.tsv", "w") as f:  # same format as the Sesi D runner: run_id cond rep t_start t_end (epoch s)
    for cond, d in exp.items():
        f.write(f"syn-run\t{cond}\t1\t{d['t0'] - 0.01:.3f}\t{d['t1']:.3f}\n")
print({k: {s: len(v) for s, v in d.items() if isinstance(v, list)} for k, d in exp.items()})
