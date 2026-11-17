#!/bin/bash
# Startup vm-emu: Docker + chrony + KVM + direktori emulator.
# http_proxy mengarah ke proxy CONNECT di vm-core-ran (disisipkan Terraform).
# Tidak mengisi kredensial. Image Android/Play dipasang saat test run.
set -euxo pipefail
export DEBIAN_FRONTEND=noninteractive

CORE_PROXY_HOST="${core_proxy_host}"
CORE_PROXY_PORT="${core_proxy_port}"
PROXY_URL="http://$${CORE_PROXY_HOST}:$${CORE_PROXY_PORT}"

install -d -m 0755 \
  /opt/lab5g \
  /opt/lab5g/emulator \
  /opt/lab5g/avd \
  /var/lib/lab5g/runs \
  /var/log/lab5g

apt-get update -y
apt-get install -y chrony ca-certificates curl gnupg lsb-release jq python3 cpu-checker qemu-kvm

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

# Nested virtualization: pastikan /dev/kvm ada.
modprobe kvm_intel || modprobe kvm || true
if [[ -e /dev/kvm ]]; then
  chmod 666 /dev/kvm || true
  echo "kvm-ok" >/opt/lab5g/kvm-status
  kvm-ok >/opt/lab5g/kvm-status 2>&1 || true
else
  echo "KVM tidak tersedia; emulator akan sangat lambat tanpa nested virt." >/opt/lab5g/kvm-status
fi

# Proxy default host mengarah ke jalur lab (UE). Setting di dalam Android
# emulator diatur saat test run; ini hanya untuk host dan dokumentasi.
cat >/etc/profile.d/lab5g-proxy.sh <<PROXY
# Proxy lab (HTTP CONNECT di vm-core-ran:18080). Tidak berisi kredensial.
export LAB5G_HTTP_PROXY="$${PROXY_URL}"
export LAB5G_CORE_PROXY_HOST="$${CORE_PROXY_HOST}"
export LAB5G_CORE_PROXY_PORT="$${CORE_PROXY_PORT}"
PROXY
chmod 0644 /etc/profile.d/lab5g-proxy.sh
echo "$${PROXY_URL}" >/opt/lab5g/http-proxy.url

cat >/opt/lab5g/README <<NOTE
Peran: vm-emu
Nested virtualization harus aktif. GPU emulator: swiftshader_indirect.
AVD: hw.keyboard=yes, x11vnc bind 127.0.0.1 (akses lewat IAP :5900).
http_proxy global emulator: $${PROXY_URL}
Jangan pasang IP publik dan jangan buka VNC ke 0.0.0.0.
NOTE

touch /opt/lab5g/.bootstrap-complete
date -u +"bootstrap complete %FT%TZ" >>/var/log/lab5g/startup.log
