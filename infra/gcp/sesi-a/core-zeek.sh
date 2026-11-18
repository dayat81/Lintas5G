#!/bin/bash
# Zeek paralel (1 core, nice 10) + tcpdump ring buffer + mpstat.
# N2 (SCTP/NGAP 38412), N3 (GTP-U 2152), N4 (PFCP 8805), SBI (7777) semuanya di lo (topologi all-in-one);
# N6 di ogstun. Usage: core-zeek.sh start|stop|status
L=/var/log/lab5g; Z=/opt/zeek/bin/zeek
CPU=${ZEEK_CPU:-$(( $(nproc) - 1 ))}
case "$1" in
start)
  mkdir -p $L/zeek/lo $L/zeek/ogstun $L/pcap
  for ifc in lo ogstun; do
    systemctl stop lab5g-zeek-$ifc 2>/dev/null; systemctl reset-failed lab5g-zeek-$ifc 2>/dev/null
    systemd-run --unit=lab5g-zeek-$ifc --working-directory=$L/zeek/$ifc \
      taskset -c $CPU nice -n 10 $Z -C -i $ifc local policy/misc/capture-loss policy/misc/stats \
      "CaptureLoss::watch_interval=1min" "Log::default_rotation_interval=0secs"
  done
  systemctl stop lab5g-pcap-lo lab5g-pcap-n6 lab5g-mpstat 2>/dev/null
  systemctl reset-failed lab5g-pcap-lo lab5g-pcap-n6 lab5g-mpstat 2>/dev/null
  # dumpcap (bukan tcpdump): profil AppArmor tcpdump menolak nama file ring buffer (*.pcap0).
  systemd-run --unit=lab5g-pcap-lo dumpcap -q -i lo -s 256 -b filesize:100000 -b files:10 -w $L/pcap/n2n3n4sbi.pcapng \
    -f 'sctp or udp port 2152 or udp port 8805 or tcp port 7777'
  systemd-run --unit=lab5g-pcap-n6 dumpcap -q -i ogstun -s 128 -b filesize:100000 -b files:5 -w $L/pcap/n6.pcapng
  systemd-run --unit=lab5g-mpstat bash -c "mpstat -P ALL 5 > $L/mpstat.log"
  sleep 3; $0 status ;;
stop)
  systemctl stop lab5g-zeek-lo lab5g-zeek-ogstun lab5g-pcap-lo lab5g-pcap-n6 lab5g-mpstat 2>/dev/null
  sleep 2; ls -la $L/zeek/* $L/pcap ;;
status)
  for u in lab5g-zeek-lo lab5g-zeek-ogstun lab5g-pcap-lo lab5g-pcap-n6 lab5g-mpstat; do printf "%-20s %s\n" $u "$(systemctl is-active $u)"; done
  pgrep -a zeek | head; for p in $(pgrep -x zeek); do echo "pid $p affinity: $(taskset -cp $p | awk -F: '{print $2}') nice: $(ps -o ni= -p $p)"; done
  for ifc in lo ogstun; do echo "== capture_loss $ifc =="; cat $L/zeek/$ifc/capture_loss.log 2>/dev/null | grep -v '^#' | tail -5; done ;;
esac
