#!/bin/bash
T=$1; D=/opt/pixel/d.sh; R=/opt/pixel/run; mkdir -p $R
bash $D ttext '^OK$|Not now|No thanks' 1 >/dev/null 2>&1; bash $D ui > $R/$T.pre 2>&1; old=$(grep -oE 'Test ID [0-9]+' $R/$T.pre | head -1)
sleep 2; bash $D ttext '^OK$|Not now' 1 >/dev/null 2>&1; sleep 2; bash $D ttext 'Test Again|Start a Speedtest|^GO$' 1 >/dev/null 2>&1
sleep 20
for j in $(seq 40); do bash $D ui > $R/$T.ui 2>&1; id=$(grep -oE 'Test ID [0-9]+' $R/$T.ui | head -1)
  { [ -n "$id" ] && [ "$id" != "$old" ] && grep -qE "Upload speed [0-9]" $R/$T.ui; } && break; grep -qi 'failed' $R/$T.ui && break; sleep 5; done
docker exec android-emu adb exec-out screencap -p > $R/$T.png
echo "$T: $(grep -oE "(Download|Upload) speed [0-9.,]+ m" $R/$T.ui | sort -u | tr '\n' ' ') $(grep -oE 'Test ID [0-9]+' $R/$T.ui|head -1) srv=$(grep speedtest_server_title $R/$T.ui | grep -oE "'[A-Za-z .]+'" | head -1)"
