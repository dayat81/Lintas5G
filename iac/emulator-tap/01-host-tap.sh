#!/bin/bash
# vm-emu (root). TAP host side. Android emulator static eth0 = 10.0.2.15/24, gw 10.0.2.2, dns 10.0.2.3 -> host owns .2 and .3 on tap0.
# NEVER run `sysctl --system` here (it reset net.ipv4.ip_forward to 0 and killed docker NAT). Use sysctl -w only.
set -e
export DEBIAN_FRONTEND=noninteractive
IF=$(ip -o -4 route show default | awk '{print $5}' | head -1)   # ens4, MTU 1460
command -v dnsmasq >/dev/null || { apt-get update -q >/dev/null; apt-get install -y -q dnsmasq-base >/dev/null; }
ip link show tap0 >/dev/null 2>&1 || ip tuntap add dev tap0 mode tap user 1300 group 1301   # 1300 = androidusr in the emulator image
ip addr flush dev tap0; ip addr add 10.0.2.2/24 dev tap0; ip addr add 10.0.2.3/24 dev tap0; ip link set tap0 mtu 1460 up
sysctl -w net.ipv4.ip_forward=1 >/dev/null
iptables -t nat -C POSTROUTING -s 10.0.2.0/24 -o $IF -j MASQUERADE 2>/dev/null || iptables -t nat -A POSTROUTING -s 10.0.2.0/24 -o $IF -j MASQUERADE
iptables -C DOCKER-USER -i tap0 -j ACCEPT 2>/dev/null || iptables -I DOCKER-USER -i tap0 -j ACCEPT
iptables -C DOCKER-USER -o tap0 -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT 2>/dev/null || iptables -I DOCKER-USER -o tap0 -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
iptables -C FORWARD -i tap0 -j ACCEPT 2>/dev/null || iptables -I FORWARD -i tap0 -j ACCEPT
iptables -C FORWARD -o tap0 -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT 2>/dev/null || iptables -I FORWARD -o tap0 -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
iptables -t mangle -C FORWARD -i tap0 -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu 2>/dev/null || iptables -t mangle -A FORWARD -i tap0 -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu
# container uses --network host: keep VNC/noVNC/adb/console off every non-loopback interface
iptables -C INPUT -p tcp -m multiport --dports 5900,6080,5555,5554,9000 ! -i lo -j DROP 2>/dev/null || iptables -I INPUT -p tcp -m multiport --dports 5900,6080,5555,5554,9000 ! -i lo -j DROP
# DNS only (guest DNS = 10.0.2.3); no DHCP needed
pkill -f 'dnsmasq.*tap0' 2>/dev/null || true
dnsmasq --interface=tap0 --bind-interfaces --except-interface=lo --listen-address=10.0.2.3 --no-dhcp-interface=tap0 --server=8.8.8.8 --server=1.1.1.1 --no-resolv --no-hosts --pid-file=/run/dnsmasq-tap0.pid --log-facility=/var/log/dnsmasq-tap0.log
ip -br a show tap0; sysctl -n net.ipv4.ip_forward
