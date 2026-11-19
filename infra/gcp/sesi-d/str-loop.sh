#!/bin/bash
# vm-core-ran (root), Sesi D: STR auto-remove under continuous load, N cycles (default 10). Per cycle:
# AAR (Rx, TCP emu:9000, gbr 5 Mbit/s) -> AAA -> adapter apply (tc filters 6) -> hold H s with ping probe -> STR -> STA ->
# adapter DELETE (filters 0) -> post-STR ping probe P s (latency back to load level?) -> RLF / link check (ZMQ stability).
# A cycle whose link dies is recorded (rlf, reattach) and the UE is re-attached before the next cycle.
# usage: str-loop.sh <emu_ip> [N=10 H=30 PROBE=30]
. /opt/lab5g/sesi-d/common.sh
E=${1:?emu_ip}; N=${N:-10}; H=${H:-30}; PR=${PROBE:-30}; D=$P/str; mkdir -p $D
fc(){ echo $(( $(tc filter show dev ogstun | grep -c flowid) + $(tc filter show dev ifb0 | grep -c 'flowid 1:10') )); }
pst(){ awk -F'time=' '/time=/{split($2,a," "); v[++n]=a[1]} END{if(!n){print "n=0";exit} asort(v); printf "n=%d p50=%.1f p99=%.1f", n, v[int(n*.5)+1], v[(int(n*.99)>0)?int(n*.99):1]}' $1; }
echo -e "cycle\tfilters_before\tfilters_qod\tfilters_after\tsta\tremove_ms\tqod_ping\tpost_ping\trlf_delta\tlink_ok\treattached" > $D/str-cycles.tsv
load_start $E $(( N * (H + PR + 40) + 60 )) str; sleep 8
for c in $(seq 1 $N); do
  re=$(health); r0=$(rlf_count); f0=$(fc); UE=$(ue_ip)
  python3 $S/rx-af.py --pcrf 127.0.0.9 --ue $UE --remote $E --port 9000 --hold $H --qod-url http://127.0.0.1:8090 > $D/c$c-rx.log 2>&1 & RX=$!
  sleep 3; f1=$(fc)
  $NS ping -i 0.2 -c $(( (H - 5) * 5 )) -W 3 $E > $D/c$c-qod-ping.txt 2>&1
  wait $RX; sleep 1; f2=$(fc)
  $NS ping -i 0.2 -c $(( PR * 5 )) -W 3 $E > $D/c$c-post-ping.txt 2>&1
  sleep 5; r1=$(rlf_count)
  ok=1; $NS ping -c 3 -W 2 -i 0.3 10.45.0.1 >/dev/null 2>&1 || ok=0
  sta=$(grep -a -oE "STA[^,]*2001|Result-Code[^,]*2001" $D/c$c-rx.log | head -1 | grep -q 2001 && echo 2001 || echo none)
  rms=$(tail -1 $L/tc/adapter.log 2>/dev/null | python3 -c "import json,sys;o=json.loads(sys.stdin.read() or '{}');print(o.get('remove_ms',''))" 2>/dev/null)
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' $c $f0 $f1 $f2 $sta "$rms" "$(pst $D/c$c-qod-ping.txt)" "$(pst $D/c$c-post-ping.txt)" $((r1 - r0)) $ok $re >> $D/str-cycles.tsv
  log "str c$c: filters $f0->$f1->$f2 sta=$sta remove_ms=$rms qod[$(pst $D/c$c-qod-ping.txt)] post[$(pst $D/c$c-post-ping.txt)] rlf+=$((r1 - r0)) link_ok=$ok"
  sleep 5
done
load_stop
for n in pcrf smf sgwc mme; do echo "-- $n"; grep -a -E "STR|Session-Termination|Delete Bearer|Bearer removed|E-RAB|ERROR" /var/log/open5gs/$n.log | tail -25 | redact; done > $D/str-nf.log
log "str done: $(awk -F'\t' 'NR>1{t++; if($4==0)r++; if($9>0)f++; if($10==1)o++} END{printf "cycles=%d filters_removed=%d rlf_cycles=%d link_ok=%d", t, r, f, o}' $D/str-cycles.tsv)"
