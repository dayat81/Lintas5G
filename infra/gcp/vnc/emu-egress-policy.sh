#!/bin/bash
# vm-emu (root), idempotent: egress policy for the emulator container (traffic entering from docker bridges).
#
# EMU_EGRESS=ue-l3 (default): ALL emulator traffic (TCP, UDP incl. QUIC/game UDP, ICMP) is policy-routed into a GRE
#   tunnel to vm-core-ran, which hands it to the UE netns (see core-gre-emu.sh) -> tun_srsue -> EPC -> SGi.
#   No app cooperation needed (fixes: YouTube app/ExoPlayer ignores the Android HTTP proxy -> video blocked).
#   Fail-closed: if the GRE path is down, emulator traffic is REJECTed (tcp-reset / icmp-port-unreachable), never NATed
#   directly. Exceptions kept direct: lab subnet 10.10.0.0/16, metadata DNS 169.254.169.254, docker-internal 172.16/12.
# EMU_EGRESS=ue-proxy: previous behaviour: only the Android HTTP proxy (gost core:18080) works, any direct traffic is
#   rejected (apps that ignore the proxy, e.g. the YouTube app, FAIL - documented RCA 18 Nov 2026 11:51).
# EMU_EGRESS=quic-block: only UDP/443 rejected. EMU_EGRESS=off: remove the policy (direct Cloud NAT, NOT via UE).
# CORE_IP: internal IP of vm-core-ran (GRE remote). Required for ue-l3.
set -u
MODE=${EMU_EGRESS:-ue-l3}; C=LAB5G-EMU; T=201; GL=10.201.0.2; GR=10.201.0.1
MY_IP=$(ip -4 -o addr show ens4 | awk '{print $4}' | cut -d/ -f1)
# Filter chain is rebuilt ATOMICALLY (iptables-restore --noflush: chain declared + rules committed in one transaction),
# so a re-apply never leaves an empty chain (= brief direct-egress leak).
RULES=()
iptables -N $C 2>/dev/null || true
iptables -C DOCKER-USER -j $C 2>/dev/null || iptables -I DOCKER-USER 1 -j $C
commit(){ { echo "*filter"; echo ":$C - [0:0]"; for r in "${RULES[@]}"; do echo "-A $C $r"; done; echo COMMIT; } | iptables-restore --noflush; }
gre_up(){
  CORE_IP=${CORE_IP:?CORE_IP wajib untuk ue-l3}
  cur=$(ip -d link show gre-core 2>/dev/null | grep -o "remote [0-9.]*" | awk '{print $2}')
  if [ "$cur" != "$CORE_IP" ]; then ip link del gre-core 2>/dev/null; ip link add gre-core type gre local $MY_IP remote $CORE_IP ttl 64; fi
  ip addr replace $GL/30 dev gre-core; ip link set gre-core mtu ${GRE_MTU:-1400} up
  sysctl -qw net.ipv4.ip_forward=1 net.ipv4.conf.gre-core.rp_filter=2
  # policy routing: container traffic (docker0) -> table 201; exceptions stay in main
  for pr in "100 10.10.0.0/16" "101 169.254.169.254/32" "102 172.16.0.0/12"; do
    set -- $pr; ip rule show | grep -q "^$1:" || ip rule add priority $1 to $2 lookup main
  done
  ip rule show | grep -q "^110:" || ip rule add priority 110 iif docker0 lookup $T
  ip route replace default via $GR dev gre-core table $T
  # if the GRE route disappears (link flap), table 201 still never falls through to the direct path
  ip route replace unreachable default metric 4096 table $T
}
# ROUTES_ONLY=1: periodic self-heal (lab5g-emu-gre.timer), touches only link/rules/routes, never the filter.
if [ "${ROUTES_ONLY:-0}" = 1 ]; then [ "$MODE" = ue-l3 ] && gre_up; exit 0; fi
l3_off(){
  systemctl disable --now lab5g-emu-gre.timer >/dev/null 2>&1 || true
  for pr in 100 101 102 110; do ip rule del priority $pr 2>/dev/null; done
  ip route flush table $T 2>/dev/null
  iptables -t nat -D POSTROUTING -o gre-core -j MASQUERADE 2>/dev/null
  ip link del gre-core 2>/dev/null
}
base_filter(){
  RULES+=("-m conntrack --ctstate ESTABLISHED,RELATED -j RETURN" "! -i docker+ -j RETURN" "-d 10.10.0.0/16 -j RETURN"
          "-d 169.254.169.254/32 -j RETURN" "-d 172.16.0.0/12 -j RETURN")
}
reject_rest(){ RULES+=("-p tcp -j REJECT --reject-with tcp-reset" "-j REJECT --reject-with icmp-port-unreachable"); }
case "$MODE" in
  ue-l3)
    gre_up
    # SNAT container traffic to the GRE address (core never sees docker 172.17/16)
    iptables -t nat -C POSTROUTING -o gre-core -j MASQUERADE 2>/dev/null || iptables -t nat -I POSTROUTING 1 -o gre-core -j MASQUERADE
    iptables -t mangle -C FORWARD -o gre-core -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --set-mss ${MSS_CLAMP:-1360} 2>/dev/null || \
      iptables -t mangle -A FORWARD -o gre-core -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --set-mss ${MSS_CLAMP:-1360}
    base_filter
    RULES+=("-i docker+ -o gre-core -j RETURN")      # the only way out to the internet: via the UE
    reject_rest; commit ;;
  ue-proxy)
    l3_off; base_filter; reject_rest; commit ;;
  quic-block)
    l3_off; RULES+=("-i docker+ -p udp --dport 443 -j REJECT --reject-with icmp-port-unreachable"); commit ;;
  off)
    l3_off; iptables -D DOCKER-USER -j $C 2>/dev/null; iptables -F $C; iptables -X $C ;;
  *) echo "EMU_EGRESS tidak dikenal: $MODE"; exit 1 ;;
esac
echo "emu egress policy: $MODE"
