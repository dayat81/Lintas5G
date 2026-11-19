#!/bin/bash
# Start the 5G SA RAN: srsRAN Project gNB + srsUE (ZMQ) as systemd units, or UERANSIM (sa-ueransim).
# Then default route in netns ue1 + UE keepalive (mandatory: the UE must never go idle).
MODE=${1:-sa-srsran}; C=/etc/lab5g/sa; L=/var/log/lab5g/sa; mkdir -p $L
if [ "$MODE" = sa-ueransim ]; then bash /opt/lab5g/sesi-a/ueransim-run.sh; TUN=uesimtun0; else
  TUN=tun_srsue
  # shellcheck disable=SC1091
  . "$(cd "$(dirname "$0")" && pwd)/zmq-pair-lib.sh"
  # ordered + supervised start (gNB ready -> UE, pair restart on failure); see zmq-pair-lib.sh for the root cause
  zmq_pair_up lab5g-gnb lab5g-srsue $L/gnb.out $L/ue.out ue1 $TUN 2000 \
    "stdbuf -oL /opt/srsran/bin/gnb -c $C/gnb.yaml" "stdbuf -oL /opt/srsran/bin/srsue $C/ue.conf" || echo "sa-run: pair start FAILED"
fi
for _ in $(seq 1 60); do ip netns exec ue1 ip -4 -o addr show $TUN 2>/dev/null | grep -q inet && break; sleep 2; done
UEIP=$(ip netns exec ue1 ip -4 -o addr show $TUN 2>/dev/null | awk '{print $4}')
echo "ue $TUN ${UEIP:-NO_IP}"
[ -n "$UEIP" ] && ip netns exec ue1 ip route replace default dev $TUN
grep -m2 -E "PDU Session Establishment successful|RRC Connected" $L/ue.out 2>/dev/null
systemctl stop lab5g-ue-keepalive 2>/dev/null; systemctl reset-failed lab5g-ue-keepalive 2>/dev/null
systemd-run --unit=lab5g-ue-keepalive -p Restart=always ip netns exec ue1 ping -i 1 -W 2 8.8.8.8 >/dev/null
