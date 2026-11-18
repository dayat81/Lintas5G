#!/bin/bash
# Fix Sesi C #2: hentikan runner, simpan data rep 2 invalid (link ZMQ RLF), attach ulang, jalankan run-tests2.sh.
L=/var/log/lab5g
systemctl stop lab5g-run 2>/dev/null; pkill -x iperf3; pkill -f "ping -i 0[.]2"; sleep 1
mkdir -p $L/p99-invalid-try2 && mv $L/p99/c1-idle-r2* $L/p99-invalid-try2/ 2>/dev/null; cp $L/sesi-c-run.log $L/p99-invalid-try2/run1.log
tail -40 $L/ue.stdout > $L/p99-invalid-try2/ue-stdout-tail.txt; tail -40 $L/enb.stdout > $L/p99-invalid-try2/enb-stdout-tail.txt
bash /opt/lab5g/sesi-c/core-run.sh 2>&1 | grep -E "Attach complete|tun_srsue" | tail -2
sleep 3; ip netns exec ue1 ping -c 10 -i 0.2 10.10.0.3 | tail -2
systemctl reset-failed lab5g-run 2>/dev/null
systemd-run --unit=lab5g-run -p StandardOutput=file:$L/sesi-c-run2.log -p StandardError=file:$L/sesi-c-run2.log bash /opt/lab5g/sesi-c/run-tests2.sh 10.10.0.3
