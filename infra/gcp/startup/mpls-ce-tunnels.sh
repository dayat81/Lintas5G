#!/bin/bash
# Sisi CE backhaul MPLS di vm-core-ran.
# Dua terowongan GRE (gretap) atau VXLAN tanpa label ke vm-mpls:
#   ce-enb (10.255.10.2/24) <-> PE1 (10.255.10.1)
#   ce-sgw (10.255.20.2/24) <-> PE2 (10.255.20.1)
# Label MPLS tidak dipakai di VM ini.
#
# Pakai: mpls-ce-tunnels.sh setup|verify|status|rollback
# Pasangan di vm-mpls: /opt/lab5g/scripts/mpls-backhaul.sh
set -euo pipefail

TUN_MTU="${TUN_MTU:-1400}"
KEY_ENB=100
KEY_SGW=200
NS_LIST=(ce-enb ce-sgw)

log() { printf '%s %s\n' "$(date -u +%FT%TZ)" "$*" | tee -a /var/log/lab5g/mpls-ce-tunnels.log; }
die() { log "ERROR: $*"; exit 1; }
need_root() { [[ $(id -u) -eq 0 ]] || die "jalankan sebagai root"; }

meta_attr() {
  curl -fsS -H "Metadata-Flavor: Google" \
    "http://metadata.google.internal/computeMetadata/v1/instance/attributes/${1}" 2>/dev/null || true
}

underlay_if() {
  ip route show default 0.0.0.0/0 2>/dev/null | awk '{for (i=1;i<=NF;i++) if ($i=="dev") {print $(i+1); exit}}'
}

underlay_ip() {
  local ifc
  ifc="$(underlay_if)"
  [[ -n "$ifc" ]] || die "tidak ketemu interface underlay (default route)"
  ip -4 addr show dev "$ifc" | awk '/inet / {print $2}' | cut -d/ -f1 | head -n1
}

resolve_host() {
  local h="$1" ip=""
  ip="$(getent ahostsv4 "$h" 2>/dev/null | awk '{print $1; exit}')"
  [[ -n "$ip" ]] || ip="$(getent hosts "$h" 2>/dev/null | awk '{print $1; exit}')"
  printf '%s' "$ip"
}

tunnel_mode() {
  local m="${TUN_MODE:-}"
  if [[ -z "$m" ]]; then
    m="$(meta_attr mpls-tunnel-mode)"
  fi
  m="$(echo "${m:-gre}" | tr '[:upper:]' '[:lower:]')"
  case "$m" in
    gre|gretap) echo gre ;;
    vxlan) echo vxlan ;;
    *) die "TUN_MODE tidak dikenal: $m (gre|vxlan)" ;;
  esac
}

mpls_enabled() {
  local v="${MPLS_ENABLED:-$(meta_attr mpls-enabled)}"
  [[ "$v" == "true" || "$v" == "1" || "$v" == "yes" ]]
}

mpls_peer_ip() {
  local host ip
  host="${MPLS_PEER_HOST:-$(meta_attr mpls-peer-host)}"
  [[ -n "$host" ]] || die "mpls-peer-host belum di-set (metadata atau MPLS_PEER_HOST)"
  local i
  for i in 1 2 3 4 5 6; do
    ip="$(resolve_host "$host")"
    if [[ -n "$ip" ]]; then
      echo "$ip"
      return 0
    fi
    sleep 2
  done
  die "gagal resolve mpls peer: $host"
}

ensure_ns() {
  local ns="$1"
  ip netns add "$ns" 2>/dev/null || true
  ip netns exec "$ns" ip link set lo up
}

# Terowongan L2 di root, di-bridge ke veth di netns CE.
ensure_ce_tunnel() {
  local side="$1"   # enb|sgw
  local ns="$2"
  local ceif="$3"   # ce-pe1|ce-pe2
  local cidr="$4"
  local key="$5"
  local mode remote local_ip dev br tun veth
  mode="$(tunnel_mode)"
  remote="$(mpls_peer_ip)"
  local_ip="$(underlay_ip)"
  dev="$(underlay_if)"
  br="br-ce-${side}"
  tun="${mode}-ce-${side}"
  veth="veth-ce-${side}"

  if ip netns exec "$ns" ip link show "$ceif" >/dev/null 2>&1; then
    log "tunnel CE ${side}: ${ceif} sudah ada"
  else
    ip link del "$tun" 2>/dev/null || true
    ip link del "$veth" 2>/dev/null || true
    ip link del "$br" 2>/dev/null || true

    if [[ "$mode" == gre ]]; then
      ip link add "$tun" type gretap remote "$remote" local "$local_ip" dev "$dev" key "$key" ttl 64
    else
      ip link add "$tun" type vxlan id "$key" dev "$dev" remote "$remote" local "$local_ip" dstport 4789 ttl 64
    fi
    ip link set "$tun" mtu "$TUN_MTU"
    ip link add "$br" type bridge stp_state 0
    ip link set "$br" mtu "$TUN_MTU"
    ip link add "$veth" type veth peer name "$ceif"
    ip link set "$ceif" netns "$ns"
    ip link set "$tun" master "$br"
    ip link set "$veth" master "$br"
    ip link set "$veth" mtu "$TUN_MTU"
    ip netns exec "$ns" ip link set "$ceif" mtu "$TUN_MTU"
    ip link set "$tun" up
    ip link set "$veth" up
    ip link set "$br" up
    log "tunnel CE ${mode} ${side}: local=${local_ip} remote=${remote} key/vni=${key} mtu=${TUN_MTU} -> ${ns}/${ceif}"
  fi

  ip netns exec "$ns" ip link set "$ceif" up
  ip netns exec "$ns" ip addr replace "$cidr" dev "$ceif"
}

