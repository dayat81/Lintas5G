#!/bin/bash
# Proxy HTTP CONNECT di netns UE (src = IP UE, keluar tun_srsue -> eNB -> SGW-U -> UPF -> SGi).
apt-get install -y tinyproxy-bin  # fallback only
# Host hanya meneruskan TCP 10.10.0.2:18080 -> netns ue1 127.0.0.1:8888 (socat), tidak memproksi sendiri.
N="ip netns exec ue1"
$N ip link set lo up
cat > /etc/lab5g-tinyproxy-ue.conf <<C
Port 8888
Listen 127.0.0.1
Timeout 600
MaxClients 100
Allow 127.0.0.1
ConnectPort 443
ConnectPort 80
LogFile "/var/log/lab5g/tinyproxy-ue.log"
LogLevel Connect
ViaProxyName "lab5g-ue-path"
C
systemctl stop tinyproxy 2>/dev/null; systemctl disable tinyproxy 2>/dev/null
for u in lab5g-tinyproxy-ue lab5g-socat-ue; do systemctl stop $u 2>/dev/null; systemctl reset-failed $u 2>/dev/null; done
touch /var/log/lab5g/tinyproxy-ue.log; chmod 666 /var/log/lab5g/tinyproxy-ue.log
systemd-run --unit=lab5g-tinyproxy-ue ip netns exec ue1 tinyproxy -d -c /etc/lab5g-tinyproxy-ue.conf
sleep 1
systemd-run --unit=lab5g-socat-ue socat TCP-LISTEN:18080,bind=10.10.0.2,fork,reuseaddr EXEC:"ip netns exec ue1 socat STDIO TCP\:127.0.0.1\:8888"
sleep 1; ss -ltnp | grep 18080; $N ss -ltnp | grep 8888
echo "== self-test dari host via proxy =="; curl -s -o /dev/null -x http://10.10.0.2:18080 -w "code=%{http_code}\n" http://example.com/
