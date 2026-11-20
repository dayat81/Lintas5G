#!/bin/bash
# run_variant_n5.sh: copy of run_variant.sh for the oai-n5-test lab (n5-lab/n5-ue*)
# run_variant.sh <tag> <ue 1|2> <mode: a|b|c> [dur=60] : one gate run. See RESULT.md for the variants.
T=$1; U=$2; M=$3; DUR=${4:-60}; D=/workspace/booster-qod-test; R=$D/res/$T; mkdir -p $R; rm -f $R/*
LAB=$(sudo docker inspect -f '{{.State.Pid}}' n5-lab); UP=$(sudo docker inspect -f '{{.State.Pid}}' n5-ue$U)
UEIP=$(sudo docker exec n5-ue$U ip -4 -o addr show oaitun_ue1 | awk '{print $4}' | cut -d/ -f1)
sudo docker exec n5-lab sh -c 'ip addr add 10.45.0.2/32 dev ogstun 2>/dev/null; pkill -f "[a]s_server.py"; pkill -f "[u]dpecho.py"; pkill -x iperf3; true'
sudo docker cp $D/as_server.py n5-lab:/tmp/as_server.py; sudo docker exec -d n5-lab python3 /tmp/as_server.py 6e6
sudo docker exec n5-lab rm -f /tmp/n3.pcap; sudo docker exec -d n5-lab sh -c "timeout $((DUR+25)) tcpdump -Z root -i lo -s 128 -w /tmp/n3.pcap udp port 2152 2>/tmp/td.err"
# netns for the 'phone' apps + booster relay (stand-in) when tunnel is used
sudo ip netns del appns$U 2>/dev/null; sudo ip netns add appns$U
sudo ip netns exec appns$U sh -c 'ip link set lo up'
sudo rm -f $R/relay.log
sudo BOOSTER_TUN_NETNS=/run/netns/appns$U nsenter -t $UP -n $D/fwd/booster_relay tun0 > /dev/null 2> $R/relay.log &
sleep 2
sudo ip netns exec appns$U sh -c 'ip addr add 10.111.222.1/32 dev tun0 && ip link set tun0 mtu 1500 up && ip route add default dev tun0 && ip addr add 10.111.222.2/32 dev lo 2>/dev/null; ip -o addr show tun0; ip route'  > $R/appns.txt 2>&1
sudo cp $D/bin/targetapp $D/bin/targetapp 2>/dev/null
case $M in
 a) TCMD="sudo ip netns exec appns$U $D/bin/targetapp"; BCMD="sudo ip netns exec appns$U python3"; DET=relay;;
 b) TCMD="sudo nsenter -t $UP -n $D/bin/targetapp"; BCMD="sudo ip netns exec appns$U python3"; DET=owner;;
 c) TCMD="sudo ip netns exec appns$U $D/bin/targetapp"; BCMD="sudo nsenter -t $UP -n python3"; DET=relay;;
esac
T0=$(date +%s.%N); echo $T0 > $R/t0
BASE=15   # seconds baseline (no boost) before the target flow is created / detected
sudo rm -f $R/events.jsonl
$BCMD $D/app_client.py bulk $DUR $R/bulk.csv & 
P1=$!
sleep 3
( sleep $((BASE-3)); $TCMD $D/app_client.py target $((DUR-BASE-3)) $R/target.csv ) &
P2=$!
python3 $D/detect_boost.py --mode $DET --relay-log $R/relay.log --uepid $UP --labpid $LAB --tag $T --ue $U --events $R/events.jsonl --hold 10 --delete-after ${DELAFTER:-0} --max $((DUR-5)) | tee $R/detect.out
wait $P1 $P2
sleep 2
sudo docker exec n5-lab pkill -x tcpdump; sleep 1; sudo docker cp n5-lab:/tmp/n3.pcap $R/n3.pcap >/dev/null
sudo pkill -f booster_relay; sudo ip netns del appns$U
python3 $D/qfi_flow.py $R/n3.pcap $R/events.jsonl $UEIP $R/$T | tee $R/qfi.txt
sudo docker exec n5-ue$U sh -c 'tail -2 /tmp/keepalive.log' | sed -E 's/10\.45\.[0-9.]+/10.45.x.x/g' | tee $R/keepalive.txt
sed -i -E "s/$UEIP/<UE>/g" $R/*.txt $R/*.jsonl $R/relay.log 2>/dev/null
