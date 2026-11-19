#!/bin/bash
# vm-core-ran (root): run run-youtube-qod.sh once per TRANSPORT mode, in sequence, each into its own result dir.
# usage: run-transport-matrix.sh <emu_ip>     env: MODES="auto quic-only tcp-only" REPS=3 DUR=180 GAP=20 PAUSE=60
# Results: $P/matrix/<mode>/{ytqod/,phases.tsv,run.log.part}. $P = /var/log/lab5g/sesi-d.
set -u
. /opt/lab5g/sesi-d/common.sh 2>/dev/null || . "$(cd "$(dirname "$0")" && pwd)/common.sh"
E=${1:?emu_ip}
MODES=${MODES:-auto quic-only tcp-only}
SDIR=$(cd "$(dirname "$0")" && pwd)
EMU_SSH=${EMU_SSH:-ssh -i /root/.ssh/ytqod_ed25519 -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10 root@$E}
export EMU_SSH
mkdir -p "$P/matrix"
for mode in $MODES; do
  log "matrix: mode=$mode start"
  rm -rf "$P/ytqod"; rm -f "$P/phases.tsv"
  RUN_ID="ytqod4-${mode}-$(date +%Y%m%d-%H%M%S)" TRANSPORT=$mode bash "$SDIR/run-youtube-qod.sh" "$E"
  rc=$?
  mkdir -p "$P/matrix/$mode"
  [ -d "$P/ytqod" ] && mv "$P/ytqod" "$P/matrix/$mode/ytqod"
  [ -f "$P/phases.tsv" ] && mv "$P/phases.tsv" "$P/matrix/$mode/phases.tsv"
  log "matrix: mode=$mode done rc=$rc"
  [ "$rc" -eq 3 ] && { echo "$mode rc=$rc ABORT(pktlat2)" >> "$P/matrix/status.txt"; log "matrix: ABORT pktlat2 failed"; break; }
  echo "$mode rc=$rc" >> "$P/matrix/status.txt"
  sleep "${PAUSE:-60}"
done
log "matrix: ALL DONE"
