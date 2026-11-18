#!/bin/bash
# OPT-IN: public URL noVNC: Cloudflare Quick Tunnel -> Caddy basic auth (127.0.0.1:6081) -> noVNC 127.0.0.1:6080.
# Tanpa firewall rule / IP publik baru. Password dibuat di VM, tidak pernah dicetak.
set -e
export DEBIAN_FRONTEND=noninteractive
# 1. caddy (repo apt resmi Caddy di Cloudsmith)
if ! command -v caddy >/dev/null; then
  apt-get install -y -q debian-keyring debian-archive-keyring apt-transport-https curl gnupg >/dev/null
  curl -1sLf https://dl.cloudsmith.io/public/caddy/stable/gpg.key | gpg --dearmor --yes -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
  curl -1sLf https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt > /etc/apt/sources.list.d/caddy-stable.list
  apt-get update -q >/dev/null; apt-get install -y -q caddy >/dev/null
fi
# 2. cloudflared (repo apt resmi Cloudflare)
if ! command -v cloudflared >/dev/null; then
  mkdir -p --mode=0755 /usr/share/keyrings
  curl -fsSL https://pkg.cloudflare.com/cloudflare-main.gpg -o /usr/share/keyrings/cloudflare-main.gpg
  echo "deb [signed-by=/usr/share/keyrings/cloudflare-main.gpg] https://pkg.cloudflare.com/cloudflared $(. /etc/os-release; echo $VERSION_CODENAME) main" > /etc/apt/sources.list.d/cloudflared.list
  apt-get update -q >/dev/null; apt-get install -y -q cloudflared >/dev/null
fi
caddy version | cut -c1-40; cloudflared --version | head -1
# 3. password basic auth (user lab)
umask 077; P=/opt/lab5g/novnc-web-password.txt
[ -s $P ] || tr -dc 'A-Za-z0-9' </dev/urandom | head -c 24 > $P
chown root:root $P; chmod 0600 $P
H=$(caddy hash-password < $P)   # via stdin, tidak muncul di argv
umask 022
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
	reverse_proxy 127.0.0.1:6080
}
C
chown root:caddy /etc/caddy/Caddyfile; chmod 0640 /etc/caddy/Caddyfile
caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile >/dev/null 2>&1 && echo caddyfile_valid
systemctl enable -q caddy; systemctl restart caddy
# 4. cloudflared quick tunnel sebagai service
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
ls -l $P | awk '{print $1,$3,$4,$NF}'
