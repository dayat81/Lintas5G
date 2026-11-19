#!/bin/bash
# vm-core-ran (root), Sesi D: on top of the gui_session bring-up (EPC + srsRAN ZMQ + UE + GRE emulator path + watchdog):
# Rx peer (PCRF restart -> MUST be followed by a re-attach), tc HTB bottleneck DL 15 / UL 8 Mbit/s + QoD adapter,
# Zeek pkthash taps (ue/n3/n6) + the Sesi C Zeek (lo/ogstun, capture_loss). usage: core-prep.sh
. /opt/lab5g/sesi-d/common.sh
log "core-prep start"
for i in $(seq 1 120); do [ "$(cat /run/lab5g-phase 2>/dev/null)" = ready ] && break; sleep 10; done
log "gui-core phase=$(cat /run/lab5g-phase 2>/dev/null)"
bash $S/rx-setup.sh >/dev/null 2>&1 && log "rx peer ok (PCRF restarted)"
systemctl stop lab5g-watchdog.timer 2>/dev/null   # no concurrent re-attach while we re-attach
bash $S/core-run.sh 2>&1 | grep -E "Attach|tun_srsue" | redact | tail -2 | tee -a $P/run.log
bash $V/gui-net-fix.sh >/dev/null 2>&1; bash $V/core-gre-emu.sh >/dev/null 2>&1
systemctl start lab5g-watchdog.timer 2>/dev/null
python3 $S/qod-tc.py setup --dl 15mbit --ul 8mbit --depth 300 >/dev/null
systemctl stop lab5g-qod 2>/dev/null; systemctl reset-failed lab5g-qod 2>/dev/null
systemd-run --unit=lab5g-qod python3 $S/qod-tc.py serve --listen 127.0.0.1:8090 --dl 15mbit --ul 8mbit >/dev/null
bash $S/core-zeek.sh start >/dev/null 2>&1
bash $SD/zeek-taps.sh start | tee -a $P/run.log
log "ue_ip=$(ue_ip) ping: $($NS ping -c 5 -i 0.3 -W 2 8.8.8.8 | tail -1)"
tc -s qdisc show dev ogstun | head -3 >> $P/run.log
log "core-prep done"
