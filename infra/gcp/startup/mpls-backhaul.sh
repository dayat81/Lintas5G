#!/bin/bash
# USULAN: backhaul MPLS untuk segmen S1 (S1-U GTP-U, opsional S1-AP)
# di dalam vm-mpls. Label MPLS hanya di netns PE/P pada VM ini.
#
# Sisi CE (tanpa label) adalah terowongan GRE (gretap) atau VXLAN ke
# vm-core-ran: satu untuk eNB, satu untuk SGW. Skrip pasangan di core:
#   /opt/lab5g/scripts/mpls-ce-tunnels.sh
#
# VPC GCP tidak meneruskan frame berlabel MPLS antar-VM, karena itu
# label tetap di dalam vm-mpls; antar-VM hanya GRE/VXLAN tanpa label.
#
# Pakai:  mpls-backhaul.sh setup|status|verify|netem|rollback|hint
# Idempotent untuk setup. rollback hanya menghapus netns/FRR/terowongan lab ini.
set -euo pipefail

PREFIX="lab5g-mpls"
BASE="/opt/lab5g/mpls"
CONF="${BASE}/frr"
RUN="/run/${PREFIX}"
NS_LIST=(pe1 p1 p2 pe2)
ASN=65001
RD="65001:1"
RT="65001:1"
VRF="S1"
VRF_TABLE=100
PLATFORM_LABELS=65535
TUN_MTU="${TUN_MTU:-1400}"
KEY_ENB=100
KEY_SGW=200

# Addressing (hanya di overlay lab, bukan VPC):
# Loopback: PE1 10.255.0.1, PE2 10.255.0.2, P1 10.255.0.11, P2 10.255.0.12
# P2P /30 inti (veth, berlabel):
#   pe1-p1 10.255.1.0/30  pe1=.1  p1=.2
#   pe1-p2 10.255.1.4/30  pe1=.5  p2=.6
#   p1-pe2 10.255.1.8/30  p1=.9   pe2=.10
#   p2-pe2 10.255.1.12/30 p2=.13  pe2=.14
# CE VRF S1 (tanpa label, lewat terowongan ke vm-core-ran):
#   pe1-ce 10.255.10.1/24  ce-enb 10.255.10.2/24
#   pe2-ce 10.255.20.1/24  ce-sgw 10.255.20.2/24

log() { printf '%s %s\n' "$(date -u +%FT%TZ)" "$*" | tee -a /var/log/lab5g/mpls-backhaul.log; }
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

core_peer_ip() {
  local host ip
  host="${CORE_PEER_HOST:-$(meta_attr core-peer-host)}"
  [[ -n "$host" ]] || die "core-peer-host belum di-set (metadata atau CORE_PEER_HOST)"
  local i
  for i in 1 2 3 4 5 6; do
    ip="$(resolve_host "$host")"
    if [[ -n "$ip" ]]; then
      echo "$ip"
      return 0
    fi
    sleep 2
  done
  die "gagal resolve core peer: $host"
}

vtysh_ns() {
  local ns="$1"; shift
  ip netns exec "$ns" vtysh -N "${PREFIX}-${ns}" "$@"
}

ensure_dirs() {
  install -d -m 0755 "${BASE}" "${CONF}" /var/log/lab5g
  install -d -m 0755 /opt/lab5g/scripts /opt/lab5g/zeek
}
load_mpls() {
  if ! modprobe mpls_router 2>/dev/null; then
    log "modul mpls_router belum ada; coba pasang linux-modules-extra untuk kernel $(uname -r)"
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq || true
    apt-get install -y -qq "linux-modules-extra-$(uname -r)" || apt-get install -y -qq linux-modules-extra-gcp || true
    modprobe mpls_router 2>/dev/null || die "modul mpls_router tidak tersedia (butuh linux-modules-extra untuk kernel $(uname -r))"
  fi
  modprobe mpls_iptunnel 2>/dev/null || true
  modprobe mpls_gso 2>/dev/null || true
  cat >/etc/modules-load.d/${PREFIX}.conf <<MODS
mpls_router
mpls_iptunnel
MODS
  cat >/etc/sysctl.d/99-${PREFIX}.conf <<SYS
net.mpls.platform_labels = ${PLATFORM_LABELS}
net.ipv4.ip_forward = 1
net.ipv4.conf.all.rp_filter = 0
net.ipv4.conf.default.rp_filter = 0
SYS
  sysctl -w net.mpls.platform_labels="${PLATFORM_LABELS}" >/dev/null
  sysctl -w net.ipv4.ip_forward=1 >/dev/null
}

