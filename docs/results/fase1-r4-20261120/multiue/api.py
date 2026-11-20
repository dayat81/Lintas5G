#!/usr/bin/env python3
"""CAMARA helper for mu5.py (core netns): create <ue1|ue2> <profile> <ports,> <sinkpath> <duration> | delete <sid> <ue>. Prints JSON (no tokens)."""
import sys, os, time, json
sys.path.insert(0, "/workspace/fase1-closeout/tools"); import camclient as cc
a = sys.argv[1:]
if a[0] == "create":
    who, prof, ports, sink, dur = a[1], a[2], [int(x) for x in a[3].split(",")], a[4], int(a[5]); c = cc.C(who)
    st, o, t0 = c.create(prof, dur, ports=ports, sink=sink); sid = o.get("sessionId")
    av = c.wait(sid, lambda x: x["qosStatus"] != "REQUESTED", to=10) if st == 201 else o
    print(json.dumps({"who": who, "create": st, "sessionId": sid, "profile": prof, "ports": ports, "status": av.get("qosStatus"), "statusInfo": av.get("statusInfo"),
                      "t_create": t0, "create_to_status_ms": round((time.time() - t0) * 1000, 1), "sink": sink}))
else:
    sid, who = a[1], a[2]; c = cc.C(who); st, t0 = c.delete(sid); print(json.dumps({"who": who, "sessionId": sid, "delete": st}))
