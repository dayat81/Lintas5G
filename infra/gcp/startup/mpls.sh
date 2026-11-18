#!/bin/bash
# Startup vm-mpls: chrony + modul MPLS + skrip backhaul FRR.
# Topologi PE1/P1/P2/PE2 tidak di-setup otomatis (jalankan mpls-backhaul.sh setup).
# Tidak menginstal Docker. Tidak mengisi kredensial.
set -euxo pipefail
export DEBIAN_FRONTEND=noninteractive

install -d -m 0755 \
  /opt/lab5g \
  /opt/lab5g/scripts \
  /opt/lab5g/mpls \
  /var/lib/lab5g/runs \
  /var/log/lab5g

apt-get update -y
apt-get install -y chrony ca-certificates curl jq python3 iproute2 \
  iputils-ping traceroute tcpdump bridge-utils procps

cat >/etc/chrony/chrony.conf <<'CHRONY'
server metadata.google.internal iburst prefer
driftfile /var/lib/chrony/chrony.drift
ntsdumpdir /var/lib/chrony
logdir /var/log/chrony
maxupdateskew 100.0
makestep 1.0 3
rtcsync
leapsectz right/UTC
CHRONY
systemctl enable chrony
systemctl restart chrony

# Modul mpls_router sering tidak ada di kernel bawaan Ubuntu 22.04 GCP.
if ! modprobe mpls_router 2>/dev/null; then
  apt-get install -y "linux-modules-extra-$(uname -r)" || apt-get install -y linux-modules-extra-gcp || true
  modprobe mpls_router 2>/dev/null || true
fi
modprobe mpls_iptunnel 2>/dev/null || true
modprobe mpls_gso 2>/dev/null || true

cat >/etc/modules-load.d/lab5g-mpls.conf <<'MOD'
mpls_router
mpls_iptunnel
MOD
cat >/etc/sysctl.d/99-lab5g-mpls.conf <<'SYSCTL'
net.ipv4.ip_forward=1
net.ipv6.conf.all.forwarding=0
net.mpls.platform_labels=65535
net.ipv4.conf.all.rp_filter=0
net.ipv4.conf.default.rp_filter=0
SYSCTL
sysctl --system || true

META=http://metadata.google.internal/computeMetadata/v1/instance/attributes
if curl -fsS -H "Metadata-Flavor: Google" "${META}/mpls-backhaul-script" -o /opt/lab5g/scripts/mpls-backhaul.sh; then
  chmod 0755 /opt/lab5g/scripts/mpls-backhaul.sh
else
  echo "mpls-backhaul-script metadata belum ada; salin manual dari paket Terraform" >>/var/log/lab5g/startup.log
fi

if lsmod | grep -q '^mpls_router'; then
  echo "mpls_router loaded" >/opt/lab5g/mpls-module-status
else
  echo "mpls_router NOT loaded after linux-modules-extra attempt" >/opt/lab5g/mpls-module-status
fi
lsmod | grep -E '^mpls' >>/opt/lab5g/mpls-module-status || true

cat >/opt/lab5g/README <<'NOTE'
Peran: vm-mpls
FRR PE1 / P1 / P2 / PE2 berjalan di netns di VM ini. Label MPLS hanya
di veth inti (PE-P, P-PE). Sisi CE adalah terowongan GRE (gretap) atau
VXLAN tanpa label ke vm-core-ran (eNB di satu terowongan, SGW di terowongan lain).

Setup (tidak otomatis):
  sudo /opt/lab5g/scripts/mpls-backhaul.sh setup
  # lalu di vm-core-ran: sudo /opt/lab5g/scripts/mpls-ce-tunnels.sh setup

MTU:
  VPC GCP default 1460.
  gretap + key: ~28 byte (IP+GRE) + 14 byte Ethernet → MTU iface terowongan 1400.
  VXLAN: 50 byte (IP+UDP+VXLAN+Eth) → MTU iface 1400 juga aman.
  GTP-U di atas itu (~36 byte) → MTU tun aplikasi 1360-1400.
  Fragmentasi GTP-U sudah pernah terlihat di lab fisik jika MTU tidak diturunkan.
NOTE

touch /opt/lab5g/.bootstrap-complete
date -u +"bootstrap complete %FT%TZ" >>/var/log/lab5g/startup.log
