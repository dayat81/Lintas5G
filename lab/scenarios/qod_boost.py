#!/usr/bin/env python3
"""Step 2: boost trigger. Run in core netns. Mongo bridge -> BSF -> N5 Create (no DELETE: unpatched gNB crashes on DELETE)."""
import sys, argparse, uuid, time, json
sys.path.insert(0, "/workspace/oai-n5-test"); import n5proto as n
a = argparse.ArgumentParser(); a.add_argument("--imsi-file"); a.add_argument("--ue-ip"); a.add_argument("--as-ip"); a.add_argument("--as-port")
a.add_argument("--profile", default="QOS_7"); a.add_argument("--protos", default="6,17"); a.add_argument("--events"); a.add_argument("--t-detect", type=float, default=0); a.add_argument("--t-trigger", type=float, default=0); a.add_argument("--delete-after", type=float, default=0); a.add_argument("--extra-as", default="")
o = a.parse_args(); imsi = open(o.imsi_file).read().strip()
mb = n.MongoBridge(); sbi = n.Sbi(); n.start_callback_server("/tmp/mq-callbacks.jsonl")
if o.t_detect: n.ev("detect", t_trigger=o.t_trigger, t_detect=o.t_detect, as_ip=o.as_ip, as_port=o.as_port, protos=o.protos)
t0 = time.time(); n.ev("mongo_provision", profile=o.profile, modified=mb.provision(imsi, "oai", o.profile), ms=round((time.time()-t0)*1e3, 2))
pcf, _ = sbi.bsf_discover(o.ue_ip)
asc = n.build_asc(o.ue_ip, "oai", 1, o.profile, o.as_ip, [int(x) for x in o.as_port.split(",")], f"http://127.0.0.99:9999/lintas5g/v1/notify/{uuid.uuid4().hex[:8]}", tuple(int(x) for x in o.protos.split(",")))
if o.extra_as:   # applicationServer list: extra "ip:port" entries (e.g. MGLT reflector) in the same media component
    for x in o.extra_as.split(","):
        xi, xp = x.split(":"); asc["ascReqData"]["medComponents"]["1"]["medSubComps"]["1"]["fDescs"] += n.flow_descs(xi, [int(xp)], o.ue_ip, tuple(int(y) for y in o.protos.split(",")))
r, ce = sbi.create(pcf, asc)
mb.remove(imsi, "oai", n.PROFILES[o.profile]["qi"]); n.ev("mongo_unprovision")
n.ev("apply_total", ms=round((time.time()-t0)*1e3, 2), status=r.status_code, t_detect_to_201_ms=round((time.time()-o.t_detect)*1e3, 1) if o.t_detect else None)
with open(o.events, "a") as f:
    for e in n.LOG: f.write(n.mask(json.dumps(e)) + "\n")
if o.delete_after and r.status_code == 201:
    time.sleep(o.delete_after); sbi.delete(r.headers["location"]); time.sleep(1)
    with open(o.events, "a") as f:
        for e in n.LOG[-1:]: f.write(n.mask(json.dumps(e)) + "\n")
time.sleep(1)
