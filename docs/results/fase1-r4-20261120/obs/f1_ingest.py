#!/usr/bin/env python3
"""Item 6: normalize n5-lab results (multiue/res, adapter 0.1.3 events export, N3 pcaps) into booster.* rows (JSONEachRow) and load
them into ch-test. No IMSI/IP/token: device = ue1/ue2 label, ue_hash = sha256(ip)[:12], adapter deviceKey is already a hash."""
import json, glob, os, csv, hashlib, subprocess as sp, statistics as st, datetime as dt
F = "/workspace/fase1-closeout"; O = F + "/obs/in"; os.makedirs(O, exist_ok=True)
EV = "/workspace/qod-adapter-013/res/events"; RAW = "/workspace/fase1-raw/multiue"
iso = lambda t: dt.datetime.fromtimestamp(t, dt.timezone.utc).strftime("%Y-%m-%d %H:%M:%S.%f")
q = lambda xs, p: sorted(xs)[min(len(xs) - 1, int(p * len(xs)))] if xs else None
events = []
for f in sorted(glob.glob(EV + "/events-*.jsonl")):
    for l in open(f): events.append(json.loads(l))
evt = lambda sid, pred: [e for e in events if e["sessionId"] == sid and pred(e)]
tsf = lambda s: dt.datetime.fromisoformat(s.replace("Z", "+00:00")).timestamp()
rows = {k: [] for k in ("run_phase", "mglt_sample", "mglt_window", "qod_event", "n3_qfi_flow")}
sid_run = {}
def probe(f):
    out = []
    for r in csv.DictReader(open(f)):
        out.append((int(r["seq"]), float(r["t_send"]), float(r["rtt_ms"])))
    return sorted(out, key=lambda x: x[1])   # udpprobe appends lost packets at the end
def windows(run, dev, app, ph_of, samples, sid_of, prof_of):
    by = {}
    for seq, t, rtt in samples: by.setdefault(int(t), []).append(rtt)
    for sec, v in sorted(by.items()):
        ok = [x for x in v if x >= 0]; ph = ph_of(sec + 0.5)
        if ph is None: continue
        p99 = q(ok, 0.99)
        rows["mglt_window"].append(dict(run_id=run, ts=iso(sec + 1), device=dev, app_pkg=app, flow="udp/<AS_IP>:18080", phase=ph, session_id=sid_of(sec) or "",
            qos_profile=prof_of(sec) or "", n=len(v), p50_ms=q(ok, 0.5), p99_ms=p99, loss_pct=round(100 * (len(v) - len(ok)) / len(v), 2),
            stall=int(p99 is None or p99 > 1000), source="app-echo", policy_state="lab-udpprobe"))
