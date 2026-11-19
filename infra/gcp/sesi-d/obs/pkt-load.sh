#!/bin/bash
# vm-obs: session-scoped batch load of pkt_tap/pkt_phase (re-running a session replaces only that session), then print
# per-packet p50/p99 per condition/segment and coverage. usage: pkt-load.sh <csv_dir> <session>
set -e
C=${1:?csv_dir}; S=${2:?session}; D=${D:-/opt/lab5g/obs}; [ -f $D/.env ] && . $D/.env
CH=${CH:-"docker exec -i clickhouse clickhouse-client --user lab --password $CH_PASS"}
for t in pkt_tap pkt_phase pkt_conn; do
  [ -f $C/$t.csv ] || continue
  $CH -q "ALTER TABLE poc_latency.$t DELETE WHERE session = '$S' SETTINGS mutations_sync = 1"
  $CH -q "INSERT INTO poc_latency.$t FORMAT CSVWithNames" < $C/$t.csv
  echo "$t rows(session=$S)=$($CH -q "SELECT count() FROM poc_latency.$t WHERE session = '$S'")"
done
$CH -q "SELECT * FROM poc_latency.v_pkt_q WHERE session = '$S' ORDER BY dir, seg, cond FORMAT PrettyCompactMonoBlock"
$CH -q "SELECT * FROM poc_latency.v_pkt_cov WHERE session = '$S' ORDER BY dir, cond FORMAT PrettyCompactMonoBlock"
echo PKT_LOAD_DONE
