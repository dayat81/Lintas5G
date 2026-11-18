#!/bin/bash
# Watchdog UE (sesi VNC): cek tiap 60 s lewat systemd timer. UE tidak boleh idle / link ZMQ putus -> attach ulang.
exec 9>/run/lab5g-watchdog.lock; flock -n 9 || exit 0
# do not interfere while the boot-time bring-up is still running
[ "$(systemctl is-active lab5g-gui-core 2>/dev/null)" = activating ] && exit 0
L=/var/log/lab5g/watchdog.log; S=/opt/lab5g/sesi-c; N="ip netns exec ue1"
ts(){ TZ=Asia/Jakarta date '+%F %T WIB'; }
ok=1
for u in lab5g-enb lab5g-ue lab5g-keepalive; do systemctl is-active -q $u || { echo "$(ts) $u tidak aktif" >>$L; ok=0; }; done
if [ $ok = 1 ]; then
  $N ip -4 -br a show tun_srsue 2>/dev/null | grep -q 10.45 || { echo "$(ts) tun_srsue tanpa IP" >>$L; ok=0; }
fi
if [ $ok = 1 ]; then
  $N ping -c 3 -W 2 -i 0.5 10.45.0.1 >/dev/null 2>&1 || $N ping -c 3 -W 2 -i 0.5 8.8.8.8 >/dev/null 2>&1 || { echo "$(ts) ping UE gagal" >>$L; ok=0; }
fi
if [ $ok = 0 ]; then
  echo "$(ts) REATTACH mulai" >>$L
  bash $S/core-run.sh 2>&1 | grep -E "Attach complete|tun_srsue|10\.45" | sed -E 's/[0-9]{15}/IMSI_REDACTED/g' | tail -3 >>$L
  $N ip -4 -br a show tun_srsue >>$L 2>&1
  echo "$(ts) REATTACH selesai" >>$L
fi
# proxy gost (emulator via UE) harus hidup
if ! systemctl is-active -q lab5g-gost-ue; then echo "$(ts) gost mati -> core-proxy.sh" >>$L; P=/opt/lab5g/vnc/core-proxy-gui.sh; [ -f $P ] || P=$S/core-proxy.sh; MSS_CLAMP=1360 bash $P >/dev/null 2>&1; fi
# default route netns UE tetap via tun_srsue
$N ip route replace default via 10.45.0.1 dev tun_srsue 2>/dev/null || true
# MTU/MSS fix is idempotent; re-apply every tick (tun_srsue is recreated on every re-attach)
[ -x /opt/lab5g/vnc/gui-net-fix.sh ] && bash /opt/lab5g/vnc/gui-net-fix.sh
# GRE L3 path for the emulator (idempotent; also recovers after veth/netns re-creation)
if [ -f /opt/lab5g/vnc/core-gre-emu.sh ]; then bash /opt/lab5g/vnc/core-gre-emu.sh >/dev/null 2>&1 || echo "$(ts) core-gre-emu gagal" >>$L; fi
exit 0
