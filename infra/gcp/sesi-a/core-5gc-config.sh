#!/bin/bash
# Sesi A: konfigurasi Open5GS 5GC SA (PLMN 001/01, TAC 1, SST 1) + subscriber acak + UERANSIM gNB/UE.
# KEY/OPC hanya di /root/lab5g-sub.env (0600) di VM ephemeral; tidak dicetak.
set -e
cd /etc/open5gs
sed -i 's/mcc: 999/mcc: 001/g; s/mnc: 70/mnc: 01/g' *.yaml
# EPC-only NF dimatikan (5GC SA saja); SMF/UPF/PCF dipakai bersama.
systemctl stop open5gs-mmed open5gs-sgwcd open5gs-sgwud open5gs-hssd open5gs-pcrfd || true
systemctl disable open5gs-mmed open5gs-sgwcd open5gs-sgwud open5gs-hssd open5gs-pcrfd >/dev/null 2>&1 || true
NFS="nrfd scpd amfd smfd upfd ausfd udmd udrd pcfd bsfd nssfd"
for n in $NFS; do systemctl restart open5gs-$n; done
sleep 3
for n in $NFS; do printf "%-8s %s\n" $n "$(systemctl is-active open5gs-$n)"; done
grep -n -A3 "plmn_id" amf.yaml | grep -v "^.*#" | head -12
# N6 NAT: UE pool 10.45.0.0/16 keluar ens4 -> Cloud NAT
EGR=$(ip route get 8.8.8.8 | awk '{for(i=1;i<=NF;i++) if($i=="dev") print $(i+1)}')
iptables -t nat -C POSTROUTING -s 10.45.0.0/16 ! -o ogstun -j MASQUERADE 2>/dev/null || iptables -t nat -A POSTROUTING -s 10.45.0.0/16 ! -o ogstun -j MASQUERADE
iptables -C FORWARD -i ogstun -j ACCEPT 2>/dev/null || iptables -I FORWARD 1 -i ogstun -j ACCEPT
iptables -C FORWARD -o ogstun -j ACCEPT 2>/dev/null || iptables -I FORWARD 1 -o ogstun -j ACCEPT
umask 077
if [ ! -f /root/lab5g-sub.env ]; then
  MSIN=$(printf "%010d" $(( $(od -An -N4 -tu4 /dev/urandom) % 10000000000 )))
  { echo "IMSI=00101${MSIN}"; echo "KEY=$(openssl rand -hex 16)"; echo "OPC=$(openssl rand -hex 16)"; } > /root/lab5g-sub.env
fi
. /root/lab5g-sub.env
# Subscriber 5G: slice SST1, DNN internet, 5QI 9 default; PCC rule 5QI 2 (GBR, tanpa flow) sebagai
# template untuk Npcf_PolicyAuthorization medType=VIDEO (PCF memetakan VIDEO -> QoS index 2).
docker exec -e IMSI=$IMSI -e K=$KEY -e OPC=$OPC mongo mongosh --quiet open5gs --eval '
const e=process.env; db.subscribers.deleteMany({});
const amb={downlink:{value:1,unit:3},uplink:{value:1,unit:3}};
const pcc={qos:{index:2,arp:{priority_level:2,pre_emption_capability:1,pre_emption_vulnerability:1},
  mbr:{downlink:{value:20,unit:2},uplink:{value:20,unit:2}},gbr:{downlink:{value:1,unit:2},uplink:{value:1,unit:2}}},flow:[]};
db.subscribers.insertOne({schema_version:1,imsi:e.IMSI,msisdn:[],imeisv:[],mme_host:[],mme_realm:[],purge_flag:[],
 security:{k:e.K,op:null,opc:e.OPC,amf:"8000",sqn:NumberLong(161)},ambr:amb,
 slice:[{sst:1,default_indicator:true,session:[{name:"internet",type:3,ambr:amb,
  qos:{index:9,arp:{priority_level:8,pre_emption_capability:1,pre_emption_vulnerability:1}},pcc_rule:[pcc]}]}],
 access_restriction_data:32,network_access_mode:0,subscriber_status:0,operator_determined_barring:0,subscribed_rau_tau_timer:12,__v:0});
print("SUB_ADDED")'
docker exec mongo mongosh --quiet open5gs --eval 'db.subscribers.countDocuments()'
# UERANSIM: UE di netns ue1 (veth 10.201.0.0/24) supaya trafik UE<->host tidak short-circuit lokal.
ip netns list | grep -q '^ue1' || ip netns add ue1
ip link show veth-ue >/dev/null 2>&1 || { ip link add veth-ue type veth peer name veth-ue-ns; ip link set veth-ue-ns netns ue1; }
ip addr replace 10.201.0.1/24 dev veth-ue; ip link set veth-ue up
ip netns exec ue1 ip addr replace 10.201.0.2/24 dev veth-ue-ns
ip netns exec ue1 ip link set veth-ue-ns up; ip netns exec ue1 ip link set lo up
mkdir -p /etc/netns/ue1; echo "nameserver 8.8.8.8" > /etc/netns/ue1/resolv.conf
C=/opt/lab5g/ueransim/conf; mkdir -p $C /var/log/lab5g
umask 022
cat > $C/gnb.yaml <<GNB
mcc: '001'
mnc: '01'
nci: '0x000000010'
idLength: 32
tac: 1
linkIp: 10.201.0.1
ngapIp: 127.0.0.1
gtpIp: 127.0.0.1
amfConfigs:
  - address: 127.0.0.5
    port: 38412
slices:
  - sst: 1
ignoreStreamIds: true
GNB
umask 077
cat > $C/ue.yaml <<UE
supi: 'imsi-$IMSI'
mcc: '001'
mnc: '01'
protectionScheme: 0
homeNetworkPublicKey: '5a8d38864820197c3394b92613b20b91633cbd897119273bf8e4a6f4eec0a650'
homeNetworkPublicKeyId: 1
routingIndicator: '0000'
key: '$KEY'
op: '$OPC'
opType: 'OPC'
amf: '8000'
imei: '356938035643803'
imeiSv: '4370816125816151'
tunNetmask: '255.255.255.0'
gnbSearchList:
  - 10.201.0.1
uacAic: {mps: false, mcs: false}
uacAcc: {normalClass: 0, class11: false, class12: false, class13: false, class14: false, class15: false}
sessions:
  - type: 'IPv4'
    apn: 'internet'
    slice:
      sst: 1
configured-nssai:
  - sst: 1
default-nssai:
  - sst: 1
integrity: {IA1: true, IA2: true, IA3: true}
ciphering: {EA1: true, EA2: true, EA3: true}
integrityMaxRate: {uplink: 'full', downlink: 'full'}
UE
umask 022
echo CONFIG_DONE
