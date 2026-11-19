#!/bin/bash
# vm-core-ran GUI session bring-up (root). Idempotent; run at every boot by lab5g-gui-core.service
# (installed by terraform/startup/core-ran.sh when gui_session=true) or manually.
# Profile: EPC + srsRAN ZMQ + UE keepalive + gost proxy (emulator via UE), WITHOUT Sesi C QoD/HTB shaping,
# WITHOUT Zeek/Rx, with MTU/MSS fix, GRE L3 path for the emulator, watchdog and dashboard collector.
set -u
S=/opt/lab5g/sesi-c; V=/opt/lab5g/vnc; L=/var/log/lab5g; mkdir -p $L
log(){ echo "$(TZ=Asia/Jakarta date '+%F %T WIB') $*" | tee -a $L/gui-core-up.log; }
log "start"
# 0. collector first, so the dashboard shows progress during the (long) first install
bash $V/install-collector.sh >>$L/gui-core-up.log 2>&1 || log "collector install failed"
echo installing > /run/lab5g-phase 2>/dev/null || true
# 0b. 5G SA profile (terraform var ran_mode = sa-srsran | sa-ueransim | sa-oai): separate bring-up, same netns/tun names
RAN_MODE=$(curl -fsS -H 'Metadata-Flavor: Google' http://metadata.google.internal/computeMetadata/v1/instance/attributes/ran-mode 2>/dev/null || echo epc-srsran4g)
case "$RAN_MODE" in sa-*) log "ran_mode=$RAN_MODE -> sa-up.sh"; exec bash /opt/lab5g/sa/sa-up.sh "$RAN_MODE";; esac
# 1. install Open5GS + srsRAN (first boot only, ~12 min)
if [ ! -x /opt/lab5g/srsran/srsRAN_4G/build/srsue/src/srsue ] || ! dpkg -s open5gs >/dev/null 2>&1; then
  log "install"; bash $S/core-install.sh > $L/install.log 2>&1; log "install rc=$?"
fi
echo configuring > /run/lab5g-phase
# 2. EPC config + subscriber (output filtered: never log KEY/OPC/IMSI)
bash $S/core-config.sh 2>&1 | grep -v -i -E "key|opc|imsi" | tail -3 >>$L/gui-core-up.log
bash $S/enb-qci2.sh >/dev/null 2>&1
# 3. remove leftover Sesi C QoD shaping (HTB 15/8 Mbit + ifb) - not wanted for a GUI session
systemctl stop lab5g-qod 2>/dev/null; systemctl reset-failed lab5g-qod 2>/dev/null
python3 $S/qod-tc.py clear >/dev/null 2>&1 || true
tc qdisc del dev ogstun root 2>/dev/null; tc qdisc del dev ogstun ingress 2>/dev/null
ip link show ifb0 >/dev/null 2>&1 && { tc qdisc del dev ifb0 root 2>/dev/null; ip link del ifb0 2>/dev/null; }
# 4. eNB/UE attach + keepalive
echo attaching > /run/lab5g-phase
bash $S/core-run.sh 2>&1 | grep -E "attach successful|tun_srsue" | sed -E 's/[0-9]{15}/IMSI_REDACTED/g' >>$L/gui-core-up.log
bash $V/gui-net-fix.sh
# 5. gost proxy in the UE netns (DNAT :18080), MSS clamp on
MSS_CLAMP=1360 bash $V/core-proxy-gui.sh >>$L/gui-core-up.log 2>&1
# 5b. GRE from vm-emu -> UE netns (all emulator TCP/UDP via the UE; retried by the watchdog until vm-emu is up)
bash $V/core-gre-emu.sh >>$L/gui-core-up.log 2>&1 || log "core-gre-emu not ready yet (watchdog retries)"
# 6. watchdog
bash $V/install-watchdog.sh $V/ue-watchdog.sh >>$L/gui-core-up.log 2>&1
echo ready > /run/lab5g-phase
ip netns exec ue1 ping -c 5 -i 0.3 -W 2 8.8.8.8 | tail -1 | tee -a $L/gui-core-up.log
log "done"