mpls_input() {
  local ns="$1" ifc="$2"
  ip netns exec "$ns" sysctl -w "net.mpls.conf.${ifc}.input=1" >/dev/null
  ip netns exec "$ns" sysctl -w net.ipv4.conf.all.rp_filter=0 >/dev/null || true
  ip netns exec "$ns" sysctl -w "net.ipv4.conf.${ifc}.rp_filter=0" >/dev/null || true
}

ensure_ns() {
  local ns="$1"
  ip netns add "$ns" 2>/dev/null || true
  ip netns exec "$ns" ip link set lo up
  # platform_labels bersifat per-netns; 0 (default) membuat LDP/MPLS tidak terpasang di FIB.
  ip netns exec "$ns" sysctl -w net.mpls.platform_labels="${PLATFORM_LABELS}" >/dev/null
  ip netns exec "$ns" sysctl -w net.ipv4.ip_forward=1 >/dev/null || true
  ip netns exec "$ns" sysctl -w net.ipv4.conf.all.rp_filter=0 >/dev/null || true
}

# veth: $1 ns-a  $2 if-a  $3 ns-b  $4 if-b
ensure_veth() {
  local nsa="$1" ifa="$2" nsb="$3" ifb="$4"
  if ip netns exec "$nsa" ip link show "$ifa" >/dev/null 2>&1; then
    return 0
  fi
  ip link add "$ifa" type veth peer name "$ifb"
  ip link set "$ifa" netns "$nsa"
  ip link set "$ifb" netns "$nsb"
}

addr_up() {
  local ns="$1" ifc="$2" cidr="$3"
  ip netns exec "$ns" ip link set "$ifc" up
  ip netns exec "$ns" ip addr replace "$cidr" dev "$ifc"
}

# Terowongan L2 (gretap/vxlan) di root netns, di-bridge ke veth ke netns PE.
# GRE/VXLAN harus tetap di root karena underlay (ens4) ada di sana.
ensure_pe_tunnel() {
  local side="$1"
  local ns="$2"
  local ceif="$3"
  local key="$4"
  local mode remote local_ip dev br tun veth
  mode="$(tunnel_mode)"
  remote="$(core_peer_ip)"
  local_ip="$(underlay_ip)"
  dev="$(underlay_if)"
  br="br-${side}"
  tun="${mode}-${side}"
  veth="veth-${side}"

  if ip netns exec "$ns" ip link show "$ceif" >/dev/null 2>&1; then
    log "tunnel ${side}: ${ceif} sudah ada di netns ${ns}"
    return 0
  fi

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
  log "tunnel ${mode} ${side}: local=${local_ip} remote=${remote} key/vni=${key} mtu=${TUN_MTU} -> ${ns}/${ceif}"
}

destroy_pe_tunnels() {
  local side tun br veth mode
  mode="$(tunnel_mode 2>/dev/null || echo gre)"
  for side in enb sgw; do
    tun="${mode}-${side}"
    br="br-${side}"
    veth="veth-${side}"
    ip link del "$tun" 2>/dev/null || true
    ip link del "$veth" 2>/dev/null || true
    ip link del "$br" 2>/dev/null || true
    ip link del "gre-${side}" 2>/dev/null || true
    ip link del "vxlan-${side}" 2>/dev/null || true
  done
}

