#!/bin/bash
# vm-core-ran (root), idempotent: L3 path for ALL emulator traffic (TCP + UDP/QUIC + ICMP) through the UE.
#   vm-emu docker0 --policy route--> GRE (gre-core 10.201.0.2) ==GRE/proto 47 (lab5g-allow-internal)==>
#   vm-core-ran gre-emu 10.201.0.1 --ip rule iif gre-emu--> veth-ueh -> netns ue1 (MASQUERADE to UE IP)
#   -> tun_srsue -> srsUE/eNB (ZMQ) -> SGW-U/UPF -> ogstun -> SGi NAT -> internet.
# vm-emu SNATs container traffic to 10.201.0.2 before GRE, so the core never sees docker 172.17/16 (core has its own).
# RCA 18 Nov 2026 11:51: YouTube app ignores the Android HTTP proxy -> googlevideo blocked (ue-only reject). This
# replaces proxy-only egress with a transparent L3 path (no app cooperation needed, QUIC/UDP games included).
# EMU_IP: env, else derived from this VM's internal DNS name (vm-core-ran.<zone>.c.<project>.internal -> vm-emu...).
set -u
N="ip netns exec ue1"; GL=10.201.0.1; GR=10.201.0.2; NET=10.201.0.0/30; VH=10.200.0.1; VU=10.200.0.2; T=201
MY_IP=$(ip -4 -o addr show ens4 | awk '{print $4}' | cut -d/ -f1)
if [ -z "${EMU_IP:-}" ]; then
  H=$(curl -fsS -m 3 -H "Metadata-Flavor: Google" http://metadata.google.internal/computeMetadata/v1/instance/hostname 2>/dev/null | sed 's/^vm-core-ran\./vm-emu./')
  EMU_IP=$(getent ahostsv4 "$H" 2>/dev/null | awk 'NR==1{print $1}')
fi
[ -n "${EMU_IP:-}" ] || { echo "EMU_IP tidak ditemukan"; exit 1; }
ip netns list | grep -q '^ue1' || { echo "netns ue1 belum ada"; exit 1; }
ip link show veth-ueh >/dev/null 2>&1 || { echo "veth-ueh belum ada (jalankan core-proxy-gui.sh dulu)"; exit 1; }
# GRE tunnel (recreate if endpoints changed)
cur=$(ip -d link show gre-emu 2>/dev/null | grep -o "remote [0-9.]*" | awk '{print $2}')
if [ "$cur" != "$EMU_IP" ]; then
  ip link del gre-emu 2>/dev/null
  ip link add gre-emu type gre local $MY_IP remote $EMU_IP ttl 64
fi
ip addr replace $GL/30 dev gre-emu; ip link set gre-emu mtu ${GRE_MTU:-1400} up
sysctl -qw net.ipv4.ip_forward=1 net.ipv4.conf.gre-emu.rp_filter=2 net.ipv4.conf.veth-ueh.rp_filter=2
# policy routing: everything arriving from gre-emu goes into the UE netns
ip rule show | grep -q "iif gre-emu lookup $T" || ip rule add iif gre-emu lookup $T priority 100
ip route replace default via $VU dev veth-ueh table $T
# host filter: allow forwarding gre-emu <-> veth-ueh
iptables -C FORWARD -i gre-emu -o veth-ueh -j ACCEPT 2>/dev/null || iptables -I FORWARD 1 -i gre-emu -o veth-ueh -j ACCEPT
iptables -C FORWARD -i veth-ueh -o gre-emu -j ACCEPT 2>/dev/null || iptables -I FORWARD 1 -i veth-ueh -o gre-emu -j ACCEPT
# MSS clamp for TCP over GRE+tun (1400 MTU)
iptables -t mangle -C FORWARD -i gre-emu -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --set-mss ${MSS_CLAMP:-1360} 2>/dev/null || \
  iptables -t mangle -A FORWARD -i gre-emu -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --set-mss ${MSS_CLAMP:-1360}
# UE netns: forward + NAT to the UE IP out of tun_srsue, return route for the GRE /30 via the veth
$N sysctl -qw net.ipv4.ip_forward=1
$N ip route replace $NET via $VH dev veth-uen
$N iptables -t nat -C POSTROUTING -s $NET -o tun_srsue -j MASQUERADE 2>/dev/null || $N iptables -t nat -A POSTROUTING -s $NET -o tun_srsue -j MASQUERADE
echo "gre-emu: $MY_IP <-> $EMU_IP ($GL/30) table $T -> ue1"
