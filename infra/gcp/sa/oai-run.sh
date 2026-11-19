#!/bin/bash
# ran_mode=sa-oai: start/stop/status OAI v3.0.0 gNB + N nrUE (1..3) as systemd-supervised docker containers.
# gNB: --network host (native kernel SCTP N2 to the AMF, N3 bind 127.0.1.1), log -> /var/log/lab5g/sa/oai-gnb.out
# (the Frame.Slot lines give the sim/real ratio, see nr_summary.py ratio). UE i: own docker netns, exposed as
# "ip netns ue<i>" (symlink to /proc/<pid>/ns/net) so nr-iperf-run.sh / nr-health.sh / keepalive work unchanged.
# Order (same rule as zmq-pair-lib.sh): gNB first, only after NGSetupResponse + RF server ready; UE BindsTo the gNB;
# no per-process auto-restart; on failure restart the UE, after the last try the whole RAN. One keepalive per UE
# (1 ping/s: the UE must never go idle). Real-time: SYS_NICE + rtprio + memlock when the host allows SCHED_FIFO.
# Usage: oai-run.sh start|stop|status <N>
# env: OAI_RF=rfsim|vrtsim  OAI_TIMESCALE=1.0 (vrtsim only)  OAI_MIMO=2|1  OAI_RT=auto|1|0  CORE_CPUS=2  NPROC=$(nproc)
#      OAI_GNB_IMAGE / OAI_UE_IMAGE (default: metadata oai-gnb-image / oai-ue-image)  CONF_DIR=/etc/lab5g/sa/oai  DRY_RUN=1
#      offline test hooks only (box without kernel SCTP; never set on the lab VM): OAI_GNB_NET (default host),
#      OAI_GNB_DOCKER_OPTS (extra docker args for the gNB, e.g. the sctp2tcp shim), OAI_RFSIM_ADDR (default docker0 gateway)
CMD=${1:-status}; N=${2:-1}; C=${CONF_DIR:-/etc/lab5g/sa/oai}; L=${LOG_DIR:-/var/log/lab5g/sa}; DRY=${DRY_RUN:-0}
RF=${OAI_RF:-rfsim}; TS=${OAI_TIMESCALE:-1.0}; MIMO=${OAI_MIMO:-2}; NPROC=${NPROC:-$(nproc)}; CORE_N=${CORE_CPUS:-2}
MD=http://metadata.google.internal/computeMetadata/v1/instance/attributes
md() { curl -fsS -m 3 -H 'Metadata-Flavor: Google' "$MD/$1" 2>/dev/null; }
run() { if [ "$DRY" = 1 ]; then echo "+ $*"; else "$@"; fi; }
GU=lab5g-oai-gnb
case "$N" in 1|2|3) ;; *) echo "N must be 1..3" >&2; exit 2;; esac
units() { for i in 1 2 3; do echo lab5g-nr$i-keepalive lab5g-nr$i-ue; done; echo $GU; }
stop_all() {
  for u in $(units); do run systemctl stop "$u" 2>/dev/null; run systemctl reset-failed "$u" 2>/dev/null; done
  for i in 1 2 3; do run docker rm -f "oai-ue$i" >/dev/null 2>&1; run rm -f "/run/netns/ue$i"; done
  run docker rm -f oai-gnb >/dev/null 2>&1
  # systemd only kills the docker CLI; wait until the containers (and their --rm cleanup) are really gone
  [ "$DRY" = 1 ] || for _ in $(seq 1 20); do
    [ -z "$(docker ps -aq -f 'name=^oai-(gnb|ue[123])$')" ] && break
    docker rm -f oai-gnb oai-ue1 oai-ue2 oai-ue3 >/dev/null 2>&1; sleep 1
  done
}
case "$CMD" in
stop) stop_all; exit 0;;
status)
  for i in $(seq 1 "$N"); do
    printf 'ue%s gnb=%s ue=%s keepalive=%s ip=%s\n' "$i" "$(systemctl is-active $GU)" "$(systemctl is-active lab5g-nr$i-ue)" \
      "$(systemctl is-active lab5g-nr$i-keepalive)" "$(ip netns exec ue$i ip -4 -o addr show oaitun_ue1 2>/dev/null | awk '{print $4}' | sed 's/\.[0-9]*\//.x\//')"
  done; exit 0;;