install_frr() {
  if ! command -v vtysh >/dev/null 2>&1; then
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -y
    apt-get install -y frr frr-pythontools
  fi
  systemctl disable --now frr 2>/dev/null || true
  if [[ -f /etc/frr/vtysh.conf ]]; then
    grep -q '^service integrated-vtysh-config' /etc/frr/vtysh.conf \
      || echo 'service integrated-vtysh-config' >>/etc/frr/vtysh.conf
  fi
}
write_common_daemons() {
  local d="$1" with_bgp="$2"
  cat >"${d}/daemons" <<DAEMONS
zebra=yes
bgpd=${with_bgp}
ospfd=yes
ospf6d=no
ripd=no
ripngd=no
isisd=no
pimd=no
ldpd=yes
nhrpd=no
eigrpd=no
babeld=no
sharpd=no
pbrd=no
bfdd=no
fabricd=no
vrrpd=no
pathd=no
vtysh_enable=yes
zebra_options="  -A 127.0.0.1 -s 90000000"
bgpd_options="   -A 127.0.0.1"
ospfd_options="  -A 127.0.0.1"
ldpd_options="   -A 127.0.0.1"
DAEMONS
}

write_frr_p() {
  local name="$1" lo="$2"
  local if1="$3" ip1="$4" if2="$5" ip2="$6"
  local d="${CONF}/${name}"
  install -d -m 0750 "$d"
  write_common_daemons "$d" no
  cat >"${d}/frr.conf" <<PCONF
! ${PREFIX} ${name} (P) — OSPF + LDP
frr version 8
frr defaults traditional
hostname ${name}
log file /var/log/lab5g/${name}.frr.log
service integrated-vtysh-config
!
interface lo
 ip address ${lo}/32
 ip ospf area 0
!
interface ${if1}
 ip address ${ip1}
 ip ospf area 0
 ip ospf network point-to-point
!
interface ${if2}
 ip address ${ip2}
 ip ospf area 0
 ip ospf network point-to-point
!
router ospf
 ospf router-id ${lo}
 network ${lo}/32 area 0
 passive-interface lo
!
mpls ldp
 router-id ${lo}
 ordered-control
 address-family ipv4
  discovery transport-address ${lo}
  interface ${if1}
  interface ${if2}
 exit-address-family
!
line vty
PCONF
  chown -R frr:frr "$d" 2>/dev/null || true
}

write_frr_pe() {
  local name="$1" lo="$2" peer="$3"
  local if1="$4" ip1="$5" if2="$6" ip2="$7"
  local cegw="$8" ceif="$9"
  local d="${CONF}/${name}"
  install -d -m 0750 "$d"
  write_common_daemons "$d" yes
  cat >"${d}/frr.conf" <<PECONF
! ${PREFIX} ${name} (PE) — OSPF + LDP + BGP VPNv4 L3VPN VRF ${VRF}
! S1-U dan (opsional) S1-AP diarahkan ke VRF ${VRF}.
frr version 8
frr defaults traditional
hostname ${name}
log file /var/log/lab5g/${name}.frr.log
service integrated-vtysh-config
!
vrf ${VRF}
exit-vrf
!
interface lo
 ip address ${lo}/32
 ip ospf area 0
!
interface ${if1}
 ip address ${ip1}
 ip ospf area 0
 ip ospf network point-to-point
!
interface ${if2}
 ip address ${ip2}
 ip ospf area 0
 ip ospf network point-to-point
!
interface ${ceif}
 ip address ${cegw}
!
router ospf
 ospf router-id ${lo}
 network ${lo}/32 area 0
 passive-interface lo
!
mpls ldp
 router-id ${lo}
 ordered-control
 address-family ipv4
  discovery transport-address ${lo}
  interface ${if1}
  interface ${if2}
 exit-address-family
!
router bgp ${ASN}
 no bgp default ipv4-unicast
 bgp router-id ${lo}
 neighbor ${peer} remote-as ${ASN}
 neighbor ${peer} update-source lo
 !
 address-family ipv4 vpn
  neighbor ${peer} activate
 exit-address-family
!
router bgp ${ASN} vrf ${VRF}
 address-family ipv4 unicast
  redistribute connected
  label vpn export auto
  rd vpn export ${RD}
  rt vpn import ${RT}
  rt vpn export ${RT}
  export vpn
  import vpn
 exit-address-family
!
line vty
PECONF
  chown -R frr:frr "$d" 2>/dev/null || true
}

