#!/bin/bash
A="docker exec android-emu adb"
P=${P:-10.10.0.3:18080}
echo "== set global http_proxy (hanya VM ephemeral) =="
$A shell settings put global http_proxy $P; $A shell settings get global http_proxy
echo "== curl di emulator? =="; $A shell 'which curl; curl -s -o /dev/null -w "emu-curl code=%{http_code} connect=%{time_connect} ttfb=%{time_starttransfer}\n" -x http://'$P' http://example.com/' 2>&1
$A shell 'curl -s -o /dev/null -w "emu-curl https code=%{http_code} ttfb=%{time_starttransfer}\n" -x http://'$P' https://www.google.com/' 2>&1
echo "== Chrome via proxy =="
$A shell am force-stop com.android.chrome
$A shell am start -a android.intent.action.VIEW -d http://example.com/ com.android.chrome
sleep 15; $A shell dumpsys window | grep -E "mCurrentFocus" ; $A exec-out screencap -p > /tmp/emu-chrome-gost.png; ls -la /tmp/emu-chrome-gost.png
$A shell am start -a android.intent.action.VIEW -d https://www.wikipedia.org/ com.android.chrome
sleep 12; $A exec-out screencap -p > /tmp/emu-chrome-gost2.png
$A shell dumpsys window | grep -E "mCurrentFocus"
echo "== mpstat vm-emu (Chrome aktif) =="; mpstat 1 5 | tail -1
docker stats --no-stream android-emu
