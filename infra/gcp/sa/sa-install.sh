#!/bin/bash
# Install for the 5G SA profile: Open5GS (PPA) + MongoDB (docker, 127.0.0.1) + Zeek + tshark + srsRAN runtime.
# srsRAN Project gNB + srsUE: prebuilt tarball from the runs bucket (metadata ran-prebuild) if set and the sha256
# matches, else built from source in an ubuntu:22.04 container (prebuild/build-srsran.sh, ~30-40 min on 4 vCPU).
set -x
MODE=${1:-sa-srsran}; export DEBIAN_FRONTEND=noninteractive
MD=http://metadata.google.internal/computeMetadata/v1/instance/attributes
echo "wireshark-common wireshark-common/install-setuid boolean false" | debconf-set-selections
apt-get update -y
apt-get install -y software-properties-common iperf3 tcpdump tshark jq git curl gnupg lksctp-tools iproute2 ethtool \
  libzmq5 libfftw3-single3 libfftw3-double3 libmbedtls14 libsctp1 libyaml-cpp0.7 libconfig++9v5 libboost-program-options1.74.0 zstd
modprobe sctp || { apt-get install -y linux-modules-extra-$(uname -r) && modprobe sctp; }
docker inspect mongo >/dev/null 2>&1 || docker run -d --name mongo --restart unless-stopped -p 127.0.0.1:27017:27017 mongo:6
add-apt-repository -y ppa:open5gs/latest
curl -fsSL https://download.opensuse.org/repositories/security:zeek/xUbuntu_22.04/Release.key | gpg --dearmor --yes -o /etc/apt/trusted.gpg.d/security_zeek.gpg
echo 'deb http://download.opensuse.org/repositories/security:/zeek/xUbuntu_22.04/ /' > /etc/apt/sources.list.d/security-zeek.list
apt-get update -y
apt-get install -y open5gs
apt-get install -y zeek-lts || apt-get install -y zeek
if [ "$MODE" = sa-srsran ] && [ ! -x /opt/srsran/bin/gnb ]; then
  B=$(curl -fsS -H 'Metadata-Flavor: Google' $MD/lab5g-bucket); O=$(curl -fsS -H 'Metadata-Flavor: Google' $MD/ran-prebuild 2>/dev/null || true)
  GCLOUD=$(command -v gcloud || echo /snap/bin/gcloud); W=/var/lib/lab5g/prebuild; mkdir -p $W
  ok=0
  if [ -n "$O" ] && "$GCLOUD" storage cp "gs://$B/$O" "gs://$B/$O.sha256" $W/ ; then
    f=$W/$(basename "$O")
    [ "$(sha256sum "$f" | awk '{print $1}')" = "$(awk '{print $1}' "$f.sha256")" ] && tar -I zstd -xf "$f" -C / && ok=1
    echo "prebuild from bucket ok=$ok"
  fi
  if [ $ok = 0 ]; then
    docker run --rm -v $W:/out -v /opt/lab5g/prebuild/build-srsran.sh:/build-srsran.sh:ro -e JOBS=$(nproc) ubuntu:22.04 bash /build-srsran.sh
    tar -I zstd -xf $W/srsran-*.tar.zst -C /
  fi
  echo /opt/srsran/lib > /etc/ld.so.conf.d/srsran.conf; ldconfig
  ldd /opt/srsran/bin/gnb /opt/srsran/bin/srsue | grep "not found" || true
fi
if [ "$MODE" = sa-oai ]; then
  # OAI gNB / nrUE official images, pulled by digest only (metadata oai-gnb-image / oai-ue-image); configs: oai-config.sh
  for k in oai-gnb-image oai-ue-image; do
    IMG=$(curl -fsS -H 'Metadata-Flavor: Google' $MD/$k)
    case "$IMG" in *@sha256:*) docker pull -q "$IMG" && docker image inspect "$IMG" --format '{{index .RepoDigests 0}}';; *) echo "$k not pinned by digest: $IMG"; exit 3;; esac
  done
fi
if [ "$MODE" = sa-ueransim ] && [ ! -x /opt/lab5g/ueransim/UERANSIM/build/nr-gnb ]; then
  apt-get install -y make g++ cmake libsctp-dev
  mkdir -p /opt/lab5g/ueransim && cd /opt/lab5g/ueransim
  [ -d UERANSIM ] || git clone -q --depth 1 https://github.com/aligungr/UERANSIM
  cd UERANSIM && make -j"$(nproc)" > /var/log/lab5g/ueransim-build.log 2>&1
fi
dpkg -l | grep -E "open5gs |zeek" | awk '{print $2,$3}'
echo SA_INSTALL_DONE
