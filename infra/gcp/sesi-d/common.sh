# Sesi D common helpers (sourced; vm-core-ran, root). No secrets, IMSI redacted in any copied NF log line.
S=/opt/lab5g/sesi-c; SD=/opt/lab5g/sesi-d; V=/opt/lab5g/vnc; L=/var/log/lab5g; NS="ip netns exec ue1"
P=$L/sesi-d; mkdir -p $P
ts(){ TZ=Asia/Jakarta date '+%F %T WIB'; }
log(){ echo "$(ts) $*" | tee -a $P/run.log; }
ue_ip(){ $NS ip -4 -o addr show tun_srsue 2>/dev/null | awk '{print $4}' | cut -d/ -f1; }
redact(){ sed -E 's/\b00101[0-9]{10}\b/IMSI_REDACTED/g; s/IMSI\[[0-9]+\]/IMSI[redacted]/g; s/[0-9]{15}/IMSI_REDACTED/g'; }
rlf_count(){ grep -a -c -i -E "radio.link.failure|RLF" $L/ue.stdout $L/enb.stdout 2>/dev/null | awk -F: '{s+=$NF} END{print s+0}'; }
health(){ # ensure UE attached + data path + taps; re-attach once if needed. echo 0=ok 1=reattached
  if $NS ping -c 3 -W 2 -i 0.3 10.45.0.1 >/dev/null 2>&1 || $NS ping -c 3 -W 2 -i 0.3 8.8.8.8 >/dev/null 2>&1; then
    bash $SD/zeek-taps.sh ensure >/dev/null 2>&1; echo 0; return; fi
  log "health: UE data path down -> re-attach"
  bash $S/core-run.sh >/dev/null 2>&1; bash $V/gui-net-fix.sh >/dev/null 2>&1; bash $V/core-gre-emu.sh >/dev/null 2>&1
  bash $SD/zeek-taps.sh ensure >/dev/null 2>&1; echo 1
}
load_start(){ # $1 emu ip, $2 seconds: iperf3 TCP DL 4 streams + UL 1 stream (same as Sesi C)
  $NS iperf3 -c $1 -p 8123 -R -P 4 -t $2 -J > $P/$3-iperf-dl.json 2>&1 & LP1=$!
  $NS iperf3 -c $1 -p 6000 -t $2 -J > $P/$3-iperf-ul.json 2>&1 & LP2=$!
}
load_stop(){ kill -INT $LP1 $LP2 2>/dev/null; wait $LP1 $LP2 2>/dev/null; }
qod_post(){ curl -s -X POST -H 'Content-Type: application/json' -d "$1" http://127.0.0.1:8090/qod; }
qod_del_all(){ curl -s -X DELETE http://127.0.0.1:8090/qod/qod; }
