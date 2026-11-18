#!/bin/bash
# Start nr-gnb (host) + nr-ue (netns ue1), tunggu uesimtun0, set default route, keepalive ping.
B=/opt/lab5g/ueransim/UERANSIM/build; C=/opt/lab5g/ueransim/conf; L=/var/log/lab5g
for u in lab5g-gnb lab5g-ue lab5g-keepalive; do systemctl stop $u 2>/dev/null; systemctl reset-failed $u 2>/dev/null; done
systemd-run --unit=lab5g-gnb bash -c "$B/nr-gnb -c $C/gnb.yaml > $L/gnb.log 2>&1"
sleep 3
systemd-run --unit=lab5g-ue bash -c "ip netns exec ue1 $B/nr-ue -c $C/ue.yaml > $L/ue.log 2>&1"
for i in $(seq 1 30); do ip netns exec ue1 ip -4 -o addr show uesimtun0 2>/dev/null | grep -q 10.45 && break; sleep 1; done
UEIP=$(ip netns exec ue1 ip -4 -o addr show uesimtun0 | awk '{print $4}' | cut -d/ -f1)
echo "UE_IP=$UEIP"
ip netns exec ue1 ip route replace default dev uesimtun0
ip netns exec ue1 ip route
echo "== gnb.log =="; tail -8 $L/gnb.log
echo "== ue.log (IMSI disamarkan) =="; sed -E 's/imsi-[0-9]+/imsi-REDACTED/g' $L/ue.log | tail -15
echo "== AMF/SMF =="; grep -E "Registration|InitialUEMessage|NG-Setup|PDU|Session|UE IPv4" /var/log/open5gs/amf.log /var/log/open5gs/smf.log | sed -E 's/(imsi|suci)-[0-9-]+/\1-REDACTED/g; s/\[[0-9]{15}\]/[REDACTED]/g' | tail -15
systemd-run --unit=lab5g-keepalive bash -c "ip netns exec ue1 ping -i 1 -D 10.45.0.1 > $L/keepalive.log 2>&1"
