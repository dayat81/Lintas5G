#!/bin/bash
# srsRAN 4G PPA 22.10 tidak membawa plugin ZMQ -> build dari source (release_23_11) dengan ZMQ.
set -ex
export DEBIAN_FRONTEND=noninteractive
apt-get install -y build-essential cmake git libfftw3-dev libmbedtls-dev libboost-program-options-dev libconfig++-dev libsctp-dev libzmq3-dev
cd /opt/lab5g/srsran
[ -d srsRAN_4G ] || git clone --depth 1 -b release_23_11 https://github.com/srsran/srsRAN_4G.git
cd srsRAN_4G && mkdir -p build && cd build
cmake .. -DENABLE_UHD=OFF -DENABLE_BLADERF=OFF -DENABLE_SOAPYSDR=OFF -DENABLE_ZEROMQ=ON -DENABLE_SRSEPC=OFF -DCMAKE_BUILD_TYPE=Release -DENABLE_WERROR=OFF
make -j4 srsenb srsue
ls -la srsenb/src/srsenb srsue/src/srsue lib/src/phy/rf/*.so
echo BUILD_DONE
