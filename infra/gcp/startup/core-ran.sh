#!/bin/bash
# Startup vm-core-ran: Docker + chrony + direktori lab.
# Tidak mengisi kredensial. Stack Open5GS/srsRAN/Zeek dipasang saat test run.
set -euxo pipefail
export DEBIAN_FRONTEND=noninteractive

install -d -m 0755 \
  /opt/lab5g \
  /opt/lab5g/open5gs \
  /opt/lab5g/srsran \
  /opt/lab5g/zeek \
  /opt/lab5g/proxy \
  /opt/lab5g/vector \
  /opt/lab5g/scripts \
  /opt/lab5g/mpls \
  /var/lib/lab5g/runs \
  /var/log/lab5g

# Jam: NTP Google (metadata.google.internal). Target skew sub-ms.
apt-get update -y
apt-get install -y chrony ca-certificates curl gnupg lsb-release jq python3

cat >/etc/chrony/chrony.conf <<'CHRONY'
# Lab 5G latency PoC — sumber waktu resmi GCP.
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

# Docker (repo resmi).
if ! command -v docker >/dev/null 2>&1; then
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
  chmod a+r /etc/apt/keyrings/docker.asc
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
    >/etc/apt/sources.list.d/docker.list
  apt-get update -y
  apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
fi
systemctl enable --now docker

# IP forwarding untuk netns UE / SNAT SGi di dalam host.
# Modul MPLS dimuat sekarang; topologi FRR tidak di-setup otomatis
# (USULAN: jalankan /opt/lab5g/scripts/mpls-backhaul.sh setup saat test run).
modprobe mpls_router 2>/dev/null || true
modprobe mpls_iptunnel 2>/dev/null || true
cat >/etc/modules-load.d/lab5g-mpls.conf <<'MOD'
mpls_router
mpls_iptunnel
MOD
cat >/etc/sysctl.d/99-lab5g.conf <<'SYSCTL'
net.ipv4.ip_forward=1
net.ipv6.conf.all.forwarding=0
net.mpls.platform_labels=65535
SYSCTL
sysctl --system || true

META=http://metadata.google.internal/computeMetadata/v1/instance/attributes/mpls-backhaul-script
if curl -fsS -H "Metadata-Flavor: Google" "${META}" -o /opt/lab5g/scripts/mpls-backhaul.sh; then
  chmod 0755 /opt/lab5g/scripts/mpls-backhaul.sh
else
  echo "mpls-backhaul-script metadata belum ada; salin manual dari paket Terraform" >>/var/log/lab5g/startup.log
fi

# Catatan peran. Secret tidak disimpan di sini.
cat >/opt/lab5g/README <<'NOTE'
Peran: vm-core-ran
Isi yang diharapkan (dipasang saat test run, bukan oleh startup ini):
  Open5GS 2.8.0 EPC CUPS, srsRAN 4G ZMQ (eNB + UE netns l5g-ue),
  Zeek tap bridge S1-U/SGi, proxy HTTP CONNECT :18080 di netns UE,
  keepalive ping dari UE (wajib, UE tidak boleh idle), Vector ke vm-obs:6000.

  USULAN backhaul MPLS S1: /opt/lab5g/scripts/mpls-backhaul.sh setup
  (tidak dijalankan otomatis). Default: netns di VM ini, OSPF+LDP+L3VPN VRF S1.

Proxy harus bind di netns UE dan keluar lewat tun_srsue.
NOTE

touch /opt/lab5g/.bootstrap-complete
date -u +"bootstrap complete %FT%TZ" >>/var/log/lab5g/startup.log
