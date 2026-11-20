#!/usr/bin/env python3
"""Step 1+2 stand-in for booster-app examine -> booster.
 mode relay: tail relay log (FLOW lines = NAT row creation = flows seen in examine TUN) and pick flows whose dst matches the media rule.
 mode owner: poll `ss -tunp` in the UE netns for sockets owned by process 'targetapp' (stand-in for getConnectionOwnerUid / split-tunnel app).
Derives (ue_ip, as_ip, as_port, protos) and triggers qod_boost.py through N5."""
import sys, time, re, subprocess, json, argparse
a = argparse.ArgumentParser(); a.add_argument("--mode"); a.add_argument("--relay-log"); a.add_argument("--uepid"); a.add_argument("--labpid"); a.add_argument("--tag"); a.add_argument("--ue")
a.add_argument("--as-ip", default="10.45.0.1"); a.add_argument("--rule-port", type=int, default=18080); a.add_argument("--max", type=float, default=60)
a.add_argument("--events"); a.add_argument("--delete-after", type=float, default=0); a.add_argument("--extra-as", default=""); a.add_argument("--hold", type=float, default=0, help="baseline hold after detection before the QoD request")
o = a.parse_args(); D = "/workspace/booster-qod-test"; t_start = time.time(); seen = {}; det = None
ueip = subprocess.run(f"sudo nsenter -t {o.uepid} -n ip -4 -o addr show oaitun_ue1", shell=True, capture_output=True, text=True).stdout.split()[3].split("/")[0]
while time.time() - t_start < o.max and time.time() - t_start >= 0:
    if o.mode == "relay":
        for l in open(o.relay_log):
            m = re.match(r"FLOW t=([\d.]+) proto=(\w+) dst=([\d.]+):(\d+)", l)
            if m and float(m[1]) >= t_start - 0.01 and m[3] == o.as_ip and int(m[4]) == o.rule_port: seen.setdefault(m[2], (float(m[1]), m[3], int(m[4])))
    else:
        out = subprocess.run(f"sudo nsenter -t {o.uepid} -n ss -H -tunp", shell=True, capture_output=True, text=True).stdout
        for l in out.splitlines():
            if '"targetapp"' in l:
                f = l.split(); pr = f[0]; peer = f[5]; ip, port = peer.rsplit(":", 1)
                if ip == o.as_ip and int(port) == o.rule_port: seen.setdefault("tcp" if pr == "tcp" else "udp", (time.time(), ip, int(port)))
    if seen and det is None: det = time.time()
    if det and time.time() - det > 1.0: break   # 1 s window to collect both protocols of the same server:port
    time.sleep(0.05)
if not seen: print(json.dumps(dict(detect="none"))); sys.exit(1)
protos = "6,17"  # CAMARA names no protocol: always TCP+UDP for the detected server:port
tdet = min(v[0] for v in seen.values())
print(json.dumps(dict(ev="detect_result", tag=o.tag, via=o.mode, ue_ip="<UE>", as_ip=o.as_ip, as_port=o.rule_port, protos=protos, t_detect=tdet)), flush=True)
time.sleep(o.hold)
r = subprocess.run(f"sudo nsenter -t {o.labpid} -n /workspace/oai-n5-test/.venv/bin/python {D}/qod_boost.py --imsi-file {D}/secrets/imsi{o.ue} --ue-ip {ueip} --as-ip {o.as_ip} --as-port {o.rule_port} --profile QOS_7 --protos {protos} --events {o.events} --t-detect {tdet} --t-trigger {time.time()} --delete-after {o.delete_after} --extra-as '{o.extra_as}'", shell=True, capture_output=True, text=True)
print(re.sub(r"10\.45\.\d+\.\d+", "10.45.x.x", r.stdout)[-600:], r.stderr[-300:])
