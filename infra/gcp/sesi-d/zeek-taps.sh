#!/bin/bash
# vm-core-ran (root): pkthash.zeek per tap, pinned to the last CPU, nice 10, offloads off.
# Taps:
#   ue   tun_srsue in netns ue1
#   n3   lo GTP-U eNB<->SGW-U
#   n6   ogstun (SGi). AF_PACKET TX is AFTER the egress qdisc, so n6 DL is post-HTB;
#        ogstun ingress UL is BEFORE ifb0 shaping.
#   sgiq complementary side of the SGi shaper, so queue delay is a measurable segment:
#        - DL pre-HTB: tc mirred+continue on the ogstun HTB root (enqueue, before the qdisc)
#          onto dummy 'sgiq', Zeek unit lab5g-pkt-sgiq-dl, PKTHASH::tap=sgiq (no nft: dup-to-device invalid in ip family)
#        - UL post-ifb0: ifb0 TX (after ifb0 HTB). Both points carry RAW IP on Ethernet-type devices,
#          so zeek/sgiq-feed.py re-frames them (fake Ethernet) onto veth pairs sgiqd/sgiqu that Zeek reads.
#          unit lab5g-pkt-sgiq-ul,
#          PKTHASH::tap=sgiq
#        Do NOT use ens4 egress as "DL before shaping": DL arrives on ens4 ingress,
#        is routed to ogstun, then shaped on ogstun egress. ens4 egress is UL toward
#        the internet (post-NAT), too late and mixed with other VM traffic.
#        Do NOT attach clsact on ogstun: it conflicts with the ingress qdisc qod-tc
#        uses to redirect UL to ifb0.
# Logs: /var/log/lab5g/pkt/<tap>/pkthash.log  (sgiq uses sgiq-dl/ and sgiq-ul/)
# n6 also loads base/protocols/conn so conn.log can report tcp/443 vs udp/443 share.
# usage: zeek-taps.sh start|stop|ensure|status
# env: PKT_UDP_PORTS="443 4789"  ENB_IP=127.0.1.1
Z=/opt/zeek/bin/zeek; L=/var/log/lab5g/pkt; SD=$(cd "$(dirname "$0")" && pwd); SCR=$SD/zeek/pkthash.zeek
CPU=${ZEEK_CPU:-$(( $(nproc) - 1 ))}; ENB=${ENB_IP:-127.0.1.1}; PORTS=${PKT_UDP_PORTS:-443 4789}
# N3 tap BPF: GTP-U only, for every gNB bind address (ENB_IPS, default = ENB_IP; multi-pair NR: "127.0.1.1 127.0.1.2 127.0.1.3").
# N3_EXCLUDE_ZMQ=1 (default) additionally rejects srsRAN ZMQ I/Q (tcp 2000-2299) that shares lo.
ENB_IPS=${ENB_IPS:-$ENB}; N3_H=""; for h in $ENB_IPS; do N3_H="${N3_H:+$N3_H or }host $h"; done
N3_BPF="udp port 2152 and ($N3_H)"; [ "${N3_EXCLUDE_ZMQ:-1}" = 1 ] && N3_BPF="$N3_BPF and not tcp portrange 2000-2299"
UBPF=$(for p in $PORTS; do printf 'udp port %s or ' $p; done | sed 's/ or $//')
# Always hash tcp/443 as well (TRANSPORT=tcp-only / mixed auto). Retransmits share a hash.
BPF="($UBPF) or tcp port 443"
REDEF="redef PKTHASH::udp_ports += { $(for p in $PORTS; do printf '%s/udp, ' $p; done | sed 's/, $//') }; redef PKTHASH::tcp_ports += { 443/tcp };"
NS="ip netns exec ue1"
unit(){ echo lab5g-pkt-$1; }

start_tap(){ # name ifc bpf netns-prefix [tap-label] [extra-zeek-scripts]
  local t=$1 i=$2 f=$3 pre=$4
  local label=${5:-$t}
  local extra=${6:-}
  mkdir -p $L/$t
  systemctl stop "$(unit "$t")" 2>/dev/null; systemctl reset-failed "$(unit "$t")" 2>/dev/null
  $pre ethtool -K $i gro off gso off tso off >/dev/null 2>&1 || true
  echo "$REDEF" > $L/$t/redef.zeek
  # shellcheck disable=SC2086
  systemd-run --unit="$(unit "$t")" --working-directory=$L/$t taskset -c $CPU nice -n 10 $pre $Z -C -i $i -f "$f" $SCR $L/$t/redef.zeek $extra \
    policy/misc/capture-loss "PKTHASH::tap=$label" "CaptureLoss::watch_interval=1min" "Log::default_rotation_interval=0secs" >/dev/null
}

