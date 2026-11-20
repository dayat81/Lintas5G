#!/usr/bin/env python3
"""provision_db.py check|apply <lab-qos.yaml>: static PCC rules in the Open5GS subscriber DB (run in the core netns).
Desired per lab UE / dnn: [api-prio rule (5QI 69, flows to the booster API)] + one flow-less template per QoD 5QI
(marker lintas5g=qod-template). Templates are built with the adapter's own MongoBridge.rule() so adapter and IaC agree.
Prints JSON with drift per UE (no IMSI). Exit 0 = no drift after the run, 3 = drift found (check mode)."""
import sys, json, yaml
sys.path.insert(0, "/workspace/qod-adapter-013")
from qod_adapter.southbound import MongoBridge
from pymongo import MongoClient
mode, cfgf = sys.argv[1], sys.argv[2]
C = yaml.safe_load(open(cfgf)); P = yaml.safe_load(open(C["adapter_profiles"]))["profiles"]
nets = [p["network"] for p in P if p.get("status", "ACTIVE") == "ACTIVE"]
nets += [{"qi": e["qos_index"], "arp": e.get("arp", 6), "mbr_dl_kbps": e["mbr_dl_kbps"], "mbr_ul_kbps": e["mbr_ul_kbps"]} for e in C.get("extra_qos_profiles", [])]
a = C["api_prio"]; desc = f"permit out 6 from {a['ip']} {a['port']} to {a['ue_net']}"
api = {"lintas5g": "api-prio", "qos": {"index": a["qi"], "arp": {"priority_level": a["arp"], "pre_emption_capability": 1, "pre_emption_vulnerability": 1}},
       "flow": [{"direction": 1, "description": desc}, {"direction": 2, "description": desc}]}
want = [api] + [dict(lintas5g="qod-template", **MongoBridge.rule(n)) for n in sorted(nets, key=lambda n: n["qi"])]
db = MongoClient("mongodb://127.0.0.1/open5gs", serverSelectionTimeoutMS=3000).open5gs
out, drift = [], 0
for i, f in enumerate(C["subscribers"]["imsi_files"], 1):
    imsi = open(f).read().strip()
    sub = db.subscribers.find_one({"imsi": imsi}, {"slice": 1})
    if not sub: out.append({"ue": i, "error": "subscriber missing (subscriber DB is a prerequisite, see README)"}); drift += 1; continue
    for si, sl in enumerate(sub["slice"]):
        for ei, se in enumerate(sl.get("session", [])):
            if se.get("name") != C["subscribers"]["dnn"]: continue
            cur = se.get("pcc_rule") or []
            ok = cur == want
            rec = {"ue": i, "dnn": se["name"], "rules_before": [(r.get("lintas5g"), r["qos"]["index"], len(r.get("flow", []))) for r in cur], "in_sync": ok}
            if not ok:
                drift += 1
                if mode == "apply":
                    db.subscribers.update_one({"_id": sub["_id"]}, {"$set": {f"slice.{si}.session.{ei}.pcc_rule": want}}); rec["action"] = "written"
            out.append(rec)
print(json.dumps({"component": "subscriber-pcc", "mode": mode, "drift": drift,
                  "want": [(r.get("lintas5g"), r["qos"]["index"], len(r["flow"])) for r in want], "ues": out}))
sys.exit(3 if (drift and mode == "check") else 0)
