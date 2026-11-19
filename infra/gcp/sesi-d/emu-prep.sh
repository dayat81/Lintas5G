#!/bin/bash
# vm-emu (root), Sesi D: test servers (http :9000, iperf3 :8123/:6000/:18080, udp-flow :4789) without clashing with the GUI
# session's K2 iperf3 on :9000 (stopped; K2 uses :18080 in Sesi D). Prints emulator + session status (accounts count only).
systemctl disable -q --now lab5g-iperf3 2>/dev/null
apt-get install -y -q iperf3 >/dev/null 2>&1
mkdir -p /opt/lab5g/www && [ -s /opt/lab5g/www/1k.bin ] || head -c 1024 /dev/urandom > /opt/lab5g/www/1k.bin
for u in lab5g-srv-http lab5g-srv-dl lab5g-srv-ul lab5g-srv-gbr lab5g-srv-udp; do systemctl stop $u 2>/dev/null; systemctl reset-failed $u 2>/dev/null; done
systemd-run --unit=lab5g-srv-http --working-directory=/opt/lab5g/www python3 -m http.server 9000 --bind 0.0.0.0 >/dev/null
systemd-run --unit=lab5g-srv-dl iperf3 -s -p 8123 >/dev/null
systemd-run --unit=lab5g-srv-ul iperf3 -s -p 6000 >/dev/null
systemd-run --unit=lab5g-srv-gbr iperf3 -s -p 18080 >/dev/null
systemd-run --unit=lab5g-srv-udp python3 /opt/lab5g/sesi-c/udp-flow.py server --port 4789 >/dev/null
sleep 1; ss -ltnu | awk 'NR>1{print $1,$5}' | grep -E ':(9000|8123|6000|18080|4789)$' | tr '\n' ' '; echo
A="timeout 20 docker exec android-emu adb shell"
echo "boot=$($A getprop sys.boot_completed 2>/dev/null | tr -d '\r') accounts=$($A dumpsys account 2>/dev/null | grep -c 'Account {.*type=com.google') restored=$([ -f /var/lib/lab5g/emu-userdata/.lab5g-restored ] && echo yes || echo no)"
ss -ltn | awk 'NR>1{print $4}' | grep -E ':(5900|6080|6081)$' && echo "WARN: VNC listener present" || echo "vnc_listeners=none"
pgrep -x cloudflared >/dev/null && echo "WARN: cloudflared running" || echo "cloudflared=none"
# Optional Magnon examine v0.10.2 for the YouTube+QoD run (skip if the APK is not on this VM).
# The APK is not in the public repo; copy it to /opt/lab5g/sesi-d/ before this script.
APK=${EXAMINE_APK:-/opt/lab5g/sesi-d/magnon-poc-examine-v0.10.2.apk}
if [ -f "$APK" ]; then
  APK=$APK bash /opt/lab5g/sesi-d/emu-youtube-qod.sh install || echo "WARN: examine APK install failed"
else
  echo "examine apk=absent (YouTube+QoD install skipped)"
fi
