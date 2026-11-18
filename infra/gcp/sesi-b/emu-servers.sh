#!/bin/bash
# vm-emu: target probe/bulk untuk tes (c): HTTP 1 KB (:9000) + 2x iperf3 server (:8123 DL, :6000 UL); port dipilih dari allow-list firewall lab (tcp 22,18080,8123,9000,6000).
apt-get install -y iperf3 sysstat >/dev/null 2>&1
mkdir -p /opt/lab5g/www && head -c 1024 /dev/urandom > /opt/lab5g/www/1k.bin
for u in lab5g-http lab5g-iperf1 lab5g-iperf2; do systemctl stop $u 2>/dev/null; systemctl reset-failed $u 2>/dev/null; done
systemd-run --unit=lab5g-http --working-directory=/opt/lab5g/www python3 -m http.server 9000 --bind 0.0.0.0
systemd-run --unit=lab5g-iperf1 iperf3 -s -p 8123
systemd-run --unit=lab5g-iperf2 iperf3 -s -p 6000
sleep 1; ss -ltn | grep -E ':9000|:8123|:6000'
