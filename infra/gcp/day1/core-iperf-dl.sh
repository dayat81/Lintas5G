#!/bin/bash
N="ip netns exec ue1"
pkill iperf3; sleep 1; iperf3 -s -B 10.45.0.1 -1 -D; sleep 1
(mpstat 1 12 > /var/log/lab5g/mpstat-iperf-dl.txt) &
echo "== iperf3 DL (UPF->UE) TCP 10s =="; $N iperf3 -c 10.45.0.1 -t 10 -R | tail -4
wait; tail -1 /var/log/lab5g/mpstat-iperf-dl.txt
echo "== steal vm-core-ran (mpstat 5s, seluruh tes) =="; awk '$2=="all" && $1!="Average:"{n++; st=$(NF-3); s+=st; if(st>m)m=st} END{printf "samples=%d steal_avg=%.2f steal_max=%.2f\n",n,s/n,m}' /var/log/lab5g/mpstat.log
awk '$2=="all"{st=$(NF-3); if(st>m)m=st; u=$3+$5; if(u>mu)mu=u} END{print "iperf window steal_max="m" usr+sys_max="mu}' /var/log/lab5g/mpstat-iperf.txt /var/log/lab5g/mpstat-iperf-dl.txt
echo "== keepalive =="; tail -2 /var/log/lab5g/keepalive.log; grep -c "bytes from" /var/log/lab5g/keepalive.log
grep -E "^[LUO]" /var/log/lab5g/ue.stdout /var/log/lab5g/enb.stdout | head
