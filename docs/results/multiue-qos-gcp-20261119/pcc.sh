#!/bin/bash
# pcc.sh: static PCC rules (2nd QoS flow) for the OAI multi-UE QoS test. UE1: 5QI 7 (ARP 6) SDF tcp/udp 18080;
# UE2: 5QI 1 GBR/MBR 20 Mbit/s (ARP 5) SDF tcp/udp 18081; UE3: none. "pcc.sh clear" removes them. IMSIs never printed.
. /root/lab5g-sub.env; IMSI1=$IMSI; . /root/lab5g-pairs.env
set1() { # imsi 5qi arp gbr port
  docker exec -e IMSI=$1 -e Q=$2 -e A=$3 -e G=$4 -e PORT=$5 mongo mongosh --quiet open5gs --eval '
const e=process.env, q=+e.Q, g=+e.G;
const fl=["tcp","udp"].flatMap(p=>[1,2].map(d=>({direction:d,description:"permit out "+p+" from any "+e.PORT+" to assigned"})));
const qos={index:q,arp:{priority_level:+e.A,pre_emption_capability:1,pre_emption_vulnerability:1}};
if(g>0){qos.mbr={downlink:{value:g,unit:2},uplink:{value:g,unit:2}};qos.gbr={downlink:{value:g,unit:2},uplink:{value:g,unit:2}};}
const r=db.subscribers.updateOne({imsi:e.IMSI},{$set:{"slice.0.session.0.pcc_rule":(q>0?[{qos:qos,flow:fl}]:[])}});
print("matched="+r.matchedCount+" modified="+r.modifiedCount+" 5qi="+q+" gbr="+g+" port="+e.PORT);'
}
if [ "$1" = clear ]; then set1 $IMSI1 0 6 0 18080; set1 $IMSI2 0 5 0 18081
else set1 $IMSI1 7 6 0 18080; set1 $IMSI2 1 5 20 18081; fi
