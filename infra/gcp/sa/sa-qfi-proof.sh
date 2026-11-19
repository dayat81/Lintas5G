#!/bin/bash
# Evidence: QFI 2 end-to-end on N3 (5G SA). Static PCC rule (sa-config.sh) maps udp/4789 + tcp/18080 to a second
# Needs SA_STATIC_PCC=1 in sa-config.sh AND a UE with multi-QoS-flow SDAP (UERANSIM/handset); srsUE 23.11 NR cannot (1 flow only).
# QoS flow (5QI 7). Captures N3 (lo, GTP-U) while sending ICMP (default flow, QFI 1) and UDP 4789 both directions,
# and counts GTP-U PDU Session Container QFIs per direction. Output: /var/log/lab5g/sa/qfi/ (pcap stays on the VM).
O=/var/log/lab5g/sa/qfi; mkdir -p $O; N="ip netns exec ue1"; TUN=${TUN:-tun_srsue}
UE=$($N ip -4 -o addr show $TUN | awk '{print $4}' | cut -d/ -f1)
SRV=$(ip route get 8.8.8.8 | awk '{for(i=1;i<=NF;i++) if($i=="src") print $(i+1)}')
[ -n "$UE" ] || { echo "no UE IP on $TUN"; exit 1; }
dumpcap -q -i lo -s 160 -a duration:12 -w $O/n3.pcapng -f 'udp port 2152' 2>/dev/null & CP=$!; sleep 1
$N ping -c 20 -i 0.2 -q 8.8.8.8 >/dev/null &
python3 - "$UE" "$SRV" <<'PY' &
import socket,sys,time
ue,srv=sys.argv[1],sys.argv[2]
rx=socket.socket(socket.AF_INET,socket.SOCK_DGRAM); rx.bind((srv,4789)); rx.settimeout(0.2)
tx=socket.socket(socket.AF_INET,socket.SOCK_DGRAM); tx.bind((srv,4789))
for i in range(50):  # DL: server port 4789 -> UE (matches "from any 4789 to assigned")
    tx.sendto(b"lab5g-qfi-dl %d"%i,(ue,40000)); time.sleep(0.1)
PY
$N python3 -c "
import socket,time,sys
s=socket.socket(socket.AF_INET,socket.SOCK_DGRAM); s.bind(('0.0.0.0',40000))
for i in range(50): s.sendto(b'lab5g-qfi-ul %d'%i,('$SRV',4789)); time.sleep(0.1)"
wait $CP
echo "count  pdu_type(0=DL,1=UL)  QFI   [all GTP-U]"
tshark -r $O/n3.pcapng -Y gtp -T fields -e gtp.ext_hdr.pdu_ses_cont.pdu_type -e gtp.ext_hdr.pdu_ses_cont.qos_flow_id 2>/dev/null | sort | uniq -c | tee $O/qfi-all.txt
echo "count  pdu_type  QFI   [inner udp port 4789]"
tshark -r $O/n3.pcapng -Y 'gtp && udp.port==4789' -T fields -e gtp.ext_hdr.pdu_ses_cont.pdu_type -e gtp.ext_hdr.pdu_ses_cont.qos_flow_id 2>/dev/null | sort | uniq -c | tee $O/qfi-4789.txt
ul=$(awk '$2==1 && $3==2{s+=$1} END{print s+0}' $O/qfi-4789.txt); dl=$(awk '$2==0 && $3==2{s+=$1} END{print s+0}' $O/qfi-4789.txt)
[ "$ul" -gt 0 ] && [ "$dl" -gt 0 ] && echo "QFI2_E2E=PASS ul=$ul dl=$dl" || echo "QFI2_E2E=FAIL ul=$ul dl=$dl"
