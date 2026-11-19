#!/bin/bash
# vm-obs: ClickHouse + Grafana (+ plugin ClickHouse) + grafana-image-renderer di Docker. Tidak ada port publik:
# ClickHouse tidak dipublish (hanya jaringan docker), Grafana dipublish ke 127.0.0.1:3000 (akses via IAP/SSH tunnel).
# Password acak dibuat di VM (0600), tidak dicetak.
set -e
D=/opt/lab5g/obs; mkdir -p $D/prov/datasources $D/prov/dashboards $D/dash $D/data
for i in $(seq 1 60); do [ -f /opt/lab5g/.bootstrap-complete ] && command -v docker >/dev/null && break; sleep 5; done
umask 077; [ -f $D/.env ] || { echo "CH_PASS=$(openssl rand -hex 16)" > $D/.env; echo "GF_PASS=$(openssl rand -hex 16)" >> $D/.env; }; umask 022
. $D/.env
cat > $D/prov/datasources/ch.yaml <<'Y'
apiVersion: 1
datasources:
- name: ClickHouse
  uid: ch
  type: grafana-clickhouse-datasource
  isDefault: true
  jsonData: {host: clickhouse, server: clickhouse, port: 9000, protocol: native, username: lab, defaultDatabase: poc_latency}
  secureJsonData: {password: $CH_PASS}
Y
cat > $D/prov/dashboards/d.yaml <<'Y'
apiVersion: 1
providers:
- name: lab5g
  type: file
  options: {path: /var/lib/grafana/dashboards}
Y
cp /opt/lab5g/sesi-c/obs/dashboard-fase0.json $D/dash/
[ -f /opt/lab5g/sesi-d/obs/dashboard-pktlat.json ] && cp /opt/lab5g/sesi-d/obs/dashboard-pktlat.json $D/dash/   # Sesi D per-packet
docker network create lab5g-obs 2>/dev/null || true
docker rm -f clickhouse grafana renderer 2>/dev/null || true
docker run -d --name clickhouse --network lab5g-obs --ulimit nofile=262144:262144 -e CLICKHOUSE_USER=lab -e CLICKHOUSE_PASSWORD=$CH_PASS \
  -e CLICKHOUSE_DEFAULT_ACCESS_MANAGEMENT=0 -v $D/data:/var/lib/clickhouse clickhouse/clickhouse-server:24.8
docker run -d --name renderer --network lab5g-obs grafana/grafana-image-renderer:latest
docker run -d --name grafana --network lab5g-obs -p 127.0.0.1:3000:3000 -e CH_PASS=$CH_PASS -e GF_SECURITY_ADMIN_PASSWORD=$GF_PASS \
  -e GF_INSTALL_PLUGINS=grafana-clickhouse-datasource -e GF_RENDERING_SERVER_URL=http://renderer:8081/render \
  -e GF_RENDERING_CALLBACK_URL=http://grafana:3000/ -e GF_ANALYTICS_REPORTING_ENABLED=false -e GF_USERS_ALLOW_SIGN_UP=false \
  -v $D/prov:/etc/grafana/provisioning -v $D/dash:/var/lib/grafana/dashboards grafana/grafana:11.3.0
for i in $(seq 1 60); do docker exec clickhouse clickhouse-client --user lab --password "$CH_PASS" -q "SELECT 1" >/dev/null 2>&1 && break; sleep 2; done
docker exec -i clickhouse clickhouse-client --user lab --password "$CH_PASS" --multiquery < /opt/lab5g/sesi-c/obs/obs-schema.sql
[ -f /opt/lab5g/sesi-d/obs/pkt-schema.sql ] && docker exec -i clickhouse clickhouse-client --user lab --password "$CH_PASS" --multiquery < /opt/lab5g/sesi-d/obs/pkt-schema.sql
for i in $(seq 1 90); do curl -sf http://127.0.0.1:3000/api/health >/dev/null && break; sleep 2; done
curl -s http://127.0.0.1:3000/api/health; echo; docker ps --format '{{.Names}} {{.Image}} {{.Ports}}'
ss -ltnp | grep -E ':3000|:8123|:9000' || true
echo OBS_SETUP_DONE
