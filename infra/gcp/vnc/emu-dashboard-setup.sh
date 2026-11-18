#!/bin/bash
# vm-emu (root), idempotent: Caddy on 127.0.0.1:6081 (basic auth user `lab`) serving the side-by-side page at /
# (noVNC left + lab dashboard right), /api/emu.json (local collector), /api/core.json (vm-core-ran collector over the
# internal network, tcp 8099), and everything else proxied to noVNC 127.0.0.1:6080 (incl. /websockify).
# Reached via IAP SSH tunnel (-L 6081:localhost:6081) or, opt-in, via the Cloudflare Quick Tunnel.
# usage: CORE_IP=<internal ip vm-core-ran> bash emu-dashboard-setup.sh
set -e
export DEBIAN_FRONTEND=noninteractive
V=/opt/lab5g/vnc; CORE_IP=${CORE_IP:?CORE_IP wajib}; COST_PER_HOUR=${COST_PER_HOUR:-0.80}
if ! command -v caddy >/dev/null; then
  apt-get install -y -q debian-keyring debian-archive-keyring apt-transport-https curl gnupg >/dev/null
  curl -1sLf https://dl.cloudsmith.io/public/caddy/stable/gpg.key | gpg --dearmor --yes -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
  curl -1sLf https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt > /etc/apt/sources.list.d/caddy-stable.list
  apt-get update -q >/dev/null; apt-get install -y -q caddy >/dev/null
fi
# basic auth password: generated on the VM, never printed
umask 077; P=/opt/lab5g/novnc-web-password.txt
[ -s $P ] || tr -dc 'A-Za-z0-9' </dev/urandom | head -c 24 > $P
chown root:root $P; chmod 0600 $P
H=$(caddy hash-password < $P)
umask 022
install -d -m 0755 /opt/lab5g/dash /opt/lab5g/dash/api
install -m 0644 $V/lab.html /opt/lab5g/dash/lab.html
cat > /etc/caddy/Caddyfile <<C
{
	admin localhost:2019
	auto_https off
}
http://:6081 {
	bind 127.0.0.1
	basic_auth {
		lab $H
	}
	handle / {
		rewrite * /lab.html
		file_server {
			root /opt/lab5g/dash
		}
	}
	handle /lab.html {
		file_server {
			root /opt/lab5g/dash
		}
	}
	handle /api/emu.json {
		header Cache-Control no-store
		file_server {
			root /opt/lab5g/dash
		}
	}
	handle /api/core.json {
		header Cache-Control no-store
		rewrite * /status.json
		reverse_proxy $CORE_IP:8099
	}
	handle {
		reverse_proxy 127.0.0.1:6080
	}
}
C
chown root:caddy /etc/caddy/Caddyfile; chmod 0640 /etc/caddy/Caddyfile
caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile >/dev/null 2>&1 && echo caddyfile_valid
systemctl enable -q caddy; systemctl restart caddy
# emu collector (persistent, survives reboot)
install -m 0755 $V/emu-collector.py /opt/lab5g/emu-collector.py
cat > /etc/systemd/system/lab5g-emu-collector.service <<U
[Unit]
Description=Lab5G dashboard collector (vm-emu)
After=docker.service
[Service]
Environment=INTERVAL=2 PROXY_EVERY=10 CORE_PROXY=http://$CORE_IP:18080 COST_PER_HOUR=$COST_PER_HOUR EMU_EGRESS=${EMU_EGRESS:-ue-l3}
ExecStart=/usr/bin/python3 /opt/lab5g/emu-collector.py
Restart=always
RestartSec=3
[Install]
WantedBy=multi-user.target
U
systemctl daemon-reload; systemctl enable -q lab5g-emu-collector; systemctl restart lab5g-emu-collector
systemctl is-active caddy lab5g-emu-collector | tr '\n' ' '; echo
