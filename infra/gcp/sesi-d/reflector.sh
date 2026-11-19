#!/bin/bash
# vm-core-ran (root): MGLT sink/echo at 10.99.9.20 — default of examine APK v0.10.1 (overridable via --es probehost).
# App v0.10.1 forces IPv4 probe/marker sockets, so the IPv4 sink is the official path.
# Optional IPv6 sink: set REFLECTOR_IP6 (e.g. a ULA /128 on ogstun) to also bind :9000/:9001 on AF_INET6.
#   :9000  UDP echo  (MGLT v1 per-flow markers; app connects this socket)
#   :9001  UDP sink  (MGLT v2.1 per-packet probes; app does NOT connect, no echo)
# Address is added as /32 on ogstun (SGi) so UE traffic to 10.99.9.20 stays on the lab path
# (ue-l3 GRE -> radio -> UPF) and is not Cloud-NATed. A POSTROUTING ACCEPT is inserted
# before MASQUERADE for 10.45.0.0/16 -> 10.99.9.20.
# usage: reflector.sh start|stop|status
# env: REFLECTOR_DEV=ogstun  REFLECTOR_IP=10.99.9.20  REFLECTOR_IP6=
set -u
DEV=${REFLECTOR_DEV:-ogstun}
IP=${REFLECTOR_IP:-10.99.9.20}
IP6=${REFLECTOR_IP6:-}
L=/var/log/lab5g/pktlat
mkdir -p "$L"
echo_py=$L/mglt-echo.py
sink_py=$L/mglt-sink.py

write_py() {
  cat > "$echo_py" <<'ENDPY'
import socket, time, sys
ip, port = sys.argv[1], int(sys.argv[2])
s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
s.bind((ip, port))
while True:
    d, a = s.recvfrom(65535)
    s.sendto(d, a)
    print("%.6f echo %s:%d len=%d" % (time.time(), a[0], a[1], len(d)), flush=True)
ENDPY
  cat > "$sink_py" <<'ENDPY'
import socket, time, sys
ip, port = sys.argv[1], int(sys.argv[2])
s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
s.bind((ip, port))
while True:
    d, a = s.recvfrom(65535)
    print("%.6f sink %s:%d len=%d" % (time.time(), a[0], a[1], len(d)), flush=True)
ENDPY
  # Optional dual-stack helper: argv3 "echo"|"sink", bind AF_INET6 on IP6.
  cat > "$L/mglt-v6.py" <<'ENDPY'
import socket, time, sys
ip, port, mode = sys.argv[1], int(sys.argv[2]), sys.argv[3]
s = socket.socket(socket.AF_INET6, socket.SOCK_DGRAM)
s.setsockopt(socket.IPPROTO_IPV6, socket.IPV6_V6ONLY, 1)
s.bind((ip, port))
while True:
    d, a = s.recvfrom(65535)
    if mode == "echo":
        s.sendto(d, a)
    print("%.6f %s %s:%d len=%d" % (time.time(), mode, a[0], a[1], len(d)), flush=True)
ENDPY
}

# 18 Nov rerun finding: 10.99.9.20 is a LOCAL address (table local, ip rule pref 0). GRE traffic from the emulator
# to it was delivered locally at the core and never entered netns ue1 (v1 echo RTT ~6-14 ms, no radio, no taps).
# Fix: move the local lookup below the GRE policy rule (pref 100) and keep local delivery for the GRE /30 itself,
# so emulator -> 10.99.9.20 goes ue1 -> tun_srsue -> radio -> UPF -> ogstun -> local delivery (UL taps + ifb0 shaping).
route_fix() {
  ip link show gre-emu >/dev/null 2>&1 || { echo "route_fix: gre-emu missing (skip)"; return 0; }
  ip rule show | grep -q "^10:.*iif gre-emu.*lookup local" || ip rule add priority 10 iif gre-emu to 10.201.0.1 lookup local
  if ip rule show | grep -q "^0:.*lookup local"; then
    ip rule add priority 1000 from all lookup local 2>/dev/null || true
    ip rule del priority 0 from all lookup local 2>/dev/null || true
  fi
  echo "route_fix: ip rule $(ip rule show | tr '\n' ';' | tr -s '\t ' ' ')"
}

