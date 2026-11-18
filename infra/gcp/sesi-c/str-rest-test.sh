#!/bin/bash
# Sesi C: varian DELETE REST (tanpa bearer dedicated). Dipakai karena pada str-test.sh link srsRAN ZMQ jatuh ke RLF
# ~8 s setelah E-RAB release (Delete Bearer) di bawah beban -> probe pasca-remove tidak valid.
# POST /qod (curl, gbrKbps=5000) -> probe QoD N=150 -> DELETE /qod/<id> -> probe pasca-remove N=150, beban jalan terus.
E=${1:?emu_ip}; S=/opt/lab5g/sesi-c; D=/var/log/lab5g/str; mkdir -p $D; NS="ip netns exec ue1"; P=/var/log/lab5g/p99; Q=http://127.0.0.1:8090
UE=$($NS ip -4 -o addr show tun_srsue | awk '{print $4}' | cut -d/ -f1)
tf(){ { echo "## $1 $(date -u +%T.%3N)Z"; tc filter show dev ogstun; echo ---ifb0; tc filter show dev ifb0; } > $D/rest-tc-$1.txt; echo "rest-tc-$1 flowid_count=$(grep -c flowid $D/rest-tc-$1.txt)"; }
$NS ping -c 10 -i 0.2 $E | tail -1
$NS iperf3 -c $E -p 8123 -R -P 4 -t 170 -J > $D/rest-iperf-dl.json 2>&1 & P1=$!
$NS iperf3 -c $E -p 6000 -t 170 -J > $D/rest-iperf-ul.json 2>&1 & P2=$!
sleep 8; tf 0-before-post
curl -s -X POST -H 'Content-Type: application/json' -d "{\"ueIpv4\":\"$UE\",\"remote\":\"$E\",\"port\":9000,\"gbrKbps\":5000,\"source\":\"manual-curl-af\"}" $Q/qod | tee $D/rest-post.json; echo
tf 1-after-post
N=150 bash $S/p99-run.sh r1-load-qod $E 0
curl -s -X DELETE $Q/qod/qod | tee $D/rest-delete.json; echo
tf 2-after-delete
N=150 bash $S/p99-run.sh r2-load-after-delete $E 0
kill -INT $P1 $P2 2>/dev/null; sleep 3
cp $P/r1-load-qod-* $P/r2-load-after-delete-* $D/ 2>/dev/null
python3 $S/p99-stats.py $P r1-load-qod r2-load-after-delete | tee $D/summary-rest.csv
tail -2 /var/log/lab5g/keepalive.log
echo REST_TEST_DONE
