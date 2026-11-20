#!/bin/bash
# run-behave.sh [tag]: official CAMARA Test_definitions (unchanged .feature files) via behave against qod-adapter 0.1.3 (mock backend).
# Starts the reference HTTPS sink (with PRIVATE_KEY_JWT token endpoint) + the adapter (dev venv, tests/conformance config).
set -u; H=$(cd "$(dirname "$0")" && pwd); A=/workspace/qod-adapter-013; T=/tmp/qod-conf; PY=/workspace/qod-adapter/.venv/bin/python
TAG=${1:-run}; OUT=$H/results/$TAG; mkdir -p $OUT; umask 077; mkdir -p $T; rm -f $T/sink.jsonl $T/events.jsonl
[ -f $T/sink.pem ] || { bash $A/tools/mkcert.sh $T/certs 127.0.0.1 >/dev/null; cp $T/certs/sink-ca.pem $T/certs/sink.pem $T/certs/sink.key $T/; }
pkill -f "tools/sink.py 127.0.0.1 18443" 2>/dev/null; pkill -f "port 18080" 2>/dev/null; sleep 0.5
(cd $A && QOD_CONFIG=$A/tests/conformance/adapter.yaml exec $PY -m uvicorn qod_adapter.app:app --host 127.0.0.1 --port 18080 --log-level warning --no-access-log > $T/adapter.out 2>&1) &
for i in $(seq 60); do curl -s -m1 http://127.0.0.1:18080/healthz >/dev/null 2>&1 && break; sleep 0.25; done
SINK_JWKS=$T/sink-jwks.json SINK_CLIENT_ID=conf-b-notify SINK_TOKEN_URI=https://127.0.0.1:18443/token $PY $A/tools/sink.py 127.0.0.1 18443 $T/sink.pem $T/sink.key $T/sink.jsonl > $T/sink.out 2>&1 &
sleep 1
cd $H/behave && sha256sum -c features.sha256 > $OUT/features-sha256-check.txt 2>&1 || { echo "FEATURE FILES CHANGED"; exit 1; }
QOD_BASE=http://127.0.0.1:18080 QOD_SINK_URL=https://127.0.0.1:18443/sink QOD_SINK_LOG=$T/sink.jsonl \
  $PY -m behave --no-capture -f json.pretty -o $OUT/behave.json -f progress -o $OUT/progress.txt --junit --junit-directory $OUT/junit -f plain -o $OUT/plain.txt > $OUT/stdout.txt 2>&1
rc=$?; tail -4 $OUT/progress.txt; $PY $H/pkjwt_check.py > $OUT/pkjwt-check.json 2>&1; echo "pkjwt: $(grep verdict $OUT/pkjwt-check.json)"
$PY $H/summarize.py $OUT/behave.json > $OUT/summary.md; cat $OUT/summary.md | head -40
pkill -f "tools/sink.py 127.0.0.1 18443"; pkill -f "port 18080"; exit $rc
