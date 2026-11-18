#!/usr/bin/env bash
# Trafik latar untuk kontensi: matriks beban x pengulangan. Hasil JSON per run di results/qod/<run>/.
# Pakai: ./iperf-matrix.sh <label: before|after|after-delete> [repeat=5] [durasi_s=60]
set -euo pipefail
cd "$(dirname "$0")"; [ -f .env ] && set -a && . ./.env && set +a
LABEL="${1:?label}"; REP="${2:-5}"; DUR="${3:-60}"; SRV="${IPERF_SERVER:?set IPERF_SERVER}"
OUT="../../results/qod/$(date +%Y%m%d-%H%M%S)-$LABEL"; mkdir -p "$OUT"
for load in 10M 18M 25M; do            # di bawah, dekat, dan di atas bottleneck 20 Mbit
  for i in $(seq 1 "$REP"); do
    echo "load=$load run=$i"
    iperf3 -c "$SRV" -u -b "$load" -t "$DUR" -R -J > "$OUT/iperf-$load-$i.json" &
    IP=$!
    # Probe QUIC terukur berjalan paralel (77-ue-quic-gen.py / app); id run dipakai Zeek via skew.cfg run_id
    sleep "$DUR"; wait "$IP" || true
  done
done
echo "hasil: $OUT"
