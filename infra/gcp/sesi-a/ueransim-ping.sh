#!/bin/bash
# Bukti N3/N6: ping UE -> UPF gw & 8.8.8.8, pcap ogstun.
N="ip netns exec ue1"
timeout 30 tcpdump -ni ogstun -c 6 icmp and host 8.8.8.8 > /var/log/lab5g/tcpdump-ogstun-ping.txt 2>&1 &
echo "== ping UE -> 10.45.0.1 (100) =="; $N ping -c 100 -i 0.2 -q 10.45.0.1 | tail -2
echo "== ping UE -> 8.8.8.8 via UPF/N6 (100) =="; $N ping -c 100 -i 0.2 -q 8.8.8.8 | tail -2
echo "== host ping 8.8.8.8 langsung (100) =="; ping -c 100 -i 0.2 -q 8.8.8.8 | tail -2
wait; cat /var/log/lab5g/tcpdump-ogstun-ping.txt
