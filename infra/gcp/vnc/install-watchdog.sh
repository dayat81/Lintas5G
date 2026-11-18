#!/bin/bash
install -m 0755 ${1:-/tmp/ue-watchdog.sh} /opt/lab5g/ue-watchdog.sh
cat > /etc/systemd/system/lab5g-watchdog.service <<U
[Unit]
Description=Lab5G UE re-attach watchdog
[Service]
Type=oneshot
ExecStart=/opt/lab5g/ue-watchdog.sh
U
cat > /etc/systemd/system/lab5g-watchdog.timer <<U
[Unit]
Description=Lab5G UE watchdog tiap 60 s
[Timer]
OnBootSec=120
OnUnitActiveSec=60
AccuracySec=5
[Install]
WantedBy=timers.target
U
systemctl daemon-reload; systemctl enable --now lab5g-watchdog.timer
systemctl list-timers lab5g-watchdog.timer --no-pager | head -3
