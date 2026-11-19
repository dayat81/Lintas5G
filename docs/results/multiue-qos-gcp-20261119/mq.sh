# Copy of the test scripts used on vm-core-ran (19 Nov 2026 run6); local only, not part of infra/.
#!/bin/bash
# mq.sh <cmd> ... : OAI multi-UE + dedicated QoS flow tests on vm-core-ran (run as root). Output /var/log/lab5g/mq/<tag>.
# IMSIs redacted in all printed output; UE IPs shown as hashes only.
SA=/opt/lab5g/sa; G=/var/log/lab5g/sa/oai-gnb.out; M=/opt/mq; B=/var/log/lab5g/mq; SRV=10.45.0.1; mkdir -p $B
red() { sed -E 's/[0-9]{15}/IMSI_REDACTED/g; s/10\.45\.[0-9]+\.[0-9]+/10.45.x.x/g'; }
uehash() { for i in 1 2 3; do ip=$(ip netns exec ue$i ip -4 -o addr show oaitun_ue1 2>/dev/null | awk '{print $4}' | cut -d/ -f1)
  printf 'ue%s=%s ' $i "$(python3 -c "import hashlib,socket,sys;print(hashlib.md5(socket.inet_aton(sys.argv[1])).hexdigest()[:6])" "$ip" 2>/dev/null)"; done; echo; }
gseg() { tail -c +$(( $1 + 1 )) $G; }
macsum() { # gNB log segment on stdin -> last MAC block per RNTI + counters
  python3 -c '
import re,sys
L=sys.stdin.read().splitlines(); m={}
for l in L:
  for k,rx in (("csi",r"(\w+): CSI \[CQI (\d+) RI (\d+)"),("dl",r"(\w+): dlsch_rounds ([\d/]+), dlsch_errors (\d+).*BLER ([\d.]+) MCS \((\d)\) (\d+)"),("ul",r"(\w+): ulsch_rounds ([\d/]+), ulsch_errors (\d+).*BLER ([\d.]+) MCS \((\d)\) (\d+)")):
    x=re.search(rx,l)
    if x: m.setdefault(x[1],{})[k]=x.groups()[1:]
for r,v in m.items(): print("MAC",r,"CQI/RI",v.get("csi"),"DL rounds/err/BLER/tbl/MCS",v.get("dl"),"UL",v.get("ul"))
print("reestablish",sum("Reestablishment RNTI" in l for l in L),"ULfailure",sum("Detected UL Failure" in l for l in L),"RRCRelease",sum("Send RRC Release" in l for l in L),"late/underflow",sum(bool(re.search("late decode|underflow",l,re.I)) for l in L))'; }
case "$1" in
start)
  bash $M/pcc.sh | red
  OAI_RF=vrtsim OAI_TIMESCALE=1.0 OAI_MIMO=2 bash $SA/oai-run.sh start 3 2>&1 | red
  sleep 8; uehash
  for i in 1 2 3; do echo "ue$i: $(grep -cE 'QoS rule 2 with QFI 2' /var/log/lab5g/sa/ue$i.out) qos-rule2, $(grep -c PduSessionModificationComplete /var/log/lab5g/sa/ue$i.out) modcomplete"; done
  grep -E "created new DRB|PDUSESSIONModify|Send RRC Release|Reestablishment RNTI" $G | red | cut -c1-140
  grep -h -E "Received PDU Session Modification Command|CREATE new QoS rule" /var/log/lab5g/sa/ue[12].out | red | cut -c1-140
  bash $SA/nr-health.sh rlf 3;;
t1)
  O=$B/t1; mkdir -p $O; off=$(stat -c %s $G)
  (bash $SA/nr-health.sh n3drop 60 1 > $O/n3drop.json 2>/dev/null &)
  PROTO=tcp DUR=60 MIN_PAIR=1 bash $SA/nr-iperf-run.sh 3 $O dl >/dev/null 2>&1
  gseg $off > $O/gnb.seg; macsum < $O/gnb.seg | red
  python3 -c "
import json;d=json.load(open('$O/summary.json'));x=d['dirs']['dl'];c=d.get('cpu',{}).get('dl',{})
print('t1 tcp dl per',x.get('per_pair_mbps'),'agg',x.get('aggregate_mbps'),'ratio',x.get('sim_ratio'),'air',x.get('air_mbps'),'busy',c.get('mean_busy_pct'),'max',c.get('max_sec_busy_pct'),'procs',c.get('procs_pct_of_1cpu'))"
  cat $O/n3drop.json; echo; bash $SA/nr-health.sh rlf 3;;
qfi)
  O=$B/qfi; mkdir -p $O; pkill -x iperf3; sleep 0.5
  for p in 18080 18081 5201 5202 5203; do iperf3 -s -D -B $SRV -p $p; done; sleep 1
  timeout 40 tcpdump -i lo -s 128 -w $O/n3.pcap udp port 2152 2>/dev/null & CP=$!; sleep 2
  n() { ip netns exec ue$1 "${@:2}" >/dev/null 2>&1; }
  n 1 ping -c 10 -i 0.2 $SRV
  n 1 iperf3 -c $SRV -p 18080 -t 3 -b 5M; n 1 iperf3 -c $SRV -p 18080 -t 3 -b 5M -R; n 1 iperf3 -c $SRV -p 18080 -t 3 -b 5M -u -R
  n 1 iperf3 -c $SRV -p 5201 -t 3 -b 5M -R
  n 2 iperf3 -c $SRV -p 18081 -t 3 -b 5M; n 2 iperf3 -c $SRV -p 18081 -t 3 -b 5M -R
  n 2 iperf3 -c $SRV -p 18080 -t 3 -b 5M -R; n 2 ping -c 10 -i 0.2 $SRV
  n 3 iperf3 -c $SRV -p 18080 -t 3 -b 5M -R; n 3 iperf3 -c $SRV -p 18081 -t 3 -b 5M -R; n 3 iperf3 -c $SRV -p 5203 -t 3 -b 5M -R
  sleep 2; kill -INT $CP; wait $CP 2>/dev/null; pkill -x iperf3
  uehash; python3 $M/qfi.py $O/n3.pcap | tee $O/qfi.txt
  echo "tshark cross-check (pdu_type QFI count):"; tshark -r $O/n3.pcap -Y gtp -T fields -e gtp.ext_hdr.pdu_ses_cont.pdu_type -e gtp.ext_hdr.pdu_ses_cont.qos_flow_id 2>/dev/null | sort | uniq -c;;
