#!/bin/bash
# vm-emu (Sesi C): HTTP 1 KB (:9000) + iperf3 server (:8123 DL bulk, :6000 UL bulk, :18080 flow GBR TCP) + udp-flow (:4789 flow GBR UDP).
# Port dari allow-list firewall lab (tcp 22,18080,8123,9000,6000; udp 4789).
apt-get install -y iperf3 sysstat >/dev/null 2>&1
mkdir -p /opt/lab5g/www && head -c 1024 /dev/urandom > /opt/lab5g/www/1k.bin
for u in lab5g-http lab5g-iperf1 lab5g-iperf2 lab5g-iperf3 lab5g-udpflow; do systemctl stop $u 2>/dev/null; systemctl reset-failed $u 2>/dev/null; done
systemd-run --unit=lab5g-http --working-directory=/opt/lab5g/www python3 -m http.server 9000 --bind 0.0.0.0
systemd-run --unit=lab5g-iperf1 iperf3 -s -p 8123
systemd-run --unit=lab5g-iperf2 iperf3 -s -p 6000
systemd-run --unit=lab5g-iperf3 iperf3 -s -p 18080
systemd-run --unit=lab5g-udpflow python3 /opt/lab5g/sesi-c/udp-flow.py server --port 4789
sleep 1; ss -ltnu | grep -E ':9000|:8123|:6000|:18080|:4789'
