#!/bin/bash
# cycle.sh <tag> <profile> [mode] [protos]: one on-demand QoD cycle with traffic + N3 capture + log windows.
T=$1; P=${2:-QOS_E}; M=${3:-ephemeral}; PR=${4:-6,17}; D=/workspace/oai-n5-test; R=$D/res/$T; mkdir -p $R; rm -f $R/*
PID=$(sudo docker inspect -f '{{.State.Pid}}' n5-lab); U1=$(sudo cat $D/secrets/ue1.ip); U2=$(sudo cat $D/secrets/ue2.ip)
for c in n5-lab n5-ue1 n5-ue2; do sudo docker cp $D/udpgen.py $c:/tmp/udpgen.py; done
for n in smf pcf amf bsf upf; do sudo docker exec n5-lab wc -l < /dev/null; sudo docker exec n5-lab sh -c "wc -l < /var/log/open5gs/$n.log" > $R/$n.l0; done
sudo docker logs n5-gnb 2>&1 | wc -l > $R/gnb.l0; for i in 1 2; do sudo docker logs n5-ue$i 2>&1 | wc -l > $R/ue$i.l0; done
sudo docker exec n5-lab pkill -x iperf3; sudo docker exec -d n5-lab iperf3 -s -1 -B 10.45.0.1 -p 18080
sudo docker exec n5-lab rm -f /tmp/n3.pcap; sudo docker exec -d n5-lab sh -c "timeout 70 tcpdump -Z root -i lo -s 128 -w /tmp/n3.pcap udp port 2152 2>/tmp/td.err"
sleep 2; DUR=40
# DL UDP generators (AS side): QoD port 18080 -> ue1, ue2 (isolation); control port 5201 -> ue1
sudo docker exec -d n5-lab python3 /tmp/udpgen.py 10.45.0.1 18080 $U1 40000 100 $DUR
sudo docker exec -d n5-lab python3 /tmp/udpgen.py 10.45.0.1 18080 $U2 40000 100 $DUR
sudo docker exec -d n5-lab python3 /tmp/udpgen.py 10.45.0.1 5201 $U1 40001 100 $DUR
# UL UDP generators (UE side)
sudo docker exec -d n5-ue1 python3 /tmp/udpgen.py $U1 40000 10.45.0.1 18080 100 $DUR
sudo docker exec -d n5-ue2 python3 /tmp/udpgen.py $U2 40000 10.45.0.1 18080 100 $DUR
sudo docker exec -d n5-ue1 python3 /tmp/udpgen.py $U1 40001 10.45.0.1 5201 100 $DUR
# TCP on QoD port (ue1), 1 Mbit/s
sudo docker exec -d n5-ue1 sh -c "iperf3 -c 10.45.0.1 -p 18080 -b 1M -t $((DUR-2)) > /tmp/iperf-tcp.txt 2>&1"
sleep 6
WF=""; if [ "${REL:-0}" = 1 ]; then WF="--wait-before-delete /tmp/n5-wf"; sudo rm -f /tmp/n5-wf
  # release path: after 15 s stop UE1 (PDU session release / deregistration) instead of N5 delete; delete afterwards (expect 404)
  (sleep 15; date +%s.%N > $R/ue1_stop.ts; sudo docker stop -t 10 n5-ue1 >/dev/null; date +%s.%N >> $R/ue1_stop.ts; sleep 3; sudo touch /tmp/n5-wf) & fi
sudo nsenter -t $PID -n $D/.venv/bin/python $D/n5proto.py cycle --imsi-file $D/secrets/imsi1 --ue-ip-file $D/secrets/ue1.ip \
  --profile $P --mode $M --protos $PR --hold 15 $WF --events $R/events.jsonl --callbacks $R/callbacks.jsonl 2>&1 | tee $R/n5proto.out
sleep $((DUR-6-22>0 ? DUR-6-22 : 1)); sleep 4
sudo docker exec n5-lab pkill -x tcpdump; sleep 1; sudo docker cp n5-lab:/tmp/n3.pcap $R/n3.pcap >/dev/null
for n in smf pcf amf bsf upf; do sudo docker exec n5-lab sh -c "tail -n +$(( $(cat $R/$n.l0)+1 )) /var/log/open5gs/$n.log" | sed -E 's/imsi-[0-9]+/imsi-<redacted>/g; s/suci-[0-9-]+/suci-<redacted>/g; s/\b[0-9]{15}\b/<IMSI>/g; s/10\.45\.[0-9]+\.[0-9]+/10.45.x.x/g' > $R/$n.win.log; done
sudo docker logs n5-gnb 2>&1 | tail -n +$(( $(cat $R/gnb.l0)+1 )) | sed -E 's/10\.45\.[0-9]+\.[0-9]+/10.45.x.x/g' > $R/gnb.win.log
for i in 1 2; do sudo docker logs n5-ue$i 2>&1 | tail -n +$(( $(cat $R/ue$i.l0)+1 )) | sed -E 's/10\.45\.[0-9]+\.[0-9]+/10.45.x.x/g; s/\b[0-9]{15}\b/<IMSI>/g' > $R/ue$i.win.log; done
python3 $D/qfi_timeline.py $R/n3.pcap $R/events.jsonl $U1 $U2 | tee $R/qfi.txt
for i in 1 2; do sudo docker exec n5-ue$i sh -c 'tail -2 /tmp/keepalive.log' | sed -E 's/10\.45\.[0-9.]+/10.45.x.x/g'; done | tee $R/keepalive.txt
rm -f $R/*.l0
