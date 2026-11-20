#!/usr/bin/env python3
"""provision_subs.py check|apply <lab-qos.yaml>: lab subscribers (UE1..N) in the Open5GS DB from the UE confs in the secrets dir
(IMSI/K/OPc are read, never printed). Upsert keeps any pcc_rule (owned by provision_db.py). Run in the core netns as root."""
import sys, re, json, yaml
from pymongo import MongoClient
mode, cfgf = sys.argv[1], sys.argv[2]; C = yaml.safe_load(open(cfgf)); S = C["subscribers"]
db = MongoClient("mongodb://127.0.0.1/open5gs", serverSelectionTimeoutMS=3000).open5gs
amb = {"downlink": {"value": 1, "unit": 3}, "uplink": {"value": 1, "unit": 3}}
out, drift = [], 0
for i, cf in enumerate(S["ue_confs"], 1):
    t = open(cf).read(); g = lambda k: re.search(rf'\b{k}\s*=\s*"?([0-9A-Fa-f]+)"?', t).group(1)
    imsi, k, opc = g("imsi"), g("key"), g("opc")
    cur = db.subscribers.find_one({"imsi": imsi})
    sess_cur = None
    if cur:
        for sl in cur.get("slice", []):
            for se in sl.get("session", []):
                if se.get("name") == S["dnn"]: sess_cur = se
    ok = bool(cur and cur["security"]["k"] == k and cur["security"]["opc"] == opc and sess_cur)
    rec = {"ue": i, "in_sync": ok}
    if not ok:
        drift += 1
        if mode == "apply":
            pcc = (sess_cur or {}).get("pcc_rule", [])
            doc = {"schema_version": 1, "imsi": imsi, "msisdn": [], "imeisv": [], "mme_host": [], "mme_realm": [], "purge_flag": [],
                   "security": {"k": k, "op": None, "opc": opc, "amf": "8000", "sqn": 161}, "ambr": amb,
                   "slice": [{"sst": S.get("sst", 1), "default_indicator": True, "session": [{"name": S["dnn"], "type": 3, "ambr": amb,
                             "qos": {"index": 9, "arp": {"priority_level": 8, "pre_emption_capability": 1, "pre_emption_vulnerability": 1}}, "pcc_rule": pcc}]}],
                   "access_restriction_data": 32, "network_access_mode": 0, "subscriber_status": 0, "operator_determined_barring": 0,
                   "subscribed_rau_tau_timer": 12, "__v": 0}
            db.subscribers.replace_one({"imsi": imsi}, doc, upsert=True); rec["action"] = "upserted"
        if open(S["imsi_files"][i - 1]).read().strip() != imsi: rec["warn"] = "imsi file differs from UE conf"
    out.append(rec)
print(json.dumps({"component": "subscribers", "mode": mode, "drift": drift, "ues": out}))
sys.exit(3 if (drift and mode == "check") else 0)
