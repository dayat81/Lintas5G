#!/bin/bash
# Sesi C runner #3 (setelah RLF pasca-STR): attach ulang -> DELETE REST -> GBR (health check sebelum GBR).
E=${1:?emu_ip}; S=/opt/lab5g/sesi-c; NS="ip netns exec ue1"
echo "RUN3_START $(date -u +%FT%TZ)"
bash $S/core-run.sh > /var/log/lab5g/reattach-run3.log 2>&1; sleep 5
bash $S/str-rest-test.sh $E
o=$($NS ping -c 10 -i 0.2 -W 1 $E | tail -2); echo "$o"
echo "$o" | grep -q " 0% packet loss" || { echo HEALTH_FAIL_REATTACH; bash $S/core-run.sh > /var/log/lab5g/reattach-run3b.log 2>&1; sleep 5; }
bash $S/gbr-test.sh $E
echo "RUN_END $(date -u +%FT%TZ)"
