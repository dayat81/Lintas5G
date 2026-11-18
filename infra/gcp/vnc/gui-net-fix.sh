#!/bin/bash
# Idempotent: MTU/MSS fix for the GUI session (run after every attach, and by the watchdog every tick).
# Evidence (RCA 18 Nov 2026): ogstun MTU 1400, tun_srsue MTU 1500, no TCPMSS clamp anywhere.
# gost (in netns ue1) advertised MSS 1460 -> downlink segments >1400 B hit ogstun (MTU 1400) and depend on
# ICMP frag-needed reaching the remote server (PMTUD blackhole risk -> stalled page loads/downloads).
N="ip netns exec ue1"; MTU=${UE_MTU:-1400}; MSS=${MSS_CLAMP:-1360}
$N ip link show tun_srsue >/dev/null 2>&1 && $N ip link set tun_srsue mtu $MTU
# clamp in the UE netns (covers gost + anything else originating from the UE)
$N iptables -t mangle -C POSTROUTING -o tun_srsue -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --set-mss $MSS 2>/dev/null || \
  $N iptables -t mangle -A POSTROUTING -o tun_srsue -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --set-mss $MSS
# clamp on the host for SGi traffic in both directions through ogstun
for d in "-i ogstun" "-o ogstun"; do
  iptables -t mangle -C FORWARD $d -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --set-mss $MSS 2>/dev/null || \
    iptables -t mangle -A FORWARD $d -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --set-mss $MSS
done
exit 0
