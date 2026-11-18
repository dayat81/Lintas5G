#!/bin/bash
# Jalankan di vm-emu (root): proxy HTTP global Android.
#   EMU_ANDROID_PROXY=1 : set ke gost di netns UE (CORE_IP:18080) - wajib untuk mode egress ue-proxy.
#   EMU_ANDROID_PROXY=0 : hapus proxy (default untuk mode ue-l3: semua trafik sudah lewat UE via GRE, satu jalur).
# usage: CORE_IP=<ip internal vm-core-ran> [EMU_ANDROID_PROXY=0|1] bash emu-proxy-ue.sh
set -e
PORT=${PORT:-18080}; A="docker exec android-emu adb"
if [ "${EMU_ANDROID_PROXY:-1}" = 1 ]; then
  CORE_IP=${CORE_IP:?CORE_IP wajib}
  $A shell settings put global http_proxy $CORE_IP:$PORT
else
  $A shell settings put global http_proxy :0
  $A shell settings delete global http_proxy >/dev/null 2>&1 || true
fi
echo "proxy=$($A shell settings get global http_proxy)"