link_frr_instance() {
  local name="$1"
  rm -rf "/etc/frr/${PREFIX}-${name}" "/var/run/frr/${PREFIX}-${name}"
  ln -sfn "${CONF}/${name}" "/etc/frr/${PREFIX}-${name}"
  install -d -m 0750 -o frr -g frr "/var/run/frr/${PREFIX}-${name}"
}

start_frr_ns() {
  local name="$1"
  local extra=""
  link_frr_instance "$name"
  stop_frr_ns "$name" || true
  if [[ "$name" == pe1 || "$name" == pe2 ]]; then
    extra="bgpd"
  fi
  # shellcheck disable=SC2086
  ip netns exec "$name" /usr/lib/frr/watchfrr -d \
    -N "${PREFIX}-${name}" \
    zebra ospfd ldpd ${extra} \
    || die "gagal start FRR di netns ${name}"
  log "FRR ${name} started"
}

stop_frr_ns() {
  local name="$1"
  pkill -f "/usr/lib/frr/.*-N ${PREFIX}-${name}" 2>/dev/null || true
  pkill -f "watchfrr.*${PREFIX}-${name}" 2>/dev/null || true
  sleep 0.3
}
setup_topo() {
  need_root
  ensure_dirs
  load_mpls
  install_frr

  local ns
  for ns in "${NS_LIST[@]}"; do
    ensure_ns "$ns"
  done

  # Dua jalur PE1—P1—PE2 dan PE1—P2—PE2 untuk uji failover.
  ensure_veth pe1 pe1-p1 p1 p1-pe1
  ensure_veth pe1 pe1-p2 p2 p2-pe1
  ensure_veth p1  p1-pe2 pe2 pe2-p1
  ensure_veth p2  p2-pe2 pe2 pe2-p2

  # CE-facing: terowongan ke vm-core-ran, masuk VRF, tanpa label MPLS.
  ensure_pe_tunnel enb pe1 pe1-ce "$KEY_ENB"
  ensure_pe_tunnel sgw pe2 pe2-ce "$KEY_SGW"

  ip netns exec pe1 ip link add "${VRF}" type vrf table "${VRF_TABLE}" 2>/dev/null || true
  ip netns exec pe1 ip link set "${VRF}" up
  ip netns exec pe1 ip link set pe1-ce master "${VRF}" 2>/dev/null || true
  ip netns exec pe2 ip link add "${VRF}" type vrf table "${VRF_TABLE}" 2>/dev/null || true
  ip netns exec pe2 ip link set "${VRF}" up
  ip netns exec pe2 ip link set pe2-ce master "${VRF}" 2>/dev/null || true

  addr_up pe1 lo 10.255.0.1/32
  addr_up p1  lo 10.255.0.11/32
  addr_up p2  lo 10.255.0.12/32
  addr_up pe2 lo 10.255.0.2/32

  addr_up pe1 pe1-p1 10.255.1.1/30
  addr_up p1  p1-pe1 10.255.1.2/30
  addr_up pe1 pe1-p2 10.255.1.5/30
  addr_up p2  p2-pe1 10.255.1.6/30
  addr_up p1  p1-pe2 10.255.1.9/30
  addr_up pe2 pe2-p1 10.255.1.10/30
  addr_up p2  p2-pe2 10.255.1.13/30
  addr_up pe2 pe2-p2 10.255.1.14/30

  addr_up pe1 pe1-ce 10.255.10.1/24
  addr_up pe2 pe2-ce 10.255.20.1/24

  local x
  for x in pe1-p1 pe1-p2; do mpls_input pe1 "$x"; done
  for x in p1-pe1 p1-pe2; do mpls_input p1 "$x"; done
  for x in p2-pe1 p2-pe2; do mpls_input p2 "$x"; done
  for x in pe2-p1 pe2-p2; do mpls_input pe2 "$x"; done

  write_frr_p  p1  10.255.0.11 p1-pe1 10.255.1.2/30  p1-pe2 10.255.1.9/30
  write_frr_p  p2  10.255.0.12 p2-pe1 10.255.1.6/30  p2-pe2 10.255.1.13/30
  write_frr_pe pe1 10.255.0.1 10.255.0.2 \
    pe1-p1 10.255.1.1/30 pe1-p2 10.255.1.5/30 \
    10.255.10.1/24 pe1-ce
  write_frr_pe pe2 10.255.0.2 10.255.0.1 \
    pe2-p1 10.255.1.10/30 pe2-p2 10.255.1.14/30 \
    10.255.20.1/24 pe2-ce

  start_frr_ns p1
  start_frr_ns p2
  start_frr_ns pe1
  start_frr_ns pe2

  write_docs
  log "setup PE/P selesai. Lanjut di vm-core-ran: mpls-ce-tunnels.sh setup, lalu $0 verify"
}

