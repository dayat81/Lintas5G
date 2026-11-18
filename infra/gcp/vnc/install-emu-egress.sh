#!/bin/bash
# vm-emu (root): persist the egress policy as a systemd unit (re-applied on boot and whenever docker restarts).
MODE=${EMU_EGRESS:-ue-l3}
install -m 0755 /opt/lab5g/vnc/emu-egress-policy.sh /opt/lab5g/emu-egress-policy.sh
cat > /etc/systemd/system/lab5g-emu-egress.service <<U
[Unit]
Description=Lab5G emulator egress policy ($MODE)
After=docker.service
PartOf=docker.service
[Service]
Type=oneshot
RemainAfterExit=yes
Environment=EMU_EGRESS=$MODE CORE_IP=${CORE_IP:-}
ExecStart=/opt/lab5g/emu-egress-policy.sh
[Install]
WantedBy=multi-user.target docker.service
U
# self-heal for the GRE routes (link flap drops table-201 routes) every 30 s; ue-l3 only
cat > /etc/systemd/system/lab5g-emu-gre.service <<U
[Unit]
Description=Lab5G emulator GRE route self-heal
[Service]
Type=oneshot
Environment=EMU_EGRESS=$MODE CORE_IP=${CORE_IP:-} ROUTES_ONLY=1
ExecStart=/opt/lab5g/emu-egress-policy.sh
U
cat > /etc/systemd/system/lab5g-emu-gre.timer <<U
[Unit]
Description=Lab5G emulator GRE route self-heal (30 s)
[Timer]
OnBootSec=60
OnUnitActiveSec=30
[Install]
WantedBy=timers.target
U
systemctl daemon-reload; systemctl enable -q lab5g-emu-egress; systemctl restart lab5g-emu-egress
if [ "$MODE" = ue-l3 ]; then systemctl enable -q --now lab5g-emu-gre.timer; else systemctl disable --now lab5g-emu-gre.timer >/dev/null 2>&1 || true; fi
iptables -S LAB5G-EMU 2>/dev/null | head -8; ip rule show | grep -E "lookup (201|main)" | head -5; ip -br addr show gre-core 2>/dev/null
