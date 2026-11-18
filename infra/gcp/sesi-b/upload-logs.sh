#!/bin/bash
# Bundle log Zeek + pcap + log NF (+ UERANSIM, n5) lalu upload ke gs://<bucket>/sesi-b/<ts>/.
# Usage: upload-logs.sh <bucket> [ts]
B=${1:?bucket}; TS=${2:-$(date +%Y%m%d-%H%M%S)}
L=/var/log/lab5g; T=/tmp/sesi-b-$TS; mkdir -p $T
systemctl stop lab5g-zeek-lo lab5g-zeek-ogstun lab5g-pcap-lo lab5g-pcap-cp lab5g-pcap-n6 2>/dev/null; sleep 2
tar czf $T/zeek.tgz -C $L zeek 2>/dev/null
tar czf $T/pcap.tgz -C $L pcap 2>/dev/null
# log NF; IMSI/SUPI disamarkan sebelum keluar VM
mkdir -p $T/nf; for f in /var/log/open5gs/*.log; do sed -E 's/(imsi|suci|supi)-[0-9-]+/\1-REDACTED/g; s/\b00101[0-9]{10}\b/IMSI_REDACTED/g' $f > $T/nf/$(basename $f); done
for f in $L/*.log $L/*.txt $L/*.json $L/*.csv $L/rx/* $L/tc/* $L/p99/* ; do [ -f "$f" ] && sed -E 's/imsi-[0-9]+/imsi-REDACTED/g; s/\b00101[0-9]{10}\b/IMSI_REDACTED/g' "$f" > $T/nf/$(basename $f); done
tar czf $T/nf-logs.tgz -C $T nf && rm -rf $T/nf
ls -la $T
if command -v gcloud >/dev/null; then gcloud storage cp $T/* gs://$B/sesi-b/$TS/ ; else gsutil -m cp $T/* gs://$B/sesi-b/$TS/; fi
echo "UPLOADED gs://$B/sesi-b/$TS/"
(gcloud storage ls -l gs://$B/sesi-b/$TS/ 2>/dev/null || gsutil ls -l gs://$B/sesi-b/$TS/)
