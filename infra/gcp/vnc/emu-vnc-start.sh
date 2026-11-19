#!/bin/bash
# Emulator container (budtmo-based) with a random VNC password (generated on the VM, never printed).
# Ports 5900/6080/5555 bind 127.0.0.1 only -> IAP SSH tunnel / caddy. Idempotent: the container is recreated only when
# absent, stopped, or when image/device/screen differ from the running one (label lab5g.spec), or FORCE=1.
# Params (env, defaults = large screen + newest Play Store image):
#   EMU_IMAGE        image tag (default: built by emu-image-build.sh from EMU_API/EMU_IMG_TYPE)
#   EMU_API=36  EMU_IMG_TYPE=google_apis_playstore   (EMU_API=budtmo -> budtmo/docker-android:emulator_14.0)
#   EMU_DEVICE="Pixel C" (tablet 2560x1800; budtmo list: Nexus 4/5/7/One/S, Samsung Galaxy S6-S10, Pixel C/8/9)
#   EMU_SCREEN=1920x1080 (X/VNC framebuffer)  EMU_RAM_MB=8192  EMU_CORES=6  EMU_DATA=16g
#   EMU_USERDATA_URI=gs://<private-bucket>/<path>/session.tar.zst : restore saved session (SENSITIVE, see README)
#   EMU_USERDATA_MOUNT=1 (default): AVD lives in host dir EMU_USERDATA_DIR (/var/lib/lab5g/emu-userdata), bind-mounted
#            into the container -> survives container recreate/reboot; restore = extract once, no `docker cp`. 0 = ephemeral.
#   EMU_VNC=1 (default) publishes VNC 5900 / noVNC 6080 on 127.0.0.1; EMU_VNC=0 = HEADLESS (only adb 127.0.0.1:5555).
#   EMU_GPU: auto (default) = "host" through VirtualGL EGL (vglrun -d egl0) + `--gpus all` when /opt/lab5g/gpu.env says
#            EMU_HAS_GPU=1 and docker has the nvidia runtime; otherwise swiftshader_indirect (CPU). Explicit values win.
set -e
V=${V:-/opt/lab5g/vnc}
for i in $(seq 1 60); do command -v docker >/dev/null && ! pgrep -x apt-get >/dev/null && break; sleep 5; done
mkdir -p /opt/lab5g /var/log/lab5g; umask 077
P=/opt/lab5g/vnc-password.txt
[ -s $P ] || tr -dc 'A-Za-z0-9' </dev/urandom 2>/dev/null | head -c 20 > $P
chown root:root $P; chmod 0600 $P
printf 'VNC_PASSWORD=%s\n' "$(cat $P)" > /opt/lab5g/emu.env; chmod 0600 /opt/lab5g/emu.env
umask 022
IMG=${EMU_IMAGE:-$(EMU_API=${EMU_API:-36} EMU_IMG_TYPE=${EMU_IMG_TYPE:-google_apis_playstore} bash $V/emu-image-build.sh)} || true
if [ -z "$IMG" ] && [ "${EMU_API:-36}" = 36 ] && [ -z "${EMU_IMAGE:-}" ]; then
  echo "build API 36 gagal -> coba API 35 sekali"; IMG=$(EMU_API=35 EMU_IMG_TYPE=${EMU_IMG_TYPE:-google_apis_playstore} bash $V/emu-image-build.sh) || true
fi
[ -n "$IMG" ] || { echo "EMU_IMAGE kosong: build gagal (lihat /var/log/lab5g/emu-image-build.log)"; exit 1; }
DEV=${EMU_DEVICE:-Pixel C}; SCR=${EMU_SCREEN:-1920x1080}; GPU=${EMU_GPU:-auto}
EMU_HAS_GPU=0; [ -f /opt/lab5g/gpu.env ] && . /opt/lab5g/gpu.env
GARGS=(); PREFIX=""
if [ "$GPU" = auto ]; then
  if [ "$EMU_HAS_GPU" = 1 ] && nvidia-smi -L >/dev/null 2>&1 && docker info 2>/dev/null | grep -q nvidia; then GPU=host; else GPU=swiftshader_indirect; fi
