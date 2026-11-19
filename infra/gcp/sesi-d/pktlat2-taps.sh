#!/bin/bash
# vm-core-ran (root): run stock pktlat2.zeek v2.1 alongside pkthash taps.
# A veth pair (pktlat0/pktlat1) carries VLAN-tagged copies of ue/n3/n6 (see zeek/pktlat-mirror.py).
# usage: pktlat2-taps.sh start|stop|ensure|status
# env: ZEEK=/opt/zeek/bin/zeek  ZEEKPATH=...  SKEW_CFG=/var/log/lab5g/pktlat/skew.cfg
set -u
SD=$(cd "$(dirname "$0")" && pwd)
Z=${ZEEK:-/opt/zeek/bin/zeek}
L=/var/log/lab5g/pktlat
OBS=${OBS_ZEEK:-/opt/lab5g/observability/zeek}
# Script lookup order: $OBS_ZEEK, /opt/lab5g/observability/zeek, repo copy, then the copy vendored next to this
# script ($SD/zeek/{mglt,pktlat2}.zeek, uploaded by terraform with the rest of sesi-d/). A VM built from terraform only
# has the vendored copy; v0.10.1 run failed with "can't find mglt" because nothing shipped these two files.
has_scripts() { [ -f "$1/mglt.zeek" ] && [ -f "$1/pktlat2.zeek" ]; }
if ! has_scripts "$OBS"; then
  OBS=$(cd "$SD/../../../observability/zeek" 2>/dev/null && pwd || echo "$SD/zeek")
  has_scripts "$OBS" || OBS="$SD/zeek"
fi
mkdir -p "$L"
unit_z=lab5g-pktlat2
unit_m=lab5g-pktlat-mirror

veth_up() {
  ip link add pktlat0 type veth peer name pktlat1 2>/dev/null || true
  ip link set pktlat0 mtu 65000 up
  ip link set pktlat1 mtu 65000 up
  # MTU 65000: GSO/GRO frames on ogstun/tun were dropped by the mirror ("Message too long") with MTU 2000
  # no IPv4: Zeek captures only
  ip addr flush dev pktlat0 2>/dev/null || true
  ip addr flush dev pktlat1 2>/dev/null || true
}

veth_down() {
  ip link del pktlat0 2>/dev/null || true
}

case "${1:-status}" in
start)
  has_scripts "$OBS" || { echo "pktlat2-taps: mglt.zeek/pktlat2.zeek not found in $OBS" >&2; exit 2; }
  veth_up
  [ -f "$L/skew.cfg" ] || printf 'PKTLAT2::skew_s 0.0\nPKTLAT2::run_id live\n' > "$L/skew.cfg"
  systemctl stop $unit_z $unit_m 2>/dev/null || true
  systemctl reset-failed $unit_z $unit_m 2>/dev/null || true
  systemd-run --unit=$unit_m --working-directory="$L" \
    python3 -u "$SD/zeek/pktlat-mirror.py" run --out-iface pktlat1 \
      --ue tun_srsue --n3 lo --n6 ogstun --ue-netns ue1
  # Prepend site policies to the stock ZEEKPATH. Replacing it entirely makes Zeek
  # fail with "can't find base/init-bare.zeek" (seen on 9.0.1).
  ZP=$("$Z-config" --zeekpath 2>/dev/null || echo ".:/opt/zeek/share/zeek:/opt/zeek/share/zeek/policy:/opt/zeek/share/zeek/site:/opt/zeek/share/zeek/builtin-plugins")
  # shellcheck disable=SC2086
  systemd-run --unit=$unit_z --working-directory="$L" \
    --setenv=ZEEKPATH="$OBS:$SD/zeek:$ZP" \
    "$Z" -C -i pktlat0 "$SD/zeek/run-live-yt.zeek" \
      "Log::default_rotation_interval=0secs"
  sleep 3
  bash "$0" status
  # fail loudly: a dead pktlat2 means NO MGLT coverage (this went unnoticed in the v0.10.1 run)
  if ! systemctl is-active -q $unit_z; then
    echo "pktlat2-taps: $unit_z is not active after start" >&2
    journalctl -u $unit_z -n 15 --no-pager 2>/dev/null | cut -c1-200 >&2 || true
    exit 1
  fi
  ;;
ensure)
  systemctl is-active -q $unit_z && systemctl is-active -q $unit_m && exit 0
  bash "$0" start
  ;;
stop)
  systemctl stop $unit_z $unit_m 2>/dev/null || true
  veth_down
  ls -la "$L"/*.log 2>/dev/null || true
  ;;
status)
  for u in $unit_m $unit_z; do printf '%-22s %s\n' "$u" "$(systemctl is-active $u 2>/dev/null || echo n/a)"; done
  [ -f "$L/pktlat_stats.log" ] && tail -1 "$L/pktlat_stats.log" | python3 -c 'import sys,json
try:
  d=json.loads(sys.stdin.read()); print("pktlat stats probes=%s crc_bad=%s q_pkts=%s q_ul_ok=%s q_dl_ok=%s q_miss=%s"%tuple(d.get(k) for k in ("probes","crc_bad","q_pkts","q_ul_ok","q_dl_ok","q_miss")))
except Exception: pass'
  [ -f "$L/pktlat.log" ] && echo "pktlat rows=$(grep -c '^{' "$L/pktlat.log" 2>/dev/null || echo 0)"
  [ -f "$L/skew.cfg" ] && cat "$L/skew.cfg"
  ;;
*) echo "usage: $0 start|stop|ensure|status"; exit 1 ;;
esac
