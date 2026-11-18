#!/bin/bash
# vm-emu (root): restore a saved emulator user session into a CREATED (not yet started) android-emu container.
# Called by emu-vnc-start.sh when EMU_USERDATA_URI is set. Idempotent per container (label-free: marker file).
# Validates sha256 and the manifest (api/img_type/device); on any mismatch or error it WARNS and the emulator boots
# fresh (exit 0). SENSITIVE data: never print archive content; working dir is root-only and removed afterwards.
set -uo pipefail
URI=${EMU_USERDATA_URI:-}; C=android-emu; H=/home/androidusr; W=/var/lib/lab5g/session-restore
[ -n "$URI" ] || exit 0
GCLOUD=$(command -v gcloud || echo /snap/bin/gcloud)
warn(){ echo "session restore SKIPPED: $*" >&2; rm -rf $W; exit 0; }
command -v zstd >/dev/null || DEBIAN_FRONTEND=noninteractive apt-get install -y -q zstd >/dev/null 2>&1
install -d -m 0700 $W; rm -rf $W/*; umask 077
$GCLOUD storage cp -q "$URI" $W/session.tar.zst 2>/dev/null || warn "download gagal ($URI)"
$GCLOUD storage cp -q "$URI.sha256" $W/expected.sha256 2>/dev/null || warn "checksum object tidak ada"
[ "$(sha256sum $W/session.tar.zst | awk '{print $1}')" = "$(tr -d ' \n' < $W/expected.sha256)" ] || warn "checksum mismatch"
mkdir -p $W/root && tar -C $W/root -I zstd -xf $W/session.tar.zst || warn "extract gagal"
M=$W/root/lab5g-session.json; [ -f $M ] || warn "manifest tidak ada"
mf(){ python3 -c "import json,sys;print(json.load(open('$M')).get('$1',''))"; }
ENVS=$(docker inspect -f '{{range .Config.Env}}{{println .}}{{end}}' $C)
for k in api:EMULATOR_API_LEVEL img_type:EMULATOR_IMG_TYPE device:EMULATOR_DEVICE; do
  want=$(echo "$ENVS" | sed -n "s/^${k#*:}=//p"); have=$(mf ${k%%:*})
  [ "$want" = "$have" ] || warn "${k%%:*} berbeda (sesi=$have, sekarang=$want) -> boot fresh"
done
chown -R 1300:1301 $W/root/emulator $W/root/avd
docker cp -a $W/root/emulator/. $C:$H/emulator/ || warn "docker cp emulator gagal"
docker cp -a $W/root/avd/. $C:$H/.android/avd/ || warn "docker cp avd gagal"
echo "session restored (api=$(mf api) img=$(mf img_type) device=$(mf device) created=$(mf created_utc))"
rm -rf $W
