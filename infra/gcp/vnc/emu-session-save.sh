#!/bin/bash
# vm-emu (root): save the emulator USER SESSION (AVD userdata incl. signed-in Google account) to a PRIVATE GCS object.
# SENSITIVE: the archive contains Google account credentials/tokens. Never commit it, never log its content, keep the
# bucket private (uniform access, public access prevention, access only lab SA + owner). Not managed by lab terraform.
# usage: EMU_USERDATA_URI=gs://<bucket>/<path>/session.tar.zst bash emu-session-save.sh
# Steps: adb sync -> clean emulator shutdown (adb emu kill) -> docker stop -> copy AVD dir out -> tar.zst (no RAM
# snapshots/locks) -> sha256 + manifest (api/img/device, no secrets) -> upload -> start the container again.
set -euo pipefail
URI=${EMU_USERDATA_URI:?EMU_USERDATA_URI wajib (gs://bucket/path/session.tar.zst)}
W=/var/lib/lab5g/session-save; C=android-emu; H=/home/androidusr
GCLOUD=$(command -v gcloud || echo /snap/bin/gcloud)
command -v zstd >/dev/null || DEBIAN_FRONTEND=noninteractive apt-get install -y -q zstd >/dev/null
install -d -m 0700 $W; rm -rf $W/*; umask 077
IMG=$(docker inspect -f '{{.Config.Image}}' $C)
ENVS=$(docker inspect -f '{{range .Config.Env}}{{println .}}{{end}}' $C)
api=$(echo "$ENVS" | sed -n 's/^EMULATOR_API_LEVEL=//p'); img=$(echo "$ENVS" | sed -n 's/^EMULATOR_IMG_TYPE=//p'); dev=$(echo "$ENVS" | sed -n 's/^EMULATOR_DEVICE=//p')
docker exec $C adb shell sync || true
docker exec $C adb emu kill >/dev/null 2>&1 || true
for i in $(seq 1 60); do docker exec $C pgrep -f qemu-system >/dev/null 2>&1 || break; sleep 2; done
docker stop -t 30 $C >/dev/null
mkdir -p $W/root/emulator $W/root/avd
docker cp -a $C:$H/emulator/. $W/root/emulator/
docker cp -a $C:$H/.android/avd/. $W/root/avd/
rm -rf $W/root/emulator/snapshots $W/root/emulator/tmpAdbCmds $W/root/emulator/*.lock $W/root/emulator/bootcompleted.ini
printf '{"api":"%s","img_type":"%s","device":"%s","image":"%s","created_utc":"%s"}\n' "$api" "$img" "$dev" "$IMG" "$(date -u +%FT%TZ)" > $W/root/lab5g-session.json
tar -C $W/root -I 'zstd -T0 -3' -cf $W/session.tar.zst .
( cd $W && sha256sum session.tar.zst | awk '{print $1}' > session.tar.zst.sha256 )
$GCLOUD storage cp -q $W/session.tar.zst "$URI"
$GCLOUD storage cp -q $W/session.tar.zst.sha256 "$URI.sha256"
$GCLOUD storage cp -q $W/root/lab5g-session.json "$URI.json"
echo "session saved: size=$(stat -c %s $W/session.tar.zst) sha256=$(cat $W/session.tar.zst.sha256) api=$api img=$img device=$dev"
rm -rf $W/root $W/session.tar.zst
docker start $C >/dev/null && echo "android-emu started again"