write_docs() {
  cat >"${BASE}/README" <<'DOCEOF'
USULAN backhaul MPLS S1 di vm-mpls (bukan di vm-core-ran).

Topologi:

  vm-core-ran                         vm-mpls
  ce-enb (10.255.10.2)
       \  GRE/VXLAN (tanpa label)
        \                             PE1 --+-- P1 --+-- PE2
        /                                   +-- P2 --+
  ce-sgw (10.255.20.2)
       /  GRE/VXLAN (tanpa label)

Alasan VM terpisah: isolasi transport dari core/RAN. Label MPLS tidak
keluar dari vm-mpls karena VPC GCP tidak meneruskan frame berlabel.

MTU:
  VPC default 1460 byte.
  gretap+key: IP 20 + GRE 8 + Ethernet 14 approx 42 byte -> MTU iface 1400.
  VXLAN: IP 20 + UDP 8 + VXLAN 8 + Ethernet 14 approx 50 byte -> MTU iface 1400.
  GTP-U (IP 20+UDP 8+GTP 8) di dalam overlay -> tun aplikasi 1360-1400.
  Fragmentasi GTP-U sudah pernah terlihat di lab fisik jika MTU tidak
  diturunkan (FAKTA).

Pengukuran Zeek (interface tanpa label):
  - pe1-ce  : PE1-ingress (sisi eNB)
  - pe2-ce  : PE2-egress  (sisi SGW)
  - plus tap S1-U lama di stack Open5GS/srsRAN
  Breakdown latency: RAN | transport MPLS | core | SGi

Injeksi gangguan:
  mpls-backhaul.sh netem set p1 delay 20ms jitter 5ms loss 0.1%
  mpls-backhaul.sh netem clear

SR-MPLS adalah opsi (FRR pathd / IS-IS-SR); default skrip: OSPF + LDP.
VPLS/EVPN tidak didukung FRR secara penuh — risiko jika butuh L2 S1.
DOCEOF

  cat >"${BASE}/zeek-taps.txt" <<TAPS
# Titik tap yang diusulkan (interface di netns, tanpa label)
# ns        iface     peran
pe1         pe1-ce    PE1-ingress eNB side (unlabeled, VRF ${VRF})
pe2         pe2-ce    PE2-egress  SGW side (unlabeled, VRF ${VRF})
# plus tap S1-U lama di stack Open5GS/srsRAN
TAPS
}
cmd_status() {
  echo "== netns =="
  ip netns list | grep -E 'pe1|pe2|^p1|^p2' || true
  echo "== tunnels (root) =="
  ip -d link show type gretap 2>/dev/null || true
  ip -d link show type vxlan 2>/dev/null || true
  local ns
  for ns in pe1 p1 p2 pe2; do
    echo "== ${ns} mpls route =="
    ip netns exec "$ns" ip -f mpls route || true
    echo "== ${ns} ldp / ospf / bgp =="
    vtysh_ns "$ns" -c "show mpls ldp neighbor" 2>/dev/null || true
    vtysh_ns "$ns" -c "show ip ospf neighbor" 2>/dev/null || true
    if [[ "$ns" == pe1 || "$ns" == pe2 ]]; then
      vtysh_ns "$ns" -c "show bgp ipv4 vpn summary" 2>/dev/null || true
    fi
  done
}

