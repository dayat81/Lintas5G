#!/usr/bin/env python3
"""Offline analysis of a YouTube + QoD + MGLT v2.1 run (no ClickHouse required).

Inputs (a run directory, or explicit paths):
  phases.tsv          run_id cond rep t_start t_end
  pktlat.log          Zeek pktlat2 JSON (one object per line)
  pktlat_stats.log    optional
  playback/*.json or playback-<cond>-r<rep>.json from yt-playback.py
  playback/*.tsv      optional samples
  proto-counts.json   optional {cond: {udp443, tcp443, ...}} written by the runner
  conn.log            Zeek conn.log (n6); authoritative per-phase tcp/443 vs udp/443 share
  transport.json      optional {mode: auto|quic-only|tcp-only}
  pkt/*/pkthash.log   optional; used to compute the sgi-queue segment (n6↔sgiq)
  overhead / logcat   optional mglt2 closed line

Outputs: summary JSON (stdout and --out) + markdown table (--md).

Lab tap labels (pktlat2 VLAN fan-in): s1u=n3, s5s8=ue (NOT S5/S8), sgi=n6.

Pass criteria (USULAN, not a verdict until a lab run exists):
  P1  transport matches the requested mode (auto/quic-only: QUIC majority; tcp-only: TCP majority)
  P2  stall_count and stall_s on load+qod <= idle (or both zero)
  P3  startup_s on load+qod <= 1.5 x idle (or <= idle + 2 s)
  P4  advanced_s >= 0.80 * dur_s on load+qod (playback kept up)
  P5  p99 one_way DL at sgi (n6) on load+qod <= 50% of the load phase, if n>=100
      When sgi-queue samples exist, also report p99 DL sgi-queue (the shaper itself).
  P6  coverage q_ok / (q_ok+q_miss) >= 95% per phase when probes are present
  Throughput vs bitrate is reported when bitrate is obtainable; not a hard gate
      (ABR masks latency; bitrate may be missing).
"""
from __future__ import annotations

import argparse, collections, json, math, os, re, statistics, sys
from typing import Any, Optional

LAB_SEG = {"s1u": "n3", "s5s8": "ue", "sgi": "n6", "cgnat": "cgnat", "sgi-queue": "sgi-queue"}
CONDS = ("idle", "load", "load+qod")


def quantiles(xs: list[float], ps=(0.50, 0.95, 0.99)):
    if not xs:
        return {f"p{int(p*100)}": None for p in ps} | {"n": 0, "max": None}
    ys = sorted(xs)
    n = len(ys)
    out = {"n": n, "max": round(ys[-1], 3)}
    for p in ps:
        # nearest-rank, same idea as Sesi D ping awk
        i = min(n - 1, max(0, int(n * p) if n * p == int(n * p) and int(n * p) > 0 else int(n * p)))
        # match ClickHouse quantileExact-ish: index at floor(p*(n-1))
        j = min(n - 1, max(0, int(round(p * (n - 1)))))
        out[f"p{int(p*100)}"] = round(ys[j], 3)
    return out


def load_phases(path: str) -> list[dict[str, Any]]:
    rows = []
    with open(path) as f:
        for line in f:
            p = line.rstrip("\n").split("\t")
            if len(p) < 5 or p[0] in ("run_id", "session"):
                continue
            rows.append({"run_id": p[0], "cond": p[1], "rep": int(float(p[2])),
                         "t_start": float(p[3]), "t_end": float(p[4])})
    return rows


def _ts(obj: dict) -> Optional[float]:
    v = obj.get("ts") or obj.get("t0") or obj.get("t_ue")
    if v is None:
        return None
    if isinstance(v, (int, float)):
        return float(v)
    # Zeek JSON time may be a float string
    try:
        return float(v)
    except (TypeError, ValueError):
        return None


def load_pktlat(path: str) -> list[dict[str, Any]]:
    rows = []
    if not path or not os.path.isfile(path):
        return rows
    with open(path, errors="replace") as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            if line.startswith("{"):
                try:
                    rows.append(json.loads(line))
                except json.JSONDecodeError:
                    continue
    return rows


def assign_phase(ts: Optional[float], phases: list[dict]) -> Optional[dict]:
    if ts is None:
        return None
    for ph in phases:
        if ph["t_start"] <= ts <= ph["t_end"]:
            return ph
    return None


