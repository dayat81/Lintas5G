#!/usr/bin/env python3
"""Korelasi N5 -> N7 -> PFCP -> NGAP -> paket QFI pertama dari satu pcap (lo, netns n5-lab).
Output: timeline teredaksi (tanpa IMSI/SUPI, tanpa IP UE, tanpa token). Usage: correlate.py raw.pcap [gnb.log] > timeline.json"""
import json, subprocess, sys, re, datetime as dt
pcap = sys.argv[1]; gnblog = sys.argv[2] if len(sys.argv) > 2 else None
sinklog, sid = (sys.argv[3], sys.argv[4]) if len(sys.argv) > 4 else (None, None)
def ts(cmd_filter, fields, extra=(), occ="a"):
    a = ["tshark", "-r", pcap, "-n", "-d", "tcp.port==7777,http2", "-Y", cmd_filter, "-T", "fields", "-E", "separator=\t", "-E", "occurrence=" + occ, "-E", "aggregator=|"]
    for f in fields: a += ["-e", f]
    out = subprocess.run(a + list(extra), capture_output=True, text=True).stdout
    return [l.split("\t") for l in out.splitlines() if l.strip()]
NF = {"127.0.0.1": "client@127.0.0.1", "127.0.1.2": "gNB", "127.0.0.4": "SMF", "127.0.0.5": "AMF", "127.0.0.7": "UPF", "127.0.0.13": "PCF",
      "127.0.0.15": "BSF", "127.0.0.200": "SCP", "127.0.0.10": "NRF", "127.0.0.99": "adapter-notify"}
nf = lambda ip: NF.get(ip, "lo-other")
red = lambda p: re.sub(r"10\.45\.\d+\.\d+", "<ue-ip>", _red(p))
_red = lambda p: re.sub(r"(imsi|suci|supi)-[0-9a-z-]+", r"\1-<redacted>", re.sub(r"/[0-9a-f]{8,}", "/<id>", p))
ev = []
# Open5GS NF clients send from 127.0.0.1, so the caller is inferred from the SBI service (3GPP TS 29.5xx producer/consumer pairs)
CALLER = [("npcf-policyauthorization", "adapter(AF)"), ("nbsf-management", "adapter(AF)"), ("nsmf-callback/v1/sm-policy-notify", "PCF"),
          ("namf-comm/v1/ue-contexts", "SMF"), ("nsmf-pdusession/v1/sm-contexts", "AMF"), ("npcf-smpolicycontrol", "SMF"), ("naf-", "PCF")]
# SBI (h2c) requests
for t, s, d, meth, path, st in ts("http2.headers.method || http2.headers.status", ["frame.time_epoch", "ip.src", "ip.dst", "http2.headers.method", "http2.headers.path", "http2.headers.status"]):
    for m, p in zip(meth.split("|") if meth else [], path.split("|") if path else []):
        caller = next((v for k_, v in CALLER if k_ in p), nf(s))
        ev.append({"t": float(t), "if": "SBI", "src": caller, "dst": nf(d), "msg": f"{m} {red(p)}"})
    for code in (st.split("|") if st else []):
        ev.append({"t": float(t), "if": "SBI", "src": nf(s), "dst": nf(d), "msg": f"HTTP {code}"})
# CAMARA northbound (plain HTTP/1.1 on 127.0.0.1:8080, captured when the filter includes it)
for t, meth, uri, code in ts("tcp.port == 8080 && http", ["frame.time_epoch", "http.request.method", "http.request.uri", "http.response.code"]):
    if meth and "/quality-on-demand/" in uri: ev.append({"t": float(t), "if": "CAMARA-API", "src": "API-consumer", "dst": "adapter", "msg": f"{meth} {red(uri)}"})
    if code: ev.append({"t": float(t), "if": "CAMARA-API", "src": "adapter", "dst": "API-consumer", "msg": f"HTTP/1.1 {code}"})
if sinklog:
    for l in open(sinklog):
        e = json.loads(l); d = ((e.get("body") or {}).get("data") or {})
        if d.get("sessionId") == sid: ev.append({"t": e["t"], "if": "callback", "src": "adapter", "dst": "sink", "msg": f"{d['qosStatus']} {d.get('statusInfo') or ''}".strip()})
# PFCP
PF = {"50": "SessionEstablishmentReq", "51": "SessionEstablishmentResp", "52": "SessionModificationReq", "53": "SessionModificationResp", "54": "SessionDeletionReq", "55": "SessionDeletionResp"}
for t, s, d, mt in ts("pfcp && pfcp.msg_type >= 50", ["frame.time_epoch", "ip.src", "ip.dst", "pfcp.msg_type"]):
    ev.append({"t": float(t), "if": "PFCP", "src": nf(s), "dst": nf(d), "msg": PF.get(mt, "type" + mt)})
