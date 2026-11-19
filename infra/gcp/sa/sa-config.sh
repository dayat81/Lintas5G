#!/bin/bash
# 5G SA config: Open5GS 5GC (PLMN 001/01, TAC 1, SST 1, DNN internet), N6 NAT, subscriber (optional STATIC PCC rule, SA_STATIC_PCC=1)
# (second QoS flow, 5QI 7 non-GBR -> QFI 2 at PDU session setup, SDF = udp/4789 + tcp/18080 = sesi-d test ports),
# srsRAN Project gNB (ZMQ, band 3 FDD, SCS 15 kHz) + srsUE SA config. sa-ueransim -> sesi-a/core-5gc-config.sh.
# Secrets: /root/lab5g-sub.env and /etc/lab5g/sa/ue.conf are 0600, never printed.
set -e
MODE=${1:-sa-srsran}
if [ "$MODE" = sa-ueransim ]; then exec bash /opt/lab5g/sesi-a/core-5gc-config.sh; fi
BW=${SA_BW_MHZ:-20}   # 20 = srsRAN reference ZMQ config (23.04 MHz); 10 = 52 PRB / 11.52 MHz (less CPU, less tested)
# Static PCC rule (2nd QoS flow 5QI 7 / QFI 2) only on request: srsUE 23.11 NR SDAP supports ONE QoS flow per PDU session
# ("Configuring SDAP: only UL headder is supported ... number of QoS flows must be 1" -> RRC reconfiguration failure ->
# RRC Release, verified offline 19 Nov 2026). SA_STATIC_PCC=1 only with a UE that supports multiple flows (UERANSIM/handset).
PCC=${SA_STATIC_PCC:-0}
cd /etc/open5gs
sed -i 's/mcc: 999/mcc: 001/g; s/mnc: 70/mnc: 01/g' *.yaml
systemctl stop open5gs-mmed open5gs-sgwcd open5gs-sgwud open5gs-hssd open5gs-pcrfd 2>/dev/null || true
systemctl disable open5gs-mmed open5gs-sgwcd open5gs-sgwud open5gs-hssd open5gs-pcrfd >/dev/null 2>&1 || true
NFS="nrfd scpd amfd smfd upfd ausfd udmd udrd pcfd bsfd nssfd"
for n in $NFS; do systemctl restart open5gs-$n; done; sleep 3
for n in $NFS; do printf "%s=%s " $n "$(systemctl is-active open5gs-$n)"; done; echo
iptables -t nat -C POSTROUTING -s 10.45.0.0/16 ! -o ogstun -j MASQUERADE 2>/dev/null || iptables -t nat -A POSTROUTING -s 10.45.0.0/16 ! -o ogstun -j MASQUERADE
iptables -C FORWARD -i ogstun -j ACCEPT 2>/dev/null || iptables -I FORWARD 1 -i ogstun -j ACCEPT
iptables -C FORWARD -o ogstun -j ACCEPT 2>/dev/null || iptables -I FORWARD 1 -o ogstun -j ACCEPT
umask 077
if [ ! -f /root/lab5g-sub.env ]; then
  MSIN=$(printf "%010d" $(( $(od -An -N4 -tu4 /dev/urandom) % 10000000000 )))
  { echo "IMSI=00101${MSIN}"; echo "KEY=$(openssl rand -hex 16)"; echo "OPC=$(openssl rand -hex 16)"; } > /root/lab5g-sub.env
fi
. /root/lab5g-sub.env
docker exec -e IMSI=$IMSI -e K=$KEY -e OPC=$OPC -e PCC="$PCC" mongo mongosh --quiet open5gs --eval '
const e=process.env; db.subscribers.deleteMany({});
const amb={downlink:{value:1,unit:3},uplink:{value:1,unit:3}};
const fl=[{direction:1,description:"permit out udp from any 4789 to assigned"},{direction:2,description:"permit out udp from any 4789 to assigned"},
          {direction:1,description:"permit out tcp from any 18080 to assigned"},{direction:2,description:"permit out tcp from any 18080 to assigned"}];
const pcc={qos:{index:7,arp:{priority_level:6,pre_emption_capability:1,pre_emption_vulnerability:1}},flow:fl};
db.subscribers.insertOne({schema_version:1,imsi:e.IMSI,msisdn:[],imeisv:[],mme_host:[],mme_realm:[],purge_flag:[],
 security:{k:e.K,op:null,opc:e.OPC,amf:"8000",sqn:NumberLong(161)},ambr:amb,
 slice:[{sst:1,default_indicator:true,session:[{name:"internet",type:3,ambr:amb,
  qos:{index:9,arp:{priority_level:8,pre_emption_capability:1,pre_emption_vulnerability:1}},pcc_rule:(e.PCC==="1"?[pcc]:[])}]}],
 access_restriction_data:32,network_access_mode:0,subscriber_status:0,operator_determined_barring:0,subscribed_rau_tau_timer:12,__v:0});
print("SUB_ADDED pcc=" + (e.PCC==="1" ? "5qi7 flows=" + fl.length : "none"))'
C=/etc/lab5g/sa; install -d -m 0755 /etc/lab5g $C
if [ "$BW" = 10 ]; then SR=11.52; PRB=52; CS0=6; else SR=23.04; PRB=106; CS0=12; fi
umask 022
sed -e "s/__SR__/$SR/g" -e "s/__BW__/$BW/g" -e "s/__CS0__/$CS0/g" /opt/lab5g/sa/gnb-zmq.yaml.tmpl > $C/gnb.yaml
umask 077
sed -e "s/__SR__/$SR/g" -e "s/__PRB__/$PRB/g" -e "s/__IMSI__/$IMSI/" -e "s/__K__/$KEY/" -e "s/__OPC__/$OPC/" /opt/lab5g/sa/ue-zmq.conf.tmpl > $C/ue.conf
chmod 0600 $C/ue.conf
ip netns list | grep -qw ue1 || ip netns add ue1
mkdir -p /etc/netns/ue1; echo "nameserver 8.8.8.8" > /etc/netns/ue1/resolv.conf
echo "SA_CONFIG_DONE bw=${BW}MHz srate=${SR}"
