#!/usr/bin/env bash
# Uji (a): Npcf_PolicyAuthorization manual ke PCF Open5GS (N5, HTTP/2 cleartext).
# Pakai: ./app-sessions.sh create|get|patch|delete
# Membaca .env (lihat env.example). Location app-session disimpan di .app-session.loc.
set -euo pipefail
cd "$(dirname "$0")"
[ -f .env ] && set -a && . ./.env && set +a
: "${PCF_URL:?set PCF_URL}"
API="$PCF_URL/npcf-policyauthorization/v1/app-sessions"
LOC_FILE=.app-session.loc
render() { envsubst < "$1"; }
case "${1:-}" in
  create)
    render app-session-create.json > /tmp/qod-asc.json
    curl -sS --http2-prior-knowledge -D /tmp/qod-hdr.txt -o /tmp/qod-body.json \
      -H 'Content-Type: application/json' -X POST "$API" --data @/tmp/qod-asc.json -w '%{http_code}\n'
    awk -F': ' 'tolower($1)=="location"{print $2}' /tmp/qod-hdr.txt | tr -d '\r' > "$LOC_FILE"
    echo "location: $(cat "$LOC_FILE")"; cat /tmp/qod-body.json; echo ;;
  get)    curl -sS --http2-prior-knowledge "$(cat "$LOC_FILE")" -w '\n%{http_code}\n' ;;
  patch)
    render app-session-patch.json > /tmp/qod-patch.json
    curl -sS --http2-prior-knowledge -H 'Content-Type: application/merge-patch+json' \
      -X PATCH "$(cat "$LOC_FILE")" --data @/tmp/qod-patch.json -w '\n%{http_code}\n' ;;
  delete)
    curl -sS --http2-prior-knowledge -H 'Content-Type: application/json' \
      -X POST "$(cat "$LOC_FILE")/delete" -d '{}' -w '\n%{http_code}\n' ;;
  *) echo "pakai: $0 create|get|patch|delete" >&2; exit 2 ;;
esac
