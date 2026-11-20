#!/bin/bash
# par.sh <tag>: 2 parallel QoD sessions (UE1 QOS_7, UE2 QOS_L), templates persistent, then DELETE both; N3 capture + logs.
T=$1; D=/workspace/oai-n5-test; R=$D/res/$T; mkdir -p $R; rm -f $R/*
PID=$(sudo docker inspect -f '{{.State.Pid}}' n5-lab); U1=$(sudo cat $D/secrets/ue1.ip); U2=$(sudo cat $D/secrets/ue2.ip)
PY="sudo nsenter -t $PID -n $D/.venv/bin/python"
for u in 1 2; do $PY $D/n5proto.py provision --imsi-file $D/secrets/imsi$u --profile QOS_7 --events $R/events.jsonl >/dev/null; $PY $D/n5proto.py provision --imsi-file $D/secrets/imsi$u --profile QOS_L --events $R/events.jsonl >/dev/null; done
for c in n5-lab n5-ue1 n5-ue2; do sudo docker cp $D/udpgen.py $c:/tmp/udpgen.py; done
for n in smf upf; do sudo docker exec n5-lab sh -c "wc -l < /var/log/open5gs/$n.log" > $R/$n.l0; done; sudo docker logs n5-gnb 2>&1 | wc -l > $R/gnb.l0
sudo docker exec n5-lab rm -f /tmp/n3.pcap; sudo docker exec -d n5-lab sh -c "timeout 50 tcpdump -Z root -i lo -s 128 -w /tmp/n3.pcap udp port 2152"; sleep 2
for u in 1 2; do U=$(sudo cat $D/secrets/ue$u.ip); sudo docker exec -d n5-lab python3 /tmp/udpgen.py 10.45.0.1 18080 $U 40000 100 40; sudo docker exec -d n5-ue$u python3 /tmp/udpgen.py $U 40000 10.45.0.1 18080 100 40; done
sleep 5; sudo rm -f /tmp/n5-wf
$PY $D/n5proto.py cycle --mode none --imsi-file $D/secrets/imsi1 --ue-ip-file $D/secrets/ue1.ip --profile QOS_7 --wait-before-delete /tmp/n5-wf --events $R/ev-ue1.jsonl --callbacks $R/cb1.jsonl > $R/ue1.out 2>&1 &
sleep 0.3
sudo nsenter -t $PID -n env CB=1 $D/.venv/bin/python - > $R/ue2.out 2>&1 <<PYEOF &
import sys, os, time, json; sys.argv=['x']; sys.path.insert(0,'$D'); import n5proto as n
ip=open('$D/secrets/ue2.ip').read().strip(); s=n.Sbi(); pcf,_=s.bsf_discover(ip)
r,e=s.create(pcf, n.build_asc(ip,'oai',1,'QOS_L','10.45.0.1',[18080],'http://127.0.0.99:9999/lintas5g/v1/notify/ue2'))
while not os.path.exists('/tmp/n5-wf'): time.sleep(0.05)
s.delete(r.headers['location'])
open('$R/ev-ue2.jsonl','w').write("\n".join(n.mask(json.dumps(x)) for x in n.LOG)+"\n")
PYEOF
sleep 14; sudo touch /tmp/n5-wf; sleep 22; wait
sudo docker exec n5-lab pkill -x tcpdump; sleep 1; sudo docker cp n5-lab:/tmp/n3.pcap $R/n3.pcap >/dev/null
for n in smf upf; do sudo docker exec n5-lab sh -c "tail -n +$(( $(cat $R/$n.l0)+1 )) /var/log/open5gs/$n.log" | sed -E 's/imsi-[0-9]+/imsi-<redacted>/g; s/suci-[0-9-]+/suci-<redacted>/g; s/10\.45\.[0-9]+\.[0-9]+/10.45.x.x/g' > $R/$n.win.log; done
sudo docker logs n5-gnb 2>&1 | tail -n +$(( $(cat $R/gnb.l0)+1 )) | sed -E 's/10\.45\.[0-9]+\.[0-9]+/10.45.x.x/g' > $R/gnb.win.log
for u in 1 2; do echo "== ue$u"; TARGET_UE=ue$u python3 $D/qfi_timeline.py $R/n3.pcap $R/ev-ue$u.jsonl $U1 $U2 | grep -v "icmp\|5201" ; done | tee $R/qfi.txt
$PY $D/n5proto.py reset --events $R/events.jsonl >/dev/null; rm -f $R/*.l0
for f in $R/*.jsonl $R/*.out; do sed -i -E 's/imsi-[0-9]+/imsi-<redacted>/g; s/\b10\.45\.[0-9]+\.[0-9]+\b/10.45.x.x/g' $f; done
