#!/bin/bash
# Dari laptop/box (gcloud sudah login, terraform apply selesai): siapkan sesi remote GUI emulator.
# usage: PROJECT_ID=<PROJECT_ID> ZONE=asia-southeast2-a bash infra/gcp/vnc/vnc-deploy.sh [--public]
#   --public : OPT-IN, nyalakan juga Quick Tunnel publik (caddy basic auth + password VNC).
set -euo pipefail
PROJECT_ID=${PROJECT_ID:-$(gcloud config get-value project 2>/dev/null)}
ZONE=${ZONE:-$(gcloud config get-value compute/zone 2>/dev/null)}; ZONE=${ZONE:-asia-southeast2-a}
: "${PROJECT_ID:?set PROJECT_ID atau gcloud config set project}"
HERE=$(cd "$(dirname "$0")" && pwd); GCP=$(dirname "$HERE")
G="--project=$PROJECT_ID --zone=$ZONE --tunnel-through-iap --quiet"
ssh_() { local h=$1; shift; gcloud compute ssh "$h" $G --command="$*"; }
scp_() { gcloud compute scp $G "$@"; }
CORE_IP=$(gcloud compute instances describe vm-core-ran --project="$PROJECT_ID" --zone="$ZONE" --format='value(networkInterfaces[0].networkIP)')

# 1. core: install + bring-up EPC/srsRAN ZMQ (resep Sesi C, tanpa Zeek) + watchdog UE
tar czf /tmp/lintas5g-sesi-c.tgz -C "$GCP" sesi-c
scp_ /tmp/lintas5g-sesi-c.tgz "$HERE/ue-watchdog.sh" "$HERE/install-watchdog.sh" "$HERE/core-bringup-vnc.sh" vm-core-ran:/tmp/
ssh_ vm-core-ran 'sudo mkdir -p /opt/lab5g /var/log/lab5g && sudo tar xzf /tmp/lintas5g-sesi-c.tgz -C /opt/lab5g'
ssh_ vm-core-ran 'test -x /opt/lab5g/srsran/srsRAN_4G/build/srsue/src/srsue || sudo bash /opt/lab5g/sesi-c/core-install.sh > /tmp/core-install.log 2>&1; tail -1 /tmp/core-install.log 2>/dev/null || true'
ssh_ vm-core-ran 'sudo bash /tmp/core-bringup-vnc.sh 2>&1 | grep -v -i -E "key|opc" | tail -5; sudo bash /tmp/install-watchdog.sh'

# 2. emulator: VNC password acak di VM + port 127.0.0.1 saja, lalu proxy via UE
scp_ "$HERE/emu-vnc-start.sh" "$HERE/emu-proxy-ue.sh" "$HERE/novnc-public-setup.sh" "$HERE/novnc-public-toggle.sh" vm-emu:/tmp/
ssh_ vm-emu 'sudo bash /tmp/emu-vnc-start.sh'
ssh_ vm-emu "sudo CORE_IP=$CORE_IP bash /tmp/emu-proxy-ue.sh; sudo install -m 0755 /tmp/novnc-public-toggle.sh /opt/lab5g/novnc-public-toggle.sh"

# 3. opsional: public Quick Tunnel
if [ "${1:-}" = "--public" ]; then
  ssh_ vm-emu 'sudo bash /tmp/novnc-public-setup.sh'
fi
echo "Selesai. Lihat infra/gcp/vnc/README.md untuk cara konek."
