#!/bin/bash
D=/workspace/booster-qod-test; cd $D
other() { sudo docker ps --format '{{.Names}}' | grep -E '^(n5-gnb|oai-gnb|qa-gnb)$' | tr '\n' ' '; }
run() { TAG=$1; echo "$(date +%T) other_before='$(other)'" > res/$TAG.coexist; DELAFTER=28 ./run_m.sh $TAG $2 $3 70 > res/$TAG.run 2>&1; echo "$(date +%T) other_after='$(other)'" >> res/$TAG.coexist; }
./run-ue.sh 1; EXTRA="" ALLOW="" run m3 1 c
./run-ue.sh 2; EXTRA="10.45.0.3:9000" ALLOW="10.45.0.3:9000" run m4 2 c
echo BATCH5_DONE
