#!/bin/bash
N="ip netns exec ue1"
pkill iperf3; iperf3 -s -B 10.45.0.1 -D; sleep 1
(mpstat 1 25 > /var/log/lab5g/mpstat-iperf.txt) &
(vmstat 1 25 > /var/log/lab5g/vmstat-iperf.txt) &
echo "== iperf3 UL (UE->UPF) TCP 10s =="; $N iperf3 -c 10.45.0.1 -t 10 | tail -4
echo "== iperf3 DL (UPF->UE) TCP 10s =="; $N iperf3 -c 10.45.0.1 -t 10 -R | tail -4
wait
echo "== mpstat selama iperf (avg) =="; head -3 /var/log/lab5g/mpstat-iperf.txt | tail -1; tail -1 /var/log/lab5g/mpstat-iperf.txt
echo "== vmstat st col =="; awk 'NR>2{print $NF-0, $(NF-1)}' /var/log/lab5g/vmstat-iperf.txt | sort -n | tail -1; head -2 /var/log/lab5g/vmstat-iperf.txt
echo "== mpstat long-run (steal max/avg) =="; awk '$2=="all"{n++; s+=$(NF-2); st=$(NF-2); if(st>m)m=st} END{print "samples="n" steal_avg="s/n" steal_max="m}' /var/log/lab5g/mpstat.log 2>/dev/null; awk '$3=="all"{n++; s+=$(NF-2); st=$(NF-2); if(st>m)m=st} END{print "samples="n" steal_avg="s/n" steal_max="m}' /var/log/lab5g/mpstat.log
uptime
echo "== ZMQ late/underflow/overflow =="
for f in enb.stdout ue.stdout enb.log ue.log; do echo "$f: late=$(grep -ci 'late' /var/log/lab5g/$f) underflow=$(grep -ci 'underflow' /var/log/lab5g/$f) overflow=$(grep -ci 'overflow' /var/log/lab5g/$f) LUO=$(grep -cE '^[LUO]+$' /var/log/lab5g/$f)"; done
grep -iE "late|underflow|overflow" /var/log/lab5g/enb.log /var/log/lab5g/ue.log | tail -5
tail -3 /var/log/lab5g/enb_metrics.csv
