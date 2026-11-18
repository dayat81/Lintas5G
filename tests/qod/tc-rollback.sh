#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"; [ -f .env ] && set -a && . ./.env && set +a
DEV="${TC_DEV:?set TC_DEV}"
tc qdisc del dev "$DEV" root 2>/dev/null || true
tc qdisc show dev "$DEV"
echo "tc root di $DEV dihapus"
