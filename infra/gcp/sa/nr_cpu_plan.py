#!/usr/bin/env python3
"""CPU split for N srsRAN gNB+srsUE NR pairs on one VM (budget 12 vCPU). Pure function, unit-tested.

Layout: first CORE CPUs (+ leftovers) = Open5GS/UPF/system/Zeek/iperf servers; each pair gets P CPUs
(P = min(PAIR_MAX, (nproc-core)//pairs)); the HEAVY side gets ceil(P/2), the other the rest (>=1).
Default heavy = gNB (FAKTA, box 19 Nov 2026: gNB pinned to 1 CPU saturates at 100% and caps a pair at ~36 Mbit/s DL;
unpinned 1 pair at ~56 Mbit/s DL uses gNB ~180% / srsUE ~135% of one CPU). NR_HEAVY=ue restores the old split.
Output (CLI): one line per pair: `pair=<i> gnb=<cpulist> ue=<cpulist>` and `core=<cpulist>`.
"""
import argparse
import math


def _rng(a, n):
    return ",".join(str(c) for c in range(a, a + n))


def plan(nproc, pairs, core=2, pair_max=5, heavy="gnb"):
    if pairs < 1 or pairs > 4:
        raise ValueError("pairs must be 1..4")
    if heavy not in ("gnb", "ue"):
        raise ValueError("heavy must be gnb|ue")
    if nproc < core + 2 * pairs:
        raise ValueError(f"nproc={nproc} too small for {pairs} pairs (+{core} core)")
    per = min(pair_max, (nproc - core) // pairs)
    out = {"pairs": {}}
    nxt = core
    for i in range(1, pairs + 1):
        big = math.ceil(per / 2)
        gnb, ue = (big, per - big) if heavy == "gnb" else (per - big, big)
        out["pairs"][i] = {"gnb": _rng(nxt, gnb), "ue": _rng(nxt + gnb, ue)}
        nxt += per
    # leftovers (tail CPUs) go to the core side
    tail = list(range(nxt, nproc))
    out["core"] = ",".join(str(c) for c in list(range(core)) + tail)
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--nproc", type=int, required=True)
    ap.add_argument("--pairs", type=int, required=True)
    ap.add_argument("--core", type=int, default=2)
    ap.add_argument("--pair-max", type=int, default=5)
    ap.add_argument("--heavy", choices=("gnb", "ue"), default="gnb")
    a = ap.parse_args()
    p = plan(a.nproc, a.pairs, a.core, a.pair_max, a.heavy)
    print(f"core={p['core']}")
    for i, v in p["pairs"].items():
        print(f"pair={i} gnb={v['gnb']} ue={v['ue']}")


if __name__ == "__main__":
    main()
