#!/bin/bash
# lab-up.sh [up|adapter|sink|sync-ips|status] -- rebuild the Lintas5G offline QoD lab from scratch with ONE script (r4 baseline).
#  up: stop n5-* -> core (n5-lab + n5-mongo; DB volume n5-mongo-db created if missing) -> provision.sh apply (subscribers from UE
#      confs + static QoS IaC) -> gNB (slice-qosrel4, slice.conf) -> UEs (attach + keepalive 1 s) -> adapter 0.1.3 (core netns,
#      loopback only) -> sink -> provision.sh check. After this, CAMARA sessions need no manual step (no DB/config edits per session/app).
# Images (local only): lintas5g/open5gs:2.8.0-qosrel (oai-n5-test/lab/img-open5gs, base build/core-base), lintas5g/oai-gnb:v3.0.0-slice-qosrel4
# (build/build-gnb.sh), lintas5g/qod-adapter:0.1.3 (qod-adapter-013).
set -u; H=$(cd "$(dirname "$0")" && pwd); LAB=/workspace/oai-n5-test; A=/workspace/qod-adapter-013; S=/workspace/qod-adapter/secrets
DK="sudo docker"; CORE_IMG=${CORE_IMG:-lintas5g/open5gs:2.8.0-qosrel}; GNB_IMG=${GNB_IMG:-lintas5g/oai-gnb:v3.0.0-slice-qosrel4}
AIMG=${AIMG:-lintas5g/qod-adapter:0.1.3}; N_UE=${N_UE:-2}; CPUS=${CPUS:-4-7}; CORE_CPUS=${CORE_CPUS:-0-3}
log() { echo "[$(date +%H:%M:%S)] $*"; }
sync_ips() { for i in $(seq $N_UE); do sudo cat $LAB/secrets/ue$i.ip > $S/ue$i.ip; chmod 600 $S/ue$i.ip; done; }
adapter() {
  mkdir -p $A/data $A/res/events && chmod 700 $A/data && chmod 755 $A/res/events
  local HIDE=""; for f in $S/ue*.conf $S/*.secret; do [ -f "$f" ] && HIDE="$HIDE -v /dev/null:/secrets/$(basename $f):ro"; done
  $DK rm -f n5-adapter >/dev/null 2>&1
  $DK run -d --name n5-adapter --network container:n5-lab --user $(id -u):$(id -g) --cap-drop ALL --cap-add NET_RAW --read-only --tmpfs /tmp \
    -v $S:/secrets:ro $HIDE --tmpfs /secrets/sinkcerts:ro,size=1k -v $A/config:/opt/qod-adapter/config:ro -v $A/data:/data -v $A/res/events:/export $AIMG >/dev/null
  for i in $(seq 40); do $DK exec n5-lab curl -s -m1 http://127.0.0.1:8080/healthz >/dev/null 2>&1 && break; sleep 0.5; done
  log "adapter: $($DK exec n5-lab curl -s -m2 http://127.0.0.1:8080/healthz)"
}
sink() {  # reference sink + PRIVATE_KEY_JWT token endpoint, core netns 127.0.0.1:8443 (log fase1-closeout/run/sink.jsonl: no tokens, hashes only)
  local P; P=$($DK inspect -f '{{.State.Pid}}' n5-lab); mkdir -p $H/../run
  sudo pkill -f "tools/sink.py 127.0.0.1 8443" 2>/dev/null; sleep 0.3
  sudo nsenter -t $P -n sudo -u $(id -un) env SINK_JWKS=$A/data/sink-jwks.json SINK_CLIENT_ID=lintas5g-qod-adapter SINK_TOKEN_URI=https://127.0.0.1:8443/token \
    nohup /workspace/qod-adapter/.venv/bin/python $A/tools/sink.py 127.0.0.1 8443 $S/sinkcerts/sink.pem $S/sinkcerts/sink.key $H/../run/sink.jsonl > $H/../run/sink.out 2>&1 &
  sleep 1.5; log "sink: $(cat $H/../run/sink.out)"
}
core() {
  log "stop old n5-*"; $DK rm -f n5-adapter n5-gnb n5-ue1 n5-ue2 n5-ue3 n5-mongo n5-lab >/dev/null 2>&1
  [ "${FRESH:-0}" = 1 ] && { $DK volume rm n5-mongo-db >/dev/null 2>&1; log "FRESH=1: removed DB volume n5-mongo-db (from-scratch rebuild)"; }
  $DK volume inspect n5-mongo-db >/dev/null 2>&1 || { $DK volume create n5-mongo-db >/dev/null; log "created empty volume n5-mongo-db"; }
  $DK run -d --name n5-lab --cpuset-cpus $CORE_CPUS --cap-add NET_ADMIN --cap-add NET_RAW --device /dev/net/tun \
    --sysctl net.ipv4.ip_forward=1 -e DEBUG_LOG=1 $CORE_IMG >/dev/null
  $DK run -d --name n5-mongo --network container:n5-lab --cpuset-cpus $CORE_CPUS -v n5-mongo-db:/data/db mongo:6 --bind_ip 127.0.0.1 >/dev/null
  $DK exec n5-lab bash /opt/lintas5g/core-up.sh | sed 's/^/core: /'
  log "provision apply (before any UE attaches)"; bash $H/provision.sh apply | sed 's/^/prov: /'
}
ran() {
  $DK rm -f n5-gnb n5-ue1 n5-ue2 n5-ue3 >/dev/null 2>&1
  $DK run -d --name n5-gnb --network container:n5-lab --cap-drop ALL --cpuset-cpus $CPUS -v $LAB/slice:/opt/slice:ro -e OAI_DL_SLICE_CONF=/opt/slice/slice.conf \
    -v /workspace/oai-multiue/shim/libsctp2tcp2.so:/opt/shim.so:ro -v /workspace/oai-multiue/conf/gnb-c-n78-106-2x2.conf:/opt/oai-gnb/etc/gnb.conf:ro \
    -e LD_PRELOAD=/opt/shim.so -e USE_ADDITIONAL_OPTIONS="--rfsim -E --log_config.global_log_options level,nocolor,time" $GNB_IMG >/dev/null
  local s; for s in $(seq 40); do $DK logs n5-gnb 2>&1 | grep -q "Received NGSetupResponse" && break; sleep 1; done
  $DK logs n5-gnb 2>&1 | grep -q "Received NGSetupResponse" && log "gnb: ngsetup_ok=${s}s img=$GNB_IMG" || { log "gnb: NGSETUP_FAIL"; exit 1; }
  # nrUE runs as root with --cap-drop ALL (no DAC override): conf must be readable via group root, not world (K/OPc)
  sudo chgrp root $LAB/secrets/ue*.conf; sudo chmod 640 $LAB/secrets/ue*.conf
  for i in $(seq $N_UE); do bash $LAB/lab/lab.sh ue-restart $i || { log "ue$i: ATTACH_FAIL"; exit 1; }; done   # attach + keepalive ping 1 s (UE never idle)
  sync_ips; adapter; sink
  log "final check"; bash $H/provision.sh check | sed 's/^/prov: /'
}
up() { core; ran; }
case "${1:-up}" in up) up ;; core) core ;; ran) ran ;; adapter) sync_ips; adapter ;; sink) sink ;; sync-ips) sync_ips ;; status) bash $LAB/lab/lab.sh status; $DK ps --format '{{.Names}} {{.Status}}' | grep n5-adapter ;; esac