route_unfix() {
  ip rule show | grep -q "^0:.*lookup local" || ip rule add priority 0 from all lookup local 2>/dev/null || true
  ip rule del priority 1000 from all lookup local 2>/dev/null || true
  ip rule del priority 10 iif gre-emu to 10.201.0.1 lookup local 2>/dev/null || true
}

addr_add() {
  if ! ip link show "$DEV" >/dev/null 2>&1; then
    echo "WARN: dev $DEV missing (ok for a dry local test)"; return 0
  fi
  ip addr replace "$IP/32" dev "$DEV"
  route_fix
  # do not SNAT the sink into the internet path
  iptables -t nat -C POSTROUTING -s 10.45.0.0/16 -d "$IP" -j ACCEPT 2>/dev/null \
    || iptables -t nat -I POSTROUTING 1 -s 10.45.0.0/16 -d "$IP" -j ACCEPT
  if [ -n "$IP6" ]; then
    ip -6 addr replace "$IP6/128" dev "$DEV"
    ip6tables -t nat -C POSTROUTING -d "$IP6" -j ACCEPT 2>/dev/null \
      || ip6tables -t nat -I POSTROUTING 1 -d "$IP6" -j ACCEPT 2>/dev/null || true
  fi
}

addr_del() {
  route_unfix
  ip addr del "$IP/32" dev "$DEV" 2>/dev/null || true
  iptables -t nat -D POSTROUTING -s 10.45.0.0/16 -d "$IP" -j ACCEPT 2>/dev/null || true
  if [ -n "$IP6" ]; then
    ip -6 addr del "$IP6/128" dev "$DEV" 2>/dev/null || true
    ip6tables -t nat -D POSTROUTING -d "$IP6" -j ACCEPT 2>/dev/null || true
  fi
}

case "${1:-status}" in
start)
  write_py; addr_add
  systemctl stop lab5g-mglt-echo lab5g-mglt-sink 2>/dev/null || true
  systemctl reset-failed lab5g-mglt-echo lab5g-mglt-sink 2>/dev/null || true
  systemd-run --unit=lab5g-mglt-echo python3 -u "$echo_py" "$IP" 9000 >>"$L/mglt-echo.log" 2>&1
  systemd-run --unit=lab5g-mglt-sink python3 -u "$sink_py" "$IP" 9001 >>"$L/mglt-sink.log" 2>&1
  if [ -n "$IP6" ]; then
    systemctl stop lab5g-mglt-echo6 lab5g-mglt-sink6 2>/dev/null || true
    systemd-run --unit=lab5g-mglt-echo6 python3 -u "$L/mglt-v6.py" "$IP6" 9000 echo >>"$L/mglt-echo6.log" 2>&1
    systemd-run --unit=lab5g-mglt-sink6 python3 -u "$L/mglt-v6.py" "$IP6" 9001 sink >>"$L/mglt-sink6.log" 2>&1
  fi
  sleep 1
  bash "$0" status
  ;;
stop)
  systemctl stop lab5g-mglt-echo lab5g-mglt-sink lab5g-mglt-echo6 lab5g-mglt-sink6 2>/dev/null || true
  addr_del
  echo "reflector stopped"
  ;;
status)
  for u in lab5g-mglt-echo lab5g-mglt-sink lab5g-mglt-echo6 lab5g-mglt-sink6; do
    printf '%-18s %s\n' "$u" "$(systemctl is-active "$u" 2>/dev/null || echo n/a)"
  done
  ip -4 addr show dev "$DEV" 2>/dev/null | grep -F "$IP" || echo "addr $IP not on $DEV"
  if [ -n "$IP6" ]; then ip -6 addr show dev "$DEV" 2>/dev/null | grep -F "$IP6" || echo "addr $IP6 not on $DEV"; fi
  ss -lun | grep -E ":900[01]\\b" || echo "ports 9000/9001 not listening"
  ;;
*) echo "usage: $0 start|stop|status"; exit 1 ;;
esac
