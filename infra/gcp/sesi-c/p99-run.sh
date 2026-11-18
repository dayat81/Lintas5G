#!/bin/bash
# Tes (c) p99 satu kondisi. Usage: p99-run.sh <label> <emu_ip> <load:0|1> [N=330]
# Probe interaktif dari netns UE: ping ICMP (-i 0.2) + HTTP/TCP TTFB (3 worker paralel, objek 1 KB di emu:9000).
# Beban bulk (load=1): iperf3 TCP DL 4 stream (-R, emu:8123) + TCP UL 1 stream (emu:6000), dari netns UE.
L=$1; E=$2; LOAD=$3; N=${N:-330}; D=/var/log/lab5g/p99; mkdir -p $D; NS="ip netns exec ue1"
echo "== $L start $(date +%T) load=$LOAD"
if [ "$LOAD" = 1 ]; then
  $NS iperf3 -c $E -p 8123 -R -P 4 -t 150 -J > $D/$L-iperf-dl.json 2>&1 & P1=$!
  $NS iperf3 -c $E -p 6000 -t 150 -J > $D/$L-iperf-ul.json 2>&1 & P2=$!
  sleep 8
fi
mpstat 5 > $D/$L-mpstat.txt & PM=$!
$NS ping -i 0.2 -c $N -W 3 $E > $D/$L-ping.txt 2>&1 & PP=$!
PW=""; W=3; per=$(( (N + W - 1) / W ))
for w in $(seq 1 $W); do
  ( for i in $(seq 1 $per); do echo "$L,$w,$i,$($NS curl -s -m 10 -o /dev/null -w '%{time_connect},%{time_starttransfer},%{time_total},%{http_code}' http://$E:9000/1k.bin)"; sleep 0.1; done ) > $D/$L-http-$w.csv & PW="$PW $!"
done
wait $PP $PW
cat $D/$L-http-*.csv > $D/$L-http.csv
kill $PM 2>/dev/null
if [ "$LOAD" = 1 ]; then kill -INT $P1 $P2 2>/dev/null; sleep 3; fi
tail -2 $D/$L-ping.txt; wc -l $D/$L-http.csv
echo "== $L end $(date +%T)"
