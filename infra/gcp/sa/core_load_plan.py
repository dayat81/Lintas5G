#!/usr/bin/env python3
"""Fase 4 non-radio core load: render K UERANSIM nr-gnb + nr-ue process configs (one netns/veth per pair).

Pair i (1..K): netns cl<i>, veth host 10.210.<i>.1 <-> ns 10.210.<i>.2, gNB NGAP/GTP bind 127.0.2.<i>
(distinct GTP-U bind: several gNBs cannot share 127.0.0.1:2152), nci 0x10+i, UE supi = base_msin+i, tun uesimtun0 in ns.
Secrets (KEY/OPC) come from the environment at run time and are never stored in the repo.
Usage: core_load_plan.py --k 4 --out DIR [--msin-base 9000000000]   (env KEY OPC; DRY: KEY/OPC default to dummy)
"""
import argparse
import json
import os

GNB = """mcc: '001'
mnc: '01'
nci: '0x{nci:09x}'
idLength: 32
tac: 1
linkIp: 10.210.{i}.1
ngapIp: 127.0.2.{i}
gtpIp: 127.0.2.{i}
amfConfigs:
  - address: 127.0.0.5
    port: 38412
slices:
  - sst: 1
ignoreStreamIds: true
"""

UE = """supi: 'imsi-{imsi}'
mcc: '001'
mnc: '01'
protectionScheme: 0
homeNetworkPublicKey: '5a8d38864820197c3394b92613b20b91633cbd897119273bf8e4a6f4eec0a650'
homeNetworkPublicKeyId: 1
routingIndicator: '0000'
key: '{key}'
op: '{opc}'
opType: 'OPC'
amf: '8000'
imei: '35693803564{i:04d}'
imeiSv: '43708161258{i:05d}'
tunNetmask: '255.255.255.0'
gnbSearchList:
  - 10.210.{i}.1
uacAic: {{mps: false, mcs: false}}
uacAcc: {{normalClass: 0, class11: false, class12: false, class13: false, class14: false, class15: false}}
sessions:
  - type: 'IPv4'
    apn: 'internet'
    slice:
      sst: 1
configured-nssai:
  - sst: 1
default-nssai:
  - sst: 1
integrity: {{IA1: true, IA2: true, IA3: true}}
ciphering: {{EA1: true, EA2: true, EA3: true}}
integrityMaxRate: {{uplink: 'full', downlink: 'full'}}
"""


def render(k, outdir, key, opc, msin_base=9000000000):
    if not 1 <= k <= 6:
        raise ValueError("k must be 1..6 (12 vCPU: 2 CPU per gNB+UE pair + core)")
    os.makedirs(outdir, exist_ok=True)
    layout = []
    for i in range(1, k + 1):
        imsi = f"00101{msin_base + i:010d}"
        with open(os.path.join(outdir, f"gnb{i}.yaml"), "w") as f:
            f.write(GNB.format(i=i, nci=0x10 + i))
        p = os.path.join(outdir, f"ue{i}.yaml")
        with open(p, "w") as f:
            f.write(UE.format(i=i, imsi=imsi, key=key, opc=opc))
        os.chmod(p, 0o600)
        layout.append({"pair": i, "netns": f"cl{i}", "host_ip": f"10.210.{i}.1", "ns_ip": f"10.210.{i}.2",
                       "bind": f"127.0.2.{i}", "gnb_cpu": 2 * i, "ue_cpu": 2 * i + 1, "iperf_port": 5300 + i})
    with open(os.path.join(outdir, "layout.json"), "w") as f:
        json.dump(layout, f, indent=1)
    # subscribers (same K/OPC for all, lab only); IMSI list is non-secret structure, keys supplied via env to mongosh
    js = "const e=process.env; const n=%d; const base=%d;\n" % (k, msin_base)
    js += """for(let i=1;i<=n;i++){const imsi='00101'+String(base+i).padStart(10,'0'); db.subscribers.deleteMany({imsi});
const amb={downlink:{value:1,unit:3},uplink:{value:1,unit:3}};
db.subscribers.insertOne({schema_version:1,imsi,msisdn:[],imeisv:[],mme_host:[],mme_realm:[],purge_flag:[],
 security:{k:e.K,op:null,opc:e.OPC,amf:"8000",sqn:NumberLong(161)},ambr:amb,
 slice:[{sst:1,default_indicator:true,session:[{name:"internet",type:3,ambr:amb,qos:{index:9,arp:{priority_level:8,pre_emption_capability:1,pre_emption_vulnerability:1}}}]}],
 access_restriction_data:32,network_access_mode:0,subscriber_status:0,operator_determined_barring:0,subscribed_rau_tau_timer:12,__v:0});}
print('SUBS_ADDED '+n)
"""
    with open(os.path.join(outdir, "provision.js"), "w") as f:
        f.write(js)
    return layout


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--k", type=int, required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--msin-base", type=int, default=9000000000)
    a = ap.parse_args()
    lay = render(a.k, a.out, os.environ.get("KEY", "0" * 32), os.environ.get("OPC", "f" * 32), a.msin_base)
    print(json.dumps(lay))


if __name__ == "__main__":
    main()
