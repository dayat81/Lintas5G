#!/bin/bash
# Sesi C: tes (c) 3 ulangan x {idle, beban, beban+QoD(Rx AAR -> adapter, STR -> remove)}, N=330 sampel/kondisi.
# Usage: p99-reps.sh <emu_ip> ["1 2 3"]
# Health check sebelum tiap ulangan: link ZMQ srsRAN kadang jatuh ke loop Radio-Link-Failure ("[zmq] tx time is in the past",
# RTT puluhan detik). Bila ping idle gagal/avg >150 ms -> attach ulang (core-run.sh), dicatat di log.
E=${1:?emu_ip}; RL=${2:-"1 2 3"}; S=/opt/lab5g/sesi-c; D=/var/log/lab5g/p99; mkdir -p $D
health(){ local o a; o=$(ip netns exec ue1 ping -c 10 -i 0.2 -W 1 $E 2>&1 | tail -2); a=$(echo "$o" | awk -F/ '/rtt/{print int($5)}')
  if ! echo "$o" | grep -q " 0% packet loss" || [ -z "$a" ] || [ "$a" -gt 150 ]; then
    echo "HEALTH_FAIL $(date -u +%T)Z: $o -> re-attach"; bash $S/core-run.sh > $D/reattach-$(date +%s).log 2>&1; sleep 5
    ip netns exec ue1 ping -c 10 -i 0.2 -W 1 $E | tail -1; else echo "HEALTH_OK avg=${a}ms"; fi; }
for r in $RL; do
  echo "##### REP $r $(date -u +%T)Z"; health
  bash $S/p99-run.sh c1-idle-r$r $E 0
  bash $S/p99-run.sh c2-load-r$r $E 1
  sleep 5
  { tc filter show dev ogstun; echo ---ifb0; tc filter show dev ifb0; } > $D/c3-r$r-tcfilter-0-pre.txt
  bash $S/rx-test.sh $E 100 http://127.0.0.1:8090 > $D/c3-r$r-rx.log 2>&1 & RX=$!
  sleep 2
  { tc filter show dev ogstun; echo ---ifb0; tc filter show dev ifb0; } > $D/c3-r$r-tcfilter-1-qod.txt
  bash $S/p99-run.sh c3-load-qod-r$r $E 1
  tc -s class show dev ogstun > $D/c3-r$r-tc-ogstun.txt; tc -s class show dev ifb0 > $D/c3-r$r-tc-ifb0.txt
  wait $RX
  { tc filter show dev ogstun; echo ---ifb0; tc filter show dev ifb0; } > $D/c3-r$r-tcfilter-2-post-str.txt
  grep -E "AAA|STA|qod-adapter|answered|Error|Trace" $D/c3-r$r-rx.log
  echo "filters: pre=$(grep -c flowid $D/c3-r$r-tcfilter-0-pre.txt) qod=$(grep -c flowid $D/c3-r$r-tcfilter-1-qod.txt) post=$(grep -c flowid $D/c3-r$r-tcfilter-2-post-str.txt)"
done
L=""; for r in 1 2 3; do L="$L c1-idle-r$r c2-load-r$r c3-load-qod-r$r"; done
python3 $S/p99-stats.py $D $L | tee $D/summary-reps.csv
echo P99_REPS_DONE
