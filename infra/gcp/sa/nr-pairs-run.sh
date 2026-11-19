#!/bin/bash
# Start/stop/status for N srsRAN gNB + srsUE NR pairs with CPU pinning and one keepalive per UE (the UE must never idle).
# Usage: nr-pairs-run.sh start|stop|status <N>      (env: CORE_CPUS=2 PAIR_MAX=5 NR_HEAVY=gnb|ue NR_PIN=0|1 (0 = default, shared RAN CPUs) NPROC=$(nproc) DRY_RUN=1 prints commands only)
CMD=${1:-status}; N=${2:-1}; C=${CONF_DIR:-/etc/lab5g/sa}; L=/var/log/lab5g/sa; HERE=$(cd "$(dirname "$0")" && pwd)
NPROC=${NPROC:-$(nproc)}; DRY=${DRY_RUN:-0}
run() { if [ "$DRY" = 1 ]; then echo "+ $*"; else "$@"; fi; }
# shellcheck disable=SC1091
. "$HERE/zmq-pair-lib.sh"
units() { for i in $(seq 1 4); do echo lab5g-nr$i-gnb lab5g-nr$i-ue lab5g-nr$i-keepalive; done; }
case "$CMD" in
stop)
  for u in $(units); do run systemctl stop "$u" 2>/dev/null; run systemctl reset-failed "$u" 2>/dev/null; done; exit 0;;
status)
  for i in $(seq 1 "$N"); do
    IF=tun_srsue; [ "$i" -gt 1 ] && IF=tun_srsue$i
    printf 'pair%s gnb=%s ue=%s keepalive=%s ip=%s\n' "$i" "$(systemctl is-active lab5g-nr$i-gnb)" "$(systemctl is-active lab5g-nr$i-ue)" \
      "$(systemctl is-active lab5g-nr$i-keepalive)" "$(ip netns exec ue$i ip -4 -o addr show $IF 2>/dev/null | awk '{print $4}')"
  done; exit 0;;
start) ;;
*) echo "usage: $0 start|stop|status N" >&2; exit 2;;
esac
mkdir -p $L
# bootstrap gap (FAKTA GCP 19 Nov: nr_pairs=1 boots via sa-run.sh, so /etc/lab5g/sa/pair<i>/ was never rendered and
# "start N" failed with "gnb.yaml was not readable"): render the per-pair configs for N if any is missing.
for i in $(seq 1 "$N"); do
  [ -s "$C/pair$i/gnb.yaml" ] && [ -s "$C/pair$i/ue.conf" ] && continue
  echo "pair$i config missing -> nr-pairs-config.sh $N"
  if [ "$DRY" = 1 ]; then echo "+ bash $HERE/nr-pairs-config.sh $N"; else OUT_DIR=$C bash "$HERE/nr-pairs-config.sh" "$N" | sed -E 's/[0-9]{15}/IMSI_REDACTED/g' || exit 4; fi
  break
done
PLAN=$(python3 "$HERE/nr_cpu_plan.py" --nproc "$NPROC" --pairs "$N" --core "${CORE_CPUS:-2}" --pair-max "${PAIR_MAX:-5}" --heavy "${NR_HEAVY:-gnb}") || exit 3
echo "$PLAN" | sed 's/^/[cpu-plan] /'
CORE=$(echo "$PLAN" | sed -n 's/^core=//p')
# pin the core side (Open5GS NFs) away from the RAN CPUs
if [ "$DRY" != 1 ]; then for p in $(pgrep -f 'open5gs-(upf|smf|amf|ausf|udm|udr|pcf|nrf|scp|bsf|nssf)d'); do taskset -a -cp "$CORE" "$p" >/dev/null 2>&1; done; fi
bash "$0" stop "$N" >/dev/null 2>&1
for i in $(seq 1 "$N"); do
  GCPU=$(echo "$PLAN" | sed -n "s/^pair=$i gnb=\([0-9,]*\) ue=.*/\1/p"); UCPU=$(echo "$PLAN" | sed -n "s/^pair=$i .* ue=//p")
  # default NR_PIN=0: no per-process pinning, all pairs share the non-core CPUs (FAKTA GCP 19 Nov, 2 pairs: pinned 28 vs shared 38 Mbit/s DL agg). NR_PIN=1 = nr_cpu_plan split
  if [ "${NR_PIN:-0}" = 0 ]; then RAN=$(seq -s, 0 $((NPROC - 1)) | tr , '\n' | grep -vxF -f <(echo "$CORE" | tr , '\n') | paste -sd,); GCPU=$RAN; UCPU=$RAN; fi
  IF=tun_srsue; [ "$i" -gt 1 ] && IF=tun_srsue$i
  TXP=$((2000 + 10 * (i - 1)))
  # ordered + supervised start per pair (gNB ready -> UE BindsTo gNB, whole-pair restart on failure): zmq-pair-lib.sh
  zmq_pair_up lab5g-nr$i-gnb lab5g-nr$i-ue $L/gnb$i.out $L/ue$i.out ue$i $IF $TXP \
    "stdbuf -oL taskset -c $GCPU /opt/srsran/bin/gnb -c $C/pair$i/gnb.yaml" \
    "stdbuf -oL taskset -c $UCPU /opt/srsran/bin/srsue $C/pair$i/ue.conf" || echo "pair$i start FAILED"
done
[ "$DRY" = 1 ] && exit 0
for i in $(seq 1 "$N"); do
  IF=tun_srsue; [ "$i" -gt 1 ] && IF=tun_srsue$i
  for _ in $(seq 1 60); do ip netns exec ue$i ip -4 -o addr show $IF 2>/dev/null | grep -q inet && break; sleep 2; done
  ip netns exec ue$i ip -4 -o addr show $IF 2>/dev/null | grep -q inet || { echo "pair$i: no IP on $IF"; continue; }
  ip netns exec ue$i ip route replace default dev $IF
  # keepalive per UE: 1 ping/s, auto-restart
  systemd-run --unit=lab5g-nr$i-keepalive -p Restart=always ip netns exec ue$i ping -i 1 -W 2 8.8.8.8 >/dev/null
done
bash "$0" status "$N"
