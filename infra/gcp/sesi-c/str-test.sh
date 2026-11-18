#!/bin/bash
# Sesi C: tes ulang DELETE/STR di bawah beban kontinu.
# AAR -> AAA -> adapter apply (bukti tc filter) -> probe QoD (N=150) -> STR -> STA -> adapter DELETE (bukti filter hilang)
# -> probe pasca-remove (N=150, >=100) dengan beban tetap jalan. Usage: str-test.sh <emu_ip>
E=${1:?emu_ip}; S=/opt/lab5g/sesi-c; D=/var/log/lab5g/str; mkdir -p $D; NS="ip netns exec ue1"; P=/var/log/lab5g/p99
UE=$($NS ip -4 -o addr show tun_srsue | awk '{print $4}' | cut -d/ -f1)
tf(){ { echo "## $1 $(date -u +%T.%3N)Z"; tc filter show dev ogstun; echo ---ifb0; tc filter show dev ifb0; } > $D/tc-$1.txt; echo "tc-$1 flowid_count=$(grep -c flowid $D/tc-$1.txt)"; }
T0=$(date -u '+%m/%d %T')
$NS iperf3 -c $E -p 8123 -R -P 4 -t 170 -J > $D/str-iperf-dl.json 2>&1 & P1=$!
$NS iperf3 -c $E -p 6000 -t 170 -J > $D/str-iperf-ul.json 2>&1 & P2=$!
sleep 8; tf 0-before-aar
python3 $S/rx-af.py --pcrf 127.0.0.9 --ue $UE --remote $E --port 9000 --hold 55 --qod-url http://127.0.0.1:8090 > $D/rx-af.log 2>&1 & RX=$!
sleep 2; tf 1-after-aar
N=150 bash $S/p99-run.sh s1-load-qod $E 0
wait $RX; tf 2-after-str
cat $D/rx-af.log
N=150 bash $S/p99-run.sh s2-load-after-str $E 0
kill -INT $P1 $P2 2>/dev/null; sleep 3
cp $P/s1-load-qod-* $P/s2-load-after-str-* $D/ 2>/dev/null
python3 $S/p99-stats.py $P s1-load-qod s2-load-after-str | tee $D/summary-str.csv
echo "== NF log STR/Delete Bearer/E-RAB Release (sejak $T0 UTC) =="
for n in pcrf smf sgwc mme; do echo "-- $n"; awk -v t="$T0" '$1" "$2 >= t' /var/log/open5gs/$n.log | grep -a -E "Rx|Gx|STR|Session-Termination|Delete Bearer|Bearer removed|Bearer added|E-RAB|Release|ERROR" | tail -12 | sed -E 's/\b00101[0-9]{10}\b/IMSI_REDACTED/g; s/IMSI\[[0-9]+\]/IMSI[redacted]/g'; done | tee $D/str-nf.log
grep -a -i -E "E-RAB|ERAB|release|bearer" /var/log/lab5g/enb.stdout /var/log/lab5g/enb.log 2>/dev/null | tail -6 | tee -a $D/str-nf.log
tail -4 /var/log/lab5g/tc/adapter.log | tee $D/adapter-tail.json
echo STR_TEST_DONE
