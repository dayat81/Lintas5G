#!/bin/bash
# 5G SA bring-up for vm-core-ran (ran_mode = sa-srsran | sa-ueransim | sa-oai). Called by vnc/gui-core-up.sh (exec), idempotent.
# Same names as the 4G profile: UE netns ue1, tun_srsue (srsUE), N3 GTP-U on lo, gNB bind 127.0.1.1, N6 ogstun,
# so sesi-d (zeek-taps, run-quic, str-loop) and core-gre-emu work unchanged.
# Never logs KEY/OPC/IMSI (subscriber in /root/lab5g-sub.env 0600, srsUE config 0600).
set -u
MODE=${1:-sa-srsran}; SA=/opt/lab5g/sa; V=/opt/lab5g/vnc; L=/var/log/lab5g; mkdir -p $L/sa
log(){ echo "$(TZ=Asia/Jakarta date '+%F %T WIB') [sa] $*" | tee -a $L/gui-core-up.log; }
echo installing > /run/lab5g-phase
if ! dpkg -s open5gs >/dev/null 2>&1 || { [ "$MODE" = sa-srsran ] && [ ! -x /opt/srsran/bin/gnb ]; } || \
   { [ "$MODE" = sa-oai ] && ! docker image inspect "$(curl -fsS -H 'Metadata-Flavor: Google' http://metadata.google.internal/computeMetadata/v1/instance/attributes/oai-gnb-image 2>/dev/null)" >/dev/null 2>&1; }; then
  log "install ($MODE)"; bash $SA/sa-install.sh "$MODE" > $L/sa/install.log 2>&1; log "install rc=$?"
fi
echo configuring > /run/lab5g-phase
bash $SA/sa-config.sh "$MODE" 2>&1 | grep -v -i -E "key|opc|imsi|k=" | tail -5 | sed 's/^/[sa] /' >> $L/gui-core-up.log
echo attaching > /run/lab5g-phase
NR_PAIRS=$(curl -fsS -H 'Metadata-Flavor: Google' http://metadata.google.internal/computeMetadata/v1/instance/attributes/nr-pairs 2>/dev/null || echo 1)
if [ "$MODE" = sa-oai ]; then
  # OAI gNB + 1..3 nrUE (rfsim, 2x2 + 256QAM by default; env/metadata oai-rf, oai-mimo), see oai-run.sh
  OAI_RF=$(curl -fsS -H 'Metadata-Flavor: Google' http://metadata.google.internal/computeMetadata/v1/instance/attributes/oai-rf 2>/dev/null || echo rfsim)
  OAI_MIMO=$(curl -fsS -H 'Metadata-Flavor: Google' http://metadata.google.internal/computeMetadata/v1/instance/attributes/oai-mimo 2>/dev/null || echo 2)
  log "sa-oai ues=$NR_PAIRS rf=$OAI_RF mimo=$OAI_MIMO -> oai-config/run"
  { OAI_MIMO=$OAI_MIMO bash $SA/oai-config.sh "$NR_PAIRS" && OAI_RF=$OAI_RF OAI_MIMO=$OAI_MIMO bash $SA/oai-run.sh start "$NR_PAIRS"; } 2>&1 | sed -E 's/[0-9]{15}/IMSI_REDACTED/g' | tail -12 | sed 's/^/[sa] /' >> $L/gui-core-up.log
elif [ "$MODE" = sa-srsran ] && [ "${NR_PAIRS:-1}" -gt 1 ] 2>/dev/null; then
  log "nr-pairs=$NR_PAIRS -> nr-pairs-config/run"
  { bash $SA/nr-pairs-config.sh "$NR_PAIRS" && bash $SA/nr-pairs-run.sh start "$NR_PAIRS"; } 2>&1 | sed -E 's/[0-9]{15}/IMSI_REDACTED/g' | tail -12 | sed 's/^/[sa] /' >> $L/gui-core-up.log
else
bash $SA/sa-run.sh "$MODE" 2>&1 | sed -E 's/[0-9]{15}/IMSI_REDACTED/g' | tail -6 | sed 's/^/[sa] /' >> $L/gui-core-up.log
fi
bash $V/gui-net-fix.sh 2>/dev/null || true
bash $V/core-gre-emu.sh >> $L/gui-core-up.log 2>&1 || log "core-gre-emu not ready yet"
echo ready > /run/lab5g-phase
ip netns exec ue1 ping -c 5 -i 0.3 -W 2 8.8.8.8 | tail -1 | tee -a $L/gui-core-up.log
log "done"
