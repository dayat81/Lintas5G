#!/bin/bash
# Fix Sesi C: rx-setup.sh me-restart PCRF SETELAH attach -> sesi Gx hilang -> AAR dijawab 5065 (IP-CAN session not available).
# Hentikan runner, pindahkan data rep invalid, attach ulang UE (sesi Gx baru), uji AAR singkat.
L=/var/log/lab5g
systemctl stop lab5g-run 2>/dev/null
pkill -x iperf3; pkill -f rx-af[.]py; pkill -f "ping -i 0[.]2"; sleep 2
curl -s -X DELETE http://127.0.0.1:8090/qod/qod; echo
mkdir -p $L/p99-invalid-try1 && mv $L/p99/* $L/p99-invalid-try1/ 2>/dev/null; cp $L/sesi-c-run.log $L/p99-invalid-try1/
bash /opt/lab5g/sesi-c/core-run.sh 2>&1 | grep -E "Attach complete|tun_srsue" | tail -3
sleep 3; ip netns exec ue1 ping -c3 -i 0.3 10.10.0.3 | tail -1
UE=$(ip netns exec ue1 ip -4 -o addr show tun_srsue | awk '{print $4}' | cut -d/ -f1); echo UE=$UE
python3 /opt/lab5g/sesi-c/rx-af.py --pcrf 127.0.0.9 --ue $UE --remote 10.10.0.3 --port 9000 --hold 3