start) ;;
*) echo "usage: $0 start|stop|status N" >&2; exit 2;;
esac
case "$RF" in rfsim|vrtsim) ;; *) echo "OAI_RF must be rfsim|vrtsim" >&2; exit 2;; esac
GI=${OAI_GNB_IMAGE:-$(md oai-gnb-image)}; UI=${OAI_UE_IMAGE:-$(md oai-ue-image)}
case "$GI$UI" in *@sha256:*@sha256:*) ;; *) echo "OAI images must be pinned by digest (got gnb='$GI' ue='$UI')" >&2; exit 2;; esac
CORE=$(seq -s, 0 $((CORE_N - 1))); RAN="$CORE_N-$((NPROC - 1))"
# real-time: probe once whether SCHED_FIFO works in a container on this host (GCP VM: yes; sandboxed hosts: no)
RT=${OAI_RT:-auto}
if [ "$RT" = auto ]; then
  if [ "$DRY" = 1 ]; then RT=1; elif docker run --rm --cap-add SYS_NICE --ulimit rtprio=99 --entrypoint chrt "$GI" -f 1 true >/dev/null 2>&1; then RT=1; else RT=0; fi
fi
if [ "$RT" = 1 ]; then RTO="--cap-add SYS_NICE --ulimit rtprio=99 --ulimit memlock=-1"; else RTO=""; fi
echo "[oai] rf=$RF timescale=$TS mimo=$MIMO ues=$N rt=$RT core_cpus=$CORE ran_cpus=$RAN"
if [ "$RF" = vrtsim ]; then
  VD=/run/lab5g/vrtsim; run install -d -m 1777 "$VD"; run rm -f "$VD/vrtsim_connection"
  VO="--ipc host -v $VD:/tmp"; GRF="--device.name vrtsim --vrtsim.role server --vrtsim.timescale $TS --vrtsim.num_ues $N"
  for k in $(seq 0 $((N - 1))); do GRF="$GRF --vrtsim.ue_config.[$k].antennas ${MIMO}x${MIMO}"; done; URF="--device.name vrtsim"
else
  VO=""; GRF="--rfsim"; GW=${OAI_RFSIM_ADDR:-}; [ -n "$GW" ] || GW=$(docker network inspect bridge -f '{{(index .IPAM.Config 0).Gateway}}' 2>/dev/null | head -1 | tr -d '[:space:]')
  URF="--rfsim --rfsimulator.[0].serveraddr ${GW:-172.17.0.1}"
