#!/bin/bash
# accept.sh <tag> [ncycles=5] [profile=QOS_7]: N x (N5 create -> hold -> DELETE) on UE1 under high UDP UL+DL load
# inside the QoD flow (AS ports 18080 timeline 100 pps, 18081 DL iperf3, 18082 UL iperf3) + UE2 isolation traffic.
# PAR=1: UE2 runs a parallel session (QOS_L, AS ports 18080,18083,18084, own iperf3 DL/UL) created/deleted together with UE1.
# Checks: gNB alive/no assert, no PDU session release, no GTP-U Error Indication, same UE IP, keepalive loss.
T=$1; N=${2:-5}; P=${3:-QOS_7}; DLR=${DLR:-20M}; ULR=${ULR:-8M}; HOLD=${HOLD:-8}; GAP=${GAP:-5}
D=/workspace/oai-n5-test; R=$D/res/$T; mkdir -p $R; rm -f $R/*; DK="sudo docker"
PID=$($DK inspect -f '{{.State.Pid}}' n5-lab); U1=$(sudo cat $D/secrets/ue1.ip); U2=$(sudo cat $D/secrets/ue2.ip)
RED='s/imsi-[0-9]+/imsi-<redacted>/g; s/suci-[0-9-]+/suci-<redacted>/g; s/\b[0-9]{15}\b/<IMSI>/g; s/10\.45\.[0-9]+\.[0-9]+/10.45.x.x/g; s/\b(kausf|kseaf|kamf|knas[a-z_]*|kgnb|k_?enc|k_?int)\b.*/\1 <redacted>/Ig'
for c in n5-lab n5-ue1 n5-ue2; do $DK cp $D/udpgen.py $c:/tmp/udpgen.py; done
for n in smf upf amf pcf; do $DK exec n5-lab sh -c "wc -l < /var/log/open5gs/$n.log" > $R/$n.l0; done
$DK logs n5-gnb 2>&1 | wc -l > $R/gnb.l0; for i in 1 2; do $DK logs n5-ue$i 2>&1 | wc -l > $R/ue$i.l0; done
for i in 1 2; do $DK exec n5-ue$i sh -c "grep -o 'icmp_seq=[0-9]*' /tmp/keepalive.log | tail -1 | cut -d= -f2" > $R/ka$i.s0; done
GR0=$($DK inspect -f '{{.State.StartedAt}}' n5-gnb)
$DK exec n5-lab sh -c 'pkill -x iperf3; iperf3 -s -D -B 10.45.0.1 -p 18081; iperf3 -s -D -B 10.45.0.1 -p 18082; iperf3 -s -D -B 10.45.0.1 -p 18083; iperf3 -s -D -B 10.45.0.1 -p 18084'
DUR=$(( N*(HOLD+GAP+4) + 15 ))
$DK exec n5-lab rm -f /tmp/n3.pcap; $DK exec -d n5-lab sh -c "timeout $((DUR+15)) tcpdump -Z root -i lo -s 96 -w /tmp/n3.pcap udp port 2152 2>/tmp/td.err"
sleep 2
for u in 1 2; do U=$(sudo cat $D/secrets/ue$u.ip)
  $DK exec -d n5-lab python3 /tmp/udpgen.py 10.45.0.1 18080 $U 40000 100 $DUR /tmp/rx-as$u.log
  $DK exec -d n5-ue$u python3 /tmp/udpgen.py $U 40000 10.45.0.1 18080 100 $DUR /tmp/rx-ue$u.log; done
$DK exec -d n5-ue1 sh -c "iperf3 -c 10.45.0.1 -p 18081 -u -R -b $DLR -l 1200 -t $((DUR-10)) > /tmp/ipdl.txt 2>&1"
$DK exec -d n5-ue1 sh -c "iperf3 -c 10.45.0.1 -p 18082 -u -b $ULR -l 1200 -t $((DUR-10)) > /tmp/ipul.txt 2>&1"
if [ "${PAR:-0}" = 1 ]; then
  $DK exec -d n5-ue2 sh -c "iperf3 -c 10.45.0.1 -p 18083 -u -R -b $DLR -l 1200 -t $((DUR-10)) > /tmp/ipdl.txt 2>&1"
  $DK exec -d n5-ue2 sh -c "iperf3 -c 10.45.0.1 -p 18084 -u -b $ULR -l 1200 -t $((DUR-10)) > /tmp/ipul.txt 2>&1"
