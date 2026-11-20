#!/usr/bin/env python3
"""Item 5 multi-UE A/B via CAMARA API (n5 lab). Run on the box as user with sudo.
Per rep: phase BASE (no session) then phase QOD (UE1: CAMARA QoD session QOS_L, ports 18080+18081; UE2: none). Both phases, both UEs:
  BE bulk DL UDP (iperf3 -R, AS port 52x1, BE_RATE) + session-eligible DL UDP flow (AS port 1808x, QF_RATE) + UDP RTT probe 50 pps (AS 18080).
Mode PAR: UE1 QOS_L + UE2 QOS_E in parallel (separate CAMARA clients and sink paths), N3 capture headers -> QFI isolation per UE.
Usage: mu5.py ab <tag> | mu5.py par <tag>. Output res/<tag>/ (no IMSI; UE IPs replaced by ue1/ue2)."""
import json, os, subprocess as sp, sys, time, statistics as st, threading
H = os.path.dirname(os.path.abspath(__file__)); F = os.path.dirname(H); sys.path.insert(0, F + "/tools")
DUR = int(os.environ.get("DUR", 25)); BE_RATE = os.environ.get("BE_RATE", "150M"); QF_RATE = os.environ.get("QF_RATE", "15M"); WARM = 4; TAIL = 2
PY = "/workspace/qod-adapter/.venv/bin/python"
def pid(c): return sp.check_output(["sudo", "docker", "inspect", "-f", "{{.State.Pid}}", c], text=True).strip()
def sh(cmd, **kw): return sp.run(cmd, shell=True, text=True, capture_output=True, **kw)
def ueip(i): return sh(f"sudo cat /workspace/oai-n5-test/secrets/ue{i}.ip").stdout.strip()
def api(args):  # CAMARA calls run in the core netns (adapter is loopback-only)
    r = sh(f"sudo nsenter -t {pid('n5-lab')} -n {PY} {H}/api.py " + args); 
    if r.returncode: raise RuntimeError(r.stderr[-400:])
    return json.loads(r.stdout.strip().splitlines()[-1])
def traffic(R, tag, dur):
    """start BE + QF iperf3 DL and probes for both UEs; return after dur."""
    sh("sudo docker exec n5-lab pkill -x iperf3"); time.sleep(0.5)
    for u in (1, 2):
        for p in (5200 + u * 10 + 1, 18080 + u):
            sh(f"sudo docker exec -d n5-lab iperf3 -s -1 -B <AS_IP> -p {p}")
    time.sleep(1); procs = []
    for u in (1, 2):
        procs.append(sp.Popen(f"sudo nsenter -t {pid(f'n5-ue{u}')} -n python3 {F}/tools/udpprobe.py <AS_IP> 18080 50 {dur} {R}/{tag}.ue{u}.probe.csv", shell=True))
        for p, rate, nm in ((5200 + u * 10 + 1, BE_RATE, "be"), (18080 + u, QF_RATE, "qf")):
            procs.append(sp.Popen(f"timeout {dur + 20} sudo docker exec n5-ue{u} iperf3 -c <AS_IP> -p {p} -u -R -b {rate} -l 1300 -t {dur} --get-server-output -J > {R}/{tag}.ue{u}.{nm}.json 2>&1", shell=True))
    return procs
def probe_stats(f, t0, t1):
    rows = [l.split(",") for l in open(f).read().splitlines()[1:]]
    rows = [(float(t), float(r)) for _, t, r in rows if t0 <= float(t) <= t1]
    ok = sorted(r for _, r in rows if r >= 0); n = len(rows)
    q = lambda p: ok[min(len(ok) - 1, int(p * len(ok)))] if ok else None
    return {"n": n, "loss_pct": round(100 * (n - len(ok)) / n, 3) if n else None, "p50_ms": q(0.5), "p99_ms": q(0.99), "max_ms": ok[-1] if ok else None}
def ip_stats(f, skip=WARM, tail=TAIL):
    d = json.load(open(f)); iv = d["intervals"][skip:len(d["intervals"]) - tail] if "intervals" in d else []
    bits = [i["sum"]["bits_per_second"] for i in iv]; lost = sum(i["sum"].get("lost_packets", 0) for i in iv); pk = sum(i["sum"].get("packets", 0) for i in iv)
    s = d["end"]["sum"]
    return {"goodput_mbps": round(st.mean(bits) / 1e6, 2) if bits else None, "loss_pct_window": round(100 * lost / pk, 3) if pk else None,
            "loss_pct_total": round(s.get("lost_percent", 0), 3), "offered": None}
