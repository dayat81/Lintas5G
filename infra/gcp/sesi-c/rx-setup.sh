#!/bin/bash
# Daftarkan AF (af.localdomain) sebagai peer Rx di freeDiameter PCRF Open5GS (listen 127.0.0.9:3868), lalu restart PCRF.
# PCRF menerima CER masuk dari peer terdaftar; ConnectTo dummy (127.0.0.1:3870, tidak listen) hanya agar peer dikenal.
F=/etc/freeDiameter/pcrf.conf
grep -q af.localdomain $F || echo 'ConnectPeer = "af.localdomain" { ConnectTo = "127.0.0.1"; No_TLS; Port = 3870; };' >> $F
grep ConnectPeer $F
systemctl restart open5gs-pcrfd; sleep 4; systemctl is-active open5gs-pcrfd
ss -ltnp | grep 3868