def load_json(path: Optional[str]) -> Any:
    if not path or not os.path.isfile(path):
        return None
    with open(path) as f:
        return json.load(f)


def find_playback(run_dir: str) -> dict[tuple, dict]:
    """Map (cond, rep) -> playback metrics dict."""
    out = {}
    if not run_dir or not os.path.isdir(run_dir):
        return out
    # playback-idle-r1.json or playback/idle-r1.json
    for dirpath, _, files in os.walk(run_dir):
        for fn in files:
            if not fn.endswith(".json"):
                continue
            m = re.search(r"(idle|load\+qod|load)[-_]r(\d+)", fn)
            if not m:
                continue
            if "pktlat" in fn or "summary" in fn or "proto" in fn:
                continue
            rec = load_json(os.path.join(dirpath, fn))
            if isinstance(rec, dict) and ("stall_count" in rec or "advanced_s" in rec):
                out[(m.group(1), int(m.group(2)))] = rec
    return out


def phase_pkt_stats(rows: list[dict], ph: dict) -> dict[str, Any]:
    t0, t1 = ph["t_start"], ph["t_end"]
    by: dict[tuple, list[float]] = collections.defaultdict(list)
    bytes_ul = bytes_dl = 0
    ok = miss = 0
    proto = collections.Counter()
    for r in rows:
        ts = _ts(r)
        if ts is None or not (t0 <= ts <= t1):
            # t_ue also in epoch seconds for v2.1
            continue
        if r.get("run_id") and ph.get("run_id") and r["run_id"] != ph["run_id"] and r["run_id"] != "live":
            continue
        st = r.get("status") or ""
        if st.startswith("miss") or st == "expired" or st == "nomap":
            miss += 1
        elif st == "ok" or r.get("one_way") is not None:
            ok += 1
        pr = (r.get("proto") or "quic").lower()
        proto[pr] += 1
        seg = r.get("seg") or ""
        lab = LAB_SEG.get(seg, seg)
        d = r.get("dir") or ""
        ow = r.get("one_way")
        if ow is None:
            # fall back to ow_<seg>
            key = {"s1u": "ow_s1u", "s5s8": "ow_s5s8", "sgi": "ow_sgi"}.get(seg)
            if key:
                ow = r.get(key)
        try:
            ow_f = float(ow) if ow is not None and ow != "" else None
        except (TypeError, ValueError):
            ow_f = None
        if ow_f is not None and d in ("UL", "DL") and lab:
            by[(d, lab)].append(ow_f)
        try:
            ln = int(r.get("len") or 0)
        except (TypeError, ValueError):
            ln = 0
        if d == "UL":
            bytes_ul += ln
        elif d == "DL":
            bytes_dl += ln
    dur = max(1e-6, t1 - t0)
    lat = {f"{d}_{lab}": quantiles(xs) for (d, lab), xs in sorted(by.items())}
    return {
        "latency_ms": lat,
        "coverage": {"ok": ok, "miss": miss,
                     "pct": round(100.0 * ok / max(1, ok + miss), 2)},
        "throughput_bps": {"ul": round(8.0 * bytes_ul / dur, 1),
                           "dl": round(8.0 * bytes_dl / dur, 1)},
        "bytes": {"ul": bytes_ul, "dl": bytes_dl},
        "proto": dict(proto),
        "dur_s": round(dur, 3),
    }



def iter_zeek_rows(path: str):
    """Yield dicts from a Zeek TSV log (#fields header)."""
    fields = None
    with open(path, errors="replace") as f:
        for line in f:
            if line.startswith("#fields"):
                fields = line.rstrip("\n").split("\t")[1:]
                continue
            if line.startswith("#") or not fields:
                continue
            cols = line.rstrip("\n").split("\t")
            yield dict(zip(fields, cols))


def load_conn_log(path: str) -> list[dict[str, Any]]:
    if not path or not os.path.isfile(path):
        return []
    rows = []
    for o in iter_zeek_rows(path):
        try:
            ts = float(o.get("ts") or 0)
        except (TypeError, ValueError):
            continue
        proto = (o.get("proto") or "").lower()
        def _port(k):
            try:
                return int(float(o.get(k) or 0))
            except (TypeError, ValueError):
                return 0
        def _num(k):
            v = o.get(k, "-")
            if v in ("-", "(empty)", "", None):
                return 0.0
            try:
                return float(v)
            except (TypeError, ValueError):
                return 0.0
        rows.append({
            "ts": ts, "proto": proto,
            "orig_p": _port("id.orig_p"), "resp_p": _port("id.resp_p"),
            "duration": _num("duration"),
            "orig_bytes": _num("orig_bytes"), "resp_bytes": _num("resp_bytes"),
        })
    return rows


