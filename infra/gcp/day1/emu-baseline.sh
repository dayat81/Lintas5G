#!/bin/bash
A="docker exec android-emu adb"
echo "== adb ping 8.8.8.8 (direct, emulator NAT -> Cloud NAT) =="
$A shell ping -c 100 -i 0.2 8.8.8.8 | tail -3
echo "== host vm-emu ping 8.8.8.8 (Cloud NAT) =="
ping -c 100 -i 0.2 -q 8.8.8.8 | tail -2
echo "== curl direct timing (host, Cloud NAT) =="
for i in 1 2 3 4 5; do curl -s -o /dev/null -w "direct connect=%{time_connect} ttfb=%{time_starttransfer} total=%{time_total}\n" http://example.com/; done
echo "== mpstat vm-emu =="; mpstat 1 5 | tail -1
# Chrome: skip FirstRun (root adb, hanya di VM ephemeral)
$A root >/dev/null; sleep 2
$A shell 'echo "_ --disable-fre --no-default-browser-check --no-first-run" > /data/local/tmp/chrome-command-line; chmod 644 /data/local/tmp/chrome-command-line'
$A shell am set-debug-app --persistent com.android.chrome
$A shell am force-stop com.android.chrome
echo EMU_BASELINE_DONE
