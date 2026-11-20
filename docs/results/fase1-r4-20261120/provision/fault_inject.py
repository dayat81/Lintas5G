#!/usr/bin/env python3
"""TEST ONLY (item 2 c3): remove the static qod-template PCC rule for one 5QI from lab UE <i> to force a policy failure.
Restore with `provision.sh apply` (drift is then reported and repaired). Usage: fault_inject.py <ue_index> <5qi>"""
import sys, yaml
from pymongo import MongoClient
i, qi = int(sys.argv[1]), int(sys.argv[2])
C = yaml.safe_load(open("/workspace/fase1-closeout/provision/lab-qos.yaml")); imsi = open(C["subscribers"]["imsi_files"][i - 1]).read().strip()
db = MongoClient("mongodb://127.0.0.1/open5gs", serverSelectionTimeoutMS=3000).open5gs
r = db.subscribers.update_one({"imsi": imsi}, {"$pull": {"slice.$[].session.$[].pcc_rule": {"lintas5g": "qod-template", "qos.index": qi}}})
print({"ue": i, "removed_template_5qi": qi, "modified": r.modified_count})
