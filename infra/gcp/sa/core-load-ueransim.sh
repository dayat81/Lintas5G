#!/bin/bash
# Fase 4: non-radio core load. K UERANSIM nr-gnb+nr-ue process pairs (each in its own netns) push iperf3 through the UPF,
# no srsRAN / emulator running (needs the sa-ueransim 5GC profile: open5gs 5GC up, UERANSIM built under /opt/lab5g/ueransim).
# Usage: core-load-ueransim.sh <K> <outdir>   env: DUR=60 DIR=dl|ul|both PARALLEL=4 (iperf -P) DRY_RUN=1 (print only)
# UNVERIFIED on the lab (written offline, 19 Nov 2026): first Fase 4 run must start with K=1 and compare to the known 487-511 Mbit/s.
K=${1:-2}; O=${2:-/var/log/lab5g/core-load}; DUR=${DUR:-60}; DIR=${DIR:-both}; PAR=${PARALLEL:-4}; DRY=${DRY_RUN:-0}
HERE=$(cd "$(dirname "$0")" && pwd); B=/opt/lab5g/ueransim/UERANSIM/build; CF=$O/conf; SRV=10.45.0.1
run() { if [ "$DRY" = 1 ]; then echo "+ $*"; else "$@"; fi; }
mkdir -p "$O"
if [ "$DRY" != 1 ]; then . /root/lab5g-sub.env; export KEY OPC; fi
python3 "$HERE/core_load_plan.py" --k "$K" --out "$CF" >/dev/null || exit 3
[ "$DRY" != 1 ] && docker exec -i -e K="$KEY" -e OPC="$OPC" mongo mongosh --quiet open5gs < "$CF/provision.js" | tail -1
systemctl stop lab5g-ue-keepalive 2>/dev/null
for i in $(seq 1 "$K"); do
  run ip netns add cl$i 2>/dev/null
  run ip link add vcl$i type veth peer name vclns$i 2>/dev/null
  run ip link set vclns$i netns cl$i
  run ip addr replace 10.210.$i.1/24 dev vcl$i; run ip link set vcl$i up
  run ip netns exec cl$i ip addr replace 10.210.$i.2/24 dev vclns$i
  run ip netns exec cl$i ip link set vclns$i up; run ip netns exec cl$i ip link set lo up
  run systemd-run --unit=lab5g-cl$i-gnb taskset -c $((2 * i)) bash -c "$B/nr-gnb -c $CF/gnb$i.yaml > $O/gnb$i.log 2>&1"
done
sleep 4
for i in $(seq 1 "$K"); do
  run systemd-run --unit=lab5g-cl$i-ue taskset -c $((2 * i + 1)) bash -c "ip netns exec cl$i $B/nr-ue -c $CF/ue$i.yaml > $O/ue$i.log 2>&1"
done
[ "$DRY" = 1 ] && exit 0
for i in $(seq 1 "$K"); do
  for _ in $(seq 1 30); do ip netns exec cl$i ip -4 -o addr show uesimtun0 2>/dev/null | grep -q 10.45 && break; sleep 1; done
  ip netns exec cl$i ip route replace default dev uesimtun0
  systemd-run --unit=lab5g-cl$i-keepalive -p Restart=always ip netns exec cl$i ping -i 1 -W 2 $SRV >/dev/null   # never idle
  systemd-run --unit=lab5g-cl$i-iperfs iperf3 -s -B $SRV -p $((5300 + i)) >/dev/null
done
sleep 1
one() { local d=$1 x=(); [ "$d" = dl ] && x+=(-R)
  for i in $(seq 1 "$K"); do ip netns exec cl$i iperf3 -c $SRV -p $((5300 + i)) -t "$DUR" -P "$PAR" --json "${x[@]}" > "$O/cl${i}_$d.json" 2>/dev/null & done
  python3 "$HERE/nr_summary.py" cpu --seconds "$DUR" --out "$O/cpu_$d.json" > /dev/null & wait; }
case "$DIR" in dl) one dl;; ul) one ul;; *) one dl; sleep 5; one ul;; esac
python3 - "$O" "$K" <<'PY'
import json,sys
o,k=sys.argv[1],int(sys.argv[2]); r={}
for d in ("dl","ul"):
    t=0.0
    for i in range(1,k+1):
        try: s=json.load(open(f"{o}/cl{i}_{d}.json"))["end"]; t+=(s.get("sum_received") or s["sum"])["bits_per_second"]/1e6
        except Exception: pass
    if t: r[d+"_aggregate_mbps"]=round(t,1)
print(json.dumps(r))
PY
for i in $(seq 1 "$K"); do for s in gnb ue keepalive iperfs; do systemctl stop lab5g-cl$i-$s 2>/dev/null; done; ip netns del cl$i 2>/dev/null; done
