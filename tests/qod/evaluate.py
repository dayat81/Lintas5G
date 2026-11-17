#!/usr/bin/env python3
"""Evaluasi kriteria lulus uji feasibility QoD dari CSV latency per paket (export ClickHouse pkt_latency).

Masukan CSV: kolom label (before|after|after-delete), run (int), one_way_ms, status, [goodput_mbps].
Kriteria (docs/qod-feasibility-test.md):
  K1 p99(after) <= 0.5 * p99(before)
  K2 loss(after) < 1%
  K3 goodput GBR(after) >= 95% x 5 Mbps
  K4 setelah DELETE p99 kembali ke >= 80% p99(before)
  K5 CV p99 antar-run < 20% per label
Pakai: evaluate.py data.csv
"""
import csv, statistics as st, sys, collections


def pct(v, q):
    v = sorted(v)
    return v[min(len(v) - 1, int(q * len(v)))] if v else float("nan")


def main(path):
    rows = list(csv.DictReader(open(path)))
    by = collections.defaultdict(lambda: collections.defaultdict(list))
    tot = collections.Counter(); miss = collections.Counter(); gp = collections.defaultdict(list)
    for r in rows:
        lab = r["label"]; tot[lab] += 1
        if r.get("status", "ok") != "ok" or not r.get("one_way_ms"):
            miss[lab] += 1; continue
        by[lab][r.get("run", "0")].append(float(r["one_way_ms"]))
        if r.get("goodput_mbps"):
            gp[lab].append(float(r["goodput_mbps"]))
    res = {}
    for lab, runs in by.items():
        allv = [x for v in runs.values() for x in v]
        p99s = [pct(v, .99) for v in runs.values() if v]
        cv = st.pstdev(p99s) / st.mean(p99s) if len(p99s) > 1 else 0.0
        res[lab] = dict(p50=pct(allv, .5), p95=pct(allv, .95), p99=pct(allv, .99), cv=cv,
                        loss=miss[lab] / max(1, tot[lab]), goodput=st.mean(gp[lab]) if gp[lab] else None)
        print(f"{lab:13s} n={len(allv):6d} p50={res[lab]['p50']:.2f} p95={res[lab]['p95']:.2f} p99={res[lab]['p99']:.2f} "
              f"loss={100*res[lab]['loss']:.2f}% cv={100*cv:.1f}% goodput={res[lab]['goodput']}")
    b, a, d = res.get("before"), res.get("after"), res.get("after-delete")
    checks = []
    if b and a:
        checks.append(("K1 p99 turun >=50%", a["p99"] <= 0.5 * b["p99"]))
        checks.append(("K2 loss <1%", a["loss"] < 0.01))
        checks.append(("K3 goodput >=4.75 Mbps", a["goodput"] is not None and a["goodput"] >= 4.75))
    if b and d:
        checks.append(("K4 efek hilang setelah DELETE", d["p99"] >= 0.8 * b["p99"]))
    checks.append(("K5 CV<20%", all(r["cv"] < 0.2 for r in res.values())))
    ok = True
    for name, passed in checks:
        print(("PASS " if passed else "FAIL ") + name); ok &= passed
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1]))
