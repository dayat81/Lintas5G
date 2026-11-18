#!/bin/bash
# Tes (c): (i) idle, (ii) beban bulk tanpa QoD, (iii) beban bulk + QoD (trigger Rx AAA -> adapter tc HTB). Bottleneck tc HTB DL 15 / UL 8 Mbit/s di ogstun.
E=${1:?emu_ip}; S=/opt/lab5g/sesi-b; D=/var/log/lab5g/p99; mkdir -p $D
rm -f $D/c*-*
bash $S/p99-run.sh c1-idle $E 0
bash $S/p99-run.sh c2-load $E 1
sleep 5
bash $S/rx-test.sh $E 170 http://127.0.0.1:8090 > $D/c3-rx.log 2>&1 &
sleep 3; grep -E "AAA|qod-adapter" $D/c3-rx.log
bash $S/p99-run.sh c3-load-qod $E 1
tc -s class show dev ogstun > $D/c3-tc-ogstun.txt; tc -s class show dev ifb0 > $D/c3-tc-ifb0.txt
wait
python3 $S/p99-stats.py $D c1-idle c2-load c3-load-qod | tee $D/summary.csv
echo P99_ALL_DONE