fi
case "$IMG" in budtmo/*) [ "$GPU" = host ] && { echo "image budtmo asli tanpa VirtualGL -> swiftshader"; GPU=swiftshader_indirect; };; esac
if [ "$GPU" = host ]; then
  GARGS=(--gpus all -e NVIDIA_DRIVER_CAPABILITIES=all -e NVIDIA_VISIBLE_DEVICES=all); PREFIX="vglrun -d ${VGL_DEVICE:-egl0}"
fi
RAM=${EMU_RAM_MB:-8192}; CORES=${EMU_CORES:-6}; DATA=${EMU_DATA:-16g}
# headless: restored userdata trusts the adb key of the container that saved it -> skip the auth dialog
XARGS=${EMU_EXTRA_ARGS:--skip-adb-auth}
VNC=${EMU_VNC:-1}; MOUNT=${EMU_USERDATA_MOUNT:-1}; UD=${EMU_USERDATA_DIR:-/var/lib/lab5g/emu-userdata}
PORTS=(-p 127.0.0.1:5555:5555); [ "$VNC" = 1 ] && PORTS+=(-p 127.0.0.1:5900:5900 -p 127.0.0.1:6080:6080)
VOLS=(); [ "$MOUNT" = 1 ] && VOLS=(-v "$UD/emulator:/home/androidusr/emulator" -v "$UD/avd:/home/androidusr/.android/avd")
SPEC="$IMG|$DEV|$SCR|$GPU|$RAM|$CORES|$DATA|$PREFIX|vnc=$VNC|mount=$MOUNT|x=$XARGS"
cur=$(docker inspect -f '{{.State.Running}}|{{index .Config.Labels "lab5g.spec"}}' android-emu 2>/dev/null || true)
if [ "${FORCE:-0}" != 1 ] && [ "$cur" = "true|$SPEC" ]; then
  echo "android-emu already running ($SPEC)"
else
  docker rm -f android-emu >/dev/null 2>&1 || true
  if [ "$MOUNT" = 1 ]; then
    # restore (optional) BEFORE create: extract into the host dir that is bind-mounted below (no docker cp)
    [ -n "${EMU_USERDATA_URI:-}" ] && IMG="$IMG" EMU_DEVICE="$DEV" UD="$UD" bash $V/emu-session-restore.sh 2>&1 | sed 's/^/[session] /'
    install -d -m 0700 -o 1300 -g 1301 "$UD/emulator" "$UD/avd"; chmod 0711 "$UD"
  fi
  WEBVNC=true; [ "$VNC" = 1 ] || WEBVNC=false
  docker create --name android-emu --restart unless-stopped --privileged --device /dev/kvm \
    --label "lab5g.spec=$SPEC" "${PORTS[@]}" "${VOLS[@]}" \
    -e EMULATOR_DEVICE="$DEV" -e WEB_VNC=$WEBVNC -e EMULATOR_GPU="$GPU" -e EMULATOR_LAUNCH_PREFIX="$PREFIX" "${GARGS[@]}" \
    -e SCREEN_WIDTH="${SCR%x*}" -e SCREEN_HEIGHT="${SCR#*x}" \
    -e EMULATOR_DATA_PARTITION="$DATA" -e EMULATOR_ADDITIONAL_ARGS="-memory $RAM -cores $CORES -no-audio $XARGS" \
    --env-file /opt/lab5g/emu.env "$IMG" >/dev/null
  # persistent adb key pair (part of the session; never logged/committed): inject before first start
  if [ "$MOUNT" = 1 ] && [ -s "$UD/adb/adbkey" ] && [ -s "$UD/adb/adbkey.pub" ]; then
    docker cp "$UD/adb/adbkey" android-emu:/home/androidusr/.android/adbkey >/dev/null
    docker cp "$UD/adb/adbkey.pub" android-emu:/home/androidusr/.android/adbkey.pub >/dev/null
    echo "adbkey=persisted"
  fi
  docker start android-emu >/dev/null
fi
S=$(date +%s); b=
for i in $(seq 1 120); do b=$(docker exec android-emu adb shell getprop sys.boot_completed 2>/dev/null | tr -d '\r'); [ "$b" = 1 ] && break; sleep 5; done
if [ "$MOUNT" = 1 ] && [ ! -s "$UD/adb/adbkey" ]; then
  install -d -m 0700 -o root -g root "$UD/adb"
  docker cp android-emu:/home/androidusr/.android/adbkey "$UD/adb/adbkey" >/dev/null 2>&1 && \
  docker cp android-emu:/home/androidusr/.android/adbkey.pub "$UD/adb/adbkey.pub" >/dev/null 2>&1 && \
  { chown 1300:1301 "$UD/adb/adbkey" "$UD/adb/adbkey.pub"; chmod 0600 "$UD/adb/adbkey" "$UD/adb/adbkey.pub"; echo "adbkey=captured"; }
fi
echo "BOOT_COMPLETED=$b BOOT_WAIT_S=$(( $(date +%s)-S )) SPEC=$SPEC"
A="docker exec android-emu adb shell"
echo "android=$($A getprop ro.build.version.release 2>/dev/null | tr -d '\r') sdk=$($A getprop ro.build.version.sdk 2>/dev/null | tr -d '\r') abilist=$($A getprop ro.product.cpu.abilist 2>/dev/null | tr -d '\r') native_bridge=$($A getprop ro.dalvik.vm.native.bridge 2>/dev/null | tr -d '\r') wm=$($A wm size 2>/dev/null | tr -d '\r' | awk '{print $NF}')"
# Chrome without first-run/sign-in screens (automation + manual use without a Google account); idempotent
$A "echo '_ --disable-fre --no-default-browser-check --no-first-run' > /data/local/tmp/chrome-command-line" 2>/dev/null
$A am set-debug-app --persistent com.android.chrome >/dev/null 2>&1
echo "gpu_mode=$GPU renderer=$($A dumpsys SurfaceFlinger 2>/dev/null | grep -m1 -i 'GLES:' | tr -d '\r' | sed 's/^ *//')"
echo "play_store=$($A pm list packages com.android.vending 2>/dev/null | tr -d '\r')"
ls -l $P | awk '{print $1,$3,$4,$NF}'
ss -ltnp | grep -E ':(5900|6080|5555)\b' | awk '{print $4}'
echo "accounts=$($A dumpsys account 2>/dev/null | grep -c 'Account {') vnc=$VNC userdata_mount=$MOUNT"
