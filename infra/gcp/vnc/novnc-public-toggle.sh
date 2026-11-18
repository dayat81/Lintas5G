#!/bin/bash
# usage (di vm-emu, root): novnc-public-toggle.sh off|on|status
case "$1" in
  off) systemctl disable --now lab5g-cloudflared; : > /opt/lab5g/public-url.txt; echo "tunnel OFF (URL lama mati)";;
  on)  systemctl enable --now lab5g-cloudflared; sleep 8; echo "URL baru: $(cat /opt/lab5g/public-url.txt)";;
  *)   systemctl is-active lab5g-cloudflared caddy; cat /opt/lab5g/public-url.txt;;
esac
