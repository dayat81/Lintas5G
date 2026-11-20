#!/bin/bash
# ut-upf.sh <tag> <pcap-with-UE1-UL>: deterministic UPF test for the N1 fix (stale QFI on a known TEID).
T=$1; PC=$2; D=/workspace/oai-n5-test; R=$D/res/$T; mkdir -p $R; rm -f $R/*; DK="sudo docker"
PID=$($DK inspect -f '{{.State.Pid}}' n5-lab); U1=$(sudo cat $D/secrets/ue1.ip); NS="sudo nsenter -t $PID -n"
$DK exec n5-lab sh -c "wc -l < /var/log/open5gs/upf.log" > $R/upf.l0
$DK exec n5-lab rm -f /tmp/tun.pcap; $DK exec -d n5-lab sh -c "timeout 40 tcpdump -Z root -i ogstun -n -w /tmp/tun.pcap udp portrange 18080-18099 and src port 40999"; sleep 2
inj() { $NS python3 $D/gtpinj.py $PC $U1 "$@" | sed -E 's/10\.45\.[0-9.]+/10.45.x.x/g'; }
echo "== a) no QoD flow: stale QFI 2 on known TEID (expect forwarded on default PDR, no EI)"; inj 2 18091
echo "== a2) control: QFI 1 on known TEID"; inj 1 18092
sudo rm -f /tmp/n5-ut-wf
$NS $D/.venv/bin/python $D/n5proto.py cycle --imsi-file $D/secrets/imsi1 --ue-ip-file $D/secrets/ue1.ip --profile QOS_7 --mode persistent \
  --protos 6,17 --as-port 18080 --wait-before-delete /tmp/n5-ut-wf --events $R/events.jsonl --callbacks $R/cb.jsonl > $R/n5proto.out 2>&1 &
sleep 3
echo "== b1) QoD active (QFI 2 bound to AS:18080): QFI 2 to 18080 (expect forwarded by QoD PDR)"; inj 2 18080
echo "== b2) QoD active: QFI 2 to 18093 (bound QFI, no rule match: expect silent drop, no EI)"; inj 2 18093
echo "== b3) QoD active: QFI 9 to 18094 (unbound QFI: expect default PDR)"; inj 9 18094
sudo touch /tmp/n5-ut-wf; wait; sudo rm -f /tmp/n5-ut-wf
echo "== c) unknown TEID (expect Error Indication, unchanged 3GPP behaviour)"; inj 2 18095 0x7ffffff0
sleep 1; $DK exec n5-lab pkill -x tcpdump; sleep 1
$DK exec n5-lab sh -c "tcpdump -r /tmp/tun.pcap -n 2>/dev/null" | awk '{print $5}' | sed -E 's/.*\.//; s/://' | sort | uniq -c | awk '{print "ogstun dport "$2": "$1" pkts"}'
echo "upf_log_error_indication=$($DK exec n5-lab sh -c "tail -n +$(( $(cat $R/upf.l0)+1 )) /var/log/open5gs/upf.log" | grep -c 'Error Indication')"
$DK exec n5-lab sh -c "tail -n +$(( $(cat $R/upf.l0)+1 )) /var/log/open5gs/upf.log" | sed -E 's/imsi-[0-9]+/imsi-<redacted>/g; s/10\.45\.[0-9]+\.[0-9]+/10.45.x.x/g' > $R/upf.win.log; rm -f $R/upf.l0
for f in $R/*.jsonl $R/*.out; do sed -i -E 's/imsi-[0-9]+/imsi-<redacted>/g; s/\b10\.45\.[0-9]+\.[0-9]+\b/10.45.x.x/g' $f; done