def _is_443(r: dict) -> bool:
    return r.get("resp_p") == 443 or r.get("orig_p") == 443


def transport_share(conn_rows: list[dict], ph: dict) -> dict[str, Any]:
    """Count 443 flows whose interval overlaps the phase window."""
    t0, t1 = ph["t_start"], ph["t_end"]
    udp = tcp = 0
    ub = tb = 0.0
    for r in conn_rows:
        if not _is_443(r):
            continue
        end = r["ts"] + (r["duration"] if r["duration"] > 0 else 0.0)
        if r["ts"] <= t1 and end >= t0:
            b = r["orig_bytes"] + r["resp_bytes"]
            if r["proto"] == "udp":
                udp += 1
                ub += b
            elif r["proto"] == "tcp":
                tcp += 1
                tb += b
    total = udp + tcp
    return {
        "udp443": udp, "tcp443": tcp,
        "udp443_bytes": int(ub), "tcp443_bytes": int(tb),
        "share_quic": round(udp / total, 3) if total else None,
        "share_tcp": round(tcp / total, 3) if total else None,
        "source": "conn.log",
    }


def load_pkthash_logs(run_dir: str) -> list[dict[str, Any]]:
    """Load pkthash TSV rows from a run dir (pkt/<tap>/pkthash*.log or **/pkthash*.log)."""
    rows = []
    if not run_dir or not os.path.isdir(run_dir):
        return rows
    paths = []
    for dirpath, _, files in os.walk(run_dir):
        for fn in files:
            if fn.startswith("pkthash") and (fn.endswith(".log") or fn.endswith(".tsv")):
                paths.append(os.path.join(dirpath, fn))
    for path in sorted(paths):
        try:
            for o in iter_zeek_rows(path):
                try:
                    ts = float(o.get("ts") or 0)
                except (TypeError, ValueError):
                    continue
                rows.append({
                    "ts": ts,
                    "tap": o.get("tap") or "",
                    "dir": o.get("dir") or "",
                    "proto": o.get("proto") or "",
                    "h": o.get("h") or "",
                    "len": o.get("len") or "0",
                    "run_id": o.get("run_id") or "",
                })
        except OSError:
            continue
    return rows


def sgi_queue_stats(pkthash_rows: list[dict], ph: dict) -> dict[str, Any]:
    """Join n6↔sgiq by (dir, h) inside the phase window. Returns latency_ms-like dict."""
    t0, t1 = ph["t_start"], ph["t_end"]
    by: dict[tuple, dict[str, list]] = {}
    for r in pkthash_rows:
        if not (t0 <= r["ts"] <= t1):
            continue
        if r["tap"] not in ("n6", "sgiq") or not r["h"] or r["dir"] not in ("UL", "DL"):
            continue
        key = (r["dir"], r["h"])
        slot = by.setdefault(key, {"n6": [], "sgiq": []})
        slot[r["tap"]].append(r["ts"])
    xs = {"UL": [], "DL": []}
    for (d, _h), slot in by.items():
        if not slot["n6"] or not slot["sgiq"]:
            continue
        t_n6, t_sgiq = min(slot["n6"]), min(slot["sgiq"])
        # DL: sgiq pre-HTB, n6 post-HTB; UL: n6 pre-ifb, sgiq post-ifb0
        ms = (1000.0 * (t_n6 - t_sgiq)) if d == "DL" else (1000.0 * (t_sgiq - t_n6))
        if 0 <= ms < 5000:
            xs[d].append(ms)
    out = {}
    for d, arr in xs.items():
        if arr:
            out[f"{d}_sgi-queue"] = quantiles(arr)
    return out


def discover_conn_log(run_dir: str, explicit: Optional[str] = None) -> Optional[str]:
    if explicit and os.path.isfile(explicit):
        return explicit
    if not run_dir:
        return None
    for cand in (os.path.join(run_dir, "conn.log"),
                 os.path.join(run_dir, "pkt", "n6", "conn.log"),
                 os.path.join(run_dir, "n6", "conn.log")):
        if os.path.isfile(cand):
            return cand
    return None


