#!/usr/bin/env bash
# Uji (c): bottleneck terkontrol di N6/SGi (atau backhaul). HTB 20 Mbit:
#   1:10 prioritas  (DSCP EF 46 / AF41 34)  -> rate 8mbit ceil 20mbit prio 0
#   1:20 best-effort                       -> rate 12mbit ceil 20mbit prio 1, fq_codel
# + netem delay sama di kedua kelas (egress dev). Rollback: tc-rollback.sh
# DSCP ditandai oleh UPF/QER (atau iptables mangle untuk varian manual).
set -euo pipefail
cd "$(dirname "$0")"; [ -f .env ] && set -a && . ./.env && set +a
DEV="${TC_DEV:?set TC_DEV}"; RATE="${TC_RATE:-20mbit}"; DELAY="${TC_DELAY:-10ms}"
[ "$(id -u)" = 0 ] || { echo "jalankan sebagai root" >&2; exit 1; }
tc qdisc del dev "$DEV" root 2>/dev/null || true
tc qdisc add dev "$DEV" root handle 1: htb default 20
tc class add dev "$DEV" parent 1: classid 1:1 htb rate "$RATE" ceil "$RATE"
tc class add dev "$DEV" parent 1:1 classid 1:10 htb rate 8mbit ceil "$RATE" prio 0
tc class add dev "$DEV" parent 1:1 classid 1:20 htb rate 12mbit ceil "$RATE" prio 1
tc qdisc add dev "$DEV" parent 1:10 handle 10: netem delay "$DELAY" limit 1000
tc qdisc add dev "$DEV" parent 1:20 handle 20: netem delay "$DELAY" limit 1000
tc qdisc add dev "$DEV" parent 20:1 handle 21: fq_codel
# Delay dasar sama di kedua kelas; arah sebaliknya (ingress) butuh ifb jika diperlukan.
tc filter add dev "$DEV" parent 1: protocol ip prio 1 u32 match ip dsfield 0xb8 0xfc flowid 1:10   # EF
tc filter add dev "$DEV" parent 1: protocol ip prio 1 u32 match ip dsfield 0x88 0xfc flowid 1:10   # AF41
tc -s qdisc show dev "$DEV"; tc class show dev "$DEV"
