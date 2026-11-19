#!/bin/bash
# Prebuild srsRAN Project (gNB, ZMQ) + srsRAN_4G (srsUE, ZMQ) for Ubuntu 22.04 (same as the lab VMs).
# Runs inside ubuntu:22.04:  docker run --rm --network host -m 5g -v $OUT:/out -e JOBS=3 ubuntu:22.04 bash /build-srsran.sh
# Output: /out/srsran-<proj_ref>-<4g_ref>-jammy-x86_64.tar.zst + .sha256 (install prefix /opt/srsran).
set -euo pipefail
PROJ_REF=${PROJ_REF:-release_24_10_1}; G4_REF=${G4_REF:-release_23_11}; JOBS=${JOBS:-3}
# portable ISA for GCP n2/e2/c2 (AVX2/FMA, x86-64-v3, NO AVX512). AUTO_DETECT_ISA=OFF is NOT enough: both projects still
# append -march=<cache var> (default "native") after CMAKE_*_FLAGS, so the build host CPU leaked in (v1 tarball: AVX512
# VPOPCNTDQ -> SIGILL on Cascade Lake). Fix: srsRAN_Project MARCH/MTUNE and srsRAN_4G GCC_ARCH set explicitly.
# srsRAN_4G with AUTO_DETECT_ISA=OFF needs HAVE_SSE/AVX/AVX2/FMA passed explicitly (else "no SIMD instructions found").
MARCH=${MARCH:-x86-64-v3}; ISA="-march=$MARCH"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq --no-install-recommends build-essential cmake make gcc g++ pkg-config git ca-certificates \
  libfftw3-dev libmbedtls-dev libsctp-dev libyaml-cpp-dev libgtest-dev libzmq3-dev libboost-program-options-dev \
  libconfig++-dev zstd >/dev/null
mkdir -p /src && cd /src
git clone -q --depth 1 -b "$PROJ_REF" https://github.com/srsran/srsRAN_Project.git proj
git clone -q --depth 1 -b "$G4_REF" https://github.com/srsran/srsRAN_4G.git g4
cmake -S proj -B proj/build -DCMAKE_BUILD_TYPE=Release -DENABLE_ZEROMQ=ON -DENABLE_EXPORT=ON -DBUILD_TESTS=OFF \
  -DAUTO_DETECT_ISA=OFF -DMARCH="$MARCH" -DMTUNE=generic -DCMAKE_C_FLAGS="$ISA" -DCMAKE_CXX_FLAGS="$ISA" -DCMAKE_INSTALL_PREFIX=/opt/srsran >/out/proj-cmake.log 2>&1
cmake --build proj/build -j"$JOBS" --target gnb >/out/proj-build.log 2>&1
cmake -S g4 -B g4/build -DCMAKE_BUILD_TYPE=Release -DENABLE_ZEROMQ=ON -DENABLE_UHD=OFF -DENABLE_BLADERF=OFF \
  -DENABLE_SOAPYSDR=OFF -DENABLE_SRSENB=OFF -DENABLE_SRSEPC=OFF -DAUTO_DETECT_ISA=OFF -DHAVE_SSE=ON -DHAVE_AVX=ON -DHAVE_AVX2=ON -DHAVE_FMA=ON -DGCC_ARCH="$MARCH" -DCMAKE_C_FLAGS="$ISA" -DCMAKE_CXX_FLAGS="$ISA" -DCMAKE_INSTALL_PREFIX=/opt/srsran >/out/g4-cmake.log 2>&1
cmake --build g4/build -j"$JOBS" --target srsue >/out/g4-build.log 2>&1
mkdir -p /opt/srsran/bin /opt/srsran/lib /opt/srsran/share
install -m755 proj/build/apps/gnb/gnb /opt/srsran/bin/gnb
install -m755 g4/build/srsue/src/srsue /opt/srsran/bin/srsue
find g4/build -name 'libsrsran_rf*.so*' -exec cp -a {} /opt/srsran/lib/ \;
cp -a proj/configs /opt/srsran/share/gnb-configs 2>/dev/null || true
printf 'isa=%s\nproj=%s %s\n4g=%s %s\n' "$ISA" "$PROJ_REF" "$(git -C proj rev-parse HEAD)" "$G4_REF" "$(git -C g4 rev-parse HEAD)" > /opt/srsran/VERSION
# ISA gate: no -march=native, and AVX512 (zmm / vpopcnt / k-mask) ONLY inside srsRAN's runtime-dispatched kernels
# (function names *avx512*, selected by cpu_architecture_info at runtime). v1 tarball had ~20k AVX512 insns in 570
# generic functions (incl. discover_cpu_architecture -> SIGILL on Cascade Lake).
grep -q 'march=native' proj/build/CMakeCache.txt g4/build/CMakeCache.txt && { echo "ISA_FAIL: -march=native in CMakeCache"; exit 4; }
for b in /opt/srsran/bin/gnb /opt/srsran/bin/srsue /opt/srsran/lib/libsrsran_rf*.so.*; do
  [ -L "$b" ] && continue
  r=$(objdump -d --no-show-raw-insn "$b" | awk '/^[0-9a-f]+ <.*>:$/{f=$2} /%zmm|vpopcnt[dq]|%k[1-7]/{if (f ~ /avx512/) a++; else o++} END{printf "%d %d", a, o}')
  echo "isa-check $(basename "$b") avx512_dispatched=${r% *} avx512_generic=${r#* }"; [ "${r#* }" = 0 ] || { echo "ISA_FAIL $b"; exit 4; }
done
T=srsran-${PROJ_REF}-${G4_REF}-${MARCH}-jammy-x86_64.tar.zst
tar -I 'zstd -T2 -10' -cf /out/$T -C / opt/srsran
( cd /out && sha256sum $T > $T.sha256 )
ldd /opt/srsran/bin/gnb /opt/srsran/bin/srsue | grep -c "not found" || true
echo "PREBUILD_OK $T"