destroy_ce_tunnels() {
  local side tun br veth mode
  mode="$(tunnel_mode 2>/dev/null || echo gre)"
  for side in enb sgw; do
    tun="${mode}-ce-${side}"
    br="br-ce-${side}"
    veth="veth-ce-${side}"
    ip link del "$tun" 2>/dev/null || true
    ip link del "$veth" 2>/dev/null || true
    ip link del "$br" 2>/dev/null || true
    ip link del "gre-ce-${side}" 2>/dev/null || true
    ip link del "vxlan-ce-${side}" 2>/dev/null || true
  done
}

setup_ce() {
  need_root
  install -d -m 0755 /var/log/lab5g /opt/lab5g/scripts
  if ! mpls_enabled && [[ -z "${MPLS_PEER_HOST:-}" ]]; then
    die "enable_mpls=false dan MPLS_PEER_HOST kosong; vm-mpls tidak tersedia"
  fi

  local ns
  for ns in "${NS_LIST[@]}"; do
    ensure_ns "$ns"
  done

  ensure_ce_tunnel enb ce-enb ce-pe1 10.255.10.2/24 "$KEY_ENB"
  ensure_ce_tunnel sgw ce-sgw ce-pe2 10.255.20.2/24 "$KEY_SGW"

  # Rute antar sisi CE lewat gateway PE (VRF S1 di vm-mpls).
  ip netns exec ce-enb ip route replace 10.255.20.0/24 via 10.255.10.1
  ip netns exec ce-sgw ip route replace 10.255.10.0/24 via 10.255.20.1

  cat >/opt/lab5g/mpls-ce-README <<'NOTE'
Sisi CE backhaul MPLS (vm-core-ran).

  ce-enb 10.255.10.2/24  -- GRE/VXLAN (tanpa label) --  PE1 10.255.10.1  (vm-mpls)
  ce-sgw 10.255.20.2/24  -- GRE/VXLAN (tanpa label) --  PE2 10.255.20.1  (vm-mpls)

MTU iface terowongan 1400 (VPC 1460 - overhead GRE/VXLAN).
Tun aplikasi (GTP-U) 1360-1400.
Verify: sudo /opt/lab5g/scripts/mpls-ce-tunnels.sh verify
NOTE
  log "setup CE selesai. Jalankan: $0 verify (setelah mpls-backhaul.sh setup di vm-mpls)"
}

cmd_status() {
  echo "== netns CE =="
  ip netns list | grep -E 'ce-enb|ce-sgw' || true
  echo "== tunnels (root) =="
  ip -d link show type gretap 2>/dev/null || true
  ip -d link show type vxlan 2>/dev/null || true
  local ns
  for ns in ce-enb ce-sgw; do
    echo "== ${ns} addr/route =="
    ip netns exec "$ns" ip addr show || true
    ip netns exec "$ns" ip route show || true
  done
}

cmd_verify() {
  local rc=0
  need_root
  echo "== ping CE-eNB -> PE1 (10.255.10.1) =="
  if ip netns exec ce-enb ping -c 3 -W 2 10.255.10.1; then
    log "ping ce-enb -> PE1 OK"
  else
    log "ping ce-enb -> PE1 gagal"
    rc=1
  fi
  echo "== ping CE-SGW -> PE2 (10.255.20.1) =="
  if ip netns exec ce-sgw ping -c 3 -W 2 10.255.20.1; then
    log "ping ce-sgw -> PE2 OK"
  else
    log "ping ce-sgw -> PE2 gagal"
    rc=1
  fi
  echo "== ping CE-eNB -> CE-SGW (10.255.20.2, harus lewat VRF S1 / MPLS) =="
  if ip netns exec ce-enb ping -c 3 -W 2 10.255.20.2; then
    log "ping CE-eNB -> CE-SGW OK"
  else
    log "ping CE-eNB -> CE-SGW gagal — cek setup PE, LDP/BGP, terowongan"
    rc=1
  fi
  echo "== traceroute CE-eNB -> CE-SGW =="
  ip netns exec ce-enb traceroute -n -w 2 -q 1 10.255.20.2 || true
  return "$rc"
}

cmd_rollback() {
  need_root
  local ns
  for ns in "${NS_LIST[@]}"; do
    ip netns delete "$ns" 2>/dev/null || true
  done
  destroy_ce_tunnels
  log "rollback CE selesai (netns dan terowongan dihapus)"
}

usage() {
  cat <<USAGE
Sisi CE backhaul MPLS di vm-core-ran
  $0 setup     buat netns ce-enb/ce-sgw dan terowongan GRE/VXLAN ke vm-mpls
  $0 status    ringkasan netns/terowongan/rute
  $0 verify    ping PE dan ping/traceroute CE-eNB -> CE-SGW
  $0 rollback  hapus netns dan terowongan CE

Mode: TUN_MODE=gre|vxlan (default: metadata mpls-tunnel-mode, gre)
MTU:  VPC 1460, iface terowongan 1400, tun aplikasi 1360-1400.
USAGE
}

cmd="${1:-}"
shift || true
case "$cmd" in
  setup) setup_ce ;;
  status) cmd_status ;;
  verify) cmd_verify ;;
  rollback) cmd_rollback ;;
  *) usage; exit 1 ;;
esac
