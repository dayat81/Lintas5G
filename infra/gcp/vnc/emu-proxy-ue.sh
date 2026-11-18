#!/bin/bash
# Jalankan di vm-emu (root): set proxy HTTP global Android ke gost di netns UE (internet emulator lewat UE).
# usage: CORE_IP=<ip internal vm-core-ran> bash emu-proxy-ue.sh
set -e
CORE_IP=${CORE_IP:?CORE_IP wajib}; PORT=${PORT:-18080}
A="docker exec android-emu adb"
$A shell settings put global http_proxy $CORE_IP:$PORT
echo "proxy=$($A shell settings get global http_proxy)"
