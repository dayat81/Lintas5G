#!/bin/bash
# vm-emu (root): install Magnon examine v0.10.2, pre-grant VPN consent headless, start examine
# targeting YouTube, and collect 1 s playback samples. No VNC, no public tunnel, no account data
# in the TSV (screenshots go to a root-only dir, same rule as emu-youtube-headless.sh).
#
# Headless consent sequence (API 36, v0.10.2):
#   1. adb install -r -g <apk>
#   2. adb shell appops set id.magnon.poc.examine ACTIVATE_VPN allow
#      (also: cmd appops set --user 0 ... allow)
#   3. adb shell pm grant id.magnon.poc.examine android.permission.POST_NOTIFICATIONS
#   4. adb shell am start -n id.magnon.poc.examine/.MainActivity with extras
#        (apps, pktlog, probe, dns, deproxy, quic, probehost/probeport/markport).
#        MainActivity starts the VpnService after prepare() is null.
#        Do NOT use am start-foreground-service on ExamineVpnService: BIND_VPN_SERVICE
#        blocks it (Sesi D 18 Nov). Do not click a VNC dialog from this script.
#   5. Confirm: logcat -s MAGNON_EXAMINE:I | grep VPN_CONSENT   (ok|needed)
#              and `ip -4 -br a show tun0`
# Play start uses watch?v=ID&t=0 so a resumed session does not start mid-video.
# Official playback advance is still last PLAYING pos - first PLAYING pos (yt-playback.py).
#
# usage:
#   emu-youtube-qod.sh install              # apk + appops + pm grant POST_NOTIFICATIONS
#   emu-youtube-qod.sh vpn-start|vpn-stop|vpn-status
#   emu-youtube-qod.sh play-start|play-stop
#   emu-youtube-qod.sh collect <dur_s> <out.tsv>   # 1 s samples + JSON sidecar
#   emu-youtube-qod.sh date                      # Android date +%s.%N (skew)
#   emu-youtube-qod.sh proto-hint                # udp/tcp 443 sockets (best effort)
# env: C=android-emu  APK=...  VIDEO_ID=aqz-KE-bpKQ  VIDEO_QUALITY=  (e.g. hd720, optional vq=)
#      PKG=id.magnon.poc.examine  YT=com.google.android.youtube
set -u
C=${C:-android-emu}
PKG=${PKG:-id.magnon.poc.examine}
YT=${YT:-com.google.android.youtube}
APK=${APK:-/opt/lab5g/sesi-d/magnon-poc-examine-v0.10.2.apk}
PROBE_HOST=${PROBE_HOST:-10.99.9.20}
PROBE_PORT=${PROBE_PORT:-9001}
MARK_PORT=${MARK_PORT:-9000}
VIDEO_ID=${VIDEO_ID:-aqz-KE-bpKQ}
L=${L:-/var/log/lab5g/youtube}
P=/var/lib/lab5g/private-shots
SD=$(cd "$(dirname "$0")" && pwd)
A="timeout 20 docker exec $C adb shell"
ADB_HOST="timeout 20 docker exec $C adb"
mkdir -p "$L"
install -d -m 0700 "$P" 2>/dev/null || true

cmd=${1:-}

install_apk() {
  [ -f "$APK" ] || { echo "APK missing: $APK (copy v0.10.2 to the emu host first)"; return 1; }
  docker cp "$APK" "$C:/tmp/magnon-poc-examine.apk"
  $A am broadcast -n $PKG/.StopReceiver >/dev/null 2>&1 || true
  $A am force-stop $PKG >/dev/null 2>&1 || true
  $ADB_HOST install -r -g /tmp/magnon-poc-examine.apk
  # Headless VPN consent (worked on API 33 yesterday). API 36 may still show a dialog
  # if prepare() is non-null; vpn-start will report VPN_CONSENT=needed in that case.
  $A appops set $PKG ACTIVATE_VPN allow
  $A cmd appops set $PKG ACTIVATE_VPN allow >/dev/null 2>&1 || true
  $A cmd appops set --user 0 $PKG ACTIVATE_VPN allow >/dev/null 2>&1 || true
  $A pm grant $PKG android.permission.POST_NOTIFICATIONS >/dev/null 2>&1 || true
  echo "package=$($A dumpsys package $PKG 2>/dev/null | grep -m2 -E 'versionName|versionCode' | tr '\n' ' ')"
  echo "appops=$($A appops get $PKG ACTIVATE_VPN 2>/dev/null | tr '\n' ' ')"
  echo "notif=$($A dumpsys package $PKG 2>/dev/null | grep -A1 POST_NOTIFICATIONS | tr '\n' ' ')"
  echo "targetSdk=$($A dumpsys package $PKG 2>/dev/null | grep -m1 targetSdk | tr -s ' ' )"
}

vpn_extras() {
  # extras consumed by v0.10.2 ExamineVpnService / MainActivity (defaults = v0.9.1 destinations)
  echo --es apps $YT --es pktlog on --es logpkt off --es probe on \
       --es dns 8.8.8.8 --es deproxy off --es quic fwd \
       --es probehost $PROBE_HOST --es probeport $PROBE_PORT --es markport $MARK_PORT
}

