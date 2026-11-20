#!/bin/bash
# run-trace.sh <rep>: one CAMARA QoD session (QOS_E, UE1, DELETE after AVAILABLE) with capture on lo in the n5-lab netns
# (CAMARA 8080 http/1.1, SBI 7777 h2c, PFCP 8805, NGAP 38412 via sctp2tcp shim, N3 2152) + gNB log -> correlate.py -> redacted timeline.
# Raw pcap + raw gNB log stay in raw/ (700, box only).
set -eu; H=$(cd "$(dirname "$0")" && pwd); F=$(dirname "$H"); R=$1; DK="sudo docker"
LP=$($DK inspect -f '{{.State.Pid}}' n5-lab); U1=$($DK inspect -f '{{.State.Pid}}' n5-ue1); PY=/workspace/qod-adapter/.venv/bin/python
sudo nsenter -t $U1 -n nohup python3 $F/tools/udpprobe.py <AS_IP> 18080 50 25 $H/raw/probe-$R.csv >/dev/null 2>&1 &
sudo nsenter -t $LP -n tcpdump -i lo -s 0 -U -w $H/raw/trace-$R.pcap 'tcp port 8080 or tcp port 7777 or udp port 8805 or tcp port 38412 or udp port 2152' >/dev/null 2>&1 &
sleep 3; T=$(date -u +%Y-%m-%dT%H:%M:%SZ)
sudo nsenter -t $LP -n $PY $F/tools/cb_test.py c1 > $H/raw/cb-$R.json
sleep 2; sudo pkill -f "tcpdump -i lo -s 0 -U -w $H/raw/trace-$R.pcap"; sleep 0.5
$DK logs -t --since $T n5-gnb > $H/raw/gnb-$R.log 2>&1
SID=$(python3 -c "import json;print(json.load(open('$H/raw/cb-$R.json'))['sessionId'])")
python3 $H/correlate.py $H/raw/trace-$R.pcap $H/raw/gnb-$R.log $F/run/sink.jsonl $SID > $H/timeline-$R.json
python3 -c "import json;d=json.load(open('$H/timeline-$R.json'));print('$R', json.dumps(d['key_points_ms_from_N5']))"
