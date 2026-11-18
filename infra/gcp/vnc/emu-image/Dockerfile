# Lab5G emulator image: reuse budtmo/docker-android (VNC/noVNC/CLI) but with a NEWER Android system image that has
# the Google Play Store (google_apis_playstore) - budtmo's own tags stop at emulator_14.0 (API 34, google_apis, no ARM
# translation: abilist was x86_64 only on emulator_13.0, RCA 18 Nov 2026).
# API 35+ x86_64 Google images ship ARM64 translation (libndk_translation) -> ARM-only apps/games can install.
# Build args are set by emu-image-build.sh (terraform vars gui_emu_api / gui_emu_img_type).
ARG BASE=budtmo/docker-android:emulator_14.0
FROM ${BASE}
ARG API=36
ARG ANDROID_VERSION=16.0
ARG IMG_TYPE=google_apis_playstore
ARG VGL_VER=3.1.5
USER root
# GPU path (gui_emu_gpu=t4): VirtualGL EGL back end redirects the emulator's GLX (-gpu host) to the NVIDIA GPU through
# the EGL device (no 3D X server needed), frames are read back into the existing Xvfb/x11vnc/noVNC. libglvnd is required
# for the NVIDIA EGL/GL vendor libs that nvidia-container-toolkit injects (NVIDIA_DRIVER_CAPABILITIES=all).
RUN apt-get update -q && DEBIAN_FRONTEND=noninteractive apt-get install -y -q --no-install-recommends \
      libglvnd0 libgl1 libegl1 libgles2 libglx0 libvulkan1 mesa-utils curl ca-certificates \
 && curl -fsSL -o /tmp/vgl.deb https://github.com/VirtualGL/virtualgl/releases/download/${VGL_VER}/virtualgl_${VGL_VER}_amd64.deb \
 && (dpkg -i /tmp/vgl.deb || DEBIAN_FRONTEND=noninteractive apt-get install -y -q -f) \
 && rm -rf /tmp/vgl.deb /var/lib/apt/lists/* \
 && test -x /opt/VirtualGL/bin/vglrun
RUN yes | sdkmanager --licenses >/dev/null \
 && sdkmanager "platforms;android-${API}" "system-images;android-${API};${IMG_TYPE};x86_64" "emulator" \
 && rm -rf /tmp/*
COPY patch-cli.py /tmp/patch-cli.py
# CLI patches (API map 15-17, -writable-system opt-in, EMULATOR_LAUNCH_PREFIX, is_initialized fix for session restore)
RUN python3 /tmp/patch-cli.py ${APP_PATH}/cli/src/device/emulator.py && rm /tmp/patch-cli.py
ENV EMULATOR_ANDROID_VERSION=${ANDROID_VERSION} \
    EMULATOR_API_LEVEL=${API} \
    EMULATOR_IMG_TYPE=${IMG_TYPE} \
    EMULATOR_SYS_IMG=x86_64
ENV PATH="${PATH}:/opt/VirtualGL/bin"
LABEL lab5g.api="${API}" lab5g.img_type="${IMG_TYPE}" lab5g.vgl="${VGL_VER}"
USER 1300:1301