vpn_start() {
  $A input keyevent KEYCODE_WAKEUP >/dev/null 2>&1 || true
  $A wm dismiss-keyguard >/dev/null 2>&1 || true
  $A am broadcast -n $PKG/.StopReceiver >/dev/null 2>&1 || true
  $A am force-stop $PKG >/dev/null 2>&1 || true
  $A pm grant $PKG android.permission.POST_NOTIFICATIONS >/dev/null 2>&1 || true
  $A appops set $PKG ACTIVATE_VPN allow >/dev/null 2>&1 || true
  $ADB_HOST logcat -c >/dev/null 2>&1 || true
  # MainActivity only: start-foreground-service is rejected with BIND_VPN_SERVICE (18 Nov).
  # deproxy off: APK default proxy <OLD_LAB_PROXY> is a previous-lab path, not this lab.
  local tun=""
  wait_tun() { tun=""; local _i; for _i in $(seq 1 "$1"); do sleep 1; tun=$($A 'ip -4 -br a show tun0 2>/dev/null' | tr -d '\r'); [ -n "$tun" ] && return 0; done; return 1; }
  # shellcheck disable=SC2046
  $A am start -n $PKG/.MainActivity $(vpn_extras) >/tmp/ytqod-vpn-start.txt 2>&1 || true
  cat /tmp/ytqod-vpn-start.txt 2>/dev/null || true
  wait_tun 12 || true
  local log
  log=$($ADB_HOST logcat -d -s MAGNON_EXAMINE:I 2>/dev/null | grep -E 'VPN_CONSENT|VPN up|consent |POST_NOTIFICATIONS' | tail -15)
  if [ -n "$tun" ]; then
    echo "VPN_CONSENT=ok tun0=$tun"
    echo "$log"
    return 0
  fi
  echo "VPN_CONSENT=needed tun0=missing (check logcat; appops may be insufficient — headless cannot click the dialog)"
  echo "$log"
  return 2
}

vpn_stop() {
  $A am broadcast -n $PKG/.StopReceiver >/dev/null 2>&1 || true
  sleep 2
  $A am force-stop $PKG >/dev/null 2>&1 || true
  echo "vpn stopped"
}

vpn_status() {
  echo "tun0=$($A 'ip -4 -br a show tun0 2>/dev/null' | tr -d '\r')"
  echo "appops=$($A appops get $PKG ACTIVATE_VPN 2>/dev/null | tr '\n' ' ')"
  $ADB_HOST logcat -d -s MAGNON_EXAMINE:I 2>/dev/null | grep -E 'VPN_CONSENT|VPN up|mglt2 ready|quic|POST_NOTIFICATIONS=' | tail -8
}

play_url() {
  # t=0: request start at the beginning (resumed sessions otherwise mid-video).
  local url="https://www.youtube.com/watch?v=${VIDEO_ID}&t=0"
  [ -n "${VIDEO_QUALITY:-}" ] && url="${url}&vq=${VIDEO_QUALITY}"
  printf '%s\n' "$url"
}

play_start() {
  $A input keyevent KEYCODE_WAKEUP >/dev/null 2>&1 || true
  $A wm dismiss-keyguard >/dev/null 2>&1 || true
  $A am force-stop $YT >/dev/null 2>&1 || true
  sleep 1
  $A am start -a android.intent.action.VIEW -d "$(play_url)" $YT >/dev/null 2>&1
  echo "play-start video=$VIDEO_ID quality=${VIDEO_QUALITY:-default} url=$(play_url)"
}

play_stop() {
  $A am force-stop $YT >/dev/null 2>&1 || true
  echo "play-stop"
}

collect() {
  local dur=${1:?dur_s} out=${2:?out.tsv}
  mkdir -p "$(dirname "$out")"
  local js=${out%.tsv}.json
  # reuse the Python parser (same extrapolation as emu-youtube-headless.sh)
  python3 "$SD/yt-playback.py" collect --dur "$dur" --interval "${INTERVAL:-1}" --out "$out" \
    --adb "$A" | tee "$js"
  # best-effort resolution (may be empty)
  $A dumpsys media.metrics 2>/dev/null | tail -c 200000 > "${out%.tsv}.metrics.txt" || true
  $ADB_HOST logcat -d -s ExoPlayerImpl:I ExoPlayerImpl:D YouTube:I 2>/dev/null | tail -c 200000 > "${out%.tsv}.logcat.txt" || true
  python3 "$SD/yt-playback.py" analyze --samples "$out" --out "$js" \
    --metrics-dump "${out%.tsv}.metrics.txt" --logcat "${out%.tsv}.logcat.txt" >/dev/null || true
  echo "collect written $out $js"
}

android_date() {
  $A 'date +%s.%N' | tr -d '\r'
}

proto_hint() {
  # best-effort: /proc/net/udp and tcp for :0433 (hex). Not authoritative (Zeek is).
  $A 'echo UDP; grep -E " 01BB " /proc/net/udp /proc/net/udp6 2>/dev/null | wc -l; echo TCP; grep -E " 01BB " /proc/net/tcp /proc/net/tcp6 2>/dev/null | wc -l' | tr -d '\r'
}

case "$cmd" in
install) install_apk ;;
vpn-start) vpn_start ;;
vpn-stop) vpn_stop ;;
vpn-status) vpn_status ;;
play-start) play_start ;;
play-stop) play_stop ;;
collect) collect "${2:?dur}" "${3:?out.tsv}" ;;
date) android_date ;;
skew-stream) python3 "$(dirname "$0")/skew-guest.py" emu "$C" ;;
proto-hint) proto_hint ;;
*) echo "usage: $0 install|vpn-start|vpn-stop|vpn-status|play-start|play-stop|collect <dur> <out.tsv>|date|skew-stream|proto-hint"; exit 1 ;;
esac
