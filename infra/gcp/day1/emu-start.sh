#!/bin/bash
set -x
apt-get install -y sysstat >/dev/null 2>&1
docker rm -f android-emu 2>/dev/null
docker pull -q budtmo/docker-android:emulator_13.0
date -u +START_%FT%TZ
docker run -d --name android-emu --privileged --device /dev/kvm \
  -p 127.0.0.1:5555:5555 -p 127.0.0.1:5900:5900 -p 127.0.0.1:6080:6080 \
  -e EMULATOR_DEVICE="Nexus 5" -e WEB_VNC=true budtmo/docker-android:emulator_13.0
S=$(date +%s)
for i in $(seq 1 60); do b=$(docker exec android-emu adb shell getprop sys.boot_completed 2>/dev/null | tr -d '\r'); [ "$b" = 1 ] && break; sleep 5; done
echo "BOOT_COMPLETED=$b BOOT_WAIT_S=$(( $(date +%s)-S ))"
