#!/usr/bin/env python3
"""Summarise per-pair iperf3 JSON (pair<i>_<dl|ul>.json) + CPU sample; PASS/FAIL against Fase 1-2 criteria.

Criteria (plan docs/backlog/radio-capacity-uplift-plan.md): every pair >= --min-pair Mbit/s per direction;
aggregate DL >= 50 (1 pair) / 100 (2) / 150 (3); CPU (mean busy of all vCPU) < 85 %.
Subcommands: summary, cpu, ratio.
Sim/real ratio (ratio_<dir>.json, from the gNB slot log during the test): simulated radio seconds per wall second.
ZMQ (srsRAN) and rfsim (OAI) are not paced by a sample clock, so they can run faster (> 1) or slower (< 1) than real time.
"air" = wall / ratio when ratio > 1 (the honest radio-equivalent throughput), else wall (CPU-bound, already <= real time).
"""
import argparse
import datetime
import json
import os
import re
import sys
import time

AGG_MIN = {1: 50.0, 2: 100.0, 3: 150.0, 4: 170.0}  # 4 = PM target band upper (120-170 Mbit/s)


def mbps(doc):
    end = doc.get("end", {})
    if end.get("sum_received"):
        return end["sum_received"].get("bits_per_second", 0.0) / 1e6
    s = end.get("sum") or {}
    bps = s.get("bits_per_second", 0.0)
    if "lost_percent" in s:  # UDP on iperf3 < 3.10 (jammy 3.9): only the offered rate + loss -> received goodput
        bps *= max(0.0, 1.0 - float(s["lost_percent"]) / 100.0)
    return bps / 1e6


def per_second(doc):
    return [iv["sum"]["bits_per_second"] / 1e6 for iv in doc.get("intervals", [])]


def load(path):
    try:
        with open(path) as f:
            d = json.load(f)
        return None if "error" in d and "end" not in d else d
    except (OSError, ValueError):
        return None


OAI_FS = re.compile(r"^(\d+\.\d+)\s+\[NR_MAC\]\s+\w\s+Frame\.Slot\s+(\d+)\.(\d+)")
SRS_FS = re.compile(r"^(\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d\.\d+)\s+\[[^\]]*\]\s+\[\w\]\s+\[\s*(\d+)\.(\d+)\]")


def sim_ratio(lines, scs_khz=15):
    """Simulated seconds per wall second from gNB log lines.
    OAI: 'Frame.Slot F.0' every 128 frames (10 ms each, SFN wraps at 1024), wall = the log's time column.
    srsRAN: ISO timestamp + '[SFN.slot]' context (MAC/SCHED info level), slot = 1 ms * 15/scs, SFN wrap 1024."""
    pts = []
    for ln in lines:
        m = OAI_FS.match(ln)
        if m:
            pts.append(("oai", float(m.group(1)), int(m.group(2)) * 10.0))
            continue
        m = SRS_FS.match(ln)
        if m:
            w = datetime.datetime.fromisoformat(m.group(1)).replace(tzinfo=datetime.timezone.utc).timestamp()
            pts.append(("srsran", w, int(m.group(2)) * 10.0 + int(m.group(3)) * 15.0 / scs_khz))
    if len(pts) < 3:
        return {"sim_ratio": None, "source": None, "samples": len(pts)}
    sim = 0.0
    for (_, _, a), (_, _, b) in zip(pts, pts[1:]):
        step = (b - a) % 10240.0  # ms, SFN wrap (1024 frames)
        sim += step - 10240.0 if step > 5120.0 else step  # small backwards jitter between log threads stays small
    wall = pts[-1][1] - pts[0][1]
    if wall <= 0:
        return {"sim_ratio": None, "source": pts[0][0], "samples": len(pts)}
    return {"sim_ratio": round(sim / 1000.0 / wall, 3), "sim_s": round(sim / 1000.0, 2), "wall_s": round(wall, 2),
            "source": pts[0][0], "samples": len(pts)}


def ratio_from_log(path, start_offset=0, scs_khz=15):
    with open(path, "rb") as f:
        f.seek(start_offset)
        lines = f.read().decode(errors="ignore").splitlines()
    return sim_ratio(lines, scs_khz)


def honest(wall, ratio):
    """radio-equivalent throughput: wall / ratio when the emulator ran faster than real time."""
    if wall is None:
        return None
    return round(wall / ratio, 2) if ratio and ratio > 1 else wall


