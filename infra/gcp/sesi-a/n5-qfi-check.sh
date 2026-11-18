#!/bin/bash
# Verifikasi data-plane: apakah UPF menandai paket DL flow ber-policy dengan QFI baru (GTP-U PDU Session Container)?
D=$(dirname "$(readlink -f "$0")"); O=/var/log/lab5g/n5; mkdir -p $O
PCF=127.0.0.13:7777
UE=$(ip netns exec ue1 ip -4 -o addr show uesimtun0 | awk '{print $4}' | cut -d/ -f1)
SRV=$(ip route get 8.8.8.8 | awk '{for(i=1;i<=NF;i++) if($i=="src") print $(i+1)}')
N="ip netns exec ue1"
cnt() { tshark -r $1 -Y gtp -T fields -e gtp.ext_hdr.pdu_ses_cont.pdu_type -e gtp.ext_hdr.pdu_ses_cont.qos_flow_id 2>/dev/null | sort | uniq -c; }
cap() { dumpcap -q -i lo -s 128 -a duration:4 -w $O/$1.pcapng -f 'udp port 2152' 2>/dev/null & sleep 0.5; $N iperf3 -c $SRV -t 3 -R -b 20M > /dev/null; $N ping -c 3 -i 0.2 -q 8.8.8.8 >/dev/null; wait; echo "== $1: count pdu_type(0=DL,1=UL) QFI =="; cnt $O/$1.pcapng; }
cap qfi-before
sed "s|__UE_IP__|$UE|g; s|__SRV_IP__|$SRV|g; s|__BW__|10 Mbps|g" $D/n5-create.json.tmpl > $O/req-create2.json
LOC=$(curl -sS -i --http2-prior-knowledge -X POST -H 'Content-Type: application/json' --data @$O/req-create2.json http://$PCF/npcf-policyauthorization/v1/app-sessions | tee $O/resp-create2.txt | awk 'tolower($1)=="location:"{print $2}' | tr -d '\r')
head -1 $O/resp-create2.txt; echo "LOC=$LOC"; sleep 2
cap qfi-with-policy
curl -sS -o /dev/null -w "DELETE HTTP %{http_code}\n" --http2-prior-knowledge -X POST -H 'Content-Type: application/json' --data '{}' "$LOC/delete"