cmd_verify() {
  local rc=0
  need_root
  echo "== modul mpls_router =="
  if lsmod | grep -q '^mpls_router'; then
    echo "mpls_router loaded"
  else
    echo "mpls_router TIDAK loaded"
    rc=1
  fi
  echo "== ip -f mpls route =="
  local ns
  for ns in pe1 p1 p2 pe2; do
    echo "-- ${ns} --"
    ip netns exec "$ns" ip -f mpls route || rc=1
  done
  echo "== FRR: show mpls ldp neighbor =="
  for ns in pe1 p1 p2 pe2; do
    echo "-- ${ns} --"
    vtysh_ns "$ns" -c "show mpls ldp neighbor" || rc=1
  done
  echo "== FRR: show bgp ipv4 vpn (L3VPN VPNv4; bukan VPLS) =="
  for ns in pe1 pe2; do
    echo "-- ${ns} --"
    vtysh_ns "$ns" -c "show bgp ipv4 vpn summary" || rc=1
    vtysh_ns "$ns" -c "show bgp ipv4 vpn" || true
  done
  echo "== ping CE dari VRF (butuh mpls-ce-tunnels.sh setup di vm-core-ran) =="
  if ip netns exec pe1 ip vrf exec "${VRF}" ping -c 3 -W 2 10.255.10.2; then
    log "ping PE1-VRF -> ce-enb OK"
  else
    log "ping PE1-VRF -> ce-enb gagal (CE belum di-setup atau terowongan down)"
    rc=1
  fi
  if ip netns exec pe1 ip vrf exec "${VRF}" ping -c 3 -W 2 10.255.20.2; then
    log "ping PE1-VRF -> ce-sgw (lewat L3VPN) OK"
  else
    log "ping PE1-VRF -> ce-sgw gagal — cek LDP/BGP/VRF atau sisi CE"
    rc=1
  fi
  echo
  echo "Traceroute end-to-end dijalankan dari vm-core-ran:"
  echo "  sudo /opt/lab5g/scripts/mpls-ce-tunnels.sh verify"
  return "$rc"
}

cmd_netem() {
  need_root
  local action="${1:-}"
  shift || true
  case "$action" in
    clear)
      local ns ifc
      for ns in p1 p2; do
        for ifc in $(ip netns exec "$ns" ls /sys/class/net | grep -v '^lo$'); do
          ip netns exec "$ns" tc qdisc del dev "$ifc" root 2>/dev/null || true
        done
      done
      log "netem dibersihkan di P1 dan P2"
      ;;
    set)
      local path="${1:-}"; shift || true
      [[ "$path" == p1 || "$path" == p2 ]] || die "netem set {p1|p2} [delay 20ms] [jitter 5ms] [loss 0.1%]"
      local delay="20ms" jitter="0ms" loss="0%"
      while [[ $# -gt 0 ]]; do
        case "$1" in
          delay) delay="$2"; shift 2 ;;
          jitter) jitter="$2"; shift 2 ;;
          loss) loss="$2"; shift 2 ;;
          *) die "argumen netem tidak dikenal: $1" ;;
        esac
      done
      local ifaces=()
      if [[ "$path" == p1 ]]; then
        ifaces=(p1-pe1 p1-pe2)
      else
        ifaces=(p2-pe1 p2-pe2)
      fi
      local ifc
      for ifc in "${ifaces[@]}"; do
        ip netns exec "$path" tc qdisc replace dev "$ifc" root netem delay "$delay" "$jitter" loss "$loss"
        log "netem ${path}/${ifc}: delay=${delay} jitter=${jitter} loss=${loss}"
      done
      ;;
    *)
      die "pakai: $0 netem set p1|p2 [delay 20ms] [jitter 5ms] [loss 0.1%]  |  $0 netem clear"
      ;;
  esac
}

