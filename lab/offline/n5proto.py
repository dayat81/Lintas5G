#!/usr/bin/env python3
"""Lintas5G N5 prototype (ETSI OOP(26)003008 pattern) for Open5GS 2.8.0 SA.

Run inside the core netns (nsenter -t <pid of n5-lab> -n). Steps:
  1 Mongo bridge (qos-provisioning): write PCC rule (5QI from qosProfile) into subscriber session
  2 Nbsf_Management: GET pcfBindings?ipv4Addr=<UE IP> -> PCF endpoint
  3 Npcf_PolicyAuthorization Create (HTTP/2 h2c, TS 29.514) with TCP+UDP flow descriptions
  5 Delete app session
Plus an h2c callback server (Open5GS PCF -> AF notifications are HTTP/2 prior-knowledge).
Never prints IMSI/K/OPc; UE IPs are masked in output.
"""
import argparse, asyncio, json, re, sys, threading, time, uuid
import httpx
from pymongo import MongoClient

PROFILES = {  # static qos-profiles (ETSI: configured statically in the TF). 5QI must match PCF qos_profiles.
    "QOS_E": dict(qi=80, arp=6, gbr=0, mbr_dl=10_000, mbr_ul=5_000),
    "QOS_S": dict(qi=2, arp=6, gbr=1, gbr_dl=2_000, gbr_ul=500, mbr_dl=4_000, mbr_ul=1_000),
    "QOS_M": dict(qi=3, arp=6, gbr=1, gbr_dl=5_000, gbr_ul=1_000, mbr_dl=10_000, mbr_ul=2_000),
    "QOS_L": dict(qi=4, arp=6, gbr=1, gbr_dl=10_000, gbr_ul=2_000, mbr_dl=20_000, mbr_ul=5_000),
    "QOS_7": dict(qi=7, arp=6, gbr=0, mbr_dl=40_000, mbr_ul=10_000),
}
BSF = "http://127.0.0.15:7777"
CB_HOST, CB_PORT = "127.0.0.99", int(__import__("os").environ.get("N5_CB_PORT", "9999"))
LOG = []
MARBW = False

def mask(s):
    s = re.sub(r"imsi-\d+", "imsi-<redacted>", str(s))
    return re.sub(r"\b10\.45\.\d+\.\d+\b", "10.45.x.x", s)

def ev(name, **kw):
    e = dict(t=time.time(), ev=name, **kw); LOG.append(e)
    print(mask(json.dumps(e)), flush=True); return e

# ---------- 1. Mongo bridge (qos-provisioning) ----------
class MongoBridge:
    def __init__(self, uri="mongodb://127.0.0.1/open5gs"):
        self.db = MongoClient(uri, serverSelectionTimeoutMS=3000).open5gs
    def _rule(self, p):
        kbps = lambda v: {"value": v, "unit": 1}           # Open5GS unit 1 = Kbps
        q = {"index": p["qi"], "arp": {"priority_level": p["arp"], "pre_emption_capability": 1, "pre_emption_vulnerability": 1}}
        q["mbr"] = {"downlink": kbps(p["mbr_dl"]), "uplink": kbps(p["mbr_ul"])}
        if p.get("gbr"): q["gbr"] = {"downlink": kbps(p["gbr_dl"]), "uplink": kbps(p["gbr_ul"])}
        return {"qos": q, "flow": []}   # flows come from the N5 media component, not from the DB
    def provision(self, imsi, dnn, profile):
        p = PROFILES[profile]
        sub = self.db.subscribers.find_one({"imsi": imsi, "slice.session.name": dnn}, {"slice": 1})
        if not sub: raise SystemExit("subscriber/dnn not found")
        for si, sl in enumerate(sub["slice"]):
            for ei, se in enumerate(sl.get("session", [])):
                if se["name"] == dnn:
                    rules = [r for r in se.get("pcc_rule", []) if r["qos"]["index"] != p["qi"]] + [self._rule(p)]
                    r = self.db.subscribers.update_one({"_id": sub["_id"]}, {"$set": {f"slice.{si}.session.{ei}.pcc_rule": rules}})
                    return r.modified_count
    def remove(self, imsi, dnn, qi=None):
        sub = self.db.subscribers.find_one({"imsi": imsi, "slice.session.name": dnn}, {"slice": 1})
        for si, sl in enumerate(sub["slice"]):
            for ei, se in enumerate(sl.get("session", [])):
                if se["name"] == dnn:
                    rules = [r for r in se.get("pcc_rule", []) if r.get("lintas5g") == "api-prio" or (qi is not None and r["qos"]["index"] != qi)]
                    self.db.subscribers.update_one({"_id": sub["_id"]}, {"$set": {f"slice.{si}.session.{ei}.pcc_rule": rules}})
    def reset_all(self):
        n = 0
        for s in self.db.subscribers.find({}, {"slice": 1}):
            # keep static rules provisioned by lab/api-prio.py (marker lintas5g=api-prio); drop only QoD templates
            upd = {f"slice.{si}.session.{ei}.pcc_rule": [r for r in (se.get("pcc_rule") or []) if r.get("lintas5g") == "api-prio"]
                   for si, sl in enumerate(s["slice"]) for ei, se in enumerate(sl.get("session", []))}
            n += self.db.subscribers.update_one({"_id": s["_id"]}, {"$set": upd}).modified_count
        return n

