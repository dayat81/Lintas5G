#!/bin/bash
# vm-core-ran (root), Sesi D: root cause of TCP UL GBR goodput 75% (Sesi C: iperf3 -b 5M TCP UL = 3.77 Mbit/s under load+QoD).
# Matrix (each DUR s, flow to emu:18080 inside the QoD class gbrKbps=5000, bulk load running unless noted):
#   A  -b 5M, headroom 1.1 (Sesi C repro)         B  no -b (cwnd-limited max)        C  -b 5M --fq-rate 5M (paced)
#   D  -b 5M, headroom 1.5                         E  -b 5M, no bulk UL (DL bulk only) F  -b 5M, no load at all
#   G  UDP 5 Mbit/s UL (udp-flow, control)
# Evidence per case: iperf3 JSON (retransmits, snd_cwnd, rtt), ss -ti samples (cwnd/rtt/pacing/unacked) in netns ue1,
# tc -s class/qdisc ifb0 (drops/overlimits per class), srsenb/srsue MAC/BSR lines, mpstat. usage: tcpul-rca.sh <emu_ip>
. /opt/lab5g/sesi-d/common.sh
E=${1:?emu_ip}; DUR=${DUR:-30}; D=$P/tcpul; mkdir -p $D
qod(){ qod_post "{\"ueIpv4\":\"$(ue_ip)\",\"remote\":\"$E\",\"port\":18080,\"gbrKbps\":5000,\"source\":\"tcpul-rca\"}" >/dev/null; }
hdr(){ systemctl stop lab5g-qod 2>/dev/null; systemctl reset-failed lab5g-qod 2>/dev/null
  systemd-run --unit=lab5g-qod --setenv=QOD_GBR_HEADROOM=$1 python3 $S/qod-tc.py serve --listen 127.0.0.1:8090 --dl 15mbit --ul 8mbit >/dev/null; sleep 2; }
sssamp(){ for i in $(seq 1 $((DUR / 2))); do $NS ss -tin dst $E:18080 2>/dev/null | grep -oE 'cwnd:[0-9]+|rtt:[0-9.]+/[0-9.]+|pacing_rate [0-9.]+[MK]bps|unacked:[0-9]+|retrans:[0-9/]+' | tr '\n' ' '; echo; sleep 2; done > $D/$1-ss.txt; }
case_run(){ # name load(none|dl|full) headroom iperf-args
  local n=$1 ld=$2 hr=$3; shift 3
  health >/dev/null; hdr $hr; qod_del_all >/dev/null; qod
  case $ld in full) load_start $E $((DUR + 15)) tcpul-$n; sleep 8;; dl) $NS iperf3 -c $E -p 8123 -R -P 4 -t $((DUR + 15)) -J > $D/$n-bulk-dl.json 2>&1 & LP1=$!; LP2=; sleep 8;; esac
  tc -s class show dev ifb0 > $D/$n-tc-ifb0-pre.txt
  sssamp $n & SS=$!
  if [ "$1" = udp ]; then $NS python3 $S/udp-flow.py ul --host $E --port 4789 --kbps 5000 --dur $DUR > $D/$n-flow.json 2>&1
  else $NS iperf3 -c $E -p 18080 -t $DUR -J "$@" > $D/$n-flow.json 2>&1; fi
  wait $SS; tc -s class show dev ifb0 > $D/$n-tc-ifb0.txt; tc -s qdisc show dev ifb0 >> $D/$n-tc-ifb0.txt
  [ $ld != none ] && load_stop; qod_del_all >/dev/null
  grep -a -iE "bsr|ul.*grant|mcs" $L/enb.stdout 2>/dev/null | tail -5 > $D/$n-enb-mac.txt
  log "tcpul $n: $(python3 - $D/$n-flow.json <<'PY'
import json,sys
try: j=json.load(open(sys.argv[1]))
except Exception: print('parse-error'); sys.exit()
if 'goodput_kbps' in j: print(f"udp goodput={j['goodput_kbps']} kbps loss={j.get('loss_pct')}%"); sys.exit()
e=j.get('end',{}); s=e.get('sum_received',{}); t=e.get('sum_sent',{}); st=(e.get('streams') or [{}])[0].get('sender',{})
print(f"recv={s.get('bits_per_second',0)/1e6:.2f} Mbit/s retrans={t.get('retransmits')} max_cwnd={st.get('max_snd_cwnd')} mean_rtt_ms={(st.get('mean_rtt') or 0)/1000:.1f}")
PY
)"
}
case_run A full 1.1 -b 5M
case_run B full 1.1
case_run C full 1.1 -b 5M --fq-rate 5M
case_run D full 1.5 -b 5M
case_run E dl 1.1 -b 5M
case_run F none 1.1 -b 5M
case_run G full 1.1 udp
hdr 1.1
log "tcpul done (see $D)"
