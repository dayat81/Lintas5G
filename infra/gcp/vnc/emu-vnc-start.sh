#!/bin/bash
# VNC session: emulator budtmo/docker-android dengan VNC password (dibuat acak di VM, tidak pernah dicetak).
# Port 5900/6080/5555 hanya bind 127.0.0.1 -> akses lewat SSH tunnel via IAP.
set -e
for i in $(seq 1 60); do command -v docker >/dev/null && ! pgrep -x apt-get >/dev/null && break; sleep 5; done
mkdir -p /opt/lab5g; umask 077
P=/opt/lab5g/vnc-password.txt
if [ ! -s $P ]; then tr -dc 'A-Za-z0-9' </dev/urandom | head -c 20 > $P; fi
chown root:root $P; chmod 0600 $P
printf 'VNC_PASSWORD=%s\n' "$(cat $P)" > /opt/lab5g/emu.env; chmod 0600 /opt/lab5g/emu.env
umask 022
docker rm -f android-emu >/dev/null 2>&1 || true
docker pull -q budtmo/docker-android:emulator_13.0 >/dev/null
docker run -d --name android-emu --restart unless-stopped --privileged --device /dev/kvm \
  -p 127.0.0.1:5555:5555 -p 127.0.0.1:5900:5900 -p 127.0.0.1:6080:6080 \
  -e EMULATOR_DEVICE="Nexus 5" -e WEB_VNC=true --env-file /opt/lab5g/emu.env \
  budtmo/docker-android:emulator_13.0 >/dev/null
S=$(date +%s)
for i in $(seq 1 90); do b=$(docker exec android-emu adb shell getprop sys.boot_completed 2>/dev/null | tr -d '\r'); [ "$b" = 1 ] && break; sleep 5; done
echo "BOOT_COMPLETED=$b BOOT_WAIT_S=$(( $(date +%s)-S ))"
ls -l $P | awk '{print $1,$3,$4,$NF}'
ss -ltnp | grep -E ':(5900|6080|5555)\b' | awk '{print $4}'
