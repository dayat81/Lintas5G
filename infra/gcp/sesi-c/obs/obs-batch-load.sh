#!/bin/bash
# vm-obs: batch load CSV (dari obs-prep.py di box) ke ClickHouse, lalu render dashboard ke PNG via grafana-image-renderer.
# Usage: obs-batch-load.sh <csv_dir>
set -e
C=${1:?csv_dir}; D=/opt/lab5g/obs; . $D/.env
CH="docker exec -i clickhouse clickhouse-client --user lab --password $CH_PASS"
for t in probes adapter iperf zeek_conn zeek_capture_loss zeek_tunnel flow_gbr; do
  [ -f $C/$t.csv ] || continue
  $CH -q "TRUNCATE TABLE poc_latency.$t"
  $CH --input_format_null_as_default=1 --date_time_input_format=best_effort -q "INSERT INTO poc_latency.$t FORMAT CSVWithNames" < $C/$t.csv
  echo "$t rows=$($CH -q "SELECT count() FROM poc_latency.$t")"
done
$CH -q "SELECT * FROM poc_latency.v_quantiles ORDER BY session, metric, cond FORMAT PrettyCompactMonoBlock"
$CH -q "SELECT * FROM poc_latency.v_cv ORDER BY metric, cond FORMAT PrettyCompactMonoBlock"
mkdir -p $D/png
curl -s -u admin:$GF_PASS "http://127.0.0.1:3000/api/search?query=Lintas5G" ; echo
curl -s -u admin:$GF_PASS -o $D/png/dashboard-fase0.png "http://127.0.0.1:3000/render/d/lintas5g-fase0/lintas5g-fase0?orgId=1&width=1800&height=2400&kiosk&timeout=90&from=now-1h&to=now"
file $D/png/dashboard-fase0.png; ls -la $D/png
echo OBS_LOAD_DONE
