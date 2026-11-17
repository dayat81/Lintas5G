#!/usr/bin/env bash
# USULAN: backhaul MPLS untuk segmen S1 (S1-U GTP-U, opsional S1-AP)
# antara eNB dan SGW-U/MME di dalam vm-core-ran.
#
# Default: netns + veth di satu VM (VPC GCP tidak meneruskan frame berlabel
# MPLS antar-VM). Opsi multi-VM (MPLS-over-GRE/VXLAN) hanya didokumentasikan,
# tidak diaktifkan oleh skrip ini.
#
# Pakai:  mpls-backhaul.sh setup|status|verify|netem|rollback|hint
# Idempotent untuk setup. rollback hanya menghapus netns/FRR lab ini.
set -euo pipefail

PREFIX="lab5g-mpls"
BASE="/opt/lab5g/mpls"
CONF="${BASE}/frr"
RUN="/run/${PREFIX}"
NS_LIST=(pe1 p1 p2 pe2 ce-enb ce-sgw)
ASN=65001
RD="65001:1"
RT="65001:1"
VRF="S1"
VRF_TABLE=100
PLATFORM_LABELS=65535

# Addressing (USULAN, hanya di dalam host)
# Loopback: PE1 10.255.0.1, PE2 10.255.0.2, P1 10.255.0.11, P2 10.255.0.12
# P2P /30:
#   pe1-p1 10.255.1.0/30  pe1=.1  p1=.2
#   pe1-p2 10.255.1.4/30  pe1=.5  p2=.6
#   p1-pe2 10.255.1.8/30  p1=.9   pe2=.10
#   p2-pe2 10.255.1.12/30 p2=.13  pe2=.14
# CE VRF S1:
#   pe1-ce 10.255.10.1/24  ce-enb 10.255.10.2/24
#   pe2-ce 10.255.20.1/24  ce-sgw 10.255.20.2/24

log() { printf '%s %s\n' "$(date -u +%FT%TZ)" "$*" | tee -a /var/log/lab5g/mpls-backhaul.log; }
die() { log "ERROR: $*"; exit 1; }
need_root() { [[ $(id -u) -eq 0 ]] || die "jalankan sebagai root"; }

