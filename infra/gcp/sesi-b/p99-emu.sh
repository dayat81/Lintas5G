#!/bin/bash
# Run tambahan: beban bulk + trafik emulator (YouTube via UE/gost) tanpa QoD (c4) dan dengan QoD trigger manual curl (c5).
E=${1:?emu_ip}; S=/opt/lab5g/sesi-b; D=/var/log/lab5g/p99; Q=http://127.0.0.1:8090
bash $S/p99-run.sh c4-load-emu $E 1
UE=$(ip netns exec ue1 ip -4 -o addr show tun_srsue | awk '{print $4}' | cut -d/ -f1)
curl -s -X POST -H 'Content-Type: application/json' -d "{\"ueIpv4\":\"$UE\",\"remote\":\"$E\",\"port\":9000,\"source\":\"manual-curl-af\"}" $Q/qod | tee $D/c5-qod-post.json; echo
bash $S/p99-run.sh c5-load-qod-emu $E 1
curl -s -X DELETE $Q/qod/qod | tee $D/c5-qod-delete.json; echo
python3 $S/p99-stats.py $D c4-load-emu c5-load-qod-emu | tee $D/summary-emu.csv
echo P99_EMU_DONE