def summarize(d, pairs, min_pair, cpu_max=85.0):
    res = {"pairs": pairs, "dirs": {}, "verdict": "PASS", "reasons": []}
    for direction in ("dl", "ul"):
        docs = {i: load(os.path.join(d, f"pair{i}_{direction}.json")) for i in range(1, pairs + 1)}
        if not any(docs.values()):
            continue
        per = {i: round(mbps(x), 2) if x else None for i, x in docs.items()}
        series = [per_second(x) for x in docs.values() if x]
        n = min((len(s) for s in series), default=0)
        agg_series = [sum(s[k] for s in series) for k in range(n)]
        agg = round(sum(v for v in per.values() if v), 2)
        res["dirs"][direction] = {
            "per_pair_mbps": per, "aggregate_mbps": agg,
            "aggregate_sec_min": round(min(agg_series), 2) if agg_series else None,
            "aggregate_sec_p50": round(sorted(agg_series)[len(agg_series) // 2], 2) if agg_series else None,
            "retransmits": {i: (x.get("end", {}).get("sum_sent", {}).get("retransmits")) for i, x in docs.items() if x},
        }
        rt = load(os.path.join(d, f"ratio_{direction}.json")) or {}
        r = rt.get("sim_ratio")
        res["dirs"][direction].update({"sim_ratio": r, "air_mbps": honest(agg, r),
                                       "air_per_pair_mbps": {i: honest(v, r) for i, v in per.items()}})
        for i, v in per.items():
            if v is None or v < min_pair:
                res["verdict"] = "FAIL"
                res["reasons"].append(f"{direction} pair{i}={v} < {min_pair}")
        if direction == "dl" and agg < AGG_MIN[pairs]:
            res["verdict"] = "FAIL"
            res["reasons"].append(f"dl aggregate {agg} < {AGG_MIN[pairs]}")
    if not res["dirs"]:
        res["verdict"] = "FAIL"
        res["reasons"].append("no iperf3 JSON found")
    for direction in ("dl", "ul"):
        c = load(os.path.join(d, f"cpu_{direction}.json"))
        if c:
            res.setdefault("cpu", {})[direction] = c
            if c["mean_busy_pct"] >= cpu_max:
                res["verdict"] = "FAIL"
                res["reasons"].append(f"cpu {direction} mean {c['mean_busy_pct']} >= {cpu_max}")
    return res


def _stat():
    with open("/proc/stat") as f:
        rows = {}
        for ln in f:
            if ln.startswith("cpu") and ln[3].isdigit():
                p = ln.split()
                v = list(map(int, p[1:9]))
                rows[p[0]] = (sum(v), v[3] + v[4])  # total, idle+iowait
        return rows


def _procs():
    """cumulative utime+stime jiffies per labelled process (gnb<i>, srsue<i>, upf, amf, iperf3, zeek, qemu...)."""
    out = {}
    for pid in os.listdir("/proc"):
        if not pid.isdigit():
            continue
        try:
            with open(f"/proc/{pid}/stat") as f:
                st = f.read()
            comm = st[st.index("(") + 1:st.rindex(")")]
            rest = st[st.rindex(")") + 2:].split()
            j = int(rest[11]) + int(rest[12])
            with open(f"/proc/{pid}/cmdline", "rb") as f:
                cmd = f.read().replace(b"\0", b" ").decode(errors="ignore")
        except (OSError, ValueError, IndexError):
            continue
        label = comm
        if not cmd.strip():  # zombie / kernel thread: no cmdline
            continue
        if comm in ("gnb", "srsue") or "pair" in cmd and ("gnb" in cmd or "srsue" in cmd):
            import re
            m = re.search(r"pair(\d)", cmd)
            exe = comm if comm in ("gnb", "srsue") else cmd.split()[0]
            label = f"{'gnb' if 'gnb' in exe else 'srsue'}{m.group(1) if m else '1'}"
        elif comm.startswith("open5gs-"):
            label = comm.replace("open5gs-", "")
        elif comm.startswith("qemu"):
            label = "qemu"
        out[label] = out.get(label, 0) + j
    return out


def proc_cpu(before, after, seconds, hz=100):
    """percent of ONE cpu per label over the window; only labels above 1 %."""
    r = {k: round(100.0 * (after.get(k, 0) - v) / (hz * seconds), 1) for k, v in before.items() if k in after}
    return {k: v for k, v in sorted(r.items(), key=lambda kv: -kv[1]) if v >= 1.0}


def cpu_sample(seconds, interval=1.0, reader=_stat, sleep=time.sleep, procs=_procs):
    prev = reader()
    p0 = procs() if procs else {}
    means, peak = [], {}
    for _ in range(int(seconds / interval)):
        sleep(interval)
        cur = reader()
        busy = {}
        for k, (t, idle) in cur.items():
            pt, pidle = prev[k]
            dt = t - pt
            busy[k] = 100.0 * (1 - (idle - pidle) / dt) if dt > 0 else 0.0
            peak[k] = max(peak.get(k, 0.0), busy[k])
        means.append(sum(busy.values()) / len(busy))
        prev = cur
    p1 = procs() if procs else {}
    return {"procs_pct_of_1cpu": proc_cpu(p0, p1, max(seconds, 1)) if procs else {},
            "mean_busy_pct": round(sum(means) / len(means), 1) if means else 0.0,
            "max_sec_busy_pct": round(max(means), 1) if means else 0.0,
            "per_cpu_peak_pct": {k: round(v, 1) for k, v in sorted(peak.items())}}


def main(argv=None):
    ap = argparse.ArgumentParser()
    sp = ap.add_subparsers(dest="cmd", required=True)
    s = sp.add_parser("summary"); s.add_argument("--dir", required=True); s.add_argument("--pairs", type=int, required=True)
    s.add_argument("--min-pair", type=float, default=50.0); s.add_argument("--out")
    c = sp.add_parser("cpu"); c.add_argument("--seconds", type=int, default=60); c.add_argument("--out")
    r_ = sp.add_parser("ratio"); r_.add_argument("--log", required=True); r_.add_argument("--start-offset", type=int, default=0)
    r_.add_argument("--scs", type=int, default=15); r_.add_argument("--out")
    a = ap.parse_args(argv)
    if a.cmd == "summary":
        r = summarize(a.dir, a.pairs, a.min_pair)
    elif a.cmd == "ratio":
        r = ratio_from_log(a.log, a.start_offset, a.scs)
    else:
        r = cpu_sample(a.seconds)
    txt = json.dumps(r, indent=2)
    if a.out:
        with open(a.out, "w") as f:
            f.write(txt)
    print(txt)
    return 0 if r.get("verdict", "PASS") == "PASS" else 1


if __name__ == "__main__":
    sys.exit(main())
