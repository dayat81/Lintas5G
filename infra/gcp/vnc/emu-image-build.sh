#!/bin/bash
# vm-emu (root), idempotent: build the Lab5G emulator image once (tag lab5g/android:<API>-<IMG_TYPE>).
# usage: EMU_API=36 EMU_ANDROID_VERSION=16.0 EMU_IMG_TYPE=google_apis_playstore bash emu-image-build.sh ; prints the tag.
# EMU_API=budtmo -> no build, use budtmo/docker-android:emulator_14.0 as-is (fallback, API 34, no Play Store/ARM).
set -e
V=${V:-/opt/lab5g/vnc}; API=${EMU_API:-36}; AV=${EMU_ANDROID_VERSION:-}; IMG=${EMU_IMG_TYPE:-google_apis_playstore}
BASE=${EMU_BASE:-budtmo/docker-android:emulator_14.0}
if [ "$API" = budtmo ]; then docker pull -q $BASE >/dev/null; echo $BASE; exit 0; fi
[ -n "$AV" ] || case $API in 35) AV=15.0;; 36) AV=16.0;; 37) AV=17.0;; *) echo "API $API tidak dipetakan" >&2; exit 1;; esac
TAG=lab5g/android:${API}-${IMG}
if ! docker image inspect $TAG >/dev/null 2>&1; then
  docker pull -q $BASE >/dev/null
  # --network host: build steps (apt, sdkmanager, VirtualGL download) use the HOST path (Cloud NAT). Without it the
  # build containers sit on docker0 and the ue-l3 egress policy sends them into GRE -> UE, which is not attached yet
  # during first boot (RCA apply 18 Nov 2026 13:21 WIB: apt-get exit 100, build failed).
  docker build --progress=plain --network host --build-arg BASE=$BASE --build-arg API=$API --build-arg ANDROID_VERSION=$AV --build-arg IMG_TYPE=$IMG \
    -t $TAG $V/emu-image >/var/log/lab5g/emu-image-build.log 2>&1 || { echo "build gagal, lihat /var/log/lab5g/emu-image-build.log" >&2; exit 1; }
fi
echo $TAG
