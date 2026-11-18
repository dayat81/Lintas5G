#!/bin/bash
A="docker exec android-emu adb"
P=10.10.0.2:18080
echo "== set global http_proxy (hanya VM ephemeral) =="
$A shell settings put global http_proxy $P; $A shell settings get global http_proxy
echo "== curl di emulator? =="; $A shell 'which curl; curl -s -o /dev/null -w "emu-curl code=%{http_code} connect=%{time_connect} ttfb=%{time_starttransfer}\n" -x http://'$P' http://example.com/' 2>&1
$A shell 'curl -s -o /dev/null -w "emu-curl https code=%{http_code} ttfb=%{time_starttransfer}\n" -x http://'$P' https://www.google.com/' 2>&1
echo "== Chrome via proxy =="
$A shell am force-stop com.android.chrome
$A shell am start -a android.intent.action.VIEW -d http://example.com/ com.android.chrome
sleep 15; $A shell dumpsys window | grep -E "mCurrentFocus" ; $A exec-out screencap -p > /tmp/emu-chrome-ue.png; ls -la /tmp/emu-chrome-ue.png
$A shell am start -a android.intent.action.VIEW -d https://www.wikipedia.org/ com.android.chrome
sleep 12; $A exec-out screencap -p > /tmp/emu-chrome-ue2.png
$A shell dumpsys window | grep -E "mCurrentFocus"
echo "== host vm-emu timing: via UE proxy vs direct Cloud NAT (5x) =="
for i in 1 2 3 4 5; do curl -s -o /dev/null -x http://$P -w "ue-proxy http connect=%{time_connect} ttfb=%{time_starttransfer} total=%{time_total}\n" http://example.com/; done
for i in 1 2 3 4 5; do curl -s -o /dev/null -w "direct   http connect=%{time_connect} ttfb=%{time_starttransfer} total=%{time_total}\n" http://example.com/; done
for i in 1 2 3; do curl -s -o /dev/null -x http://$P -w "ue-proxy https appconnect=%{time_appconnect} ttfb=%{time_starttransfer}\n" https://www.google.com/; done
for i in 1 2 3; do curl -s -o /dev/null -w "direct   https appconnect=%{time_appconnect} ttfb=%{time_starttransfer}\n" https://www.google.com/; done
echo "== mpstat vm-emu (Chrome aktif) =="; mpstat 1 5 | tail -1
docker stats --no-stream android-emu