def load_transport_mode(run_dir: str) -> str:
    meta = load_json(os.path.join(run_dir, "transport.json") if run_dir else None) or {}
    mode = str(meta.get("mode") or os.environ.get("TRANSPORT") or "auto").lower()
    return mode if mode in ("auto", "quic-only", "tcp-only") else "auto"


def propose_pass(per: dict[str, Any], transport_mode: str = "auto") -> dict[str, Any]:
    """USULAN criteria across reps. per[cond][rep] = {playback, pkt, proto}."""
    def agg(cond, key, src="playback"):
        xs = []
        for rec in per.get(cond, {}).values():
            v = (rec.get(src) or {}).get(key)
            if v is not None:
                xs.append(v)
        return xs

    flags = []
    # P1 transport vs requested mode (counts prefer conn.log share, then proto-counts, then pkt proto)
    tcp = udp = 0
    for cond, reps in per.items():
        for rec in reps.values():
            pr = rec.get("transport_share") or rec.get("proto_counts") or rec.get("pkt", {}).get("proto") or {}
            udp += int(pr.get("udp443") or pr.get("quic") or 0)
            tcp += int(pr.get("tcp443") or pr.get("tcp") or 0)
    if udp == 0 and tcp == 0:
        flags.append("P1: no 443 flow counts (cannot judge QUIC vs TCP)")
        p1 = None
    elif transport_mode == "tcp-only":
        p1 = tcp > 0 and tcp >= udp
        if not p1:
            flags.append(f"P1: tcp-only requested but udp={udp} tcp={tcp}")
    else:
        # auto and quic-only: want QUIC majority
        p1 = udp > 0 and udp >= tcp
        if not p1:
            flags.append(f"P1: TCP fallback or no QUIC (udp={udp} tcp={tcp}, mode={transport_mode})")
        elif transport_mode == "quic-only" and tcp > 0 and tcp > 0.1 * max(udp, 1):
            flags.append(f"P1: quic-only but tcp={tcp} still present (udp={udp})")

    def median(xs, default=None):
        return default if not xs else statistics.median(xs)

    idle_stall_c = median(agg("idle", "stall_count"), 0)
    qod_stall_c = median(agg("load+qod", "stall_count"), 0)
    idle_stall_s = median(agg("idle", "stall_s"), 0.0)
    qod_stall_s = median(agg("load+qod", "stall_s"), 0.0)
    p2 = qod_stall_c <= idle_stall_c and qod_stall_s <= idle_stall_s + 0.5
    if not p2:
        flags.append(f"P2: stalls load+qod={qod_stall_c}/{qod_stall_s}s > idle={idle_stall_c}/{idle_stall_s}s")

    idle_su = median(agg("idle", "startup_s"))
    qod_su = median(agg("load+qod", "startup_s"))
    p3 = None
    if idle_su is not None and qod_su is not None:
        p3 = qod_su <= max(idle_su * 1.5, idle_su + 2.0)
        if not p3:
            flags.append(f"P3: startup load+qod={qod_su}s > 1.5x idle={idle_su}s")
    else:
        flags.append("P3: startup_s missing")

    adv, dur = [], []
    for rec in per.get("load+qod", {}).values():
        pb = rec.get("playback") or {}
        if pb.get("advanced_s") is not None:
            adv.append(pb["advanced_s"])
        if pb.get("dur_s"):
            dur.append(pb["dur_s"])
    p4 = bool(adv and dur and median(adv) >= 0.80 * median(dur))
    if not p4:
        flags.append(f"P4: advanced_s {median(adv) if adv else None} < 80% of dur {median(dur) if dur else None}")

    def p99_dl_sgi(cond):
        xs = []
        for rec in per.get(cond, {}).values():
            q = ((rec.get("pkt") or {}).get("latency_ms") or {}).get("DL_n6") or {}
            if q.get("p99") is not None:
                xs.append(q["p99"])
        return median(xs)

    load_p99, qod_p99 = p99_dl_sgi("load"), p99_dl_sgi("load+qod")
    p5 = None
    if load_p99 is not None and qod_p99 is not None:
        p5 = qod_p99 <= 0.5 * load_p99
        if not p5:
            flags.append(f"P5: p99 DL n6 load+qod={qod_p99} > 50% of load={load_p99}")
    else:
        flags.append("P5: p99 DL n6 missing (need MGLT matches)")

    cov = []
    for rec in per.get("load+qod", {}).values():
        c = (rec.get("pkt") or {}).get("coverage") or {}
        if c.get("ok", 0) + c.get("miss", 0) > 0:
            cov.append(c.get("pct", 0))
    p6 = bool(cov) and median(cov) >= 95.0
    if not p6:
        flags.append(f"P6: MGLT coverage {median(cov) if cov else None}% < 95%")

    keys = {"P1_quic": p1, "P2_stalls": p2, "P3_startup": p3, "P4_advance": p4, "P5_p99_qod": p5, "P6_coverage": p6}
    judged = [v for v in keys.values() if v is not None]
    return {"criteria": keys, "flags": flags, "verdict_usulan": "PASS" if judged and all(judged) else ("INCOMPLETE" if not judged or any(v is None for v in keys.values()) else "FAIL")}


