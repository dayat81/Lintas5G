#!/bin/bash
# lab.sh start|stop|status|reset-pcc  -- Lintas5G recommended QoD booster lab (offline, box only).
# Stack: core  lintas5g/open5gs:2.8.0-qosrel (n5-lab) + mongo:6 (n5-mongo, volume n5-mongo-db)
#        RAN   $GNB_IMG (n5-gnb, rfsim, in n5-lab netns) + oai-nr-ue:v3.0.0 (n5-ue1..N)
# env: API_PRIO (1 = static PCC rule 5QI 69 for the booster control API, see api-prio.py), GNB_IMG (default lintas5g/oai-gnb:v3.0.0-slice-qosrel3), N_UE (2), SLICE (1 = QoD DL slice policy on,
#      only with the slice image), LEGACY_CORE=1 (test: unpatched core image + lab configs), CPUS (RAN cpuset, default 4-7), CORE_CPUS (default 0-3), DEBUG_LOG (1).
# Secrets (UE confs with K/OPc) stay in ../secrets (chmod 700); nothing secret is baked into images.
set -u
D=$(cd "$(dirname "$0")/.." && pwd)
CORE_IMG=${CORE_IMG:-lintas5g/open5gs:2.8.0-qosrel}
GNB_IMG=${GNB_IMG:-lintas5g/oai-gnb:v3.0.0-slice-qosrel3}
N_UE=${N_UE:-2}; SLICE=${SLICE:-1}; CPUS=${CPUS:-4-7}; CORE_CPUS=${CORE_CPUS:-0-3}
UEARGS="-E -r 106 --numerology 1 -C 3319680000 --uecap_file /opt/up/uecap_ports2.xml --ue-nb-ant-rx 2 --ue-nb-ant-tx 2"
DK="sudo docker"

others() {  # foreign RAN instances (never touched, only reported)
  $DK ps --format '{{.Names}} {{.Image}}' | grep -E '^(oai-|mq-|qa-)' | grep -E 'oai-gnb|oai-nr-ue' || true
}

start() {
  local o; o=$(others); [ -n "$o" ] && { echo "WARN: other RAN running (left untouched, pin ours to CPUS=$CPUS):"; echo "$o"; }
  $DK rm -f n5-gnb $(seq -f 'n5-ue%g' 1 3) n5-mongo n5-lab >/dev/null 2>&1
  $DK volume inspect n5-mongo-db >/dev/null 2>&1 || { echo "ERR: volume n5-mongo-db missing (copy of the lab subscriber DB)"; exit 1; }
  $DK run -d --name n5-lab --cpuset-cpus $CORE_CPUS --cap-add NET_ADMIN --cap-add NET_RAW --device /dev/net/tun \
    --sysctl net.ipv4.ip_forward=1 -e DEBUG_LOG=${DEBUG_LOG:-1} $CORE_IMG >/dev/null
  $DK run -d --name n5-mongo --network container:n5-lab --cpuset-cpus $CORE_CPUS -v n5-mongo-db:/data/db mongo:6 --bind_ip 127.0.0.1 >/dev/null
  if [ "${LEGACY_CORE:-0}" = 1 ]; then  # test only: unpatched Open5GS (e.g. CORE_IMG=lintas5g/n5-core-base:tmp) + lab configs
    $DK cp $D/lab/img-open5gs/overlay/opt/lintas5g n5-lab:/opt/ && $DK cp $D/lab/img-open5gs/overlay/etc/open5gs/pcf.yaml n5-lab:/etc/open5gs/pcf.yaml
  fi
  $DK exec n5-lab bash /opt/lintas5g/core-up.sh | sed 's/^/core: /'
  # booster control API at high priority (static PCC rule, 5QI 69, ARP 1) before any UE attaches; API_PRIO=0 removes it
  if [ "${API_PRIO:-1}" = 1 ]; then api_prio apply | tr -d '\n ' | cut -c1-200; echo; else api_prio remove >/dev/null; echo "api-prio: removed"; fi
  local ip; ip=$($DK inspect -f '{{.NetworkSettings.IPAddress}}' n5-lab)
  local sopt=""
  [ "$SLICE" = 1 ] && sopt="-v $D/slice:/opt/slice:ro -e OAI_DL_SLICE_CONF=/opt/slice/slice.conf"
  $DK run -d --name n5-gnb --network container:n5-lab --cap-drop ALL --cpuset-cpus $CPUS $sopt \
    -v /workspace/oai-multiue/shim/libsctp2tcp2.so:/opt/shim.so:ro -v /workspace/oai-multiue/conf/gnb-c-n78-106-2x2.conf:/opt/oai-gnb/etc/gnb.conf:ro \
    -e LD_PRELOAD=/opt/shim.so -e USE_ADDITIONAL_OPTIONS="--rfsim -E --log_config.global_log_options level,nocolor,time" $GNB_IMG >/dev/null
  local s; for s in $(seq 40); do $DK logs n5-gnb 2>&1 | grep -q "Received NGSetupResponse" && break; sleep 1; done
  $DK logs n5-gnb 2>&1 | grep -q "Received NGSetupResponse" && echo "gnb: ngsetup_ok=${s}s img=$GNB_IMG slice=$SLICE" || { echo "gnb: NGSETUP_FAIL"; exit 1; }
  for i in $(seq $N_UE); do start_ue $i; done
}

