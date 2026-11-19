#!/bin/bash
# vm-emu (root): restore a saved emulator USER SESSION into the HOST userdata dir that emu-vnc-start.sh bind-mounts into
# the container (direct mount; replaces the old `docker cp` restore, which took >7 min for 3.2 GB on pd-standard).
#   $UD/emulator -> /home/androidusr/emulator      (AVD dir: config.ini, userdata-qemu.img.qcow2, ...)
#   $UD/avd      -> /home/androidusr/.android/avd  (<name>.ini pointer)
# Called by emu-vnc-start.sh BEFORE `docker create` when EMU_USERDATA_URI is set. Never fatal: on any error or manifest
# mismatch it WARNS, leaves $UD empty and the emulator boots fresh (exit 0).
# Local userdata already present (e.g. after a VM reboot or container recreate) is KEPT unless FORCE_RESTORE=1, so a
# newer on-VM login is never overwritten by an older archive.
# SENSITIVE: the archive holds Google account tokens. Never print its content; dirs are root/1300-only (0700).
# Env: EMU_USERDATA_URI (gs://...tar.zst)  IMG (image, for the api/img_type check)  EMU_DEVICE  UD (default below)
#      GCLOUD (override for offline tests)  FORCE_RESTORE=1
set -uo pipefail
URI=${EMU_USERDATA_URI:-}; UD=${UD:-/var/lib/lab5g/emu-userdata}; W=${W:-/var/lib/lab5g/session-restore}
AUID=${AUID:-1300}; AGID=${AGID:-1301}
[ -n "$URI" ] || exit 0
GCLOUD=${GCLOUD:-$(command -v gcloud || echo /snap/bin/gcloud)}
T0=$(date +%s)
warn(){ echo "session restore SKIPPED: $*" >&2; rm -rf "$W" "$UD.new"; exit 0; }
if [ -f "$UD/emulator/config.ini" ] && [ "${FORCE_RESTORE:-0}" != 1 ]; then
  echo "session restore: local userdata present in $UD -> kept (FORCE_RESTORE=1 to overwrite from archive)"; exit 0
fi
command -v zstd >/dev/null || DEBIAN_FRONTEND=noninteractive apt-get install -y -q zstd >/dev/null 2>&1
install -d -m 0700 "$W"; rm -rf "${W:?}"/* "$UD.new"; umask 077
"$GCLOUD" storage cp -q "$URI.sha256" "$W/expected.sha256" 2>/dev/null || warn "checksum object tidak ada"
# stream: GCS -> sha256 (tee) -> zstd -> tar into $UD.new. No intermediate archive on disk (pd-standard write throughput
# is ~0.12 MiB/s per GiB, so writing the 3.2 GB archive first doubled the restore time). Checksum verified after the stream;
# on mismatch the extracted tree is discarded.
install -d -m 0700 "$UD.new"
set -o pipefail
"$GCLOUD" storage cat "$URI" 2>/dev/null | tee >(sha256sum | awk '{print $1}' > "$W/actual.sha256") | zstd -dc | tar -C "$UD.new" -xf - \
  || warn "download/extract gagal"
for i in $(seq 1 50); do [ -s "$W/actual.sha256" ] && break; sleep 0.2; done
SHA=$(cat "$W/actual.sha256" 2>/dev/null)
[ -n "$SHA" ] && [ "$SHA" = "$(tr -d ' \n' < "$W/expected.sha256")" ] || warn "checksum mismatch"
T1=$(date +%s)
M="$UD.new/lab5g-session.json"; [ -f "$M" ] || warn "manifest tidak ada"
[ -f "$UD.new/emulator/config.ini" ] || warn "archive tanpa emulator/config.ini"
mf(){ python3 -c "import json,sys;print(json.load(open(sys.argv[1])).get(sys.argv[2],''))" "$M" "$1"; }
if [ -n "${IMG:-}" ]; then
  ENVS=$(docker image inspect -f '{{range .Config.Env}}{{println .}}{{end}}' "$IMG" 2>/dev/null)
  for k in api:EMULATOR_API_LEVEL img_type:EMULATOR_IMG_TYPE; do
    want=$(echo "$ENVS" | sed -n "s/^${k#*:}=//p"); have=$(mf "${k%%:*}")
    [ -z "$want" ] || [ "$want" = "$have" ] || warn "${k%%:*} berbeda (sesi=$have, image=$want) -> boot fresh"
  done
fi
[ -z "${EMU_DEVICE:-}" ] || [ "$(mf device)" = "$EMU_DEVICE" ] || warn "device berbeda (sesi=$(mf device), sekarang=$EMU_DEVICE) -> boot fresh"
# strip run-time state that must not be restored (RAM snapshots, locks, boot marker)
rm -rf "$UD.new/emulator/snapshots" "$UD.new/emulator/tmpAdbCmds" "$UD.new/emulator/bootcompleted.ini"
find "$UD.new" -name '*.lock' -prune -exec rm -rf {} + 2>/dev/null
chown -R "$AUID:$AGID" "$UD.new/emulator" "$UD.new/avd"
chmod 0700 "$UD.new/emulator" "$UD.new/avd"
# adb key pair (optional, sensitive): root-only dir, files readable only by the emulator uid
if [ -d "$UD.new/adb" ]; then chown root:root "$UD.new/adb"; chmod 0700 "$UD.new/adb"; chown "$AUID:$AGID" "$UD.new/adb/"adbkey*; chmod 0600 "$UD.new/adb/"adbkey*; fi
chown root:root "$UD.new" "$M"; chmod 0711 "$UD.new"; chmod 0600 "$M"
echo "sha256=$SHA restored_utc=$(date -u +%FT%TZ)" > "$UD.new/.lab5g-restored"
rm -rf "$UD.old"; [ -d "$UD" ] && mv "$UD" "$UD.old"; mv "$UD.new" "$UD"; rm -rf "$UD.old" "$W"; M="$UD/lab5g-session.json"
echo "session restored (api=$(mf api) img=$(mf img_type) device=$(mf device) created=$(mf created_utc)) stream_s=$((T1-T0)) total_s=$(( $(date +%s)-T0 ))"
