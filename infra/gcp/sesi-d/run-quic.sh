#!/bin/bash
# vm-core-ran (root), Sesi D: per-packet QUIC latency, conditions idle | load | load+qod x REPS, Zeek pkthash taps in parallel.
# Traffic: quic-gen.py in netns ue1 (QUIC long-header -> Version Negotiation from Google/Cloudflare/YouTube, PPS per flow)
# + whatever the emulator sends (YouTube app QUIC via ue-l3, started by the box orchestrator on the same schedule).
# load = iperf3 TCP DL 4 + UL 1 (bottleneck tc HTB DL 15 / UL 8 Mbit/s); load+qod = load + QoD session via the adapter API
# (udp/443 to any remote, gbrKbps 5000 -> class 1:10). Writes $P/phases.tsv (run_id cond rep t_start t_end) for ClickHouse.
# usage: run-quic.sh <emu_ip> [REPS=3 DUR=120 GAP=20 PPS=20]
. /opt/lab5g/sesi-d/common.sh
E=${1:?emu_ip}; REPS=${REPS:-3}; DUR=${DUR:-120}; GAP=${GAP:-20}; PPS=${PPS:-20}; RUN=${RUN_ID:-quic-$(date +%Y%m%d-%H%M%S)}
T=""; for n in www.google.com cloudflare-quic.com www.youtube.com; do ip=$(getent ahostsv4 $n | awk 'NR==1{print $1}'); [ -n "$ip" ] && T="$T,$ip"; done; T=${T#,}
log "quic start run=$RUN reps=$REPS dur=$DUR targets=$(echo $T | tr ',' ' ' | wc -w)"
for rep in $(seq 1 $REPS); do
  for cond in idle load load+qod; do
    h=$(health); [ "$h" = 1 ] && log "rep $rep $cond: re-attached before phase"
    r0=$(rlf_count); lbl=$RUN-$cond-r$rep
    [ $cond != idle ] && { load_start $E $((DUR + 15)) $lbl; sleep 8; }
    [ $cond = load+qod ] && log "qod: $(qod_post "{\"ueIpv4\":\"$(ue_ip)\",\"remote\":\"any\",\"port\":443,\"gbrKbps\":5000,\"source\":\"sesi-d-quic\"}")"
    t0=$(date +%s.%N)
    $NS ping -i 0.2 -c $((DUR * 5)) -W 3 8.8.8.8 > $P/$lbl-ping.txt 2>&1 & PG=$!
    $NS python3 $SD/quic-gen.py --out $P/$lbl --dur $DUR --pps $PPS --targets $T > /dev/null 2>&1
    wait $PG 2>/dev/null; t1=$(date +%s.%N)
    printf '%s\t%s\t%s\t%.3f\t%.3f\n' $RUN $cond $rep $t0 $t1 >> $P/phases.tsv
    [ $cond = load+qod ] && qod_del_all >/dev/null
    [ $cond != idle ] && load_stop
    log "rep $rep $cond: $(python3 -c "import json;d=json.load(open('$P/$lbl-summary.json'));print(' '.join(f\"{k.split('.')[0]}:{v['answered']}/{v['tx']} p50={v['rtt_p50']} p99={v['rtt_p99']}\" for k,v in d.items()))") ping=$(tail -1 $P/$lbl-ping.txt | cut -d= -f2) rlf+=$(( $(rlf_count) - r0 ))"
    sleep $GAP
  done
done
bash $SD/zeek-taps.sh status | tee -a $P/run.log
log "quic done run=$RUN"
