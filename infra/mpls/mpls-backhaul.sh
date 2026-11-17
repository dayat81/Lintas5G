#!/usr/bin/env bash
# Rujukan, bukan salinan kedua.
# Skrip kanonis (PE/P di vm-mpls): infra/gcp/startup/mpls-backhaul.sh
# Sisi CE (vm-core-ran):          infra/gcp/startup/mpls-ce-tunnels.sh
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CANON="${HERE}/../gcp/startup/mpls-backhaul.sh"
if [[ ! -f "${CANON}" ]]; then
  echo "skrip kanonis tidak ada: ${CANON}" >&2
  exit 1
fi
exec "${CANON}" "$@"
