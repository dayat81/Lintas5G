#!/bin/bash
# ran_mode=sa-oai: render OAI v3.0.0 gNB (n78 TDD 40 MHz, default 2x2 + 256QAM) + N nrUE configs (1..3) and provision
# subscribers 2..N. Pair 1 uses /root/lab5g-sub.env from sa-config.sh; 2..N reuse nr-pairs-config.sh (same IMSI/K/OPC
# scheme + SA_STATIC_PCC opt-in). Upstream base config + UE capability files are fetched at the pinned tag and checked
# against sha256 (not vendored). Usage: oai-config.sh <N>
# env: OAI_DNN=internet OAI_MIMO=2|1 OUT_DIR=/etc/lab5g/sa/oai OAI_SRC_DIR=<dir with the 3 upstream files> (offline) DRY_RUN=1 (fake secrets)
# Secrets: ue<i>.conf 0600, never printed.
set -euo pipefail
N=${1:-1}; HERE=$(cd "$(dirname "$0")" && pwd); OUT=${OUT_DIR:-/etc/lab5g/sa/oai}; MIMO=${OAI_MIMO:-2}; DRY=${DRY_RUN:-0}
SUBENV=${SUBENV:-/root/lab5g-sub.env}; PAIRENV=${PAIRENV:-/root/lab5g-pairs.env}
case "$N" in 1|2|3) ;; *) echo "N must be 1..3 for sa-oai" >&2; exit 2;; esac
OAI_TAG=v3.0.0; RAW=https://raw.githubusercontent.com/OPENAIRINTERFACE/openairinterface5g/$OAI_TAG
SRC=${OAI_SRC_DIR:-/var/lib/lab5g/oai-upstream}; mkdir -p "$SRC" "$OUT"
# file  upstream-path  sha256 (OAI v3.0.0, verified offline 19 Nov 2026)
while read -r f p h; do
  if [ ! -s "$SRC/$f" ] || [ "$(sha256sum "$SRC/$f" | awk '{print $1}')" != "$h" ]; then
    [ "$DRY" = 1 ] && { echo "+ fetch $p"; continue; }
    curl -fsSL --retry 3 "$RAW/$p" -o "$SRC/$f.tmp" && mv "$SRC/$f.tmp" "$SRC/$f"
  fi
  [ "$DRY" = 1 ] || [ "$(sha256sum "$SRC/$f" | awk '{print $1}')" = "$h" ] || { echo "sha256 mismatch: $f" >&2; exit 3; }
done <<'LIST'
gnb.sa.band78.106prb.rfsim.conf ci-scripts/conf_files/gnb.sa.band78.106prb.rfsim.conf 20d779c729654807cd28ddfb00f1b63a37b18b3907f9cee7b67b403f7f31cfa6
uecap_ports1.xml targets/PROJECTS/GENERIC-NR-5GC/CONF/uecap_ports1.xml c5193baa05d045e4519a9cf52dfcd1056df124bc3aff706e80312fb9d443998a
uecap_ports2.xml targets/PROJECTS/GENERIC-NR-5GC/CONF/uecap_ports2.xml a2202884ceeb8fe394e2efc618df846bcfb9e82f14e66665cfee7382a8f844fe
LIST
install -d -m 0755 "$OUT/uecap"; [ -s "$SRC/uecap_ports2.xml" ] && cp "$SRC"/uecap_ports*.xml "$OUT/uecap/"
[ "$DRY" = 1 ] && [ ! -s "$SRC/gnb.sa.band78.106prb.rfsim.conf" ] && { echo "+ render gnb.conf mimo=$MIMO; ue1..ue$N.conf"; exit 0; }
python3 "$HERE/oai_conf.py" gnb --base "$SRC/gnb.sa.band78.106prb.rfsim.conf" --out "$OUT/gnb.conf" --mimo "$MIMO"
# subscribers 2..N (and netns/lo aliases) via the srsRAN multi-pair renderer; its srsRAN files are unused in this mode
if [ "$N" -gt 1 ]; then
  PO=/etc/lab5g/sa; [ "$DRY" = 1 ] && PO=$OUT/pairs
  OUT_DIR=$PO DRY_RUN=$DRY SUBENV=$SUBENV PAIRENV=$PAIRENV bash "$HERE/nr-pairs-config.sh" "$N" | sed -E 's/[0-9]{15}/IMSI_REDACTED/g'
fi
# shellcheck disable=SC2034
if [ "$DRY" = 1 ]; then
  IMSI1=00101$(printf %010d "$(( $(od -An -N4 -tu4 /dev/urandom) % 9000000000 ))"); KEY1=$(openssl rand -hex 16); OPC1=$(openssl rand -hex 16)  # DRY: random dummy, never fixed
  for i in 2 3; do eval "IMSI$i=${IMSI1%?}$i KEY$i=$KEY1 OPC$i=$OPC1"; done
else
  # shellcheck disable=SC1090,SC2034
  . "$SUBENV"; IMSI1=$IMSI; KEY1=$KEY; OPC1=$OPC
  # shellcheck disable=SC1090
  [ "$N" -gt 1 ] && . "$PAIRENV"
fi
for i in $(seq 1 "$N"); do
  eval "IM=\$IMSI$i; K=\$KEY$i; O=\$OPC$i"
  IMSI=$IM K=$K OPC=$O python3 "$HERE/oai_conf.py" ue --out "$OUT/ue$i.conf" --dnn "${OAI_DNN:-internet}" >/dev/null
done
echo "OAI_CONFIG_DONE ues=$N mimo=$MIMO base=$OAI_TAG"