def markdown(summary: dict) -> str:
    lines = ["# YouTube + QoD — ringkasan (offline)", "",
             f"run_id: `{summary.get('run_id','')}`  transport: {summary.get('transport','?')}  "
             f"mode: {summary.get('transport_mode','auto')}", ""]
    lines += ["| cond | rep | startup_s | stall_n | stall_s | advanced_s | p99 DL n6 | p99 DL sgi-q | cov% | udp443 | tcp443 |",
              "|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|"]
    for cond in CONDS:
        for rep, rec in sorted((summary.get("phases") or {}).get(cond, {}).items()):
            pb, pkt = rec.get("playback") or {}, rec.get("pkt") or {}
            dl = (pkt.get("latency_ms") or {}).get("DL_n6") or {}
            sq = (pkt.get("latency_ms") or {}).get("DL_sgi-queue") or {}
            cov = (pkt.get("coverage") or {}).get("pct")
            sh = rec.get("transport_share") or rec.get("proto_counts") or {}
            lines.append("| {cond} | {rep} | {su} | {sc} | {ss} | {ad} | {p99} | {sq} | {cov} | {u} | {c} |".format(
                cond=cond, rep=rep,
                su=pb.get("startup_s", ""), sc=pb.get("stall_count", ""),
                ss=pb.get("stall_s", ""), ad=pb.get("advanced_s", ""),
                p99=dl.get("p99", ""), sq=sq.get("p99", ""), cov=cov if cov is not None else "",
                u=sh.get("udp443", ""), c=sh.get("tcp443", "")))
    lines += ["", "## Kriteria lulus (USULAN)", ""]
    pa = summary.get("pass") or {}
    for k, v in (pa.get("criteria") or {}).items():
        mark = "PASS" if v is True else ("n/a" if v is None else "FAIL")
        lines.append(f"- {k}: **{mark}**")
    for fl in pa.get("flags") or []:
        lines.append(f"- catatan: {fl}")
    lines.append(f"\nVerdict (USULAN): **{pa.get('verdict_usulan','')}**\n")
    if summary.get("overhead"):
        lines += ["## Overhead probe", "", f"```\n{summary['overhead']}\n```", ""]
    lines += ["## Batasan", "",
              "- ABR YouTube dapat menyembunyikan kenaikan latency (turun ke itag lebih rendah).",
              "- QUIC terenkripsi: one-way lewat hash MGLT v2.1 + ts tap, bukan spin bit.",
              "- Segmen `s5s8` pada pktlat2 di lab ini = tap UE (`tun_srsue`), bukan S5/S8.",
              "- Enforcement QoD tetap di tc SGi. Segmen `sgi-queue` (n6↔sgiq) mengukur delay antrean HTB: "
              "DL pre-HTB (nft dup / mirror) vs n6 post-HTB; UL n6 pre-ifb vs ifb0 post-HTB.",
              "- advanced_s resmi = posisi PLAYING terakhir − pertama (bukan pos dari 0 atau pre-PLAYING).",
              ""]
    return "\n".join(lines)


