#!/bin/bash
# Sesi A: install Open5GS 2.8 (PPA) 5GC + MongoDB (docker, 127.0.0.1) + UERANSIM (source) + Zeek (OBS) + tools.
# Tidak ada secret di script ini.
set -x
export DEBIAN_FRONTEND=noninteractive
echo "wireshark-common wireshark-common/install-setuid boolean false" | debconf-set-selections
echo "postfix postfix/main_mailer_type select No configuration" | debconf-set-selections
apt-get update -y
apt-get install -y software-properties-common sysstat iperf3 tcpdump tshark jq git make g++ cmake \
  libsctp-dev lksctp-tools iproute2 curl gnupg
modprobe sctp || apt-get install -y linux-modules-extra-$(uname -r) && modprobe sctp
docker rm -f mongo 2>/dev/null; docker run -d --name mongo --restart unless-stopped -p 127.0.0.1:27017:27017 mongo:6
add-apt-repository -y ppa:open5gs/latest
# Zeek dari OBS (security:zeek)
curl -fsSL https://download.opensuse.org/repositories/security:zeek/xUbuntu_22.04/Release.key | gpg --dearmor --yes -o /etc/apt/trusted.gpg.d/security_zeek.gpg
echo 'deb http://download.opensuse.org/repositories/security:/zeek/xUbuntu_22.04/ /' > /etc/apt/sources.list.d/security-zeek.list
apt-get update -y
# Serial: apt tidak boleh paralel (dpkg lock).
apt-get install -y open5gs
apt-get install -y zeek-lts || apt-get install -y zeek
# UERANSIM dari source (paralel make)
mkdir -p /opt/lab5g/ueransim && cd /opt/lab5g/ueransim
[ -d UERANSIM ] || git clone -q --depth 1 https://github.com/aligungr/UERANSIM
cd UERANSIM && make -j"$(nproc)" > /var/log/lab5g/ueransim-build.log 2>&1; echo "ueransim make exit=$?"
ls -la build/nr-gnb build/nr-ue build/nr-cli
dpkg -l | grep -E "open5gs |zeek" | awk '{print $2,$3}'
/opt/zeek/bin/zeek --version
echo INSTALL_DONE
