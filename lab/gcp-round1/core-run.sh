#!/bin/bash
# core-run.sh <tag> <dur_s> <bulk_start_s> [bulk_rate]: N3 capture + intra-UE DL bulk (default bearer) for one booster run.
set -u
T=$1; DUR=$2; BS=$3; RATE=${4:-150M}; R=/var/log/lab5g/booster/runs/$T; mkdir -p $R
now(){ date +%s.%N; }
pkill -f "tcpdump -i lo -s 128" 2>/dev/null; pkill -x iperf3 2>/dev/null; ip netns exec ue1 pkill -x iperf3 2>/dev/null
iperf3 -s -B 10.45.0.1 -p 5201 -D
for f in amf smf pcf upf; do wc -l < /var/log/open5gs/$f.log > $R/$f.l0; done
wc -l < /var/log/lab5g/sa/oai-gnb.out > $R/gnb.l0; docker logs qod-adapter 2>&1 | wc -l > $R/adapter.l0
wc -l < /var/log/lab5g/booster/backend.log > $R/backend.l0
timeout $((DUR+5)) tcpdump -i lo -s 128 -B 32768 -w $R/n3.pcap udp port 2152 2>$R/tcpdump.err &
echo "t_start $(now)" > $R/times
ip netns exec ue1 ip -4 -o addr show oaitun_ue1 | awk '{print $4}' | cut -d/ -f1 > $R/.ueip; chmod 600 $R/.ueip
sleep $BS
echo "t_bulk_on $(now)" >> $R/times
ip netns exec ue1 iperf3 -c 10.45.0.1 -p 5201 -R -u -b $RATE -l 1300 -t $((DUR-BS-2)) --forceflush -i 5 > $R/iperf-bulk.txt 2>&1
echo "t_bulk_off $(now)" >> $R/times
wait
echo "t_end $(now)" >> $R/times
for f in amf smf pcf upf; do tail -n +$(( $(cat $R/$f.l0)+1 )) /var/log/open5gs/$f.log | sed -E 's/imsi-[0-9]+/imsi-<redacted>/g; s/\b[0-9]{15}\b/<IMSI>/g; s/10\.45\.[0-9]+\.[0-9]+/10.45.x.x/g' > $R/$f.win.log; done
tail -n +$(( $(cat $R/gnb.l0)+1 )) /var/log/lab5g/sa/oai-gnb.out | sed -E 's/\b[0-9]{15}\b/<IMSI>/g' > $R/gnb.win.log
docker logs qod-adapter 2>&1 | tail -n +$(( $(cat $R/adapter.l0)+1 )) | sed -E 's/\b[0-9]{15}\b/<IMSI>/g; s/10\.45\.[0-9]+\.[0-9]+/10.45.x.x/g' > $R/adapter.win.log
tail -n +$(( $(cat $R/backend.l0)+1 )) /var/log/lab5g/booster/backend.log | sed -E 's/10\.45\.[0-9]+\.[0-9]+/10.45.x.x/g' > $R/backend.win.log
grep -cE 'Error Indication|PDU Session Release|Release Command|Assertion|Segmentation|double free' $R/*.win.log > $R/bad-counts.txt
echo done $T