cmd_rollback() {
  need_root
  local ns
  for ns in pe1 p1 p2 pe2; do
    stop_frr_ns "$ns" || true
    rm -rf "/var/run/frr/${PREFIX}-${ns}" "/etc/frr/${PREFIX}-${ns}"
  done
  for ns in "${NS_LIST[@]}"; do
    ip netns delete "$ns" 2>/dev/null || true
  done
  destroy_pe_tunnels
  rm -rf "${RUN}"
  log "rollback selesai (netns/FRR/terowongan ${PREFIX} dihapus; paket FRR tidak di-uninstall)"
}

cmd_hint() {
  cat <<'HINTEOF'
Menyambungkan eNB/SGW nyata ke VRF S1 (USULAN, manual):

  1. Luluskan dulu: mpls-backhaul.sh verify + mpls-ce-tunnels.sh verify
     (ping 10.255.10.2 <-> 10.255.20.2 lewat VRF S1).
  2. Jangan menempelkan terowongan ke bridge produksi pada langkah yang
     sama dengan menghapus jalur S1 lama — siapkan rollback.
  3. Di vm-core-ran, ganti dummy ce-enb/ce-sgw dengan veth ke Docker
     bridge S1 (eNB / SGW-U, dan MME jika S1-AP ikut VRF S1).
  4. Pastikan rute S1-U/S1-AP masuk VRF, bukan table main host.
  5. Zeek: tap pe1-ce dan pe2-ce (tanpa label) plus tap S1-U lama.
  6. Tes: UE attach, keepalive, flow Zeek, p50 per segmen, lalu netem
     di P1 (failover ke P2) dan sebaliknya.
  7. MTU tun aplikasi 1360-1400 (VPC 1460 - GRE/VXLAN - GTP-U).

VPLS/EVPN: jangan diandalkan di FRR untuk S1. Pakai L3VPN VRF S1.
SR-MPLS: opsi, belum diaktifkan skrip (OSPF+LDP adalah default).
HINTEOF
}

usage() {
  cat <<USAGE
USULAN MPLS backhaul S1 di vm-mpls
  $0 setup      buat netns PE/P, veth berlabel, terowongan CE, FRR (OSPF+LDP+VPNv4)
  $0 status     ringkasan LDP/BGP/MPLS/terowongan
  $0 verify     modul, ldp, bgp ipv4 vpn, ip -f mpls route, ping CE lewat VRF
  $0 netem set p1|p2 [delay 20ms] [jitter 5ms] [loss 0.1%]
  $0 netem clear
  $0 rollback   hapus netns, daemon FRR, dan terowongan lab ini
  $0 hint       cara menyambung eNB/SGW nyata

Pasangan di vm-core-ran: /opt/lab5g/scripts/mpls-ce-tunnels.sh
Mode terowongan: TUN_MODE=gre|vxlan (default: metadata mpls-tunnel-mode, gre)
USAGE
}

cmd="${1:-}"
shift || true
case "$cmd" in
  setup) setup_topo ;;
  status) cmd_status ;;
  verify) cmd_verify ;;
  netem) cmd_netem "$@" ;;
  rollback) cmd_rollback ;;
  hint) cmd_hint ;;
  *) usage; exit 1 ;;
esac