# ---------- 2/3/5. SBI client (HTTP/2 prior knowledge, h2c) ----------
class Sbi:
    def __init__(self): self.c = httpx.Client(http1=False, http2=True, timeout=5)
    def bsf_discover(self, ue_ip):
        t0 = time.time(); r = self.c.get(f"{BSF}/nbsf-management/v1/pcfBindings", params={"ipv4Addr": ue_ip})
        b = r.json() if r.status_code == 200 else {}
        ep = (b.get("pcfIpEndPoints") or [{}])[0]
        base = f"http://{ep.get('ipv4Address')}:{ep.get('port', 80)}" if ep else (f"http://{b['pcfFqdn']}" if b.get("pcfFqdn") else None)
        ev("bsf_discover", status=r.status_code, http=r.http_version, ms=round((time.time()-t0)*1e3, 2), binding=b, pcf=base)
        return base, b
    def create(self, pcf, asc):
        t0 = time.time(); r = self.c.post(f"{pcf}/npcf-policyauthorization/v1/app-sessions", json=asc)
        e = ev("n5_create", status=r.status_code, http=r.http_version, ms=round((time.time()-t0)*1e3, 2), t0=t0,
               location=r.headers.get("location"), body=(r.json() if r.content and r.status_code >= 300 else None))
        return r, e
    def delete(self, location):
        t0 = time.time(); r = self.c.post(f"{location}/delete", json={})
        e = ev("n5_delete", status=r.status_code, http=r.http_version, ms=round((time.time()-t0)*1e3, 2), t0=t0)
        return r, e

def flow_descs(as_ip, as_ports, ue_ip, protos=(6, 17)):
    """CAMARA names no protocol -> send TCP and UDP (ETSI lesson).
    Rx/N5 (TS 29.214/29.514) convention as Open5GS implements it:
      DL: 'permit out <p> from <AS> <port> to <UE>'
      UL: 'permit in  <p> from <UE> to <AS> <port>'   (PCF swaps to Gx 'permit out from AS to UE'; SMF swaps back for UL)
    FAKTA c1-c4: writing UL as 'permit in from <AS> to <UE>' gets swapped twice -> UL filter never matches (UL stayed QFI 1)."""
    out = []
    for pr in protos:
        for port in as_ports:
            out += [f"permit out {pr} from {as_ip} {port} to {ue_ip}", f"permit in {pr} from {ue_ip} to {as_ip} {port}"]
    return out

def build_asc(ue_ip, dnn, sst, profile, as_ip, as_ports, notif, protos=(6, 17)):
    p = PROFILES[profile]
    # FAKTA (c3): Open5GS PCF sums marBw per DL/UL flow description -> with TCP+UDP the MBR doubles.
    # Lintas5G fix: split the profile MBR over the number of protocols (and ports) so the resulting QoS = profile.
    k = max(1, len(protos) * len(as_ports))
    mc = {"medCompN": 1, "qosReference": profile, "fStatus": "ENABLED",
          "medSubComps": {"1": {"fNum": 1, "fDescs": flow_descs(as_ip, as_ports, ue_ip, protos)}}}
    # FAKTA (c4): if marBw is sent, Open5GS sets GBR = MBR = marBw (DB GBR ignored). Default (c5): omit marBw so
    # MBR/GBR come from the Mongo-bridge PCC rule = the static qos-profile (ETSI pattern).
    if MARBW: mc.update(marBwDl=f"{p['mbr_dl'] // k} Kbps", marBwUl=f"{p['mbr_ul'] // k} Kbps")
    return {"ascReqData": {"afAppId": "lintas5g-qod", "dnn": dnn, "sliceInfo": {"sst": sst}, "ueIpv4": ue_ip,
            "suppFeat": "0", "notifUri": notif, "medComponents": {"1": mc},
            "evSubsc": {"events": [{"event": "SUCCESSFUL_RESOURCES_ALLOCATION", "notifMethod": "EVENT_DETECTION"},
                                   {"event": "FAILED_RESOURCES_ALLOCATION", "notifMethod": "EVENT_DETECTION"}],
                        "notifUri": notif}}}

