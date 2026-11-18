#!/bin/bash
B=/opt/lab5g/srsran/srsRAN_4G/build; C=/opt/lab5g/srsran/conf; L=/var/log/lab5g
systemctl stop lab5g-enb lab5g-ue lab5g-mpstat 2>/dev/null; systemctl reset-failed 2>/dev/null
systemd-run --unit=lab5g-mpstat bash -c "mpstat 5 > $L/mpstat.log"
systemd-run --unit=lab5g-enb --working-directory=$L bash -c "$B/srsenb/src/srsenb $C/enb.conf > $L/enb.stdout 2>&1"
sleep 5
systemd-run --unit=lab5g-ue --working-directory=$L bash -c "$B/srsue/src/srsue $C/ue.conf > $L/ue.stdout 2>&1"
for i in $(seq 1 30); do ip netns exec ue1 ip -4 -br a show tun_srsue 2>/dev/null | grep -q 10.45 && break; sleep 2; done
echo "== enb.stdout =="; tail -20 $L/enb.stdout
echo "== ue.stdout =="; tail -20 $L/ue.stdout
echo "== UE IP =="; ip netns exec ue1 ip -4 -br a
echo "== MME log =="; grep -E "S1-Setup|Attach|InitialContext|Session|IMSI" /var/log/open5gs/mme.log | tail -15 | sed -E 's/IMSI\[[0-9]+\]/IMSI[redacted]/g'
echo "== SMF/UPF =="; tail -5 /var/log/open5gs/smf.log; tail -5 /var/log/open5gs/upf.log
