#!/bin/bash
# Diagnosa onset RLF: hentikan runner, cari detik pertama RTT keepalive > 1 s, bandingkan dengan waktu STR/remove dan Delete Bearer.
L=/var/log/lab5g; mkdir -p $L/str-invalid
systemctl stop lab5g-run 2>/dev/null; pkill -x iperf3; pkill -f "ping -i 0[.]2"; sleep 1
awk '{t=$1; gsub(/[\[\]]/,"",t); if (match($0,/time=[0-9.]+/)) {v=substr($0,RSTART+5,RLENGTH-5)+0; if (v>1000 && !s[int(t/60)]++) printf "%s rtt=%s ms seq=%s\n", strftime("%H:%M:%S",t,1), v, $6}}' $L/keepalive.log | head -12
echo "-- RTT besar dikelompokkan berdasarkan waktu kirim (ts - rtt):"
awk '{t=$1; gsub(/[\[\]]/,"",t); if (match($0,/time=[0-9.]+/)) {v=substr($0,RSTART+5,RLENGTH-5)/1000; if (v>1) {snd=t-v; if (!p[int(snd/30)]++) printf "sent~%s rtt=%.1fs\n", strftime("%H:%M:%S",snd,1), v}}}' $L/keepalive.log | head -12
grep -a -E "remove|apply" $L/tc/adapter.log | tail -4
grep -a -E "03:0[0-9]" /var/log/open5gs/mme.log | grep -a -E "Bearer|Release|E-RAB|Context" | sed -E "s/\b00101[0-9]{10}\b/IMSI_REDACTED/g; s/IMSI\[[0-9]+\]/IMSI[r]/g" | tail -10
grep -a -c "Radio-Link" $L/ue.stdout
cp $L/sesi-c-run2.log $L/str-invalid/; tail -40 $L/ue.stdout > $L/str-invalid/ue-stdout-tail.txt