# ---------- h2c callback server (AF side) ----------
def start_callback_server(path):
    import h2.connection, h2.config, h2.events
    async def handle(reader, writer):
        conn = h2.connection.H2Connection(config=h2.config.H2Configuration(client_side=False, header_encoding="utf-8"))
        conn.initiate_connection(); writer.write(conn.data_to_send()); streams = {}
        while True:
            data = await reader.read(65535)
            if not data: break
            for e in conn.receive_data(data):
                if isinstance(e, h2.events.RequestReceived): streams[e.stream_id] = [dict(e.headers), b""]
                elif isinstance(e, h2.events.DataReceived):
                    streams[e.stream_id][1] += e.data; conn.acknowledge_received_data(len(e.data), e.stream_id)
                elif isinstance(e, h2.events.StreamEnded):
                    h, b = streams.pop(e.stream_id)
                    rec = dict(t=time.time(), method=h.get(":method"), path=h.get(":path"), body=b.decode(errors="replace"))
                    open(path, "a").write(json.dumps(rec) + "\n"); print(mask("CALLBACK " + json.dumps(rec)), flush=True)
                    conn.send_headers(e.stream_id, [(":status", "204")], end_stream=True)
            writer.write(conn.data_to_send()); await writer.drain()
    def run():
        loop = asyncio.new_event_loop(); asyncio.set_event_loop(loop)
        srv = loop.run_until_complete(asyncio.start_server(handle, CB_HOST, CB_PORT)); loop.run_forever()
    threading.Thread(target=run, daemon=True).start(); time.sleep(0.3)

def main():
    a = argparse.ArgumentParser()
    a.add_argument("cmd", choices=["provision", "discover", "create", "delete", "reset", "cycle", "callback-server"])
    a.add_argument("--imsi-file"); a.add_argument("--ue-ip-file"); a.add_argument("--dnn", default="oai"); a.add_argument("--sst", type=int, default=1)
    a.add_argument("--profile", default="QOS_E"); a.add_argument("--as-ip", default="10.45.0.1"); a.add_argument("--as-port", default="18080")
    a.add_argument("--protos", default="6,17"); a.add_argument("--hold", type=float, default=20)
    a.add_argument("--mode", choices=["ephemeral", "persistent", "none"], default="ephemeral",
                   help="ephemeral: write PCC rule, Create, remove it from DB right after 201 (no static install on re-attach)")
    a.add_argument("--wait-before-delete", default=None, help="file to wait for before DELETE (optional)")
    a.add_argument("--events", default="/tmp/n5-events.jsonl"); a.add_argument("--callbacks", default="/tmp/n5-callbacks.jsonl")
    a.add_argument("--marbw", action="store_true", help="also send marBwDl/Ul (split per protocol)")
    o = a.parse_args(); global MARBW; MARBW = o.marbw
    rd = lambda f: open(f).read().strip() if f else None
    imsi, ue_ip = rd(o.imsi_file), rd(o.ue_ip_file)
    mb = MongoBridge(); sbi = Sbi()
    try:
        if o.cmd == "reset": ev("pcc_reset", modified=mb.reset_all()); return
        if o.cmd == "callback-server":
            start_callback_server(o.callbacks); time.sleep(o.hold); return
        if o.cmd == "provision": ev("mongo_provision", profile=o.profile, modified=mb.provision(imsi, o.dnn, o.profile)); return
        if o.cmd == "discover": sbi.bsf_discover(ue_ip); return
        if o.cmd == "cycle":
            start_callback_server(o.callbacks)
            cid = uuid.uuid4().hex[:8]; notif = f"http://{CB_HOST}:{CB_PORT}/lintas5g/v1/notify/{cid}"
            t0 = time.time()
            if o.mode != "none": ev("mongo_provision", profile=o.profile, modified=mb.provision(imsi, o.dnn, o.profile), ms=round((time.time()-t0)*1e3, 2))
            pcf, _ = sbi.bsf_discover(ue_ip)
            if not pcf: ev("abort", reason="no PCF binding"); return
            asc = build_asc(ue_ip, o.dnn, o.sst, o.profile, o.as_ip, [int(x) for x in o.as_port.split(",")], notif,
                            tuple(int(x) for x in o.protos.split(",")))
            r, ce = sbi.create(pcf, asc)
            if o.mode == "ephemeral": mb.remove(imsi, o.dnn, PROFILES[o.profile]["qi"]); ev("mongo_unprovision")
            if r.status_code != 201: return
            ev("apply_total", ms=round((time.time()-t0)*1e3, 2))
            if o.wait_before_delete:
                while not __import__("os").path.exists(o.wait_before_delete): time.sleep(0.2)
            else: time.sleep(o.hold)
            sbi.delete(r.headers["location"])
            if o.mode == "persistent": mb.remove(imsi, o.dnn, PROFILES[o.profile]["qi"]); ev("mongo_unprovision")
            time.sleep(3)
    finally:
        with open(o.events, "a") as f:
            for e in LOG: f.write(mask(json.dumps(e)) + "\n")

if __name__ == "__main__": main()