fi
if [ "$MIMO" = 2 ]; then UCAP=uecap_ports2.xml; UANT="--ue-nb-ant-rx 2 --ue-nb-ant-tx 2"; else UCAP=uecap_ports1.xml; UANT=""; fi
LOGO="--log_config.global_log_options level,nocolor,time"
UARGS="-E -r 106 --numerology 1 -C 3319680000 --uecap_file /opt/oai-uecap/$UCAP $UANT"
# Open5GS NFs on the core CPUs, RAN containers on the rest
[ "$DRY" = 1 ] || for p in $(pgrep -f 'open5gs-(upf|smf|amf|ausf|udm|udr|pcf|nrf|scp|bsf|nssf)d'); do taskset -a -cp "$CORE" "$p" >/dev/null 2>&1; done
mkdir -p "$L" 2>/dev/null
# UE confs hold K/OPc (0600): containers run with --cap-drop ALL (no DAC_OVERRIDE), so they must be owned by root
[ "$DRY" = 1 ] || chown root:root "$C"/ue*.conf
# one log set per bring-up (nr-health rlf counts since start); previous run kept as *.out.1
[ "$DRY" = 1 ] || for f in "$L"/oai-gnb.out "$L"/ue[123].out; do [ -f "$f" ] && mv -f "$f" "$f.1"; done
gnb_up() {
  stop_all >/dev/null 2>&1
  local off=0; [ "$DRY" = 1 ] || { touch "$L/oai-gnb.out"; off=$(stat -c %s "$L/oai-gnb.out"); }
  # shellcheck disable=SC2086
  run systemd-run --unit=$GU -p Restart=no -p StandardOutput=append:"$L/oai-gnb.out" -p StandardError=append:"$L/oai-gnb.out" \
    docker run --rm --name oai-gnb --network "${OAI_GNB_NET:-host}" $RTO $VO ${OAI_GNB_DOCKER_OPTS:-} --cpuset-cpus "$RAN" -v "$C/gnb.conf:/opt/oai-gnb/etc/gnb.conf:ro" \
    -e USE_ADDITIONAL_OPTIONS="$GRF $LOGO -E" "$GI"
  [ "$DRY" = 1 ] && { echo "+ wait NGSetupResponse + RF server ($RF)"; return 0; }
  for s in $(seq 1 "${GNB_READY_S:-90}"); do
    if tail -c +"$((off + 1))" "$L/oai-gnb.out" | grep -q "Received NGSetupResponse"; then
      if [ "$RF" = rfsim ]; then
        gp=$(docker inspect -f '{{.State.Pid}}' oai-gnb 2>/dev/null)
        [ -n "$gp" ] && [ "$gp" != 0 ] && nsenter -t "$gp" -n ss -Hltn 'sport = :4043' | grep -q . && break
      else [ -e /run/lab5g/vrtsim/vrtsim_connection ] && break; fi
    fi
    systemctl is-active -q $GU || break; sleep 1
  done
  tail -c +"$((off + 1))" "$L/oai-gnb.out" | grep -q "Received NGSetupResponse" && systemctl is-active -q $GU || { echo "[oai] gNB not ready after ${s}s"; return 1; }
  echo "[oai] gNB ready after ${s}s (NG setup ok)"
}
ue_up() { # i -> 0 when the UE has an IP
  local i=$1 UU=lab5g-nr$1-ue pid s
  run systemctl stop "$UU" 2>/dev/null; run systemctl reset-failed "$UU" 2>/dev/null; run docker rm -f "oai-ue$i" >/dev/null 2>&1
  # shellcheck disable=SC2086
  run systemd-run --unit="$UU" -p Restart=no -p BindsTo=$GU.service -p After=$GU.service \
    -p StandardOutput=append:"$L/ue$i.out" -p StandardError=append:"$L/ue$i.out" \
    docker run --rm --name "oai-ue$i" --cap-drop ALL --cap-add NET_ADMIN --cap-add NET_RAW $RTO $VO --device /dev/net/tun \
    --cpuset-cpus "$RAN" -v "$C/ue$i.conf:/opt/oai-nr-ue/etc/nr-ue.conf:ro" -v "$C/uecap:/opt/oai-uecap:ro" \
    -e USE_ADDITIONAL_OPTIONS="$URF$([ "$RF" = vrtsim ] && echo " --vrtsim.ue_id $((i - 1))") $LOGO $UARGS" "$UI"
  [ "$DRY" = 1 ] && { echo "+ ln -sf /proc/<pid>/ns/net /run/netns/ue$i; wait oaitun_ue1; default route; keepalive"; return 0; }
  for s in $(seq 1 30); do pid=$(docker inspect -f '{{.State.Pid}}' "oai-ue$i" 2>/dev/null); [ -n "$pid" ] && [ "$pid" != 0 ] && break; sleep 1; done
  [ -n "$pid" ] && [ "$pid" != 0 ] || return 1
  ip netns del "ue$i" 2>/dev/null; mkdir -p /run/netns; ln -sf "/proc/$pid/ns/net" "/run/netns/ue$i"
  for s in $(seq 1 "${UE_IP_S:-60}"); do
    ip netns exec "ue$i" ip -4 -o addr show oaitun_ue1 2>/dev/null | grep -q inet && { echo "[oai] ue$i IP after ${s}s"; return 0; }
    systemctl is-active -q "$UU" || break; sleep 1
  done
  echo "[oai] ue$i no IP after ${s}s ($(systemctl is-active "$UU"))"; return 1
}
ok=0
for t in $(seq 1 "${OAI_TRIES:-3}"); do
  gnb_up || continue
  ok=1
  for i in $(seq 1 "$N"); do ue_up "$i" || ue_up "$i" || { ok=0; echo "[oai] try $t: ue$i failed, restarting RAN"; break; }; done
  [ $ok = 1 ] && break
done
[ $ok = 1 ] || { echo "[oai] start FAILED"; exit 1; }
for i in $(seq 1 "$N"); do
  run ip netns exec "ue$i" ip route replace default dev oaitun_ue1
  KA=(systemd-run "--unit=lab5g-nr$i-keepalive" -p Restart=always ip netns exec "ue$i" ping -i 1 -W 2 8.8.8.8)
  if [ "$DRY" = 1 ]; then run "${KA[@]}"; else "${KA[@]}" >/dev/null; fi
done
[ "$DRY" = 1 ] || bash "$0" status "$N"
