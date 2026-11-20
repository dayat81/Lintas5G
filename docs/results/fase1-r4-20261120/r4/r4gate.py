#!/usr/bin/env python3
"""r4gate.py <run>... : GATES-r4 FROZEN v1.1 G1 metrics per r4 run (sha256 d396a72e...). Read-only on booster-e2e-r4/ev/<run>/core/<run>.
Window = t_booster -> t_booster_finish (tools/window.py on logcat BOOSTER_APP; fallback t_back/t_end flagged). N runs (no booster):
same harness offsets (emu times t_booster -> t_finish_req), reported only (no AVAILABLE). AVAILABLE = adapter sink_event AVAILABLE ->
next non-AVAILABLE sink_event, clipped to the window. Loss = T4 (N3 DL YouTube :443 matched to UE tun capture, by N3 send time);
share = bytes on QFI != 1 / total (T2). Intervals with < 1000 YouTube DL packets -> "tidak dinilai". Same matcher as r3avail.py."""
import sys, os, json, struct, collections, csv, subprocess
EV = "/workspace/booster-e2e-r4/ev"; TOOLS = "/workspace/booster-e2e-r4/bundle/tools"
src = open(f"{TOOLS}/flowtl.py").read().split("n3 = []")[0]
MINPKT = 1000
def times(f):
    T = {}
    for l in open(f):
        p = l.split()
        if len(p) >= 2:
            try: T.setdefault(p[0], float(p[1]))
            except ValueError: pass
    return T
def intervals(ev, lo, hi):
    out = []; cur = None
    for t, s in ev:
        if s == "AVAILABLE" and cur is None: cur = t
        elif s != "AVAILABLE" and cur is not None: out.append((cur, t)); cur = None
    if cur is not None: out.append((cur, float("inf")))
    return [(max(a, lo), min(b, hi)) for a, b in out if min(b, hi) > max(a, lo)]
