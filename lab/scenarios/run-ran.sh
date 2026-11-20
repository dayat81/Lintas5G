#!/bin/bash
# run-ran.sh <gnb-image> <nUE>: isolated RAN mq-* (gNB shares mq-lab netns; nrUE on bridge)
IMG=${1:-oaisoftwarealliance/oai-gnb:v3.0.0}; N=${2:-2}; D=/workspace/booster-qod-test
UEARGS="-E -r 106 --numerology 1 -C 3319680000 --uecap_file /opt/up/uecap_ports2.xml --ue-nb-ant-rx 2 --ue-nb-ant-tx 2"
sudo docker rm -f mq-ue1 mq-ue2 >/dev/null 2>&1; [ "${KEEPGNB:-0}" = 1 ] || sudo docker rm -f mq-gnb >/dev/null 2>&1
sudo docker run -d --name mq-gnb --network container:mq-lab --cap-drop ALL \
  -v /workspace/oai-multiue/shim/libsctp2tcp2.so:/opt/shim.so:ro -v /workspace/oai-multiue/conf/gnb-c-n78-106-2x2.conf:/opt/oai-gnb/etc/gnb.conf:ro \
  -e LD_PRELOAD=/opt/shim.so -e USE_ADDITIONAL_OPTIONS="--rfsim -E --log_config.global_log_options level,nocolor,time" $IMG >/dev/null
for s in $(seq 40); do sudo docker logs mq-gnb 2>&1 | grep -q "Received NGSetupResponse" && break; sleep 1; done
sudo docker logs mq-gnb 2>&1 | grep -q "Received NGSetupResponse" && echo "ngsetup_ok=${s}s" || { echo NGSETUP_FAIL; exit 1; }
for i in $(seq $N); do
  sudo docker run -d --name mq-ue$i --cap-drop ALL --cap-add NET_ADMIN --cap-add NET_RAW --device /dev/net/tun \
    -v /workspace/oai-multiue/conf/upstream:/opt/up:ro -v $D/secrets/ue$i.conf:/opt/oai-nr-ue/etc/nr-ue.conf:ro \
    -e USE_ADDITIONAL_OPTIONS="--rfsim --log_config.global_log_options level,nocolor,time $UEARGS" \
    oaisoftwarealliance/oai-nr-ue:v3.0.0 >/dev/null
  for s in $(seq 90); do sudo docker exec mq-ue$i ip -4 -o addr show oaitun_ue1 2>/dev/null | grep -q inet && break; sleep 1; done
  echo "ue$i ip_after=${s}s"
  sudo docker exec -d mq-ue$i sh -c 'ping -i 1 -I oaitun_ue1 10.45.0.1 > /tmp/keepalive.log 2>&1'   # UE never idle, from attach
done
