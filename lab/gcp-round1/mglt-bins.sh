#!/bin/bash
# mglt-bins.sh <run> <t_bulk_on> <boost_from> <boost_to>: MGLT v1 echo RTT (examine logcat) per phase: p50/p99/max/n
R=/var/log/lab5g/booster/runs/$1
grep "mglt echo" $R/logcat-booster.txt | awk -v L=$2 -v B0=$3 -v B1=$4 '{t=$1; for(i=1;i<=NF;i++) if($i ~ /^rtt_ms=/){split($i,a,"="); r=a[2]}
 ph=(t<L)?(t<B0||t>=B1?"1_idle":"1b_idle_boost"):((t>=B0&&t<B1)?"3_load_boost":"2_load_noboost"); print ph, r}' | sort -k1,1 -k2,2n | awk '
 {k=$1; v[k,++n[k]]=$2} END{for(k in n){m=n[k]; p50=v[k,int((m+1)/2)]; i99=int(0.99*m+0.999); if(i99<1)i99=1; printf "%s n=%d p50=%.1f p99=%.1f max=%.1f\n", k, m, p50, v[k,i99], v[k,m]}}' | sort
