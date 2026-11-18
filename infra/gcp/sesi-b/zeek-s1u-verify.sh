#!/bin/bash
# Verifikasi capture_loss Zeek di lo dengan BPF S1-U saja (hop eNB<->SGW-U), tanpa IQ ZMQ (tcp 2000/2001) dan tanpa hop S5-U.
# Dugaan: capture_loss lo 53-65% = artefak (inner TCP terlihat di 2 tunnel GTP -> tunnel_max_changes_per_connection_exceeded), bukan drop (pkts_dropped=0).
E=${1:?emu_ip}; L=/var/log/lab5g/zeek/lo-s1u; mkdir -p $L; cd $L
CPU=$(( $(nproc) - 1 ))
timeout 140 taskset -c $CPU nice -n 10 /opt/zeek/bin/zeek -C -i lo -f "udp port 2152 and host 127.0.1.1" local policy/misc/capture-loss policy/misc/stats "CaptureLoss::watch_interval=1min" &
sleep 8; ip netns exec ue1 iperf3 -c $E -p 8123 -R -P 4 -t 120 > /dev/null 2>&1; wait
grep -v '^#' capture_loss.log; grep -v '^#' stats.log | awk -F'\t' '{print $1,$4,$7}'
cut -f7 weird.log 2>/dev/null | grep -v '^#' | sort | uniq -c | sort -rn | head -3