def inside(t, iv): return any(a <= t < b for a, b in iv)
rows = []; detail = []
for run in sys.argv[1:]:
    R = f"{EV}/{run}/core/{run}"; sys.argv = ["x", R]; ns = {}; exec(src, ns)
    pcap, gtp_inner, classify, key = ns["pcap"], ns["gtp_inner"], ns["classify"], ns["key"]
    ET = times(f"{R}/emu/times"); booster = os.path.exists(f"{R}/emu/am-booster.txt") and os.path.getsize(f"{R}/emu/am-booster.txt") > 0
    W = {}
    if booster:
        W = json.loads(subprocess.run(["python3", f"{TOOLS}/window.py", f"{R}/emu/logcat-booster.txt", f"{R}/emu/times"], capture_output=True, text=True).stdout)
        lo, hi = W["t_booster"], W["t_booster_finish"]
    else:
        lo, hi = ET["t_booster"], ET.get("t_finish_req", ET.get("t_end"))
    ev = []; first_create = None
    for l in open(f"{R}/adapter.win.log"):
        try: d = json.loads(l)
        except ValueError: continue
        if d.get("ev") == "sink_event": ev.append((d["t"], d["qosStatus"]))
    ev.sort(); av = intervals(ev, lo, hi)
    nav = []; c = lo
    for a, b in av:
        if a > c: nav.append((c, a))
        c = b
    if c < hi: nav.append((c, hi))
    n3 = []
    for t, ip in pcap(f"{R}/n3.pcap"):
        r = gtp_inner(ip)
        if not r: continue
        pt, q, inner = r
        if len(inner) < 20 or inner[0] >> 4 != 4: continue
        d = "DL" if pt == 0 else "UL"
        cl, peer, pr, pp = classify(inner, d)
        if d == "DL" and cl == "youtube": n3.append((t, key(inner), q, struct.unpack(">H", inner[2:4])[0]))
    t_end = max(t for t, *_ in n3) if n3 else 0
    ue = {}
    for t, ip in pcap(f"{R}/ue.pcap"):
        if len(ip) < 20 or ip[0] >> 4 != 4: continue
        ue.setdefault(key(ip), []).append(t)
    bykey = collections.defaultdict(list)
    for i, (t, k, *_r) in enumerate(n3): bykey[k].append(i)
    match = [None] * len(n3)
    for k, arr in ue.items():
        idx = bykey.get(k)
        if not idx: continue
        for x in sorted(arr):
            best = None
            for i in idx:
                if n3[i][0] <= x + 0.001 and x - n3[i][0] <= 5 and match[i] is None: best = i
                elif n3[i][0] > x + 0.001: break
            if best is not None: match[best] = x
    def stats(iv):
        s = l = b = bb = 0
        for i, (t, k, q, ln) in enumerate(n3):
            if t > t_end - 2 or not inside(t, iv): continue
            s += 1; l += match[i] is None; b += ln; bb += ln if q not in (None, 1) else 0
        return s, l, b, bb
    win = hi - lo
    t_av = next((a for a, s in [(t, s) for t, s in ev] if s == "AVAILABLE" and lo <= a <= hi), None)
    base = dict(run=run, mode="A" if booster else "N", window_s=round(win, 1), finish_source=W.get("finish_source", "harness(N)"),
                flags="|".join(W.get("flags", [])), time_to_available_s=round(t_av - lo, 1) if t_av else "")
    for name, iv in (("window_total", [(lo, hi)]), ("AVAILABLE", av), ("non_AVAILABLE", nav)):
        s, l, b, bb = stats(iv); sec = sum(y - x for x, y in iv)
        rows.append(dict(base, interval=name, n_intervals=len(iv), seconds=round(sec, 1), coverage_pct=round(100 * sec / win, 1),
            yt_dl_pkts=s, yt_dl_lost=l, yt_dl_loss_pct=round(100 * l / s, 2) if s else "", yt_dl_bytes=b, yt_bytes_boostQFI=bb,
            yt_boost_share_pct=round(100 * bb / b, 1) if b else "", yt_dl_mbps=round(b * 8 / sec / 1e6, 2) if sec else "",
            scored="ya" if s >= MINPKT else "tidak dinilai (<1000 paket)"))
    for k, (x, y) in enumerate(av, 1):
        s, l, b, bb = stats([(x, y)])
        detail.append(dict(run=run, interval=f"s{k}", t_start_rel_s=round(x - lo, 1), seconds=round(y - x, 1), pkts=s, lost=l,
            loss_pct=round(100 * l / s, 2) if s else "", share_pct=round(100 * bb / b, 1) if b else ""))
    for k, (x, y) in enumerate([i for i in nav if i[1] - i[0] > 0.05], 1):
        s, l, b, bb = stats([(x, y)])
        detail.append(dict(run=run, interval=f"gap{k}", t_start_rel_s=round(x - lo, 1), seconds=round(y - x, 1), pkts=s, lost=l,
            loss_pct=round(100 * l / s, 2) if s else "", share_pct=round(100 * bb / b, 1) if b else ""))
    if booster:
        a = next(r for r in rows if r["run"] == run and r["interval"] == "AVAILABLE")
        ok = a["scored"] == "ya"
        g = dict(G1a=("lulus" if a["yt_dl_loss_pct"] != "" and a["yt_dl_loss_pct"] <= 5 else "gagal") if ok else "tidak dinilai",
                 G1b=("lulus" if a["yt_boost_share_pct"] != "" and a["yt_boost_share_pct"] >= 80 else "gagal") if ok else "tidak dinilai",
                 G1c="lulus" if a["coverage_pct"] >= 90 else "gagal")
        if "FAILED_SETUP_CDN_REJECTED" in base["flags"]: g = {k: "gagal (setup)" for k in g}
        print(json.dumps(dict(run=run, **g)))
out = os.path.dirname(os.path.abspath(__file__))
for fn, rr in (("r4-g1.csv", rows), ("r4-g1-sessions.csv", detail)):
    if rr:
        with open(f"{out}/{fn}", "w", newline="") as f:
            w = csv.DictWriter(f, fieldnames=list(rr[0].keys())); w.writeheader(); w.writerows(rr)
for r in rows: print(r)
for r in detail: print(r)
