#!/bin/bash
# vm-core-ran (root): dashboard collector as a persistent systemd service (survives reboot). Idempotent.
install -m 0755 /opt/lab5g/vnc/core-collector.py /opt/lab5g/core-collector.py
cat > /etc/systemd/system/lab5g-collector.service <<U
[Unit]
Description=Lab5G dashboard collector (status.json on internal IP:8099)
After=network-online.target
Wants=network-online.target
[Service]
Environment=INTERVAL=2 PORT=8099 PROXY_EVERY=10
ExecStart=/usr/bin/python3 /opt/lab5g/core-collector.py
Restart=always
RestartSec=3
[Install]
WantedBy=multi-user.target
U
systemctl daemon-reload; systemctl enable -q lab5g-collector; systemctl restart lab5g-collector
sleep 3; systemctl is-active lab5g-collector
