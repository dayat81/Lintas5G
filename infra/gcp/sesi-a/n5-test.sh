#!/bin/bash
# Tes N5 (a) Npcf_PolicyAuthorization create/patch/delete + (b) bukti N7/N4 (PFCP QER/QFI) + iperf3 sebelum/sesudah.
# Jalankan sebagai root di vm-core-ran. Usage: n5-test.sh [BW_CREATE] [BW_PATCH]
BW1=${1:-10 Mbps}; BW2=${2:-5 Mbps}
D=$(dirname "$(readlink -f "$0")"); O=/var/log/lab5g/n5; mkdir -p $O
PCF=${PCF:-$(awk '/^pcf:/{f=1} f&&/address:/{print $3; exit}' /etc/open5gs/pcf.yaml)}:7777
UE=$(ip netns exec ue1 ip -4 -o addr show uesimtun0 | awk '{print $4}' | cut -d/ -f1)
SRV=$(ip route get 8.8.8.8 | awk '{for(i=1;i<=NF;i++) if($i=="src") print $(i+1)}')
echo "PCF=$PCF UE=$UE SRV=$SRV BW1=$BW1 BW2=$BW2" | tee $O/env.txt
pgrep -f "iperf3 -s" >/dev/null || iperf3 -s -D -B $SRV
N="ip netns exec ue1"
ip3() { # $1=label $2=extra
  $N iperf3 -c $SRV -t 8 -O 1 $2 -J > $O/iperf-$1.json 2>&1
  jq -r --arg l "$1" '"\($l): \((.end.sum_received.bits_per_second // .end.sum.bits_per_second // 0)/1e6 | floor) Mbit/s recv, retr=\(.end.sum_sent.retransmits // "na") loss%=\(.end.sum.lost_percent // "na")"' $O/iperf-$1.json
}
qos_state() { echo "--- UPF/SMF log tail ($1) ---"; grep -hE "QER|QFI|qfi|Bearer|QoS|PCC|Modification|N1N2|PDU" /var/log/open5gs/smf.log /var/log/open5gs/upf.log | tail -8; }
dumpcap -q -i lo -s 0 -w $O/n5-pfcp-sbi.pcapng -f 'udp port 8805 or tcp port 7777 or sctp' 2>/dev/null & TD=$!
sleep 1
echo "== (0) baseline =="; ip3 base-ul; ip3 base-dl -R
sed "s|__UE_IP__|$UE|g; s|__SRV_IP__|$SRV|g; s|__BW__|$BW1|g" $D/n5-create.json.tmpl > $O/req-create.json
echo "== (a1) POST app-sessions =="
curl -sS -i --http2-prior-knowledge -X POST -H 'Content-Type: application/json' \
  --data @$O/req-create.json http://$PCF/npcf-policyauthorization/v1/app-sessions -o $O/resp-create.txt -w "HTTP %{http_code} t=%{time_total}s\n"
cat $O/resp-create.txt | head -40; echo
LOC=$(grep -i '^location:' $O/resp-create.txt | awk '{print $2}' | tr -d '\r')
echo "LOCATION=$LOC"
sleep 4; qos_state after-create
echo "== (b) iperf sesudah policy $BW1 =="; ip3 pol1-ul; ip3 pol1-dl -R
echo "== UDP ${BW1/ Mbps/}x3 sesudah policy (cek policing) =="; ip3 pol1-udp-dl "-u -b 30M -R"; ip3 pol1-udp-ul "-u -b 30M"
if [ -n "$LOC" ]; then
  sed "s|__UE_IP__|$UE|g; s|__SRV_IP__|$SRV|g; s|__BW__|$BW2|g" $D/n5-patch.json.tmpl > $O/req-patch.json
  echo "== (a2) PATCH =="
  curl -sS -i --http2-prior-knowledge -X PATCH -H 'Content-Type: application/merge-patch+json' \
    --data @$O/req-patch.json "$LOC" -o $O/resp-patch.txt -w "HTTP %{http_code} t=%{time_total}s\n"; head -20 $O/resp-patch.txt; echo
  sleep 4; qos_state after-patch
  echo "== iperf sesudah PATCH $BW2 =="; ip3 pol2-ul; ip3 pol2-dl -R
  echo "== (a3) DELETE (POST {id}/delete) =="
  curl -sS -i --http2-prior-knowledge -X POST -H 'Content-Type: application/json' --data '{}' \
    "$LOC/delete" -o $O/resp-delete.txt -w "HTTP %{http_code} t=%{time_total}s\n"; head -20 $O/resp-delete.txt; echo
  sleep 4; qos_state after-delete
  echo "== iperf sesudah DELETE =="; ip3 del-ul; ip3 del-dl -R
fi
sleep 1; kill $TD; sleep 1
echo "== PFCP Session Modification (tshark) =="
tshark -r $O/n5-pfcp-sbi.pcapng -Y 'pfcp.msg_type==52 || pfcp.msg_type==53' 2>/dev/null | tee $O/pfcp-summary.txt
tshark -r $O/n5-pfcp-sbi.pcapng -Y 'pfcp.msg_type==52' -O pfcp -V 2>/dev/null > $O/pfcp-mod-detail.txt
grep -nE "Session Modification Request|Create QER|Update QER|Remove QER|QER ID|QFI|MBR|GBR|Uplink|Downlink|Gate|Create PDR|Remove PDR|SDF Filter|Flow Description|Precedence" $O/pfcp-mod-detail.txt | head -80
echo "== HTTP/2 SBI (N5/N7) =="
tshark -r $O/n5-pfcp-sbi.pcapng -d tcp.port==7777,http2 -Y 'http2.header.value contains "policyauthorization" or http2.header.value contains "sm-policies" or http2.header.value contains "update-notify" or http2.header.value contains "app-sessions"' \
  -T fields -e frame.time_relative -e ip.src -e ip.dst -e http2.headers.method -e http2.headers.path -e http2.headers.status 2>/dev/null | tee $O/sbi-summary.txt | head -30
