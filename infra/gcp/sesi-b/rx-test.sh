#!/bin/bash
# Varian Rx: AAR -> (PCRF) Gx RAR -> (SMF/PGW-C) GTPv2 Create Bearer -> MME -> E-RAB Setup eNB. Bukti di pcap lo + log NF.
# Usage: rx-test.sh <emu_ip> [hold_s] [qod_url]
E=$1; H=${2:-20}; Q=${3:-}; D=/var/log/lab5g/rx; mkdir -p $D
UE=$(ip netns exec ue1 ip -4 -o addr show tun_srsue | awk '{print $4}' | cut -d/ -f1)
T0=$(date '+%m/%d %T')
python3 /opt/lab5g/sesi-b/rx-af.py --pcrf 127.0.0.9 --ue $UE --remote $E --port 9000 --hold $H ${Q:+--qod-url $Q} 2>&1 | tee $D/rx-af.log
echo "== PCRF/SMF/SGWC/MME log (setelah $T0) =="
for n in pcrf smf sgwc mme; do echo "-- $n"; grep -a -E "Rx|Gx|RAR|AAR|Charging|Create Bearer|Delete Bearer|Bearer|E-RAB|ERROR|WARN" /var/log/open5gs/$n.log | tail -15 | sed -E 's/\b00101[0-9]{10}\b/IMSI_REDACTED/g; s/IMSI\[[0-9]+\]/IMSI[redacted]/g'; done | tee $D/rx-nf.log
echo "== UE dedicated bearer? =="; grep -a -i -E "bearer|EPS|ERAB" /var/log/lab5g/ue.stdout /var/log/lab5g/ue.log 2>/dev/null | tail -8 | tee -a $D/rx-nf.log
