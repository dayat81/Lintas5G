#!/bin/bash
# run-ue.sh <i>: (re)start nrUE i with keepalive ping from attach
i=$1; D=/workspace/booster-qod-test
UEARGS="-E -r 106 --numerology 1 -C 3319680000 --uecap_file /opt/up/uecap_ports2.xml --ue-nb-ant-rx 2 --ue-nb-ant-tx 2"
sudo docker rm -f mq-ue$i >/dev/null 2>&1
sudo docker run -d --name mq-ue$i --cap-drop ALL --cap-add NET_ADMIN --cap-add NET_RAW --device /dev/net/tun \
  -v /workspace/oai-multiue/conf/upstream:/opt/up:ro -v $D/secrets/ue$i.conf:/opt/oai-nr-ue/etc/nr-ue.conf:ro \
  -e USE_ADDITIONAL_OPTIONS="--rfsim --log_config.global_log_options level,nocolor,time $UEARGS" oaisoftwarealliance/oai-nr-ue:v3.0.0 >/dev/null
for s in $(seq 90); do sudo docker exec mq-ue$i ip -4 -o addr show oaitun_ue1 2>/dev/null | grep -q inet && break; sleep 1; done
sudo docker exec -d mq-ue$i sh -c 'ping -i 1 -I oaitun_ue1 10.45.0.1 > /tmp/keepalive.log 2>&1'
echo "ue$i ip_after=${s}s"