for d in sorted(glob.glob(F + "/multiue/res/*-r[0-9]")):
    tag = os.path.basename(d); run = "f1-n5-" + tag; R = json.load(open(d + "/result.json"))
    if tag.startswith("ab"):
        b1, q1, q2, b2 = probe(d + "/base.ue1.probe.csv"), probe(d + "/qod.ue1.probe.csv"), probe(d + "/qod.ue2.probe.csv"), probe(d + "/base.ue2.probe.csv")
        a = R["qod"]["api"]; sid = a["sessionId"]; sid_run[sid] = run
        tav = tsf(evt(sid, lambda e: e["event"] == "status.changed" and e["status"] == "AVAILABLE")[0]["ts"])
        tend = tsf(evt(sid, lambda e: e["event"] == "deleted")[0]["ts"])
        bl = (b1[0][1] + 4, b1[-1][1] - 2); ql = (tav, min(q1[-1][1] - 2, tend))
        rows["run_phase"] += [dict(run_id=run, phase="load", t_from=iso(bl[0]), t_to=iso(bl[1]), boost=0, load=1, session_id=""),
                              dict(run_id=run, phase="boost+load", t_from=iso(ql[0]), t_to=iso(ql[1]), boost=1, load=1, session_id=sid)]
        for seq, t, rtt in b1 + q1:
            rows["mglt_sample"].append(dict(run_id=run, ts=iso(t + max(rtt, 0) / 1000), device="ue1", app_pkg="lab.udpprobe.ue1", fid=1, seq=seq, ev="udp", proto=17,
                                            as_ip="<AS_IP>", as_port=18080, rtt_ms=rtt if rtt >= 0 else None, crc_ok=1))
        inq = lambda t: ql[0] <= t <= ql[1]
        windows(run, "ue1", "lab.udpprobe.ue1", lambda t: "before" if bl[0] <= t <= bl[1] else "boost" if inq(t) else None, b1 + q1,
                lambda s: sid if inq(s) else None, lambda s: "QOS_L" if inq(s) else None)
        windows(run, "ue2", "lab.udpprobe.ue2", lambda t: "before" if (bl[0] <= t <= bl[1] or inq(t)) else None, b2 + q2, lambda s: None, lambda s: None)
    else:
        P = R["par"]; tav = {}
        for a in P["api"]:
            sid_run[a["sessionId"]] = run
            tav[a["who"]] = (tsf(evt(a["sessionId"], lambda e: e["event"] == "status.changed" and e["status"] == "AVAILABLE")[0]["ts"]),
                             tsf(evt(a["sessionId"], lambda e: e["event"] == "deleted")[0]["ts"]), a["sessionId"], a["profile"])
        for u in ("ue1", "ue2"):
            s = probe(f"{d}/par.{u}.probe.csv"); t0, t1, sid, prof = tav[u]; w = (t0, min(s[-1][1] - 2, t1))
            inw = lambda t, w=w: w[0] <= t <= w[1]
            windows(run, u, "lab.udpprobe." + u, lambda t, inw=inw: "boost" if inw(t) else None, s, lambda x, inw=inw, sid=sid: sid if inw(x) else None, lambda x, inw=inw, prof=prof: prof if inw(x) else None)
            if u == "ue1":
                for seq, t, rtt in s:
                    rows["mglt_sample"].append(dict(run_id=run, ts=iso(t + max(rtt, 0) / 1000), device="ue1", app_pkg="lab.udpprobe.ue1", fid=1, seq=seq, ev="udp", proto=17,
                                                    as_ip="<AS_IP>", as_port=18080, rtt_ms=rtt if rtt >= 0 else None, crc_ok=1))
        rows["run_phase"].append(dict(run_id=run, phase="boost+load", t_from=iso(max(v[0] for v in tav.values())), t_to=iso(min(v[1] for v in tav.values())), boost=1, load=1,
                                      session_id=",".join(v[2] for v in tav.values())))
        pc = f"{RAW}/{tag}-n3.pcap"
        if os.path.exists(pc):
            out = sp.run(["tshark", "-r", pc, "-n", "-T", "fields", "-E", "separator=\t", "-E", "occurrence=l", "-e", "frame.time_epoch", "-e", "ip.src", "-e", "ip.dst",
                          "-e", "udp.srcport", "-e", "udp.dstport", "-e", "ip.proto", "-e", "gtp.ext_hdr.pdu_ses_con.qos_flow_id", "-e", "frame.len"], capture_output=True, text=True).stdout
            agg = {}
            for l in out.splitlines():
                t, s_, d_, spt, dpt, pr, qfi, ln = (l.split("\t") + [""] * 8)[:8]
                if not qfi: continue
                dl = s_ == "<AS_IP>"; ue = d_ if dl else s_; asp = spt if dl else dpt
                k = (int(float(t)), "DL" if dl else "UL", int(qfi), {"17": "udp", "6": "tcp", "1": "icmp"}.get(pr, pr), int(asp or 0) if pr in ("17", "6") else 0, hashlib.sha256(ue.encode()).hexdigest()[:12])
                a = agg.setdefault(k, [0, 0]); a[0] += 1; a[1] += int(ln)
            for (sec, dr, qf, pr, asp, uh), (n, b) in agg.items():
                rows["n3_qfi_flow"].append(dict(run_id=run, ts=dt.datetime.fromtimestamp(sec, dt.timezone.utc).strftime("%Y-%m-%d %H:%M:%S"), source="pcap-n3-lo", dir=dr, qfi=qf, proto=pr,
                                                as_ip="<AS_IP>", as_port=asp, ue_hash=uh, pkts=n, bytes=b))
for f in glob.glob(F + "/multiue/res/pilot*/result.json"):
    sid_run[json.load(open(f))["qod"]["api"]["sessionId"]] = "f1-n5-pilot"
for e in events:   # all adapter 0.1.3 events; sessions outside item 5 -> run f1-n5-items2-3 (callbacks + trace)
    r = dict(e); r["run_id"] = sid_run.get(e["sessionId"], "f1-n5-items2-3"); r["source"] = "adapter"; r["ts"] = e["ts"].replace("T", " ").replace("Z", "")
    rows["qod_event"].append(r)
for k, v in rows.items():
    with open(f"{O}/{k}.jsonl", "w") as f:
        for r in v: f.write(json.dumps(r) + "\n")
    print(k, len(v))
