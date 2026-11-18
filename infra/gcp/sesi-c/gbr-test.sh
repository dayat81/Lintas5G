#!/bin/bash
# Sesi C: goodput & loss flow QoD 5 Mbit/s (GBR AAR = 5 Mbps) di bawah beban bulk.
# UDP: udp-flow.py di emu :4789 (satu-satunya UDP yang dibuka firewall). TCP: iperf3 -b 5M di emu :18080.
# Kondisi: (a) tanpa QoD, (b) QoD gbrKbps=0 (rate kelas statis 30% = perilaku Sesi B), (c) QoD gbrKbps=5000 (reservasi GBR, Sesi C).
E=${1:?emu_ip}; S=/opt/lab5g/sesi-c; D=/var/log/lab5g/gbr; mkdir -p $D; NS="ip netns exec ue1"; Q=http://127.0.0.1:8090; DUR=${DUR:-30}
UE=$($NS ip -4 -o addr show tun_srsue | awk '{print $4}' | cut -d/ -f1)
post(){ curl -s -X POST -H 'Content-Type: application/json' -d "{\"ueIpv4\":\"$UE\",\"remote\":\"$E\",\"port\":$1,\"gbrKbps\":$2,\"source\":\"gbr-test\"}" $Q/qod; }
del(){ curl -s -X DELETE $Q/qod/qod; echo; }
uf(){ $NS python3 $S/udp-flow.py $1 --host $E --port 4789 --kbps 5000 --dur $DUR; }
$NS iperf3 -c $E -p 8123 -R -P 4 -t 400 -J > $D/gbr-bulk-dl.json 2>&1 & P1=$!
$NS iperf3 -c $E -p 6000 -t 400 -J > $D/gbr-bulk-ul.json 2>&1 & P2=$!
sleep 8
echo "## a-noqod"; uf dl | tee $D/a-noqod-udp-dl.json; uf ul | tee $D/a-noqod-udp-ul.json
echo "## b-qod-static"; post 4789 0 | tee $D/b-post.json; echo; uf dl | tee $D/b-static-udp-dl.json; uf ul | tee $D/b-static-udp-ul.json; del
echo "## c-qod-gbr"; post 4789 5000 | tee $D/c-post.json; echo; tc -s class show dev ogstun > $D/c-tc-ogstun-pre.txt
uf dl | tee $D/c-gbr-udp-dl.json; uf ul | tee $D/c-gbr-udp-ul.json; tc -s class show dev ogstun > $D/c-tc-ogstun.txt; tc -s class show dev ifb0 > $D/c-tc-ifb0.txt; del
echo "## c-qod-gbr-tcp"; post 18080 5000 | tee $D/c-tcp-post.json; echo
$NS iperf3 -c $E -p 18080 -R -b 5M -t $DUR -J > $D/c-gbr-tcp-dl.json 2>&1
$NS iperf3 -c $E -p 18080 -b 5M -t $DUR -J > $D/c-gbr-tcp-ul.json 2>&1; del
python3 - $D <<'PY'
import json,sys,glob,os
d=sys.argv[1]
for f in sorted(glob.glob(d+'/c-gbr-tcp-*.json')):
    j=json.load(open(f)); e=j.get('end',{}); s=e.get('sum_received') or e.get('sum',{}); t=e.get('sum_sent',{})
    print(os.path.basename(f), 'recv_mbps=%.3f'%(s.get('bits_per_second',0)/1e6), 'retrans=%s'%t.get('retransmits'))
PY
kill -INT $P1 $P2 2>/dev/null; sleep 3
echo GBR_TEST_DONE