start_ue() {  # start_ue <i>: (re)attach one nrUE + keepalive
    local i=$1 s ip; ip=$($DK inspect -f '{{.NetworkSettings.IPAddress}}' n5-lab)
    $DK rm -f n5-ue$i >/dev/null 2>&1
    sudo sed -i -E "s/serveraddr = \"[0-9.]+\"/serveraddr = \"$ip\"/" $D/secrets/ue$i.conf
    $DK run -d --name n5-ue$i --cpuset-cpus $CPUS --cap-drop ALL --cap-add NET_ADMIN --cap-add NET_RAW --device /dev/net/tun \
      -v /workspace/oai-multiue/conf/upstream:/opt/up:ro -v $D/secrets/ue$i.conf:/opt/oai-nr-ue/etc/nr-ue.conf:ro \
      -e USE_ADDITIONAL_OPTIONS="--rfsim --log_config.global_log_options level,nocolor,time $UEARGS" \
      oaisoftwarealliance/oai-nr-ue:v3.0.0 >/dev/null
    for s in $(seq 90); do $DK exec n5-ue$i ip -4 -o addr show oaitun_ue1 2>/dev/null | grep -q inet && break; sleep 1; done
    $DK exec n5-ue$i ip -4 -o addr show oaitun_ue1 | awk '{print $4}' | cut -d/ -f1 | sudo tee $D/secrets/ue$i.ip >/dev/null
    sudo chmod 600 $D/secrets/ue$i.ip
    # keepalive on the default bearer for the whole session (UE must never go idle)
    $DK exec -d n5-ue$i sh -c 'ping -i 1 -I oaitun_ue1 10.45.0.1 > /tmp/keepalive.log 2>&1'
    echo "ue$i: attached ip_after=${s}s keepalive=on"
}

stop() {
  reset_pcc 2>/dev/null
  $DK rm -f n5-gnb $(seq -f 'n5-ue%g' 1 3) n5-mongo n5-lab >/dev/null 2>&1; echo "stopped (volume n5-mongo-db kept)"
}

api_prio() {  # api_prio apply|remove|show: static PCC rule for the booster control API (lab/api-prio.py; env API_PRIO_IP/PORT/QI)
  local pid; pid=$($DK inspect -f '{{.State.Pid}}' n5-lab) || return 1
  for s in $(seq 20); do sudo nsenter -t $pid -n $D/.venv/bin/python -c "from pymongo import MongoClient as M; M('mongodb://127.0.0.1',serverSelectionTimeoutMS=500).server_info()" >/dev/null 2>&1 && break; sleep 0.5; done
  (cd $D && sudo nsenter -t $pid -n .venv/bin/python lab/api-prio.py $1 --ip ${API_PRIO_IP:-10.45.0.1} --port ${API_PRIO_PORT:-8080} --qi ${API_PRIO_QI:-69} | sed 's/^/api-prio: /')
}

reset_pcc() {
  local pid; pid=$($DK inspect -f '{{.State.Pid}}' n5-lab 2>/dev/null) || return 0
  (cd $D && sudo nsenter -t $pid -n .venv/bin/python n5proto.py reset)
}

status() {
  $DK ps -a --format '{{.Names}}\t{{.Image}}\t{{.Status}}' | grep -E '^n5-(lab|mongo|gnb|ue)' || echo "lab down"
  $DK exec n5-lab sh -c 'for n in nrfd scpd ausfd udmd udrd pcfd bsfd nssfd smfd upfd amfd; do pgrep -x open5gs-$n >/dev/null && printf "$n=up " || printf "$n=DOWN "; done; echo' 2>/dev/null
  for i in $(seq 3); do $DK exec n5-ue$i sh -c 'ip -4 -o addr show oaitun_ue1 >/dev/null && echo "ue'$i' up; keepalive: $(tail -1 /tmp/keepalive.log | cut -c1-60)"' 2>/dev/null; done
  local o; o=$(others); [ -n "$o" ] && { echo "other RAN (not ours):"; echo "$o"; }
}

case "${1:-}" in
  start) start ;; ue-restart) start_ue ${2:-1} ;; api-prio) api_prio ${2:-show} ;; stop) stop ;; status) status ;; reset-pcc) reset_pcc ;;
  *) echo "usage: $0 start|stop|status|reset-pcc|ue-restart <i>|api-prio apply|remove|show"; exit 2 ;;
esac
