#!/bin/bash
# Render N (1..4) srsRAN Project gNB + srsUE NR 20 MHz ZMQ pairs and provision one Open5GS subscriber per extra pair.
# Pair 1 = legacy profile (netns ue1, tun_srsue, bind 127.0.1.1, ZMQ 2000/2001, subscriber from /root/lab5g-sub.env created by sa-config.sh).
# Pair i>=2: netns ue<i>, tun_srsue<i>, bind 127.0.1.<i>, ZMQ 2000+10*(i-1)/+1, PCI i, gnb_id 410+i, IMSI 00101 + MSIN base+i, own K/OPC.
# Usage: nr-pairs-config.sh <N>   (env: SA_BW_MHZ=20|10, OUT_DIR=/etc/lab5g/sa, DRY_RUN=1 -> fake secrets, no mongo/netns)
# Secrets: /root/lab5g-pairs.env and */ue.conf are 0600, never printed.
set -eu
N=${1:-1}; BW=${SA_BW_MHZ:-20}; OUT=${OUT_DIR:-/etc/lab5g/sa}; TPL=${TPL_DIR:-$(cd "$(dirname "$0")" && pwd)}
DRY=${DRY_RUN:-0}; PCC=${SA_STATIC_PCC:-0}; SUBENV=${SUBENV:-/root/lab5g-sub.env}; PAIRENV=${PAIRENV:-/root/lab5g-pairs.env}
case "$N" in 1|2|3|4) ;; *) echo "N must be 1..4" >&2; exit 2;; esac
if [ "$BW" = 10 ]; then SR=11.52; PRB=52; CS0=6; else SR=23.04; PRB=106; CS0=12; fi
umask 077
if [ "$DRY" = 1 ]; then
  IMSI1=00101$(printf %010d "$(( $(od -An -N4 -tu4 /dev/urandom) % 9000000000 ))"); KEY1=$(openssl rand -hex 16); OPC1=$(openssl rand -hex 16)  # DRY: random dummy, never fixed
  PAIRENV=$(mktemp)
else
  # shellcheck disable=SC1090
  . "$SUBENV"; IMSI1=$IMSI; KEY1=$KEY; OPC1=$OPC
fi
# extra-pair credentials: generated once, persisted (so a re-run keeps the same subscribers)
# (pairs 2..4; an older env file with only pairs 2..3 gets the missing pair appended, existing ones are kept)
[ "$DRY" = 1 ] && : > "$PAIRENV"
touch "$PAIRENV"
BASE=$(( $(od -An -N4 -tu4 /dev/urandom) % 9000000000 + 100000000 ))
for i in 2 3 4; do
  grep -q "^IMSI$i=" "$PAIRENV" && continue
  printf 'IMSI%s=00101%010d\nKEY%s=%s\nOPC%s=%s\n' "$i" $((BASE + i)) "$i" "$(openssl rand -hex 16)" "$i" "$(openssl rand -hex 16)" >> "$PAIRENV"
done
# shellcheck disable=SC1090
. "$PAIRENV"
mkdir -p "$OUT"
for i in $(seq 1 "$N"); do
  D=$OUT/pair$i; install -d -m 0755 "$D"
  TXP=$((2000 + 10 * (i - 1))); RXP=$((TXP + 1)); BIND=127.0.1.$i
  IF=tun_srsue; [ "$i" -gt 1 ] && IF=tun_srsue$i
  if [ "$i" = 1 ]; then IM=$IMSI1; K=$KEY1; O=$OPC1; else eval "IM=\$IMSI$i; K=\$KEY$i; O=\$OPC$i"; fi
  IMEI=35349006987$(printf '%04d' "$i")
  umask 022
  sed -e "s/__I__/$i/g" -e "s/__GNBID__/$((410 + i))/" -e "s/__BIND__/$BIND/g" -e "s/__TXP__/$TXP/g" -e "s/__RXP__/$RXP/g" \
      -e "s/__SR__/$SR/g" -e "s/__BW__/$BW/g" -e "s/__CS0__/$CS0/g" -e "s/__PCI__/$i/" "$TPL/gnb-pair.yaml.tmpl" > "$D/gnb.yaml"
  umask 077
  sed -e "s/__I__/$i/g" -e "s/__TXP__/$TXP/g" -e "s/__RXP__/$RXP/g" -e "s/__SR__/$SR/g" -e "s/__PRB__/$PRB/g" \
      -e "s/__IFNAME__/$IF/" -e "s/__IMSI__/$IM/" -e "s/__K__/$K/" -e "s/__OPC__/$O/" -e "s/__IMEI__/$IMEI/" "$TPL/ue-pair.conf.tmpl" > "$D/ue.conf"
  chmod 0600 "$D/ue.conf"
  if [ "$DRY" != 1 ]; then
    ip netns list | grep -qw "ue$i" || ip netns add "ue$i"
    mkdir -p "/etc/netns/ue$i"; echo "nameserver 8.8.8.8" > "/etc/netns/ue$i/resolv.conf"
    ip addr show dev lo | grep -q "127.0.1.$i/" || ip addr add "127.0.1.$i/8" dev lo 2>/dev/null || true
  fi
done
# Open5GS subscribers for pairs 2..N; static PCC rule (5QI 7 -> QFI 2) only if SA_STATIC_PCC=1 (srsUE: 1 QoS flow, see sa-config.sh); pair 1 untouched.
if [ "$DRY" != 1 ] && [ "$N" -gt 1 ]; then
  for i in $(seq 2 "$N"); do
    eval "IM=\$IMSI$i; K=\$KEY$i; O=\$OPC$i"
    docker exec -e IMSI="$IM" -e K="$K" -e OPC="$O" -e PCC="$PCC" mongo mongosh --quiet open5gs --eval '
const e=process.env; db.subscribers.deleteMany({imsi:e.IMSI});
const amb={downlink:{value:1,unit:3},uplink:{value:1,unit:3}};
const fl=[{direction:1,description:"permit out udp from any 4789 to assigned"},{direction:2,description:"permit out udp from any 4789 to assigned"},
          {direction:1,description:"permit out tcp from any 18080 to assigned"},{direction:2,description:"permit out tcp from any 18080 to assigned"}];
const pcc={qos:{index:7,arp:{priority_level:6,pre_emption_capability:1,pre_emption_vulnerability:1}},flow:fl};
db.subscribers.insertOne({schema_version:1,imsi:e.IMSI,msisdn:[],imeisv:[],mme_host:[],mme_realm:[],purge_flag:[],
 security:{k:e.K,op:null,opc:e.OPC,amf:"8000",sqn:NumberLong(161)},ambr:amb,
 slice:[{sst:1,default_indicator:true,session:[{name:"internet",type:3,ambr:amb,
  qos:{index:9,arp:{priority_level:8,pre_emption_capability:1,pre_emption_vulnerability:1}},pcc_rule:(e.PCC==="1"?[pcc]:[])}]}],
 access_restriction_data:32,network_access_mode:0,subscriber_status:0,operator_determined_barring:0,subscribed_rau_tau_timer:12,__v:0});
print("SUB_ADDED")' >/dev/null
  done
fi
echo "NR_PAIRS_CONFIG_DONE pairs=$N bw=${BW}MHz srate=$SR"
