#!/bin/bash
# vm-core-ran (root): booster E2E stack on top of the sa-oai bring-up. Never prints K/OPc/IMSI/secrets.
set -u
B=/opt/booster; S=/root/bsec; L=/var/log/lab5g/booster; mkdir -p $L
log(){ echo "$(TZ=Asia/Jakarta date '+%F %T WIB') [booster] $*" | tee -a $L/up.log; }
red(){ sed -E 's/[0-9]{15}/IMSI_REDACTED/g; s/(key|opc|k=)[^ ]*/\1<R>/Ig'; }
step=${1:-all}
images(){ docker image inspect lintas5g/oai-gnb:v3.0.0-slice-qosrel3 >/dev/null 2>&1 || gunzip -c $B/gnb.tar.gz | docker load | tail -1
  docker image inspect lintas5g/qod-adapter:0.1.1 >/dev/null 2>&1 || gunzip -c $B/adapter.tar.gz | docker load | tail -1
  docker images --format '{{.Repository}}:{{.Tag}} {{.ID}}' | grep lintas5g | tee -a $L/up.log; }
core(){
  bash /opt/lab5g/sa/oai-run.sh stop 1 >/dev/null 2>&1
  rm -rf /tmp/ov; mkdir /tmp/ov; tar -C /tmp/ov -xzf $B/open5gs-overlay.tar.gz
  for n in nrfd scpd amfd smfd upfd ausfd udmd udrd pcfd bsfd nssfd; do systemctl stop open5gs-$n; done
  chown -R root:root /tmp/ov; cp -a /tmp/ov/overlay/usr/. /usr/; chown root:root /usr /usr/bin /usr/lib /usr/lib/x86_64-linux-gnu; ldconfig
  grep -q 'reference: QOS_E' /etc/open5gs/pcf.yaml || python3 /tmp/ov/add_qos_profiles.py /etc/open5gs/pcf.yaml
  grep -c 'reference: QOS_' /etc/open5gs/pcf.yaml | sed 's/^/pcf qos_profiles entries: /' | tee -a $L/up.log
  sha256sum /usr/bin/open5gs-upfd /tmp/ov/overlay/usr/bin/open5gs-upfd | awk '{print $1}' | uniq | wc -l | sed 's/^/upfd hash variants (1=patched installed): /' | tee -a $L/up.log
  ( umask 077; I=$(sed -nE 's/.*imsi *= *"([0-9]+)".*/\1/p' $S/ue1.conf); K=$(sed -nE 's/.*key *= *"([0-9a-fA-F]+)".*/\1/p' $S/ue1.conf); O=$(sed -nE 's/.*opc *= *"([0-9a-fA-F]+)".*/\1/p' $S/ue1.conf)
    [ ${#I} = 15 ] && [ ${#K} = 32 ] && [ ${#O} = 32 ] || { echo "ue1.conf parse failed" >&2; exit 1; }
    printf 'IMSI=%s\nKEY=%s\nOPC=%s\n' "$I" "$K" "$O" > /root/lab5g-sub.env )
  bash /opt/lab5g/sa/sa-config.sh sa-oai 2>&1 | grep -v -i -E 'key|opc|imsi|k=' | tail -4 | tee -a $L/up.log
  OAI_MIMO=2 bash /opt/lab5g/sa/oai-config.sh 1 2>&1 | red | tail -2 | tee -a $L/up.log
  /usr/bin/open5gs-upfd -v 2>&1 | head -1 | tee -a $L/up.log
}
ran(){
  cp /opt/lab5g/sa/oai-run.sh $B/oai-run-local.sh
  sed -i 's/^case "\$GI\$UI" in \*@sha256:\*@sha256:\*) ;; \*) echo .*$/: # booster E2E: local gNB image (no registry digest), checked by image ID below/' $B/oai-run-local.sh
  grep -q 'booster E2E: local gNB image' $B/oai-run-local.sh || { echo "digest-check patch failed"; return 1; }
  docker image inspect -f '{{.Id}}' lintas5g/oai-gnb:v3.0.0-slice-qosrel3 | cut -c8-19 | sed 's/^/gnb image id: /' | tee -a $L/up.log
  UI=$(curl -fsS -H 'Metadata-Flavor: Google' http://metadata.google.internal/computeMetadata/v1/instance/attributes/oai-ue-image)
  OAI_GNB_IMAGE=lintas5g/oai-gnb:v3.0.0-slice-qosrel3 OAI_UE_IMAGE=$UI OAI_RF=rfsim OAI_MIMO=2 \
    OAI_GNB_DOCKER_OPTS="-v $B/slice:/opt/slice:ro -e OAI_DL_SLICE_CONF=/opt/slice/slice.conf" \
    bash $B/oai-run-local.sh start 1 2>&1 | red | tail -8 | tee -a $L/up.log
  grep -a 'SLICE' /var/log/lab5g/sa/oai-gnb.out | tail -2 | tee -a $L/up.log
}
net(){
  sed 's/tun_srsue/oaitun_ue1/g' /opt/lab5g/vnc/core-gre-emu.sh > $B/core-gre-emu.sh
  sed 's/tun_srsue/oaitun_ue1/g' /opt/lab5g/vnc/gui-net-fix.sh > $B/gui-net-fix.sh
  sed 's/tun_srsue/oaitun_ue1/g' /opt/lab5g/sesi-d/pktlat2-taps.sh > /opt/lab5g/sesi-d/pktlat2-taps-oai.sh
  # veth host<->UE netns (as core-proxy-gui.sh, without gost)
  if ! ip link show veth-ueh >/dev/null 2>&1; then
    ip link add veth-ueh type veth peer name veth-uen; ip link set veth-uen netns ue1
    ip addr add 10.200.0.1/30 dev veth-ueh; ip link set veth-ueh up
    ip netns exec ue1 ip addr add 10.200.0.2/30 dev veth-uen; ip netns exec ue1 ip link set veth-uen up
  fi
  bash $B/gui-net-fix.sh 2>&1 | tail -2; bash $B/core-gre-emu.sh 2>&1 | tail -3 | tee -a $L/up.log
  cd /opt/lab5g/sesi-d && REFLECTOR_MODE=d443 bash ./reflector.sh start 2>&1 | tail -6 | tee -a $L/up.log
}
adapter(){
  U=$(stat -c %u:%g $S/clients.yaml); A=/var/lib/booster/adapter; mkdir -p $A/data $A/events $A/sec
  # GCP copy of the secrets dir: devices.yaml = ue1 only, dnn internet (GCP DNN); IP file refreshed from the UE
  install -m 600 $S/clients.yaml $S/jwt-signing.pem $S/bindings.yaml $S/sink-ca.pem $A/sec/
  python3 - "$S/devices.yaml" "$A/sec/devices.yaml" <<'PY2'
import sys,re
src,dst=sys.argv[1:3]; out=[]
for l in open(src):
    if 'ue2.ip' in l: continue
    out.append(re.sub(r'dnn: *"?[A-Za-z0-9.-]+"?', 'dnn: internet', l))
open(dst,'w').write(''.join(out))
PY2
  chmod 600 $A/sec/devices.yaml
  ip netns exec ue1 ip -4 -o addr show oaitun_ue1 | awk '{print $4}' | cut -d/ -f1 > $A/sec/ue1.ip; chmod 600 $A/sec/ue1.ip
  chown -R $U $A; chmod 700 $A/sec $A/data; chmod 755 $A/events
  docker rm -f qod-adapter >/dev/null 2>&1
  docker run -d --name qod-adapter --network host --user $U --cap-drop ALL --cap-add NET_RAW --read-only --tmpfs /tmp \
    -v $A/sec:/secrets:ro -v $A/data:/data -v $A/events:/export lintas5g/qod-adapter:0.1.1 >/dev/null
  for i in $(seq 30); do curl -s -m1 http://127.0.0.1:8080/healthz >/dev/null 2>&1 && break; sleep 0.5; done
  curl -s http://127.0.0.1:8080/healthz | tee -a $L/up.log; echo
}
backend(){
  D=/opt/booster/backend; [ -d $D ] || tar -C /opt/booster -xzf /opt/booster/backend.tar.gz
  cd $D; [ -x .venv/bin/python ] || { apt-get install -y python3-venv >/dev/null 2>&1; python3 -m venv .venv && .venv/bin/pip -q install -r requirements.txt; }
  [ -f /root/booster-appkey ] || ( umask 077; openssl rand -hex 16 > /root/booster-appkey )
  mkdir -p /var/log/lab5g/booster/backend-data
  ( umask 077; cat > $D/.env <<ENV
ADAPTER_BASE_URL=http://127.0.0.1:8080
ADAPTER_TLS_VERIFY=true
QOD_CLIENT_ID=booster
QOD_CLIENT_SECRET_FILE=$S/booster.secret
QOD_SCOPES="quality-on-demand:sessions:create quality-on-demand:sessions:read quality-on-demand:sessions:update quality-on-demand:sessions:delete quality-on-demand:sessions:retrieve-by-device qos-profiles:read"
BACKEND_PUBLIC_URL=http://10.99.9.20:8090
APP_KEYS=emu1:$(cat /root/booster-appkey)
QOD_FLOW_PROTOCOL_FORWARD=on
TOKEN_MODE=passthrough
DATA_DIR=/var/log/lab5g/booster/backend-data
LISTEN_HOST=0.0.0.0
LISTEN_PORT=8090
ENV
  )
  systemctl stop lab5g-booster-backend 2>/dev/null; systemctl reset-failed lab5g-booster-backend 2>/dev/null
  systemd-run --unit=lab5g-booster-backend --working-directory=$D -p StandardOutput=append:/var/log/lab5g/booster/backend.log \
    -p StandardError=append:/var/log/lab5g/booster/backend.log bash $D/run.sh >/dev/null
  sleep 4; ss -ltnp | grep -E ':8090 ' | awk '{print "backend listen", $4}' | tee -a $L/up.log
}
zeek(){ cd /opt/lab5g/sesi-d && MGLT_D443=1 bash ./pktlat2-taps-oai.sh start 2>&1 | tail -3 | tee -a $L/up.log; sleep 3; systemctl is-active lab5g-pktlat2 lab5g-pktlat-mirror | tr '\n' ' ' | tee -a $L/up.log; echo; }
case "$step" in
  all) images; core; ran; net; adapter; backend; zeek;;
  *) $step;;
esac