vtysh_ns() {
  local ns="$1"; shift
  # FRR instance -N memakai /etc/frr/<ns> dan /var/run/frr/<ns>.
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
  cat >/etc/modules-load.d/${PREFIX}.conf <<EOF
mpls_router
mpls_iptunnel
EOF
  cat >/etc/sysctl.d/99-${PREFIX}.conf <<EOF
net.mpls.platform_labels = ${PLATFORM_LABELS}
net.ipv4.ip_forward = 1
net.ipv4.conf.all.rp_filter = 0
net.ipv4.conf.default.rp_filter = 0
EOF
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

install_frr() {
  if ! command -v vtysh >/dev/null 2>&1; then
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -y
    apt-get install -y frr frr-pythontools
  fi
  # Jangan biarkan instansi host mengikat interface lab.
  systemctl disable --now frr 2>/dev/null || true
  # Izin instansi -N (direktori /etc/frr/<name> dan /var/run/frr/<name>).
  if [[ -f /etc/frr/vtysh.conf ]]; then
    grep -q '^service integrated-vtysh-config' /etc/frr/vtysh.conf \
      || echo 'service integrated-vtysh-config' >>/etc/frr/vtysh.conf
  fi
}

write_common_daemons() {
  local dest="$1" with_bgp="$2"
  cat >"${dest}/daemons" <<EOF
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
EOF
  cat >"${dest}/vtysh.conf" <<EOF
service integrated-vtysh-config
hostname $(basename "${dest}")
EOF
  chown -R frr:frr "${dest}" 2>/dev/null || true
}

write_frr_p() {
  local name="$1" lo="$2" if1="$3" ip1="$4" if2="$5" ip2="$6"
  local d="${CONF}/${name}"
  install -d -m 0750 "$d"
  write_common_daemons "$d" no
  cat >"${d}/frr.conf" <<EOF
! ${PREFIX} ${name} (P router) — IGP OSPF + LDP
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
EOF
  chown -R frr:frr "$d" 2>/dev/null || true
}

write_frr_pe() {
  local name="$1" lo="$2" peer="$3"
  local if1="$4" ip1="$5" if2="$6" ip2="$7"
  local cegw="$8" ceif="$9"
  local d="${CONF}/${name}"
  install -d -m 0750 "$d"
  write_common_daemons "$d" yes
  cat >"${d}/frr.conf" <<EOF
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
EOF
  chown -R frr:frr "$d" 2>/dev/null || true
}

link_frr_instance() {
  local ns="$1"
  local inst="${PREFIX}-${ns}"
  rm -rf "/etc/frr/${inst}"
  ln -sfn "${CONF}/${ns}" "/etc/frr/${inst}"
  install -d -o frr -g frr -m 0755 "/var/run/frr/${inst}" "${RUN}/${ns}"
}

start_frr_ns() {
  local ns="$1"
  local inst="${PREFIX}-${ns}"
  link_frr_instance "$ns"
  # Hentikan daemon lama instansi ini jika ada.
  stop_frr_ns "$ns" || true
  local daemons=(zebra ospfd ldpd)
  if grep -q '^bgpd=yes' "${CONF}/${ns}/daemons"; then
    daemons+=(bgpd)
  fi
  local d
  for d in "${daemons[@]}"; do
    ip netns exec "$ns" "/usr/lib/frr/${d}" -d -N "$inst" \
      || die "gagal menjalankan ${d} di netns ${ns}"
  done
  sleep 1
  ip netns exec "$ns" vtysh -N "$inst" -f "${CONF}/${ns}/frr.conf" \
    || log "peringatan: vtysh -f di ${ns} mengembalikan non-zero"
}

stop_frr_ns() {
  local ns="$1"
  local inst="${PREFIX}-${ns}"
  local pidfile
  for pidfile in /var/run/frr/"${inst}"/*.pid; do
    [[ -f "$pidfile" ]] || continue
    kill "$(cat "$pidfile")" 2>/dev/null || true
  done
  pkill -f "/usr/lib/frr/.* -N ${inst}" 2>/dev/null || true
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
  ensure_veth pe1 pe1-ce ce-enb ce-pe1
  ensure_veth pe2 pe2-ce ce-sgw ce-pe2

  # VRF S1 di PE (CE-facing masuk VRF, core-facing tetap global).
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
  addr_up ce-enb ce-pe1 10.255.10.2/24
  addr_up pe2 pe2-ce 10.255.20.1/24
  addr_up ce-sgw ce-pe2 10.255.20.2/24

  ip netns exec ce-enb ip route replace 10.255.20.0/24 via 10.255.10.1
  ip netns exec ce-sgw ip route replace 10.255.10.0/24 via 10.255.20.1

  # MPLS input hanya di antarmuka core (berlabel), bukan di CE.
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
  log "setup selesai. Jalankan: $0 verify"
}

write_docs() {
  cat >"${BASE}/README" <<'EOF'
USULAN backhaul MPLS S1 (tidak mengubah lab on-prem).

Topologi default (semua netns di vm-core-ran):

  eNB / ce-enb -- PE1 --+-- P1 --+-- PE2 -- ce-sgw / SGW-U, MME
                        +-- P2 --+

Alasan satu VM: VPC GCP tidak meneruskan frame berlabel MPLS antar-VM.

Opsi multi-VM (belum diimplementasikan skrip):
  router di VM terpisah, MPLS-over-GRE atau VXLAN di atas VPC.
  Trade-off MTU: MTU VPC biasanya 1460; dikurangi GTP-U, 1-2 label MPLS
  (4-8 byte), dan header GRE (~24 byte). MTU aplikasi/tun 1400 atau lebih
  kecil. Fragmentasi GTP-U sudah pernah terlihat di lab saat ini (FAKTA).

Pengukuran Zeek:
  - pe1-ce  : PE1-ingress (sisi eNB, tanpa label) — awal segmen transport
  - pe2-ce  : PE2-egress  (sisi SGW, tanpa label) — akhir segmen transport
  - tap S1-U lama di bridge/core (GTP-U)
  Breakdown latency: RAN | transport MPLS | core | SGi
  Analisis GTP lebih andal di sisi CE/VRF (tanpa label). Dukungan analyzer
  MPLS di Zeek perlu dicek per versi; jangan andalkan tap di link P berlabel
  tanpa uji parser.

Injeksi gangguan:
  mpls-backhaul.sh netem set p1 delay 20ms jitter 5ms loss 0.1%
  mpls-backhaul.sh netem clear

Kabel ke eNB/SGW nyata: lihat `mpls-backhaul.sh hint`.
Jangan menempelkan veth ke bridge produksi sebelum verify CE dummy lulus
dan rencana rollback sudah siap. Keepalive UE tetap wajib.

SR-MPLS adalah opsi (FRR pathd / IS-IS-SR); default skrip: OSPF + LDP.
VPLS/EVPN tidak didukung FRR secara penuh — risiko jika butuh L2 S1.
EOF

  cat >"${BASE}/zeek-taps.txt" <<EOF
# Titik tap yang diusulkan (interface di netns)
# ns        iface     peran
pe1         pe1-ce    PE1-ingress eNB side (unlabeled, VRF ${VRF})
pe2         pe2-ce    PE2-egress  SGW side (unlabeled, VRF ${VRF})
# plus tap S1-U lama di stack Open5GS/srsRAN
EOF
}

cmd_status() {
  echo "== netns =="
  ip netns list | grep -E 'pe1|pe2|^p1|^p2|ce-enb|ce-sgw' || true
  local ns
  for ns in pe1 p1 p2 pe2; do
    echo "== ${ns} mpls route =="
    ip netns exec "$ns" ip -f mpls route || true
    echo "== ${ns} ldp / ospf / bgp =="
    vtysh_ns "$ns" -c "show mpls ldp neighbor" 2>/dev/null || true
    vtysh_ns "$ns" -c "show ip ospf neighbor" 2>/dev/null || true
    if [[ "$ns" == pe1 || "$ns" == pe2 ]]; then
      vtysh_ns "$ns" -c "show bgp ipv4 vpn summary" 2>/dev/null || true
      vtysh_ns "$ns" -c "show bgp l2vpn evpn summary" 2>/dev/null || true
    fi
  done
}

cmd_verify() {
  local rc=0
  need_root
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
  echo "== FRR: show bgp l2vpn (diharapkan kosong / tidak dipakai) =="
  vtysh_ns pe1 -c "show bgp l2vpn evpn summary" 2>/dev/null || true
  echo "== traceroute CE-eNB -> CE-SGW (harus lewat VRF S1) =="
  ip netns exec ce-enb traceroute -n -w 2 -q 1 10.255.20.2 || true
  echo "== ping CE =="
  if ip netns exec ce-enb ping -c 3 -W 2 10.255.20.2; then
    log "ping CE-eNB -> CE-SGW OK"
  else
    log "ping CE gagal — cek LDP/BGP/VRF"
    rc=1
  fi
  echo
  echo "Setelah eNB/SGW nyata tersambung ke VRF S1: pastikan UE attach tetap OK"
  echo "dan keepalive UE tetap berjalan. Rollback: $0 rollback"
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
  rm -rf "${RUN}"
  # Konfigurasi di ${BASE} dipertahankan untuk inspeksi.
  log "rollback selesai (netns/FRR ${PREFIX} dihapus; paket FRR tidak di-uninstall)"
}

cmd_hint() {
  cat <<'EOF'
Menyambungkan eNB/SGW nyata ke VRF S1 (USULAN, manual):

  1. Luluskan dulu: mpls-backhaul.sh verify (ping CE dummy 10.255.10.2 <-> 10.255.20.2).
  2. Jangan menempelkan veth ke bridge produksi pada langkah yang sama dengan
     menghapus jalur S1 lama — siapkan rollback.
  3. Pindahkan pe1-ce ke netns/bridge eNB, atau ganti dummy ce-enb dengan
     veth ke Docker bridge S1 yang lama. Hal yang sama untuk pe2-ce ke SGW-U
     (dan MME jika S1-AP ikut di VRF S1).
  4. Pastikan rute S1-U/S1-AP (contoh 172.x eNB/SGW) masuk VRF, bukan table
     main host, agar GTP-U tidak bocor melewati jalus non-MPLS.
  5. Zeek: tap pe1-ce dan pe2-ce (tanpa label) plus tap S1-U lama.
  6. Tes: UE attach, keepalive, flow Zeek, p50 per segmen, lalu netem di P1
     (failover ke P2) dan sebaliknya.
  7. Opsi multi-VM: bungkus label MPLS di GRE/VXLAN karena VPC tidak
     meneruskan MPLS. Turunkan MTU tun aplikasi ke 1400 atau lebih kecil.

VPLS/EVPN: jangan diandalkan di FRR untuk S1. Pakai L3VPN VRF S1.
SR-MPLS: opsi, belum diaktifkan skrip (OSPF+LDP adalah default).
EOF
}

usage() {
  cat <<EOF
USULAN MPLS backhaul S1 di vm-core-ran
  $0 setup      buat netns, veth, FRR (OSPF+LDP+VPNv4), idempotent
  $0 status     ringkasan LDP/BGP/MPLS
  $0 verify     ldp neighbor, bgp ipv4 vpn, ip -f mpls route, traceroute, ping CE
  $0 netem set p1|p2 [delay 20ms] [jitter 5ms] [loss 0.1%]
  $0 netem clear
  $0 rollback   hapus netns dan daemon FRR lab ini
  $0 hint       cara menyambung eNB/SGW nyata
EOF
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
