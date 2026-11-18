#!/bin/bash
# vm-emu: Chrome emulator lewat proxy gost di netns UE (internet via UE), buka YouTube selama DUR detik, screenshot.
A="docker exec android-emu adb"; P=${P:?core_ip:18080}; DUR=${DUR:-60}
$A shell settings put global http_proxy $P; echo "proxy=$($A shell settings get global http_proxy)"
$A shell 'curl -s -o /dev/null -w "emu-curl via UE code=%{http_code} ttfb=%{time_starttransfer}\n" -x http://'$P' https://www.youtube.com/' 2>&1
# Chrome: skip FirstRun (root adb, hanya di VM ephemeral) - resep day1/emu-baseline.sh
$A root >/dev/null; sleep 2
$A shell 'echo "_ --disable-fre --no-default-browser-check --no-first-run" > /data/local/tmp/chrome-command-line; chmod 644 /data/local/tmp/chrome-command-line'
$A shell am set-debug-app --persistent com.android.chrome
$A shell am force-stop com.android.chrome
$A shell am start -a android.intent.action.VIEW -d "https://m.youtube.com/watch?v=aqz-KE-bpKQ" com.android.chrome
sleep 30; $A exec-out screencap -p > /tmp/emu-youtube-30s.png; sleep $((DUR-30)); $A shell dumpsys window | grep -E "mCurrentFocus"; $A exec-out screencap -p > /tmp/emu-youtube.png; ls -la /tmp/emu-youtube.png
mpstat 1 3 | tail -1
