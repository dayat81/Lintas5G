#!/bin/bash
# provision.sh check|apply  -- one-time STATIC QoS provisioning of the Lintas5G offline lab (idempotent IaC).
# Converges 4 components (0 = lab subscribers from the UE confs) to lab-qos.yaml: (1) PCF qos_profiles in n5-lab:/etc/open5gs/pcf.yaml (+ pcfd restart only if changed),
# (2) subscriber PCC rules in Mongo (api-prio 5QI 69 + flow-less QoD 5QI templates), (3) gNB slice.conf (re-read by gNB on mtime).
# check: report drift, change nothing (exit 3 on drift). apply: converge, then re-check (exit 0 = in sync). Output has no IMSI/secrets.
set -u; H=$(cd "$(dirname "$0")" && pwd); M=${1:-check}; CFG=${CFG:-$H/lab-qos.yaml}
PY=/workspace/qod-adapter/.venv/bin/python; DK="sudo docker"; T=$(mktemp -d); trap 'rm -rf $T' EXIT; DRIFT=0
# (1) PCF
$DK exec n5-lab cat /etc/open5gs/pcf.yaml > $T/pcf.cur || { echo '{"component":"pcf","error":"n5-lab down"}'; exit 1; }
$PY $H/render.py pcf $CFG $T/pcf.cur > $T/pcf.want
if cmp -s $T/pcf.cur $T/pcf.want; then echo '{"component":"pcf-qos_profiles","drift":0}'
else DRIFT=1; echo "{\"component\":\"pcf-qos_profiles\",\"drift\":1,\"diff_lines\":$(diff $T/pcf.cur $T/pcf.want | grep -c '^[<>]')}"
  if [ $M = apply ]; then
    $DK cp $T/pcf.want n5-lab:/etc/open5gs/pcf.yaml
    $DK exec n5-lab sh -c 'pkill -x open5gs-pcfd; sleep 1; nohup /usr/bin/open5gs-pcfd > /var/log/open5gs/pcf.out 2>&1 & sleep 2; pgrep -x open5gs-pcfd >/dev/null && echo "{\"component\":\"pcf-qos_profiles\",\"action\":\"written+pcfd_restarted\"}"'
  fi
fi
# (2) subscriber DB
PID=$($DK inspect -f '{{.State.Pid}}' n5-lab)
for s in $(seq 20); do sudo nsenter -t $PID -n $PY -c "from pymongo import MongoClient as M; M('mongodb://127.0.0.1',serverSelectionTimeoutMS=500).server_info()" >/dev/null 2>&1 && break; sleep 0.5; done
sudo nsenter -t $PID -n $PY $H/provision_subs.py $M $CFG; rc=$?; [ $rc = 3 ] && DRIFT=1; [ $rc != 0 ] && [ $rc != 3 ] && exit $rc
sudo nsenter -t $PID -n $PY $H/provision_db.py $M $CFG; rc=$?; [ $rc = 3 ] && DRIFT=1; [ $rc != 0 ] && [ $rc != 3 ] && exit $rc
# (3) slice.conf
SF=$($PY -c "import yaml;print(yaml.safe_load(open('$CFG'))['slice']['file'])")
$PY $H/render.py slice $CFG > $T/slice.want
if cmp -s $SF $T/slice.want; then echo '{"component":"gnb-slice.conf","drift":0}'
else DRIFT=1; echo "{\"component\":\"gnb-slice.conf\",\"drift\":1,\"want\":\"$(tr '\n' ' ' < $T/slice.want)\"}"
  [ $M = apply ] && cp $T/slice.want $SF && echo '{"component":"gnb-slice.conf","action":"written (gNB re-reads on mtime)"}'
fi
if [ $M = apply ] && [ $DRIFT = 1 ]; then echo "--- re-check after apply"; exec "$0" check; fi
echo "{\"result\":\"$([ $DRIFT = 0 ] && echo in_sync || echo drift)\",\"mode\":\"$M\"}"; [ $DRIFT = 0 ] || exit 3
