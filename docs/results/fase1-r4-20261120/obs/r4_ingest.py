#!/usr/bin/env python3
"""G8 r4: one GCP r4 run -> booster.* rows (JSONEachRow) in obs/in-r4/<run>/ for ch-test. run_id = r4-<run>.
qod_event = adapter 0.1.3 export events (deviceKey hash, no IMSI/IP) for the run's sessions; run_phase from harness times;
n3_qfi_flow from the run's N3 pcap (as_ip blank = public CDN IP redacted, ue_hash = sha256(ip)[:12]);
mglt_sample/mglt_window from the app's in-app MGLT echo (logcat 'mglt echo', reflector <BACKEND_IP>:443)."""
import json, glob, os, sys, re, hashlib, subprocess as sp, datetime as dt
UE_POOL_PREFIX = os.environ["UE_POOL_PREFIX"]  # UE pool prefix of the lab (redacted in public repo), e.g. "<UE_POOL>." 
run = sys.argv[1]; R = f"/workspace/booster-e2e-r4/ev/{run}/core/{run}"; RID = "r4-" + run
O = f"/workspace/fase1-closeout/obs/in-r4/{run}"; os.makedirs(O, exist_ok=True)
iso = lambda t: dt.datetime.fromtimestamp(t, dt.timezone.utc).strftime("%Y-%m-%d %H:%M:%S.%f")[:-3]
q = lambda xs, p: sorted(xs)[min(len(xs) - 1, int(p * len(xs)))] if xs else None
def times(f):
    T = {}
    for l in open(f):
        p = l.split()
        if len(p) >= 2:
            try: T.setdefault(p[0], float(p[1]))
            except ValueError: pass
    return T
ET = times(f"{R}/emu/times"); CT = times(f"{R}/times")
W = json.loads(sp.run(["python3", "/workspace/booster-e2e-r4/bundle/tools/window.py", f"{R}/emu/logcat-booster.txt", f"{R}/emu/times"], capture_output=True, text=True).stdout or "{}")
t0 = W.get("t_booster") or ET["t_booster"]; t1 = W.get("t_booster_finish") or ET.get("t_finish_req", ET["t_end"])
rows = {k: [] for k in ("run_phase", "mglt_sample", "mglt_window", "qod_event", "n3_qfi_flow")}
sids = set()
for l in open(f"{R}/adapter.win.log"):
    try: d = json.loads(l)
    except ValueError: continue
    if d.get("sessionId"): sids.add(d["sessionId"])
for f in sorted(glob.glob("/workspace/booster-e2e-r4/ev/adapter-events/*.jsonl")):
    for l in open(f):
        e = json.loads(l)
        if e.get("sessionId") in sids:
            r = dict(e); r["run_id"] = RID; r["source"] = "adapter"; r["ts"] = e["ts"].replace("T", " ").replace("Z", ""); rows["qod_event"].append(r)
ph = [("load", CT["t_bulk_on"], t0, 0), ("boost+load", t0, t1, 1), ("load-after", t1, CT.get("t_bulk_off", t1), 0)]
for n, a, b, bo in ph:
    if b > a: rows["run_phase"].append(dict(run_id=RID, phase=n, t_from=iso(a), t_to=iso(b), boost=bo, load=1, session_id=",".join(sorted(sids)) if bo else ""))
phase = lambda t: "before" if CT["t_bulk_on"] <= t < t0 else "boost" if t0 <= t < t1 else None
by = {}
for l in open(f"{R}/emu/logcat-booster.txt"):
    m = re.search(r"^\s*([0-9.]+).*mglt echo fid=(\w+) seq=(\d+) rtt_ms=([0-9.]+)", l)
    if not m: continue
    t, fid, seq, rtt = float(m[1]), m[2], int(m[3]), float(m[4])
    rows["mglt_sample"].append(dict(run_id=RID, ts=iso(t), device="emu1", app_pkg="id.booster.poc.examine", fid=int(fid, 16) % 2**31, seq=seq, ev="echo", proto=17,
                                    as_ip="<BACKEND_IP>", as_port=443, rtt_ms=rtt, crc_ok=1))
    if phase(t): by.setdefault(int(t), []).append(rtt)
for sec, v in sorted(by.items()):
    p = phase(sec + 0.5)
    if p: rows["mglt_window"].append(dict(run_id=RID, ts=iso(sec + 1), device="emu1", app_pkg="id.booster.poc.examine", flow="refl/<BACKEND_IP>:443", phase=p,
        session_id="", qos_profile="QOS_L" if p == "boost" else "", n=len(v), p50_ms=q(v, .5), p99_ms=q(v, .99), loss_pct=0, stall=int(q(v, .99) > 1000), source="app-echo", policy_state="booster.5.1"))
out = sp.run(["tshark", "-r", f"{R}/n3.pcap", "-n", "-T", "fields", "-E", "separator=\t", "-E", "occurrence=l", "-e", "frame.time_epoch", "-e", "ip.src", "-e", "ip.dst",
              "-e", "udp.srcport", "-e", "udp.dstport", "-e", "tcp.srcport", "-e", "tcp.dstport", "-e", "ip.proto", "-e", "gtp.ext_hdr.pdu_ses_con.qos_flow_id", "-e", "frame.len"],
             capture_output=True, text=True).stdout
agg = {}
for l in out.splitlines():
    t, s_, d_, us, ud, ts_, td, pr, qfi, ln = (l.split("\t") + [""] * 10)[:10]
    if not qfi: continue
    dl = d_.startswith(UE_POOL_PREFIX); ue = d_ if dl else s_; sp_ = (us or ts_) if dl else (ud or td)
    k = (int(float(t)), "DL" if dl else "UL", int(qfi.split(",")[-1]), {"17": "udp", "6": "tcp", "1": "icmp"}.get(pr, pr), int(sp_ or 0), hashlib.sha256(ue.encode()).hexdigest()[:12])
    a = agg.setdefault(k, [0, 0]); a[0] += 1; a[1] += int(ln)
for (sec, dr, qf, pr, asp, uh), (n, b) in agg.items():
    rows["n3_qfi_flow"].append(dict(run_id=RID, ts=dt.datetime.fromtimestamp(sec, dt.timezone.utc).strftime("%Y-%m-%d %H:%M:%S"), source="pcap-n3-lo", dir=dr, qfi=qf, proto=pr,
                                    as_ip="", as_port=asp, ue_hash=uh, pkts=n, bytes=b))
for k, v in rows.items():
    with open(f"{O}/{k}.jsonl", "w") as f:
        for r in v: f.write(json.dumps(r) + "\n")
    print(k, len(v))
print(json.dumps(dict(run_id=RID, t_from_ms=int((CT["t_bulk_on"] - 10) * 1000), t_to_ms=int((CT.get("t_bulk_off", t1) + 10) * 1000))))
