#!/bin/bash
# Per-pair + aggregate iperf3 runner. Servers on the UPF gateway (ogstun 10.45.0.1), one port per pair (5200+i),
# clients inside netns ue<i> (all pairs in parallel = aggregate). Output: JSON per pair/direction + summary.json.
# Usage: nr-iperf-run.sh <N> <outdir> [dl|ul|both]   env: DUR=60 PROTO=tcp|udp UDP_BW=80M SRV=10.45.0.1 MIN_PAIR=50
#   RATIO_LOG=auto|<gNB log>|none: sim/real-time ratio per direction from the gNB slot log (OAI Frame.Slot lines or srsRAN
#   [SFN.slot] lines; auto = /var/log/lab5g/sa/oai-gnb.out, else gnb1.log/gnb.log) -> ratio_<dir>.json, used by summary
N=${1:-1}; O=${2:-/var/log/lab5g/nr-iperf}; DIRS=${3:-both}; DUR=${DUR:-60}; PROTO=${PROTO:-tcp}; SRV=${SRV:-10.45.0.1}
HERE=$(cd "$(dirname "$0")" && pwd); mkdir -p "$O"; SL=/var/log/lab5g/sa; RL=${RATIO_LOG:-auto}
if [ "$RL" = auto ]; then RL=none; for f in $SL/oai-gnb.out $SL/gnb1.log $SL/gnb.log; do [ -f "$f" ] && { RL=$f; break; }; done; fi
for i in $(seq 1 "$N"); do systemctl stop lab5g-nr$i-iperfs 2>/dev/null; systemctl reset-failed lab5g-nr$i-iperfs 2>/dev/null
  systemd-run --unit=lab5g-nr$i-iperfs iperf3 -s -B "$SRV" -p $((5200 + i)) >/dev/null; done
sleep 1
one() { # dir
  local d=$1 extra=() ; [ "$d" = dl ] && extra+=(-R)
  [ "$PROTO" = udp ] && extra+=(-u -b "${UDP_BW:-80M}")
  for i in $(seq 1 "$N"); do
    timeout $((DUR + 30)) ip netns exec ue$i iperf3 -c "$SRV" -p $((5200 + i)) -t "$DUR" -i 1 --json "${extra[@]}" > "$O/pair${i}_$d.json" 2>"$O/pair${i}_$d.err" &
  done
  local off=0; [ -f "$RL" ] && off=$(stat -c %s "$RL")
  python3 "$HERE/nr_summary.py" cpu --seconds "$DUR" --out "$O/cpu_$d.json" &
  wait
  [ -f "$RL" ] && python3 "$HERE/nr_summary.py" ratio --log "$RL" --start-offset "$off" --out "$O/ratio_$d.json" >/dev/null
}
case "$DIRS" in dl) one dl;; ul) one ul;; *) one dl; sleep 5; one ul;; esac
for i in $(seq 1 "$N"); do systemctl stop lab5g-nr$i-iperfs 2>/dev/null; done
python3 "$HERE/nr_summary.py" summary --dir "$O" --pairs "$N" --min-pair "${MIN_PAIR:-50}" --out "$O/summary.json"
