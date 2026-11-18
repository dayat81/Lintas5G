#!/bin/bash
# vm-core-ran (root): Emulator Usability gate - core side. Run with nohup; logs in /var/log/lab5g/usability/.
# K2: UE ping 30 min (loss <1%, p95 per 5-min window, max gap); K1: reattach count; plus iperf3 TCP via UE (retrans).
# usage: DUR_MIN=30 IPERF_SERVER=<vm-emu internal IP, running: iperf3 -s -p 9000> bash usability-core.sh  (tcp 9000 is allowed internally)
D=/var/log/lab5g/usability; mkdir -p $D; DUR=$(( ${DUR_MIN:-30} * 60 )); N="ip netns exec ue1"
R0=$(grep -c "REATTACH mulai" /var/log/lab5g/watchdog.log 2>/dev/null || echo 0)
if [ -n "${IPERF_SERVER:-}" ]; then
  $N iperf3 -c $IPERF_SERVER -p ${IPERF_PORT:-9000} -R -t 60 -J > $D/iperf-tcp-dl.json 2>&1
  $N iperf3 -c $IPERF_SERVER -p ${IPERF_PORT:-9000} -t 60 -J > $D/iperf-tcp-ul.json 2>&1
fi
$N ping -i 1 -D -W 2 -c $DUR 8.8.8.8 > $D/ping-30min.txt 2>&1
R1=$(grep -c "REATTACH mulai" /var/log/lab5g/watchdog.log 2>/dev/null || echo 0)
python3 - "$D" "$((R1-R0))" <<'P'
import re,sys,json
D,reat=sys.argv[1],int(sys.argv[2]); ts=[];rt=[];sent=0
for l in open(f"{D}/ping-30min.txt"):
    m=re.match(r"\[(\d+\.\d+)\].*icmp_seq=(\d+).*time=([\d.]+)",l)
    if m: ts.append(float(m.group(1))); rt.append(float(m.group(3)))
    m=re.search(r"(\d+) packets transmitted",l); sent=int(m.group(1)) if m else sent
loss=100*(sent-len(rt))/sent if sent else None
gaps=[b-a for a,b in zip(ts,ts[1:])]; win={}
for t,r in zip(ts,rt): win.setdefault(int((t-ts[0])//300),[]).append(r)
p95={k:sorted(v)[int(len(v)*.95)-1] for k,v in sorted(win.items())}
res={"ping_sent":sent,"ping_loss_pct":round(loss,3) if loss is not None else None,"p95_per_5min_ms":p95,
     "max_gap_s":round(max(gaps),2) if gaps else None,"reattach_during_test":reat}
for f in ("iperf-tcp-dl","iperf-tcp-ul"):
    try:
        j=json.load(open(f"{D}/{f}.json")); e=j["end"]; s=e.get("sum_sent",{})
        res[f]={"mbps":round(e["sum_received"]["bits_per_second"]/1e6,2),"retransmits":s.get("retransmits")}
    except Exception: pass
res["K2_PASS"]=bool(loss is not None and loss<1)
json.dump(res,open(f"{D}/core-summary.json","w"),indent=1); print(json.dumps(res,indent=1))
P
