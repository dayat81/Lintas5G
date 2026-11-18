#!/bin/bash
# Proxy HTTP CONNECT di netns UE (src = IP UE, keluar tun_srsue -> eNB -> SGW-U -> UPF -> SGi).
# GUI-session variant of ../sesi-c/core-proxy.sh (Sesi C stays frozen as the Fase 0 evidence).
# Changes: LimitNOFILE=65536 on gost, second DNS resolver (1.1.1.1) + timeout, MSS clamp ON by default (1360).
set -euo pipefail
NS=ue1
HOST_IP=${HOST_IP:-$(ip -4 -o addr show ens4 | awk '{print $4}' | cut -d/ -f1)}  # auto: IP vm-core-ran (bisa .2/.3 tergantung urutan create)
PORT=${PORT:-18080}                # port yang dipakai emulator
VH=10.200.0.1; VU=10.200.0.2       # veth /30 host<->netns UE
GOST_VER=${GOST_VER:-3.0.0}
N="ip netns exec $NS"
mkdir -p /var/log/lab5g

# 1. gost binary
if ! command -v gost >/dev/null; then
  curl -fsSL -o /tmp/gost.tgz "https://github.com/go-gost/gost/releases/download/v${GOST_VER}/gost_${GOST_VER}_linux_amd64.tar.gz"
  tar -xzf /tmp/gost.tgz -C /usr/local/bin gost && chmod +x /usr/local/bin/gost
fi

# 2. veth host <-> netns UE (idempoten)
$N ip link set lo up
if ! ip link show veth-ueh >/dev/null 2>&1; then
  ip link add veth-ueh type veth peer name veth-uen
  ip link set veth-uen netns $NS
  ip addr add $VH/30 dev veth-ueh; ip link set veth-ueh up
  $N ip addr add $VU/30 dev veth-uen; $N ip link set veth-uen up
fi
# default route netns UE tetap via tun_srsue; 10.200.0.0/30 connected via veth.

# 3a. config gost: resolver dengan cache (TTL) -> hindari 1 query DNS lewat UE (~40-60 ms) per request
cat > /etc/lab5g-gost-ue.yaml <<Y
services:
- name: http-ue
  addr: $VU:8080
  resolver: dns-ue
  handler:
    type: http
  listener:
    type: tcp
resolvers:
- name: dns-ue
  nameservers:
  - addr: udp://8.8.8.8:53
    timeout: 2s
    prefer: ipv4
    ttl: ${DNS_TTL:-300s}
  - addr: udp://1.1.1.1:53
    prefer: ipv4
    timeout: 2s
    ttl: ${DNS_TTL:-300s}
Y
# 3. gost di netns UE (listen di veth, egress via default route = tun_srsue)
for u in lab5g-gost-ue lab5g-tinyproxy-ue lab5g-socat-ue; do systemctl stop $u 2>/dev/null || true; systemctl reset-failed $u 2>/dev/null || true; done
# rp_filter longgar di veth (reply simetris lewat SNAT, tapi aman bila policy route berubah)
sysctl -qw net.ipv4.conf.veth-ueh.rp_filter=2
$N sysctl -qw net.ipv4.conf.veth-uen.rp_filter=2 || true
$N sysctl -qw net.ipv4.conf.all.rp_filter=2 || true
systemd-run --unit=lab5g-gost-ue -p LimitNOFILE=65536 -p Restart=always -p StandardOutput=append:/var/log/lab5g/gost-ue.log -p StandardError=append:/var/log/lab5g/gost-ue.log \
  ip netns exec $NS /usr/local/bin/gost -C /etc/lab5g-gost-ue.yaml

# 4. DNAT HOST_IP:PORT -> VU:8080 (hanya dari subnet lab), plus SNAT supaya reply kembali lewat veth
sysctl -qw net.ipv4.ip_forward=1
iptables -t nat -C PREROUTING -d $HOST_IP -p tcp --dport $PORT -j DNAT --to-destination $VU:8080 2>/dev/null || \
  iptables -t nat -A PREROUTING -d $HOST_IP -p tcp --dport $PORT -j DNAT --to-destination $VU:8080
iptables -t nat -C POSTROUTING -o veth-ueh -d $VU -j SNAT --to-source $VH 2>/dev/null || \
  iptables -t nat -A POSTROUTING -o veth-ueh -d $VU -j SNAT --to-source $VH
iptables -C FORWARD -o veth-ueh -d $VU -p tcp --dport 8080 -j ACCEPT 2>/dev/null || iptables -I FORWARD -o veth-ueh -d $VU -p tcp --dport 8080 -j ACCEPT
iptables -C FORWARD -i veth-ueh -s $VU -j ACCEPT 2>/dev/null || iptables -I FORWARD -i veth-ueh -s $VU -j ACCEPT

for i in $(seq 1 20); do $N ss -ltn | grep -q "$VU:8080" && break; sleep 0.5; done
$N ss -ltnp | grep 8080 || true
echo "== self-test dari netns UE langsung =="; $N curl -s -o /dev/null -x http://$VU:8080 -w "code=%{http_code} ttfb=%{time_starttransfer}\n" http://example.com/ || true
echo "== catatan: tes dari vm-emu (bukan host sendiri, karena DNAT PREROUTING) =="
echo "curl -x http://$HOST_IP:$PORT -w '%{time_starttransfer}\n' -o /dev/null -s http://example.com/"

# opsional: MSS clamp di tun_srsue (MSS=1360) -> MSS_CLAMP=1360 bash core-proxy.sh
MSS_CLAMP=${MSS_CLAMP:-1360}
if [ -n "${MSS_CLAMP:-}" ] && [ "$MSS_CLAMP" != 0 ]; then
  $N iptables -t mangle -C POSTROUTING -o tun_srsue -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --set-mss $MSS_CLAMP 2>/dev/null || \
    $N iptables -t mangle -A POSTROUTING -o tun_srsue -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --set-mss $MSS_CLAMP
  echo "MSS clamp $MSS_CLAMP di netns $NS tun_srsue"
fi
