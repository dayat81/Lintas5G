#!/bin/bash
# Startup vm-obs: Docker + chrony + direktori ClickHouse/Grafana.
# Tidak mengisi kredensial. Bind layanan hanya ke IP internal / 127.0.0.1 saat test run.
set -euxo pipefail
export DEBIAN_FRONTEND=noninteractive

install -d -m 0755 \
  /opt/lab5g \
  /opt/lab5g/clickhouse \
  /opt/lab5g/grafana \
  /opt/lab5g/vector \
  /opt/lab5g/dashboards \
  /var/lib/lab5g/clickhouse \
  /var/lib/lab5g/grafana \
  /var/log/lab5g

apt-get update -y
apt-get install -y chrony ca-certificates curl gnupg lsb-release jq python3

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

cat >/opt/lab5g/README <<'NOTE'
Peran: vm-obs
Isi yang diharapkan (dipasang saat test run):
  ClickHouse database poc_latency (8123/9000, bind internal saja),
  Grafana (3000, bind 127.0.0.1; akses lewat IAP tunnel),
  sink Vector di :6000 dari vm-core-ran.
Jangan publish 3000/8123/9000 ke internet.
NOTE

touch /opt/lab5g/.bootstrap-complete
date -u +"bootstrap complete %FT%TZ" >>/var/log/lab5g/startup.log