fi
sleep 5
for i in $(seq $N); do
  if [ "${PAR:-0}" = 1 ]; then
    sudo nsenter -t $PID -n env N5_CB_PORT=9998 $D/.venv/bin/python $D/n5proto.py cycle --imsi-file $D/secrets/imsi2 --ue-ip-file $D/secrets/ue2.ip \
      --profile QOS_L --mode persistent --protos 6,17 --as-port 18080,18083,18084 --hold $HOLD \
      --events $R/ev2-c$i.jsonl --callbacks $R/callbacks2.jsonl > $R/n5proto2-c$i.out 2>&1 &
  fi
  sudo nsenter -t $PID -n $D/.venv/bin/python $D/n5proto.py cycle --imsi-file $D/secrets/imsi1 --ue-ip-file $D/secrets/ue1.ip \
    --profile $P --mode persistent --protos 6,17 --as-port 18080,18081,18082 --hold $HOLD \
    --events $R/ev-c$i.jsonl --callbacks $R/callbacks.jsonl > $R/n5proto-c$i.out 2>&1
  wait; sleep $GAP
done
for s in $(seq 40); do $DK exec n5-ue1 pgrep -x iperf3 >/dev/null || $DK exec n5-ue2 pgrep -x iperf3 >/dev/null || break; sleep 1; done
$DK exec n5-ue1 pkill -x iperf3; $DK exec n5-ue2 pkill -x iperf3; sleep 2
for u in 1 2; do $DK cp n5-lab:/tmp/rx-as$u.log $R/ 2>/dev/null; $DK cp n5-ue$u:/tmp/rx-ue$u.log $R/ 2>/dev/null; done
$DK exec n5-lab pkill -x tcpdump; sleep 2; sudo rm -f $R/n3.pcap; $DK cp n5-lab:/tmp/n3.pcap $R/n3.pcap >/dev/null
$DK exec n5-lab sh -c "tail -n +$(( $(cat $R/smf.l0)+1 )) /var/log/open5gs/smf.log" > /tmp/n5-smf-raw.log
for n in smf upf amf pcf; do $DK exec n5-lab sh -c "tail -n +$(( $(cat $R/$n.l0)+1 )) /var/log/open5gs/$n.log" | sed -E "$RED" > $R/$n.win.log; done
$DK logs n5-gnb 2>&1 | tail -n +$(( $(cat $R/gnb.l0)+1 )) | sed -E "$RED" > $R/gnb.win.log
for i in 1 2; do $DK logs n5-ue$i 2>&1 | tail -n +$(( $(cat $R/ue$i.l0)+1 )) | sed -E "$RED" > $R/ue$i.win.log; done
for x in dl ul; do $DK exec n5-ue1 cat /tmp/ip$x.txt | grep -E "receiver|error" | sed -E "$RED" > $R/iperf-ue1-$x.txt; done
[ "${PAR:-0}" = 1 ] && for x in dl ul; do $DK exec n5-ue2 cat /tmp/ip$x.txt | grep -E "receiver|error" | sed -E "$RED" > $R/iperf-ue2-$x.txt; done
{
echo "gnb_running=$($DK inspect -f '{{.State.Running}}' n5-gnb) gnb_restarted=$([ "$GR0" = "$($DK inspect -f '{{.State.StartedAt}}' n5-gnb)" ] && echo no || echo YES)"
echo "rrc_setup_or_reest=$(grep -ciE 'Send RRC Setup|Reestablishment' $R/gnb.win.log) drb_already_exists=$(grep -cE 'DRB [0-9]+ already exists|LCID [0-9]+: already present' $R/gnb.win.log) ul_failure=$(grep -c 'UL Failure' $R/gnb.win.log) pdcp_no_rb=$(grep -ci 'no RB found' $R/gnb.win.log)"
echo "gnb_assert_or_crash=$(grep -ciE 'assert|segmentation|signal 11|core dumped' $R/gnb.win.log)"
echo "gnb_tbs_null=$(grep -c 'compute TBS with a NULL' $R/gnb.win.log)"
echo "gnb_pdu_release=$(grep -ciE 'PDU Session Release command|PDUSESSIONRelease|NOTIFYONRELEASE|requesting RRC connection release|Deleting N3 tunnel' $R/gnb.win.log)"
echo "amf_release=$(grep -ciE 'PDUSessionResourceRelease|UEContextRelease|Deregistration' $R/amf.win.log)"
echo "error_indication_upf=$(grep -ci 'Error Indication' $R/upf.win.log) error_indication_gnb=$(grep -ciE 'Error.?Indication' $R/gnb.win.log)"
for i in 1 2; do o=$(sudo cat $D/secrets/ue$i.ip); c=$($DK exec n5-ue$i ip -4 -o addr show oaitun_ue1 | awk '{print $4}' | cut -d/ -f1); [ "$o" = "$c" ] && echo "ue${i}_ip_same=yes" || echo "ue${i}_ip_same=NO"; done
for i in 1 2; do s0=$(cat $R/ka$i.s0); $DK exec n5-ue$i sh -c "grep -o 'icmp_seq=[0-9]*' /tmp/keepalive.log | cut -d= -f2" | awk -v s0=$s0 -v u=$i '$1>s0{n++; if(!min||$1<min)min=$1; if($1>max)max=$1} END{e=max-min+1; printf "ue%s_keepalive rx=%d expected=%d lost=%d\n",u,n,e,e-n}'; done
} | tee $R/checks.txt
python3 $D/accept_timeline.py $R/n3.pcap $U1 $U2 $(ls $R/ev-c*.jsonl | sort -V) > $R/qfi-cycles.json
python3 $D/deliv.py $R $U1 $U2 > $R/delivery.jsonl; sudo rm -f $R/rx-*.log
[ "${PAR:-0}" = 1 ] && TARGET_UE=ue2 python3 $D/accept_timeline.py $R/n3.pcap $U1 $U2 $(ls $R/ev2-c*.jsonl | sort -V) > $R/qfi-cycles-ue2.json
python3 $D/smf_lat.py /tmp/n5-smf-raw.log $(ls $R/ev-c*.jsonl | sort -V) > $R/smf-lat.json; sudo rm -f /tmp/n5-smf-raw.log
for f in $R/*.jsonl $R/*.out $R/*.json; do sed -i -E "$RED" $f; done; rm -f $R/*.l0 $R/ka*.s0
python3 - $R <<'PY'
import json,sys; R=sys.argv[1]
q=json.load(open(R+'/qfi-cycles.json')); s=[json.loads(l) for l in open(R+'/smf-lat.json')][0]
for a,b in zip(q,s): print(a['cycle'], 'create', b.get('create_status'), 'del', b.get('delete_status'), '| apply DL/UL', a['apply_DL_ms'], a['apply_UL_ms'],
   '| remove DL/UL(firstQFI1)', a['remove_DL_ms_lastQoD_firstQFI1'][1], a['remove_UL_ms_lastQoD_firstQFI1'][1], '| SMF create->modrsp', b.get('create_to_gnb_mod_rsp_ms'), 'delete->modrsp', b.get('delete_to_gnb_mod_rsp_ms'), '| ue2', a['other_ue_DL_qfi'], a['other_ue_UL_qfi'])
PY
[ -f $R/qfi-cycles-ue2.json ] && python3 -c "import json;[print('ue2',a['cycle'],'apply DL/UL',a['apply_DL_ms'],a['apply_UL_ms'],'remove DL/UL',a['remove_DL_ms_lastQoD_firstQFI1'][1],a['remove_UL_ms_lastQoD_firstQFI1'][1]) for a in json.load(open('$R/qfi-cycles-ue2.json'))]"
echo "== target flow delivery per session (AS:18080<->UE:40000, 100 pps, window create+1s..delete)"; cat $R/delivery.jsonl
python3 -c "import json;r=[json.loads(l) for l in open('$R/delivery.jsonl')];print('delivery_verdict', 'PASS' if r and all(x['dl_loss_pct']<=1 and x['ul_loss_pct']<=1 for x in r) else 'FAIL', 'max_dl_loss',max(x['dl_loss_pct'] for x in r),'max_ul_loss',max(x['ul_loss_pct'] for x in r))" | tee -a $R/checks.txt
grep -H receiver $R/iperf-*.txt | sed "s|$R/||"