# --- sgiq setup ---------------------------------------------------------------
# tc u32 on parent 1: prio 1 with mirred+gact continue copies DL BEFORE the qdisc
# (continue is mandatory — otherwise QoD filters would never match).
sgiq_mirror_on() {
  ip link add sgiq type dummy 2>/dev/null || true
  ip link set sgiq up 2>/dev/null || true
  ethtool -K sgiq gro off gso off tso off >/dev/null 2>&1 || true
  if ! ip link show ogstun >/dev/null 2>&1; then
    echo "WARN: ogstun missing; sgiq DL mirror skipped (ok for a dry local test)"
    return 0
  fi
  # tc mirred+continue on the HTB root (enqueue = BEFORE the qdisc). 'continue' keeps the QoD u32 filters
  # (prefs >= 100) matching. (nft 'dup to <dev>' is not valid in the ip family, so tc is the method.)
  if tc qdisc show dev ogstun 2>/dev/null | grep -q htb; then
    tc filter del dev ogstun parent 1: protocol ip prio 1 2>/dev/null || true
    if tc filter add dev ogstun parent 1: protocol ip prio 1 u32 match u32 0 0 \
         action mirred egress mirror dev sgiq action gact continue 2>/dev/null; then
      echo "sgiq: tc mirred+continue on ogstun HTB prio 1 (DL pre-queue; continue keeps QoD filters)"
      return 0
    fi
  fi
  echo "WARN: could not attach DL pre-shaper mirror to sgiq (htb missing or tc failed; ensure later)"
  return 0
}

sgiq_mirror_off() {
  tc filter del dev ogstun parent 1: protocol ip prio 1 2>/dev/null || true
  ip link del sgiq 2>/dev/null || true
}

# veth pair per direction: feeder (sgiq-feed.py) -> <n>0, Zeek listens on <n>1 (fake Ethernet; see sgiq-feed.py)
sgiq_feed() { # name src-iface veth-prefix
  local t=$1 src=$2 v=$3
  ip link show "${v}0" >/dev/null 2>&1 || ip link add "${v}0" type veth peer name "${v}1"
  ip link set "${v}0" up; ip link set "${v}1" up
  ethtool -K "${v}1" gro off gso off tso off >/dev/null 2>&1 || true
  systemctl stop "$(unit "feed-$t")" 2>/dev/null; systemctl reset-failed "$(unit "feed-$t")" 2>/dev/null
  systemd-run --unit="$(unit "feed-$t")" nice -n 5 python3 "$SD/zeek/sgiq-feed.py" --src "$src" --out "${v}0" >/dev/null
  start_tap "$t" "${v}1" "$BPF" "" sgiq
}

start_sgiq() {
  sgiq_mirror_on
  if ip link show sgiq >/dev/null 2>&1; then sgiq_feed sgiq-dl sgiq sgiqd; else echo "WARN: dummy sgiq missing, skip sgiq-dl"; fi
  # UL post-shaper: ifb0 TX after HTB. ifb0 is owned by qod-tc; do not delete it.
  if ip link show ifb0 >/dev/null 2>&1; then sgiq_feed sgiq-ul ifb0 sgiqu; else echo "WARN: ifb0 missing (qod-tc setup not run yet), skip sgiq-ul"; fi
}

case "${1:-status}" in
start)
  start_tap ue tun_srsue "$BPF" "$NS"
  start_tap n3 lo "$N3_BPF" ""
  start_tap n6 ogstun "$BPF" "" n6 "base/protocols/conn"
  start_sgiq
  sleep 3; bash "$SD/zeek-taps.sh" status ;;
ensure)
  for t in ue n3 n6; do
    systemctl is-active -q "$(unit "$t")" || {
      echo "restart $t"
      case $t in
        ue) start_tap ue tun_srsue "$BPF" "$NS";;
        n3) start_tap n3 lo "$N3_BPF" "";;
        n6) start_tap n6 ogstun "$BPF" "" n6 "base/protocols/conn";;
      esac
    }
  done
  sgiq_mirror_on
  systemctl is-active -q "$(unit sgiq-dl)" || { echo "restart sgiq-dl"; ip link show sgiq >/dev/null 2>&1 && sgiq_feed sgiq-dl sgiq sgiqd; }
  systemctl is-active -q "$(unit sgiq-ul)" || { echo "restart sgiq-ul"; ip link show ifb0 >/dev/null 2>&1 && sgiq_feed sgiq-ul ifb0 sgiqu; }
  ;;
stop)
  for t in ue n3 n6 sgiq-dl sgiq-ul feed-sgiq-dl feed-sgiq-ul; do systemctl stop "$(unit "$t")" 2>/dev/null; done
  ip link del sgiqd0 2>/dev/null; ip link del sgiqu0 2>/dev/null
  sgiq_mirror_off
  sleep 2; ls -la $L/*/pkthash.log $L/*/pkthash*.log 2>/dev/null
  ;;
status)
  for t in ue n3 n6 sgiq-dl sgiq-ul; do
    printf '%-8s %-8s rows=%s loss=%s\n' $t "$(systemctl is-active "$(unit "$t")" 2>/dev/null || echo n/a)" \
      "$(grep -vc '^#' $L/$t/pkthash.log 2>/dev/null || echo 0)" \
      "$(grep -v '^#' $L/$t/capture_loss.log 2>/dev/null | tail -1 | awk -F'\t' '{print $NF}')"
  done
  ;;
*) echo "usage: $0 start|stop|ensure|status"; exit 1 ;;
esac
