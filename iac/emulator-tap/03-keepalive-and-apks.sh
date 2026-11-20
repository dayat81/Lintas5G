#!/bin/bash
# vm-emu (root). Keepalive + APK install (APKs: Ookla 7.1.4, Opensignal 8.17.0 from a verified mirror; not stored in this repo).
A="docker exec android-emu adb"
$A shell svc power stayon true; $A shell settings put system screen_off_timeout 2147483647
cp pixel-keepalive.service /etc/systemd/system/; systemctl daemon-reload; systemctl enable --now pixel-keepalive
# for a in ookla.apk opensignal.apk; do docker cp $a android-emu:/tmp/$a; $A install -r /tmp/$a; done