ab) # ab <tag> "<items>" items: app=<ue>:<port> (TCP DL 40M capped + UDP RTT probe 50 pps on same port), bulk=<ue> (UDP DL 100M port 5210+ue)
  T=$2; O=$B/$T; mkdir -p $O; D=${DUR:-40}; pkill -x iperf3; pkill -f "$M/echo.py"; sleep 0.5
  for it in $3; do k=${it%%=*}; v=${it#*=}
    if [ $k = app ]; then p=${v#*:}; iperf3 -s -1 -D -B $SRV -p $p; setsid nohup python3 $M/echo.py $SRV $p >/dev/null 2>&1 < /dev/null &
    else iperf3 -s -1 -D -B $SRV -p $((5210 + v)); fi; done; sleep 1
  [ "$CAP" = 1 ] && { timeout $((D + 4)) tcpdump -i lo -s 96 -w $O/n3.pcap udp port 2152 2>/dev/null & }
  off=$(stat -c %s $G)
  python3 $SA/nr_summary.py cpu --seconds $((D - 10)) --out $O/cpu.json >/dev/null & PIDS="$!"
  for it in $3; do k=${it%%=*}; v=${it#*=}
    if [ $k = app ]; then u=${v%%:*}; p=${v#*:}
      timeout $((D + 20)) ip netns exec ue$u iperf3 -c $SRV -p $p -t $D -R -b 40M -J > $O/app.ue$u.p$p.json 2>&1 & PIDS="$PIDS $!"
      ip netns exec ue$u python3 $M/probe.py $SRV $p $D 50 $O/rtt.ue$u.p$p.json & PIDS="$PIDS $!"
    else timeout $((D + 20)) ip netns exec ue$v iperf3 -c $SRV -p $((5210 + v)) -t $D -R -u -b 100M -l 1300 -J > $O/bulk.ue$v.json 2>&1 & PIDS="$PIDS $!"; fi
  done; wait $PIDS; pkill -f "$M/echo.py"
  gseg $off > $O/gnb.seg; python3 $SA/nr_summary.py ratio --log $G --start-offset $off --out $O/ratio.json >/dev/null
  python3 - $O <<'PY'
import json,glob,os,re,sys
o=sys.argv[1]
def thr(f):
    try:
        d=json.load(open(f)); e=d["end"]
        if d["start"]["test_start"]["protocol"]=="TCP": return round(e["sum_received"]["bits_per_second"]/1e6,1),""
        s=e["sum"]; return round(s["bits_per_second"]*(1-s.get("lost_percent",0)/100)/1e6,1),f" loss {s.get('lost_percent',0):.0f}%"
    except Exception as x: return None," ERR "+str(json.load(open(f)).get("error",""))[:60] if os.path.getsize(f) else " ERR"
for f in sorted(glob.glob(o+"/app.*.json"))+sorted(glob.glob(o+"/bulk.*.json")):
    v,x=thr(f); print(os.path.basename(f)[:-5],"Mbit/s",v,x)
for f in sorted(glob.glob(o+"/rtt.*.json")):
    r=json.load(open(f)); print(os.path.basename(f)[:-5],"RTT p50/p90/p99/max ms",r["p50_ms"],r["p90_ms"],r["p99_ms"],r["max_ms"],"loss%",r["loss_pct"])
try: print("ratio",json.load(open(o+"/ratio.json")))
except Exception: pass
try:
    c=json.load(open(o+"/cpu.json")); print("cpu busy",c.get("mean_busy_pct"),"max",c.get("max_sec_busy_pct"),"procs",c.get("procs_pct_of_1cpu"))
except Exception: pass
PY
  macsum < $O/gnb.seg | red
  [ "$CAP" = 1 ] && { sleep 3; uehash; python3 $M/qfi.py $O/n3.pcap | tee $O/qfi.txt; rm -f $O/n3.pcap; }
  bash $SA/nr-health.sh rlf 3;;
status) bash $SA/oai-run.sh status 3; bash $SA/nr-health.sh rlf 3;;
collect) cd $B && for f in $(find . -name '*.json' -o -name '*.txt'); do :; done
  tar czf /tmp/mq.tgz --exclude='*.pcap' --exclude='gnb.seg' -C /var/log/lab5g mq && sed -E 's/[0-9]{15}/IMSI_REDACTED/g' $G > /tmp/oai-gnb.red
  for i in 1 2 3; do sed -E 's/[0-9]{15}/IMSI_REDACTED/g' /var/log/lab5g/sa/ue$i.out > /tmp/ue$i.red; done
  tar czf /tmp/mqlogs.tgz -C /tmp oai-gnb.red ue1.red ue2.red ue3.red; ls -la /tmp/mq.tgz /tmp/mqlogs.tgz;;
esac
