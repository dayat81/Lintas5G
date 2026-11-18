#!/bin/bash
# usage: emu-bench.sh LABEL [PROXY host:port]   -> CSV: label,proto,i,connect,appconnect,ttfb,total,code
L=$1; P=${2:-}; X=""; [ -n "$P" ] && X="-x http://$P"
F='%{time_connect},%{time_appconnect},%{time_starttransfer},%{time_total},%{http_code}'
curl -s -o /dev/null $X http://example.com/ >/dev/null; curl -s -o /dev/null $X https://www.wikipedia.org/ >/dev/null  # warm DNS
for i in $(seq 1 10); do echo "$L,http,$i,$(curl -s -o /dev/null $X -w "$F" http://example.com/)"; sleep 0.3; done
for i in $(seq 1 10); do echo "$L,https,$i,$(curl -s -o /dev/null $X -w "$F" https://www.wikipedia.org/)"; sleep 0.3; done
echo "STEAL_$L $(mpstat 1 3 | tail -1)"
