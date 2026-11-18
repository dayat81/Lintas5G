#!/bin/bash
# Day1: install Open5GS (PPA) + MongoDB (docker, 127.0.0.1) + srsRAN 4G (ZMQ) di vm-core-ran.
set -x
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y software-properties-common sysstat iperf3 tcpdump socat libzmq3-dev
docker rm -f mongo 2>/dev/null; docker run -d --name mongo --restart unless-stopped -p 127.0.0.1:27017:27017 mongo:6
add-apt-repository -y ppa:open5gs/latest
add-apt-repository -y ppa:softwareradiosystems/srsran || true
apt-get update -y
apt-get install -y open5gs
apt-cache policy srsran
apt-get install -y srsran || true
echo "== zmq plugin =="; ls /usr/lib/x86_64-linux-gnu/ | grep -i srsran_rf || true
dpkg -L srsran 2>/dev/null | grep -i -E "rf_zmq|srsenb$|srsue$"
echo INSTALL_DONE
