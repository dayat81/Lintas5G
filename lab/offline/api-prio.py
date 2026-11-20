#!/usr/bin/env python3
"""api-prio.py apply|remove|show [--ip 10.45.0.1] [--port 8080] [--qi 69] [--arp 1] [--imsi-file F ...]
Static PCC rule in the subscriber's default session (dnn oai) so the booster control API (TCP UE <-> backend/adapter
IP:port) rides its own high-priority non-GBR QoS flow from PDU session establishment (Open5GS PCF installs DB PCC rules
that carry flows in the SM policy create response). Persistent: lives in the lab DB volume n5-mongo-db; marked
{"lintas5g": "api-prio"} so the QoD PCC resets (n5proto reset, lab.sh reset-pcc, adapter pcc-reset) keep it, and kept
at index 0 so its PCC id (oai-n1) stays stable. Takes effect at the next PDU session establishment (lab.sh ue-restart).
Run inside the core netns: sudo nsenter -t <n5-lab pid> -n .venv/bin/python lab/api-prio.py apply"""
import argparse, json
from pymongo import MongoClient
a = argparse.ArgumentParser(); a.add_argument("cmd", choices=["apply", "remove", "show"])
a.add_argument("--ip", default="10.45.0.1"); a.add_argument("--port", default="8080"); a.add_argument("--qi", type=int, default=69)
a.add_argument("--arp", type=int, default=1); a.add_argument("--dnn", default="oai"); a.add_argument("--ue-net", default="10.45.0.0/16")
a.add_argument("--imsi-file", action="append"); o = a.parse_args()
D = "/workspace/oai-n5-test"; files = o.imsi_file or [f"{D}/secrets/imsi1", f"{D}/secrets/imsi2"]
db = MongoClient("mongodb://127.0.0.1/open5gs", serverSelectionTimeoutMS=3000).open5gs
# Gx/DB convention (as the Open5GS WebUI writes it): both directions 'permit out <p> from <remote> <port> to <ue>'; SMF swaps UL
desc = f"permit out 6 from {o.ip} {o.port} to {o.ue_net}"
rule = {"lintas5g": "api-prio",
        "qos": {"index": o.qi, "arp": {"priority_level": o.arp, "pre_emption_capability": 1, "pre_emption_vulnerability": 1}},
        "flow": [{"direction": 1, "description": desc}, {"direction": 2, "description": desc}]}
out = []
for i, f in enumerate(files, 1):
    imsi = open(f).read().strip()
    sub = db.subscribers.find_one({"imsi": imsi, "slice.session.name": o.dnn}, {"slice": 1})
    if not sub: out.append({"ue": i, "err": "subscriber/dnn not found"}); continue
    for si, sl in enumerate(sub["slice"]):
        for ei, se in enumerate(sl.get("session", [])):
            if se.get("name") != o.dnn: continue
            rules = se.get("pcc_rule", []) or []
            others = [r for r in rules if r.get("lintas5g") != "api-prio" and r.get("qos", {}).get("index") != o.qi]
            if o.cmd == "apply": new = [rule] + others
            elif o.cmd == "remove": new = others
            else: new = rules
            if o.cmd != "show":
                db.subscribers.update_one({"_id": sub["_id"]}, {"$set": {f"slice.{si}.session.{ei}.pcc_rule": new}})
            out.append({"ue": i, "pcc_rule": [{"qi": r["qos"]["index"], "arp": r["qos"].get("arp", {}).get("priority_level"),
                        "static": r.get("lintas5g") == "api-prio", "flows": [x["description"].replace(o.ue_net, "<ue-net>") for x in r.get("flow", [])][:2]} for r in new]})
print(json.dumps(out, indent=1))
