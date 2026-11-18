#!/bin/bash
# vm-emu (root), idempotent: NVIDIA driver (headless + GL/EGL/Vulkan libs) + nvidia-container-toolkit for docker.
# Only acts when an NVIDIA PCI device is present (gui_emu_gpu=t4 -> n1-standard-8 + nvidia-tesla-t4); otherwise no-op.
# Ubuntu 22.04, Secure Boot is OFF on vm-emu (compute.tf) so the DKMS module loads unsigned.
# Writes /opt/lab5g/gpu.env (EMU_HAS_GPU=0|1, GPU_NAME, DRIVER) for emu-vnc-start.sh and the collector.
# A single reboot is allowed if the module cannot be loaded right after install (marker /var/lib/lab5g/gpu-rebooted).
set -u
NV=${NV_DRIVER_BRANCH:-570}; L=/var/log/lab5g/gpu-setup.log; mkdir -p /var/log/lab5g /var/lib/lab5g /opt/lab5g
out(){ printf 'EMU_HAS_GPU=%s\nGPU_NAME="%s"\nDRIVER="%s"\n' "$1" "$2" "$3" > /opt/lab5g/gpu.env; echo "gpu: has=$1 name=$2 driver=$3"; }
export DEBIAN_FRONTEND=noninteractive
if ! lspci -nn 2>/dev/null | grep -qi 'nvidia'; then out 0 "" ""; exit 0; fi
if ! nvidia-smi -L >/dev/null 2>&1; then
  for i in $(seq 1 60); do pgrep -x apt-get >/dev/null || break; sleep 5; done
  apt-get update -q >>$L 2>&1
  # headless driver + userspace GL/EGL/Vulkan (needed for rendering, not just CUDA); no Xorg
  apt-get install -y -q linux-headers-$(uname -r) nvidia-headless-${NV}-server nvidia-utils-${NV}-server \
    libnvidia-gl-${NV}-server libnvidia-compute-${NV}-server pciutils >>$L 2>&1 || { echo "driver install gagal ($L)"; out 0 "" ""; exit 1; }
  modprobe nvidia >>$L 2>&1 || true
  if ! nvidia-smi -L >/dev/null 2>&1; then
    if [ ! -f /var/lib/lab5g/gpu-rebooted ]; then touch /var/lib/lab5g/gpu-rebooted; echo "reboot sekali untuk memuat modul nvidia" | tee -a $L; systemctl reboot; exit 0; fi
    echo "nvidia-smi gagal setelah reboot -> fallback swiftshader" | tee -a $L; out 0 "" ""; exit 1
  fi
fi
if ! command -v nvidia-ctk >/dev/null; then
  curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | gpg --dearmor --yes -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
  curl -fsSL https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list \
    | sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' \
    > /etc/apt/sources.list.d/nvidia-container-toolkit.list
  apt-get update -q >>$L 2>&1; apt-get install -y -q nvidia-container-toolkit >>$L 2>&1 || { echo "toolkit install gagal"; out 0 "" ""; exit 1; }
fi
if ! docker info 2>/dev/null | grep -q 'nvidia'; then nvidia-ctk runtime configure --runtime=docker >>$L 2>&1 && systemctl restart docker; fi
nvidia-smi -pm 1 >/dev/null 2>&1 || true
out 1 "$(nvidia-smi --query-gpu=name --format=csv,noheader | head -1)" "$(nvidia-smi --query-gpu=driver_version --format=csv,noheader | head -1)"
