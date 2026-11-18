#!/bin/bash
N="ip netns exec ue1"
$N ip route replace default via 10.45.0.1 dev tun_srsue
$N ip route
systemctl stop lab5g-keepalive 2>/dev/null; systemctl reset-failed lab5g-keepalive 2>/dev/null
systemd-run --unit=lab5g-keepalive bash -c "ip netns exec ue1 ping -i 1 -D 10.45.0.1 > /var/log/lab5g/keepalive.log 2>&1"
echo "== tcpdump ogstun (bukti trafik UE -> 8.8.8.8 lewat UPF/SGi) =="
timeout 25 tcpdump -ni ogstun -c 6 icmp and host 8.8.8.8 > /var/log/lab5g/tcpdump-ogstun-ping.txt 2>&1 &
echo "== ping UE -> UPF/SGi gw 10.45.0.1 (100) =="; $N ping -c 100 -i 0.2 -q 10.45.0.1 | tail -2
echo "== ping UE -> 8.8.8.8 via SGi+Cloud NAT (100) =="; $N ping -c 100 -i 0.2 -q 8.8.8.8 | tail -2
echo "== host ping 8.8.8.8 direct Cloud NAT (100) =="; ping -c 100 -i 0.2 -q 8.8.8.8 | tail -2
wait; cat /var/log/lab5g/tcpdump-ogstun-ping.txt
echo "== DNS+curl dari netns UE =="; $N curl -s -o /dev/null -w "ue-path connect=%{time_connect} ttfb=%{time_starttransfer} code=%{http_code}\n" http://example.com/