def analyze(run_dir: str, phases_path: str, pktlat_path: str, proto_path: Optional[str] = None,
            conn_path: Optional[str] = None) -> dict[str, Any]:
    phases = load_phases(phases_path)
    rows = load_pktlat(pktlat_path)
    playback = find_playback(run_dir)
    proto_all = load_json(proto_path) or {}
    conn_rows = load_conn_log(discover_conn_log(run_dir, conn_path) or "")
    pkthash_rows = load_pkthash_logs(run_dir)
    transport_mode = load_transport_mode(run_dir)
    run_id = phases[0]["run_id"] if phases else ""
    per: dict[str, dict] = collections.defaultdict(dict)
    for ph in phases:
        key = (ph["cond"], ph["rep"])
        pkt = phase_pkt_stats(rows, ph)
        sq = sgi_queue_stats(pkthash_rows, ph)
        if sq:
            pkt.setdefault("latency_ms", {}).update(sq)
        share = transport_share(conn_rows, ph) if conn_rows else None
        proto_counts = (proto_all.get(ph["cond"]) or {}).get(str(ph["rep"])) or proto_all.get(f"{ph['cond']}-r{ph['rep']}")
        if share and (share["udp443"] or share["tcp443"]):
            # conn.log is authoritative; keep proto-counts as a sidecar
            pass
        elif proto_counts:
            share = {
                "udp443": int(proto_counts.get("udp443") or proto_counts.get("quic") or 0),
                "tcp443": int(proto_counts.get("tcp443") or proto_counts.get("tcp") or 0),
                "source": "proto-counts",
            }
            tot = share["udp443"] + share["tcp443"]
            share["share_quic"] = round(share["udp443"] / tot, 3) if tot else None
            share["share_tcp"] = round(share["tcp443"] / tot, 3) if tot else None
        rec = {
            "t_start": ph["t_start"], "t_end": ph["t_end"],
            "playback": playback.get(key),
            "pkt": pkt,
            "proto_counts": proto_counts,
            "transport_share": share,
        }
        per[ph["cond"]][ph["rep"]] = rec
    # overhead from a sidecar file if present
    overhead = None
    for fn in ("overhead.txt", "mglt2-overhead.txt"):
        p = os.path.join(run_dir, fn)
        if os.path.isfile(p):
            overhead = open(p).read().strip()
            break
    transport = "unknown"
    u = tc = 0
    for reps in per.values():
        for rec in reps.values():
            pr = rec.get("transport_share") or rec.get("proto_counts") or rec.get("pkt", {}).get("proto") or {}
            u += int(pr.get("udp443") or pr.get("quic") or 0)
            tc += int(pr.get("tcp443") or pr.get("tcp") or 0)
    if u or tc:
        if transport_mode == "tcp-only":
            transport = "tcp" if tc >= u and tc > 0 else "quic-leak"
        else:
            transport = "quic" if u >= tc and u > 0 else "tcp-fallback"
    summary = {
        "run_id": run_id,
        "transport": transport,
        "transport_mode": transport_mode,
        "phases": {c: {int(r): rec for r, rec in reps.items()} for c, reps in per.items()},
        "pass": propose_pass(per, transport_mode=transport_mode),
        "overhead": overhead,
        "lab_seg": LAB_SEG,
    }
    return summary


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--dir", required=True, help="run directory")
    ap.add_argument("--phases", help="default: <dir>/phases.tsv")
    ap.add_argument("--pktlat", help="default: <dir>/pktlat.log")
    ap.add_argument("--proto", help="optional proto-counts.json")
    ap.add_argument("--conn", help="optional Zeek conn.log (default: <dir>/conn.log)")
    ap.add_argument("--out")
    ap.add_argument("--md")
    args = ap.parse_args(argv)
    d = args.dir
    summary = analyze(d, args.phases or os.path.join(d, "phases.tsv"),
                      args.pktlat or os.path.join(d, "pktlat.log"),
                      args.proto or (os.path.join(d, "proto-counts.json") if os.path.isfile(os.path.join(d, "proto-counts.json")) else None),
                      conn_path=args.conn)
    if args.out:
        with open(args.out, "w") as f:
            json.dump(summary, f, indent=2)
            f.write("\n")
    if args.md:
        with open(args.md, "w") as f:
            f.write(markdown(summary))
    if not args.out:
        json.dump(summary, sys.stdout, indent=2)
        sys.stdout.write("\n")
    else:
        sys.stdout.write(markdown(summary))
    return 0


if __name__ == "__main__":
    sys.exit(main())
