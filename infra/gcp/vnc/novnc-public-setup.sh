#!/bin/bash
# OPT-IN public URL: Cloudflare Quick Tunnel -> Caddy basic auth (127.0.0.1:6081: side-by-side page + noVNC).
# Tanpa firewall rule / IP publik baru. Password dibuat di VM, tidak pernah dicetak.
set -e
export DEBIAN_FRONTEND=noninteractive
# Requires emu-dashboard-setup.sh (caddy basic auth on 127.0.0.1:6081) first.
systemctl is-active -q caddy || { echo "caddy belum aktif: jalankan emu-dashboard-setup.sh dulu"; exit 1; }
# cloudflared (repo apt resmi Cloudflare)
if ! command -v cloudflared >/dev/null; then
  mkdir -p --mode=0755 /usr/share/keyrings
  curl -fsSL https://pkg.cloudflare.com/cloudflare-main.gpg -o /usr/share/keyrings/cloudflare-main.gpg
  echo "deb [signed-by=/usr/share/keyrings/cloudflare-main.gpg] https://pkg.cloudflare.com/cloudflared $(. /etc/os-release; echo $VERSION_CODENAME) main" > /etc/apt/sources.list.d/cloudflared.list
  apt-get update -q >/dev/null; apt-get install -y -q cloudflared >/dev/null
fi
cloudflared --version | head -1
# cloudflared quick tunnel sebagai service (Restart=always)
cat > /opt/lab5g/cf-url.sh <<'S'
#!/bin/bash
# tunggu URL trycloudflare di log, tulis ke /opt/lab5g/public-url.txt
for i in $(seq 1 60); do u=$(grep -o 'https://[a-z0-9-]*\.trycloudflare\.com' /var/log/lab5g/cloudflared.log | tail -1); [ -n "$u" ] && break; sleep 1; done
echo "$u" > /opt/lab5g/public-url.txt; chmod 0644 /opt/lab5g/public-url.txt
S
chmod 0755 /opt/lab5g/cf-url.sh; mkdir -p /var/log/lab5g
cat > /etc/systemd/system/lab5g-cloudflared.service <<U
[Unit]
Description=Lab5G Cloudflare Quick Tunnel -> Caddy basic auth -> noVNC
After=network-online.target caddy.service
Wants=network-online.target
[Service]
ExecStartPre=/bin/sh -c ': > /var/log/lab5g/cloudflared.log; : > /opt/lab5g/public-url.txt'
ExecStart=/usr/bin/cloudflared tunnel --no-autoupdate --logfile /var/log/lab5g/cloudflared.log --url http://127.0.0.1:6081
ExecStartPost=/opt/lab5g/cf-url.sh
Restart=always
RestartSec=5
[Install]
WantedBy=multi-user.target
U
systemctl daemon-reload; systemctl enable -q lab5g-cloudflared; systemctl restart lab5g-cloudflared
sleep 3; systemctl is-active caddy lab5g-cloudflared | tr '\n' ' '; echo
echo "PUBLIC_URL=$(cat /opt/lab5g/public-url.txt)"
ss -ltnp | grep -E ':(6081|6080|5900|2019)\b' | awk '{print $4, $6}' | cut -c1-80
