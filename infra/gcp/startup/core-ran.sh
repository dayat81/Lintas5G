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
# Backhaul MPLS (FRR PE/P + label) pindah ke vm-mpls (enable_mpls=true).
# VM ini hanya sisi CE: terowongan GRE/VXLAN tanpa label ke vm-mpls.
cat >/etc/sysctl.d/99-lab5g.conf <<'SYSCTL'
net.ipv4.ip_forward=1
net.ipv6.conf.all.forwarding=0
SYSCTL
sysctl --system || true

META=http://metadata.google.internal/computeMetadata/v1/instance/attributes
if curl -fsS -H "Metadata-Flavor: Google" "${META}/mpls-ce-script" -o /opt/lab5g/scripts/mpls-ce-tunnels.sh; then
  chmod 0755 /opt/lab5g/scripts/mpls-ce-tunnels.sh
else
  echo "mpls-ce-script metadata belum ada; salin manual dari paket Terraform" >>/var/log/lab5g/startup.log
fi

# Catatan peran. Secret tidak disimpan di sini.
cat >/opt/lab5g/README <<'NOTE'
Peran: vm-core-ran
Isi yang diharapkan (dipasang saat test run, bukan oleh startup ini):
  Open5GS 2.8.0 EPC CUPS, srsRAN 4G ZMQ (eNB + UE netns l5g-ue),
  Zeek tap bridge S1-U/SGi, proxy HTTP CONNECT :18080 di netns UE,
  keepalive ping dari UE (wajib, UE tidak boleh idle), Vector ke vm-obs:6000.

  USULAN backhaul MPLS S1 (jika enable_mpls=true): FRR di vm-mpls.
  Sisi CE di VM ini: /opt/lab5g/scripts/mpls-ce-tunnels.sh setup
  (GRE/VXLAN tanpa label ke PE1/PE2; tidak dijalankan otomatis).
  MTU terowongan 1400; tun aplikasi 1360-1400 (VPC 1460 - GRE - GTP-U).

Proxy harus bind di netns UE dan keluar lewat tun_srsue.
NOTE

# --- Sesi GUI (gui_session=true): ambil skrip dari bucket runs, pasang unit systemd core, start non-blocking. ---
# Idempotent: startup-script jalan di setiap boot; unit juga enabled sehingga bring-up ulang setelah reboot.
GUI_MD=http://metadata.google.internal/computeMetadata/v1/instance/attributes
if [ "$(curl -fsS -H 'Metadata-Flavor: Google' "$GUI_MD/gui-session" 2>/dev/null || echo false)" = "true" ]; then
  GUI_BUCKET=$(curl -fsS -H 'Metadata-Flavor: Google' "$GUI_MD/lab5g-bucket" 2>/dev/null || true)
  GCLOUD=$(command -v gcloud || echo /snap/bin/gcloud)
  for i in $(seq 1 30); do
    "$GCLOUD" storage cp -r "gs://$GUI_BUCKET/gui/*" /opt/lab5g/ >>/var/log/lab5g/startup.log 2>&1 && break
    sleep 10
  done
  chmod 0755 /opt/lab5g/vnc/*.sh /opt/lab5g/vnc/*.py /opt/lab5g/sesi-c/*.sh /opt/lab5g/sesi-c/*.py 2>/dev/null || true
  cat >/etc/systemd/system/lab5g-gui-core.service <<'UNIT'
[Unit]
Description=Lab5G GUI session bring-up (core)
After=network-online.target docker.service
Wants=network-online.target
[Service]
Type=oneshot
RemainAfterExit=yes
TimeoutStartSec=infinity
ExecStart=/bin/bash /opt/lab5g/vnc/gui-core-up.sh
[Install]
WantedBy=multi-user.target
UNIT
  systemctl daemon-reload
  systemctl enable lab5g-gui-core.service
  systemctl start --no-block lab5g-gui-core.service
  echo "gui session: lab5g-gui-core.service started" >>/var/log/lab5g/startup.log
fi

touch /opt/lab5g/.bootstrap-complete
date -u +"bootstrap complete %FT%TZ" >>/var/log/lab5g/startup.log