def phase(R, tag, session=None):
    procs = traffic(R, tag, DUR); t0 = time.time()
    out = {"phase": tag}
    if session:
        time.sleep(1.0); out["api"] = api(session)
    for p in procs: p.wait()
    t1 = t0 + DUR
    w0, w1 = t0 + WARM + (1.5 if session else 0), t1 - TAIL
    for u in (1, 2):
        out[f"ue{u}"] = {"probe": probe_stats(f"{R}/{tag}.ue{u}.probe.csv", w0, w1), "be": ip_stats(f"{R}/{tag}.ue{u}.be.json"), "qf": ip_stats(f"{R}/{tag}.ue{u}.qf.json")}
    if session:
        out["api_end"] = api("delete " + out["api"]["sessionId"] + " " + out["api"]["who"])
    return out
mode, tag = sys.argv[1], sys.argv[2]; R = f"{H}/res/{tag}"; os.makedirs(R, exist_ok=True)
meta = {"mode": mode, "dur_s": DUR, "be_rate": BE_RATE, "qf_rate": QF_RATE, "window": f"[t0+{WARM}s (+1.5 s after create), t_end-{TAIL}s]",
        "slice_conf": open("/workspace/oai-n5-test/slice/slice.conf").read().split()}
res = {"meta": meta}
if mode == "ab":
    res["base"] = phase(R, "base")
    time.sleep(3)
    res["qod"] = phase(R, "qod", session="create ue1 QOS_L 18080,18081 /mu-ue1 120")
elif mode == "par":
    sh(f"sudo nsenter -t {pid('n5-lab')} -n timeout {DUR + 12} tcpdump -i lo -s 128 -U -w /workspace/fase1-raw/multiue/{tag}-n3.pcap udp port 2152 > /dev/null 2>&1 &"); time.sleep(1)
    procs = traffic(R, "par", DUR); t0 = time.time(); time.sleep(1.0)
    a1 = api("create ue1 QOS_L 18080,18081 /par-ue1 120"); a2 = api("create ue2 QOS_E 18080,18082 /par-ue2 120")
    for p in procs: p.wait()
    res["par"] = {"api": [a1, a2], "api_end": [api(f"delete {a1['sessionId']} ue1"), api(f"delete {a2['sessionId']} ue2")]}
    for u in (1, 2):
        res["par"][f"ue{u}"] = {"probe": probe_stats(f"{R}/par.ue{u}.probe.csv", t0 + WARM + 1.5, t0 + DUR - TAIL), "be": ip_stats(f"{R}/par.ue{u}.be.json"), "qf": ip_stats(f"{R}/par.ue{u}.qf.json")}
    time.sleep(2); sh("sudo pkill -f 'tcpdump -i lo -s 128 -U -w /workspace/fase1-raw/multiue/" + tag + "-n3.pcap'")
    # QFI isolation: inner dst/src UE IP x QFI, from GTP-U headers
    u1, u2 = ueip(1), ueip(2)
    r = sh(f"tshark -r /workspace/fase1-raw/multiue/{tag}-n3.pcap -n -T fields -E occurrence=l -e ip.src -e ip.dst -e udp.srcport -e gtp.ext_hdr.pdu_ses_con.qos_flow_id")
    cnt = {}
    for l in r.stdout.splitlines():
        s_, d_, sp_, q = (l.split("\t") + ["", "", "", ""])[:4]
        ue = "ue1" if u1 in (s_, d_) else "ue2" if u2 in (s_, d_) else "other"
        k = f"{ue}|qfi={q}|as_port={sp_ if s_=='<AS_IP>' else '-'}"; cnt[k] = cnt.get(k, 0) + 1
    res["par"]["n3_ue_qfi_counts"] = dict(sorted(cnt.items()))
    sh(f"sudo chmod 600 /workspace/fase1-raw/multiue/{tag}-n3.pcap")
json.dump(res, open(f"{R}/result.json", "w"), indent=1); print(json.dumps(res)[:3000])
