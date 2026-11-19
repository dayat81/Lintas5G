#!/bin/bash
# Radio health probes for the radio-uplift phases. Output = one JSON line (no secrets).
#   nr-health.sh n3drop <seconds> <N>   AF_PACKET drop of the N3 tap filter on lo (tcpdump "dropped by kernel" / captured)
#   nr-health.sh rlf <N>                RLF/RRC re-establishment/late/underflow counters in gnb<i>/ue<i> logs + keepalive state
BPF_HOSTS=""; CMD=${1:-rlf}; L=/var/log/lab5g/sa
case "$CMD" in
n3drop)
  S=${2:-60}; N=${3:-1}
  for i in $(seq 1 "$N"); do BPF_HOSTS="${BPF_HOSTS:+$BPF_HOSTS or }host 127.0.1.$i"; done
  OUT=$(timeout -s INT "$S" tcpdump -i lo -s 128 -n -w /dev/null "udp port 2152 and ($BPF_HOSTS)" 2>&1 | tr '\r' '\n')
  CAP=$(echo "$OUT" | sed -n 's/^\([0-9]*\) packets captured.*/\1/p' | tail -1); DRP=$(echo "$OUT" | sed -n 's/^\([0-9]*\) packets dropped by kernel.*/\1/p' | tail -1)
  CAP=${CAP:-0}; DRP=${DRP:-0}
  python3 -c "import json,sys;c,d=int(sys.argv[1]),int(sys.argv[2]);print(json.dumps({'n3_captured':c,'n3_dropped':d,'n3_drop_pct':round(100*d/max(c+d,1),2)}))" "$CAP" "$DRP";;
rlf)
  N=${2:-1}; R=0; LU=0
  if [ -f $L/oai-gnb.out ]; then
    # OAI (ran_mode=sa-oai, logs rotated per oai-run.sh start): one gNB log for all UEs; MAC "Detected UL Failure",
    # "out-of-sync" in the per-UE stats line, UE release request; UE side: radio link failure / T310 / re-establishment.
    # Generic srsRAN patterns would false-match OAI ("RRC Released RLC entity" at shutdown, "cumuLATEd bad DCI").
    R=$((R + $(grep -ciE "Detected UL Failure|out-of-sync|request release|RLF" $L/oai-gnb.out)))
    LU=$((LU + $(grep -ciE "late decode|underflow|\\[late\\]" $L/oai-gnb.out)))
    for i in $(seq 1 "$N"); do
      [ -f $L/ue$i.out ] || continue
      R=$((R + $(grep -ciE "radio link failure|T310 expired|re-?establishment" $L/ue$i.out)))
      LU=$((LU + $(grep -ciE "underflow|late decode" $L/ue$i.out)))
    done
  else
  for i in $(seq 1 "$N"); do
    for f in $L/ue$i.out $L/ue$i.log $L/gnb$i.out $L/gnb$i.log $L/ue.out $L/gnb.out; do
      [ -f "$f" ] || continue
      [ "$i" -gt 1 ] && case "$f" in */ue.out|*/gnb.out) continue;; esac
      R=$((R + $(grep -ciE "radio link fail|RLF|re-?establishment|RRC Release|Reestablish" "$f")))
      LU=$((LU + $(grep -ciE "underflow|late" "$f")))
    done
  done
  fi
  KA=0; for i in $(seq 1 "$N"); do systemctl is-active -q lab5g-nr$i-keepalive || systemctl is-active -q lab5g-ue-keepalive && KA=$((KA + 1)); done
  echo "{\"rlf_events\":$R,\"late_underflow_lines\":$LU,\"keepalive_active\":$KA,\"pairs\":$N}";;
esac
