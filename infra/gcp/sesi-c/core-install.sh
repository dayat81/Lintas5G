#!/bin/bash
# Sesi B: Open5GS EPC (PPA) + MongoDB docker + srsRAN_4G ZMQ (source) + Zeek (OBS) + tshark/iperf3.
set -x
export DEBIAN_FRONTEND=noninteractive
echo "wireshark-common wireshark-common/install-setuid boolean false" | debconf-set-selections
for i in $(seq 1 30); do pgrep -f "apt|dpkg" >/dev/null || break; sleep 5; done
apt-get update -y
apt-get install -y software-properties-common sysstat iperf3 tcpdump tshark jq socat libzmq3-dev curl gnupg python3
docker rm -f mongo 2>/dev/null; docker run -d --name mongo --restart unless-stopped -p 127.0.0.1:27017:27017 mongo:6
add-apt-repository -y ppa:open5gs/latest
curl -fsSL https://download.opensuse.org/repositories/security:zeek/xUbuntu_22.04/Release.key | gpg --dearmor --yes -o /etc/apt/trusted.gpg.d/security_zeek.gpg
echo 'deb http://download.opensuse.org/repositories/security:/zeek/xUbuntu_22.04/ /' > /etc/apt/sources.list.d/security-zeek.list
apt-get update -y
apt-get install -y open5gs
apt-get install -y build-essential cmake git libfftw3-dev libmbedtls-dev libboost-program-options-dev libconfig++-dev libsctp-dev
mkdir -p /opt/lab5g/srsran /var/log/lab5g && cd /opt/lab5g/srsran
[ -d srsRAN_4G ] || git clone -q --depth 1 -b release_23_11 https://github.com/srsran/srsRAN_4G.git
cd srsRAN_4G && mkdir -p build && cd build
cmake .. -DENABLE_UHD=OFF -DENABLE_BLADERF=OFF -DENABLE_SOAPYSDR=OFF -DENABLE_ZEROMQ=ON -DENABLE_SRSEPC=OFF -DCMAKE_BUILD_TYPE=Release -DENABLE_WERROR=OFF > /var/log/lab5g/srs-cmake.log 2>&1
make -j4 srsenb srsue > /var/log/lab5g/srs-build.log 2>&1; echo "srs make exit=$?"
ls -la srsenb/src/srsenb srsue/src/srsue
apt-get install -y zeek-lts || apt-get install -y zeek
/opt/zeek/bin/zeek --version
dpkg -l | grep -E "open5gs |zeek" | awk '{print $2,$3}'
echo INSTALL_DONE
