#!/bin/bash
# Sesi B: konfigurasi EPC Open5GS (resep Hari 1) + PCC rule QCI 2 (template Rx VIDEO)
# Konfigurasi EPC Open5GS (PLMN 001/01) + subscriber tes acak + config srsenb/srsue ZMQ.
# KEY/OPC hanya disimpan di /root/lab5g-sub.env (0600) di VM ephemeral; tidak dicetak.
set -e
cd /etc/open5gs
for f in mme.yaml; do sed -i 's/mcc: 999/mcc: 001/g; s/mnc: 70/mnc: 01/g' $f; done
grep -n -A3 "gummei\|tai:" mme.yaml | head -20
systemctl restart open5gs-mmed open5gs-sgwcd open5gs-sgwud open5gs-smfd open5gs-upfd open5gs-hssd open5gs-pcrfd
# SGi NAT: trafik UE (10.45.0.0/16) keluar ens4 -> Cloud NAT
iptables -t nat -C POSTROUTING -s 10.45.0.0/16 ! -o ogstun -j MASQUERADE 2>/dev/null || iptables -t nat -A POSTROUTING -s 10.45.0.0/16 ! -o ogstun -j MASQUERADE
iptables -I FORWARD 1 -i ogstun -j ACCEPT; iptables -I FORWARD 1 -o ogstun -j ACCEPT
umask 077
if [ ! -f /root/lab5g-sub.env ]; then
  MSIN=$(printf "%010d" $(( $(od -An -N4 -tu4 /dev/urandom) % 10000000000 )))
  echo "IMSI=00101${MSIN}" > /root/lab5g-sub.env
  echo "KEY=$(openssl rand -hex 16)" >> /root/lab5g-sub.env
  echo "OPC=$(openssl rand -hex 16)" >> /root/lab5g-sub.env
fi
. /root/lab5g-sub.env
# open5gs-dbctl tidak ada di paket PPA -> insert langsung via mongosh (skema Open5GS 2.7/2.8).
docker exec -e IMSI=$IMSI -e K=$KEY -e OPC=$OPC mongo mongosh --quiet open5gs --eval '
const e=process.env; db.subscribers.deleteMany({});
const amb={downlink:{value:1,unit:3},uplink:{value:1,unit:3}};
const pcc={qos:{index:2,arp:{priority_level:2,pre_emption_capability:1,pre_emption_vulnerability:1},
  mbr:{downlink:{value:20,unit:2},uplink:{value:20,unit:2}},gbr:{downlink:{value:1,unit:2},uplink:{value:1,unit:2}}},flow:[]};
db.subscribers.insertOne({schema_version:1,imsi:e.IMSI,msisdn:[],imeisv:[],mme_host:[],mme_realm:[],purge_flag:[],
 security:{k:e.K,op:null,opc:e.OPC,amf:"8000",sqn:NumberLong(161)},ambr:amb,
 slice:[{sst:1,default_indicator:true,session:[{name:"internet",type:3,ambr:amb,
  qos:{index:9,arp:{priority_level:8,pre_emption_capability:1,pre_emption_vulnerability:1}},pcc_rule:[pcc]}]}],
 access_restriction_data:32,network_access_mode:0,subscriber_status:0,operator_determined_barring:0,subscribed_rau_tau_timer:12,__v:0});
print("SUB_ADDED")' && echo "IMSI=${IMSI:0:5}xxxxxxxxxx"
docker exec mongo mongosh --quiet open5gs --eval 'db.subscribers.countDocuments()'
umask 022
B=/opt/lab5g/srsran/srsRAN_4G
C=/opt/lab5g/srsran/conf; mkdir -p $C
cp $B/srsenb/rr.conf.example $C/rr.conf; cp $B/srsenb/sib.conf.example $C/sib.conf; cp $B/srsenb/rb.conf.example $C/rb.conf
cat > $C/enb.conf <<ENB
[enb]
enb_id = 0x19B
mcc = 001
mnc = 01
mme_addr = 127.0.0.2
gtp_bind_addr = 127.0.1.1
s1c_bind_addr = 127.0.1.1
s1c_bind_port = 0
n_prb = 50
[enb_files]
sib_config = $C/sib.conf
rr_config  = $C/rr.conf
rb_config  = $C/rb.conf
[rf]
tx_gain = 80
rx_gain = 40
device_name = zmq
device_args = fail_on_disconnect=true,tx_port=tcp://*:2000,rx_port=tcp://localhost:2001,id=enb,base_srate=11.52e6
[log]
filename = /var/log/lab5g/enb.log
all_level = warning
[expert]
metrics_csv_enable = true
metrics_csv_filename = /var/log/lab5g/enb_metrics.csv
metrics_period_secs = 1
ENB
sed -i 's/tac = 0x0007/tac = 0x0001/' $C/rr.conf
grep -n "tac\|dl_earfcn" $C/rr.conf | head
umask 077
cat > $C/ue.conf <<UE
[rf]
freq_offset = 0
tx_gain = 80
rx_gain = 40
srate = 11.52e6
nof_antennas = 1
device_name = zmq
device_args = tx_port=tcp://*:2001,rx_port=tcp://localhost:2000,id=ue,base_srate=11.52e6
[rat.eutra]
dl_earfcn = 3350
nof_carriers = 1
[pcap]
enable = none
[log]
all_level = warning
filename = /var/log/lab5g/ue.log
[usim]
mode = soft
algo = milenage
opc  = $OPC
k    = $KEY
imsi = $IMSI
imei = 353490069873319
[nas]
apn = internet
apn_protocol = ipv4
[gw]
netns = ue1
ip_devname = tun_srsue
ip_netmask = 255.255.255.0
[general]
metrics_csv_enable = true
metrics_period_secs = 1
metrics_csv_filename = /var/log/lab5g/ue_metrics.csv
UE
umask 022
mkdir -p /var/log/lab5g
ip netns list | grep -q ue1 || ip netns add ue1
mkdir -p /etc/netns/ue1; echo "nameserver 8.8.8.8" > /etc/netns/ue1/resolv.conf
echo CONFIG_DONE
