#!/bin/bash
# Zeek paralel (1 core, nice 10) + tcpdump ring buffer + mpstat.
# Sesi C (EPC): S1AP (SCTP), S1-U (GTP-U 2152), S11/S5 (GTPv2 2123), Sxa/Sxb (PFCP 8805), Diameter Gx/Rx/S6a (3868) di lo;
# SGi di ogstun. Zeek+dumpcap di-pin ke CPU terakhir, nice 10. Usage: core-zeek.sh start|stop|status
L=/var/log/lab5g; Z=/opt/zeek/bin/zeek
CPU=${ZEEK_CPU:-$(( $(nproc) - 1 ))}
case "$1" in
start)
  mkdir -p $L/zeek/lo $L/zeek/ogstun $L/pcap
  # Sesi C: BPF valid per interface. lo: hanya S1-U (hop eNB 127.0.1.1 <-> SGW-U) + control-plane;
  # IQ ZMQ (tcp 2000/2001) dan hop S5-U tidak ikut (sumber artefak capture_loss 53-65% di Sesi B).
  BPF_lo="(udp port 2152 and host 127.0.1.1) or sctp or udp port 2123 or udp port 8805 or tcp port 3868"
  BPF_ogstun="ip"
  for ifc in lo ogstun; do
    v=BPF_$ifc
    systemctl stop lab5g-zeek-$ifc 2>/dev/null; systemctl reset-failed lab5g-zeek-$ifc 2>/dev/null
    systemd-run --unit=lab5g-zeek-$ifc --working-directory=$L/zeek/$ifc \
      taskset -c $CPU nice -n 10 $Z -C -i $ifc -f "${!v}" local policy/misc/capture-loss policy/misc/stats \
      "CaptureLoss::watch_interval=1min" "Log::default_rotation_interval=0secs"
  done
  systemctl stop lab5g-pcap-lo lab5g-pcap-cp lab5g-pcap-n6 lab5g-mpstat 2>/dev/null
  systemctl reset-failed lab5g-pcap-lo lab5g-pcap-cp lab5g-pcap-n6 lab5g-mpstat 2>/dev/null
  # dumpcap (bukan tcpdump): profil AppArmor tcpdump menolak nama file ring buffer (*.pcap0).
  systemd-run --unit=lab5g-pcap-lo taskset -c $CPU nice -n 10 dumpcap -q -i lo -s 256 -b filesize:200000 -b files:10 -w $L/pcap/s1-s11-gx-rx.pcapng \
    -f 'sctp or udp port 2152 or udp port 2123 or udp port 8805 or tcp port 3868'
  # control-plane terpisah, full snaplen (Diameter RAR/AAR > 256 B)
  systemd-run --unit=lab5g-pcap-cp taskset -c $CPU nice -n 10 dumpcap -q -i lo -b filesize:50000 -b files:5 -w $L/pcap/cp-s1ap-gtpc-diam.pcapng \
    -f 'sctp or udp port 2123 or udp port 8805 or tcp port 3868'
  systemd-run --unit=lab5g-pcap-n6 taskset -c $CPU nice -n 10 dumpcap -q -i ogstun -s 128 -b filesize:100000 -b files:5 -w $L/pcap/n6.pcapng
  systemd-run --unit=lab5g-mpstat bash -c "mpstat -P ALL 5 > $L/mpstat.log"
  sleep 3; $0 status ;;
stop)
  systemctl stop lab5g-zeek-lo lab5g-zeek-ogstun lab5g-pcap-lo lab5g-pcap-cp lab5g-pcap-n6 lab5g-mpstat 2>/dev/null
  sleep 2; ls -la $L/zeek/* $L/pcap ;;
status)
  for u in lab5g-zeek-lo lab5g-zeek-ogstun lab5g-pcap-lo lab5g-pcap-cp lab5g-pcap-n6 lab5g-mpstat; do printf "%-20s %s\n" $u "$(systemctl is-active $u)"; done
  pgrep -a zeek | head; for p in $(pgrep -x zeek); do echo "pid $p affinity: $(taskset -cp $p | awk -F: '{print $2}') nice: $(ps -o ni= -p $p)"; done
  for ifc in lo ogstun; do echo "== capture_loss $ifc =="; cat $L/zeek/$ifc/capture_loss.log 2>/dev/null | grep -v '^#' | tail -5; done ;;
esac
