#!/bin/bash
# emu-run.sh <tag> <dur_s> <booster:0|1> [onesession on|off] [duration_s] : examine VPN (D443) [+ booster] + YouTube playback samples.
set -u
T=$1; DUR=$2; BOOST=$3; ONE=${4:-on}; BD=${5:-60}; R=/var/log/lab5g/booster/runs/$T; mkdir -p $R
C=android-emu; A="timeout 20 docker exec $C adb shell"; PKG=id.booster.poc.examine; SD=/opt/lab5g/sesi-d
now(){ date +%s.%N; }
KEY=$(cat /root/booster-appkey)
$A am force-stop com.google.android.youtube; $A am broadcast -n $PKG/.StopReceiver >/dev/null 2>&1; $A am force-stop $PKG; sleep 1
timeout 20 docker exec $C adb logcat -c
echo "t_vpn $(now)" > $R/times
$A am start -n $PKG/.MainActivity --es apps com.google.android.youtube --es pktlog on --es logpkt off --es probe on \
  --es dns 8.8.8.8 --es deproxy off --es quic fwd --es probehost 10.99.9.20 --es markhost 10.99.9.20 --es probeport 443 --es markport 443 > $R/am-vpn.txt 2>&1
for i in $(seq 15); do sleep 1; $A 'ip -4 -br a show tun0' 2>/dev/null | grep -q tun0 && break; done
echo "vpn_tun0=$($A 'ip -4 -br a show tun0' | tr -d '\r' | awk '{print $1,$2}')" >> $R/times
if [ "${PLAYFIRST:-0}" = 1 ]; then echo "t_play0 $(now)" >> $R/times; VIDEO_ID=aqz-KE-bpKQ bash $SD/emu-youtube-qod.sh play-start >/dev/null 2>&1; sleep ${PLAYWAIT:-30}; fi
if [ "$BOOST" = 1 ]; then
  echo "t_booster $(now)" >> $R/times
  $A am start -n $PKG/.booster.android.BoosterActivity --es backend http://10.99.9.20:8090 --es appkey "$KEY" \
    --es apps com.google.android.youtube --es sni googlevideo.com,youtube.com --es p99 80 --es onesession $ONE \
    --es duration $BD --es maxdur $BD --es reflector 10.99.9.20 --es reflports 443 > $R/am-booster.txt 2>&1
  sleep 3
fi
echo "t_play $(now)" >> $R/times
VIDEO_ID=aqz-KE-bpKQ bash $SD/emu-youtube-qod.sh play-start >> $R/times 2>&1
INTERVAL=1 bash $SD/emu-youtube-qod.sh collect $DUR $R/yt.tsv > $R/collect.out 2>&1
echo "t_end $(now)" >> $R/times
timeout 30 docker exec $C adb logcat -d -v epoch -s BOOSTER_EXAMINE:* BOOSTER:* > $R/logcat-booster.txt 2>&1
sed -i -E 's/10\.45\.[0-9]+\.[0-9]+/10.45.x.x/g' $R/logcat-booster.txt
bash $SD/emu-youtube-qod.sh play-stop >/dev/null 2>&1
echo done $T
