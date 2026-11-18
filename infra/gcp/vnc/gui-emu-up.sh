#!/bin/bash
# vm-emu GUI session bring-up (root). Idempotent; run at every boot by lab5g-gui-emu.service
# (installed by terraform/startup/emu.sh when gui_session=true) or manually.
# Settings come from env, else from instance metadata (terraform vars gui_*):
#   CORE_IP (metadata core-proxy host), EMU_EGRESS (gui-emu-egress, default ue-l3), EMU_API (gui-emu-api, default 36),
#   EMU_IMG_TYPE (gui-emu-img-type), EMU_DEVICE (gui-emu-device), EMU_SCREEN (gui-emu-screen), COST_PER_HOUR.
set -u
V=/opt/lab5g/vnc; L=/var/log/lab5g; mkdir -p $L
MD=http://metadata.google.internal/computeMetadata/v1/instance/attributes
md(){ curl -fsS -m 3 -H "Metadata-Flavor: Google" "$MD/$1" 2>/dev/null; }
log(){ echo "$(TZ=Asia/Jakarta date '+%F %T WIB') $*" | tee -a $L/gui-emu-up.log; }
if [ -z "${CORE_IP:-}" ]; then
  H=$(md core-proxy | sed -E 's#^[a-z]+://##; s#:[0-9]+/?$##')
  for i in $(seq 1 30); do CORE_IP=$(getent ahostsv4 "$H" | awk 'NR==1{print $1}'); [ -n "$CORE_IP" ] && break; sleep 5; done
fi
: "${CORE_IP:?CORE_IP tidak ditemukan}"; export CORE_IP
pick(){ local v="$1" k="$2" d="$3"; [ -n "$v" ] && { echo "$v"; return; }; v=$(md "$k"); echo "${v:-$d}"; }
export COST_PER_HOUR=$(pick "${COST_PER_HOUR:-}" gui-cost-per-hour 0.80)
export EMU_EGRESS=$(pick "${EMU_EGRESS:-}" gui-emu-egress ue-l3)
export EMU_API=$(pick "${EMU_API:-}" gui-emu-api 36)
export EMU_IMG_TYPE=$(pick "${EMU_IMG_TYPE:-}" gui-emu-img-type google_apis_playstore)
export EMU_DEVICE=$(pick "${EMU_DEVICE:-}" gui-emu-device "Pixel C")
export EMU_SCREEN=$(pick "${EMU_SCREEN:-}" gui-emu-screen 1920x1080)
export EMU_GPU_KIND=$(pick "${EMU_GPU_KIND:-}" gui-emu-gpu none)
export EMU_USERDATA_URI=$(pick "${EMU_USERDATA_URI:-}" gui-emu-userdata-uri "")
log "start CORE_IP=$CORE_IP egress=$EMU_EGRESS api=$EMU_API img=$EMU_IMG_TYPE device=$EMU_DEVICE screen=$EMU_SCREEN gpu=$EMU_GPU_KIND"
DEBIAN_FRONTEND=noninteractive apt-get install -y -q sysstat iperf3 >/dev/null 2>&1 || true
# iperf3 server for the K2 TCP test from the UE (tcp 9000 is allowed only inside 10.10.0.0/16)
if [ ! -f /etc/systemd/system/lab5g-iperf3.service ]; then
  printf '[Unit]\nDescription=Lab5G iperf3 server (internal, port 9000)\n[Service]\nExecStart=/usr/bin/iperf3 -s -p 9000\nRestart=always\n[Install]\nWantedBy=multi-user.target\n' > /etc/systemd/system/lab5g-iperf3.service
  systemctl daemon-reload; systemctl enable -q --now lab5g-iperf3
fi
# 1. egress policy first (ue-l3: GRE to core; fail-closed reject while the core side is not up yet)
bash $V/install-emu-egress.sh >>$L/gui-emu-up.log 2>&1
# 2. dashboard + caddy (page is up while the emulator image builds/boots)
bash $V/emu-dashboard-setup.sh >>$L/gui-emu-up.log 2>&1 || log "dashboard setup failed"
# 2b. GPU (gui_emu_gpu=t4): NVIDIA driver + container toolkit (may reboot ONCE on first boot; this unit re-runs after it)
if [ "$EMU_GPU_KIND" != none ]; then bash $V/emu-gpu-setup.sh 2>&1 | tee -a $L/gui-emu-up.log | tail -1 | while read -r l; do log "$l"; done
else printf 'EMU_HAS_GPU=0\nGPU_NAME=""\nDRIVER=""\n' > /opt/lab5g/gpu.env; fi
# 3. emulator image (newest Play Store image, built once) + container (large screen, VNC password)
bash $V/emu-vnc-start.sh 2>&1 | tee -a $L/gui-emu-up.log | grep -E "BOOT_COMPLETED|android=|play_store|gpu_mode" | while read -r l; do log "$l"; done
# 4. Android proxy: off in ue-l3 (single transparent path), on in ue-proxy
if [ "$EMU_EGRESS" = ue-proxy ]; then EMU_ANDROID_PROXY=1; else EMU_ANDROID_PROXY=0; fi
EMU_ANDROID_PROXY=$EMU_ANDROID_PROXY bash $V/emu-proxy-ue.sh >>$L/gui-emu-up.log 2>&1
install -m 0755 $V/novnc-public-toggle.sh /opt/lab5g/novnc-public-toggle.sh
# 5. opt-in public Quick Tunnel
if [ "$(md gui-public-tunnel)" = true ]; then bash $V/novnc-public-setup.sh >>$L/gui-emu-up.log 2>&1; fi
log "done"
