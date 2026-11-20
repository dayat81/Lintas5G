#!/bin/bash
# vm-emu (root). (Re)create the emulator container with TAP. Requires /opt/lab5g/emu.env (VNC_PASSWORD=..., generated on the VM, never printed)
# and an image: lab5g/android:36-google_apis_playstore (built by emu-image-build.sh) or a docker-commit backup that contains a Google login.
# AVD is inside the container layer -> take `docker commit` BEFORE recreating. No -wipe-data: docker-android only wipes when hw.device.name differs.
set -e
IMG=${IMG:-lab5g/android:36-google_apis_playstore}
ARGS='-memory 8192 -cores 6 -no-audio -net-tap tap0 -net-tap-script-up no -net-tap-script-down no'
# NOTE: -qemu -netdev tap ... -device virtio-net-pci gives an eth1 that stays DOWN (no adb root on the Play image) -> do NOT use.
docker rm -f android-emu >/dev/null 2>&1 || true
# docker-android start does `sed -i 1d /etc/passwd` (drops root); a committed image keeps that -> `sudo` breaks. Restore the root line before start.
docker run --rm --entrypoint cat "$IMG" /etc/passwd > /tmp/passwd.orig
{ echo 'root:x:0:0:root:/root:/bin/bash'; cat /tmp/passwd.orig; } | awk '!s[$0]++' > /tmp/passwd.fix
docker create --name android-emu --restart unless-stopped --privileged --device /dev/kvm --device /dev/net/tun --network host \
  -e EMULATOR_DEVICE="Pixel 8" -e WEB_VNC=true -e EMULATOR_GPU=swiftshader_indirect -e EMULATOR_LAUNCH_PREFIX="" \
  -e SCREEN_WIDTH=1920 -e SCREEN_HEIGHT=1080 -e EMULATOR_DATA_PARTITION=16g -e EMULATOR_ADDITIONAL_ARGS="$ARGS" \
  --env-file /opt/lab5g/emu.env "$IMG" >/dev/null
docker cp /tmp/passwd.fix android-emu:/etc/passwd
docker start android-emu >/dev/null
for i in $(seq 70); do [ "$(docker exec android-emu adb shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = 1 ] && break; sleep 5; done
docker exec android-emu adb shell svc wifi disable    # wlan0 still sits on SLIRP and would steal 10.0.2.x routes
docker exec android-emu adb shell 'ip -4 -br a; ip route'
