#!/bin/bash
# Sesi VNC: bring-up core seperti Sesi C (../sesi-c/core-bringup.sh) TANPA Zeek (sesi GUI saja). Jalankan di vm-core-ran sebagai root.
# Sesi C: urutan bring-up core (resep Sesi B): config EPC + subscriber acak -> rb.conf QCI 2 -> eNB/UE ZMQ + keepalive
# (peer Rx AF sebelum attach) -> tc HTB (DL 15 / UL 8 Mbit/s) + adapter QoD -> Zeek paralel (BPF valid) -> proxy gost (emulator via UE).
S=/opt/lab5g/sesi-c; L=/var/log/lab5g
bash $S/core-config.sh 2>&1 | grep -v -i -E "key|opc" | tail -8
bash $S/enb-qci2.sh
# rx-setup.sh me-restart PCRF -> WAJIB sebelum attach UE (kalau sesudah, sesi Gx hilang dan AAR dijawab 5065).
bash $S/rx-setup.sh
bash $S/core-run.sh 2>&1 | tail -25
python3 $S/qod-tc.py setup --dl 15mbit --ul 8mbit --depth 300
systemctl stop lab5g-qod 2>/dev/null; systemctl reset-failed lab5g-qod 2>/dev/null
systemd-run --unit=lab5g-qod python3 $S/qod-tc.py serve --listen 127.0.0.1:8090 --dl 15mbit --ul 8mbit
bash $S/core-proxy.sh 2>&1 | tail -5
sleep 2; ip netns exec ue1 ping -c 5 -i 0.2 10.10.0.3 | tail -2
tail -2 $L/keepalive.log
echo BRINGUP_DONE