# NGAP lewat shim sctp2tcp (TCP 38412, tidak terdekode): segmen data AMF->gNB
for t, s, d, ln in ts("tcp.port == 38412 && tcp.len > 0", ["frame.time_epoch", "ip.src", "ip.dst", "tcp.len"]):
    ev.append({"t": float(t), "if": "NGAP(tcp-shim)", "src": "AMF" if s == "127.0.0.5" else "gNB", "dst": "gNB" if s == "127.0.0.5" else "AMF", "msg": f"segment {ln} B"})
# N3 GTP-U: paket pertama per (arah, QFI)
seen = {}
for t, s, d, qfi in ts("gtp.ext_hdr.pdu_ses_con.qos_flow_id", ["frame.time_epoch", "ip.src", "ip.dst", "gtp.ext_hdr.pdu_ses_con.qos_flow_id"], occ="f"):
    q = qfi; k = ("DL" if s == "127.0.0.7" else "UL", q)
    seen.setdefault(k, float(t))
for (dr, q), t in seen.items():
    ev.append({"t": t, "if": "N3", "src": "UPF" if dr == "DL" else "gNB", "dst": "gNB" if dr == "DL" else "UPF", "msg": f"first {dr} GTP-U QFI={q}"})
# log gNB (opsional): baris PDU session modify / DRB
if gnblog:
    for l in open(gnblog, errors="ignore"):
        m = re.match(r"^(\d{4}-\d\d-\d\dT[\d:.]+)Z\s+\S+\s+(.*)$", l)   # docker logs -t (UTC)
        if m and re.search(r"PDUSESSIONModify|PDU_SESSION_RESOURCE_MODIFY|pdusession_modify|QFI|DRB", l, re.I):
            tt = dt.datetime.fromisoformat(m.group(1)[:26]).replace(tzinfo=dt.timezone.utc).timestamp()
            ev.append({"t": tt, "if": "gNB-log", "src": "gNB", "dst": "-", "msg": red(re.sub(r"\d+\.\d+\.\d+\.\d+", "<ip>", m.group(2).strip()[:160]))})
ev.sort(key=lambda e: e["t"])
def first(pred, after):
    for e in ev:
        if e["t"] >= after and pred(e): return e
k = {}
k["N5_create"] = first(lambda e: e["if"] == "SBI" and e["msg"].startswith("POST") and "npcf-policyauthorization/v1/app-sessions" in e["msg"], 0)
if k["N5_create"]:
    t0 = k["N5_create"]["t"]
    k["N7_update_notify"] = first(lambda e: e["if"] == "SBI" and "sm-policy-notify" in e["msg"] and e["msg"].startswith("POST"), t0)
    a = (k["N7_update_notify"] or k["N5_create"])["t"]
    k["N1N2_transfer"] = first(lambda e: e["if"] == "SBI" and "n1-n2-messages" in e["msg"], a)
    k["PFCP_mod_req"] = first(lambda e: e["if"] == "PFCP" and e["msg"].startswith("SessionModificationReq"), a)
    b = (k["N1N2_transfer"] or k["PFCP_mod_req"] or k["N5_create"])["t"]
    k["NGAP_AMF_to_gNB"] = first(lambda e: e["if"].startswith("NGAP") and e["src"] == "AMF", b)
    k["N3_first_nondefault_QFI"] = first(lambda e: e["if"] == "N3" and not e["msg"].endswith("QFI=1"), t0)
    k["N5_201"] = first(lambda e: e["if"] == "SBI" and e["msg"] == "HTTP 201" and e["src"] == "PCF", t0)
    k["CAMARA_201"] = first(lambda e: e["if"] == "CAMARA-API" and e["msg"].startswith("HTTP/1.1 201"), t0 - 1)
    k["sink_AVAILABLE"] = first(lambda e: e["if"] == "callback" and "AVAILABLE" == e["msg"].split()[0], t0)
iso = lambda t: dt.datetime.fromtimestamp(t, dt.timezone.utc).isoformat(timespec="milliseconds")
t0 = k["N5_create"]["t"] if k.get("N5_create") else (ev[0]["t"] if ev else 0)
out = {"pcap": "raw (box-only, tidak disalin)", "t0_utc": iso(t0) if t0 else None,
       "key_points_ms_from_N5": {n: (round((e["t"] - t0) * 1000, 2) if e else None) for n, e in k.items()},
       "key_points_msg": {n: (e["msg"] if e else None) for n, e in k.items()},
       "timeline": [dict(e, t_ms=round((e["t"] - t0) * 1000, 2), t=iso(e["t"])) for e in ev if abs(e["t"] - t0) < 30 and not (e["if"] == "SBI" and "nnrf" in e["msg"])]}
json.dump(out, sys.stdout, indent=1)
