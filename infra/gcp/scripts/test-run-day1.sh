#!/usr/bin/env bash
# Checklist test run hari pertama lab 5G latency PoC di GCP.
# Skrip ini tidak mendeploy Terraform dan tidak menyentuh lab on-prem.
# Jalankan dari laptop yang sudah punya gcloud, setelah terraform apply.
set -euo pipefail

PROJECT="${PROJECT:-}"
ZONE="${ZONE:-asia-southeast2-a}"
CORE="vm-core-ran"
EMU="vm-emu"
OBS="vm-obs"

if [[ -z "${PROJECT}" ]]; then
  PROJECT="$(gcloud config get-value project 2>/dev/null || true)"
fi

ok()   { printf "  [OK]    %s\n" "$*"; }
fail() { printf "  [FAIL]  %s\n" "$*"; }
skip() { printf "  [SKIP]  %s\n" "$*"; }
info() { printf "  [..]    %s\n" "$*"; }
hdr()  { printf "\n== %s ==\n" "$*"; }

gssh() {
  local host="$1"; shift
  gcloud compute ssh "${host}" \
    --project="${PROJECT}" \
    --zone="${ZONE}" \
    --tunnel-through-iap \
    --command="$*"
}

hdr "Prasyarat lokal"
if ! command -v gcloud >/dev/null 2>&1; then
  fail "gcloud tidak ada di PATH"
  exit 1
fi
ok "gcloud tersedia"
if [[ -z "${PROJECT}" || "${PROJECT}" == "(unset)" ]]; then
  fail "Set PROJECT=... atau gcloud config set project"
  exit 1
fi
ok "project=${PROJECT} zone=${ZONE}"

hdr "1. VM dan bootstrap (Docker + chrony)"
for h in "${CORE}" "${EMU}" "${OBS}"; do
  if gssh "${h}" "test -f /opt/lab5g/.bootstrap-complete && chronyc tracking | head -n 5 && docker info >/dev/null"; then
    ok "${h}: bootstrap, chrony, docker"
  else
    fail "${h}: bootstrap belum siap atau SSH IAP gagal"
  fi
done

hdr "2. Nested KVM di ${EMU}"
if gssh "${EMU}" "test -e /dev/kvm && cat /opt/lab5g/kvm-status"; then
  ok "/dev/kvm ada"
else
  fail "KVM tidak ada — nested virt gagal; jangan lanjutkan tes emulator"
fi

hdr "3. Deploy stack dari artefak PR (manual)"
cat <<'TXT'
  Copikan artefak pipeline latency (observability/ dan tests/latency/ repo ini) ke vm-core-ran:
    - observability/zeek (pktlat2.zeek v2.1) -> vm-core-ran
    - observability/vector/vector-agent.yaml -> vm-core-ran
    - observability/docker-compose.yml (ClickHouse+Grafana+Vector) -> vm-obs
    - tests/latency (generator QUIC + pembanding)
  Lalu naikkan Open5GS 2.8.0 EPC CUPS + srsRAN 4G ZMQ (eNB + UE di netns l5g-ue),
  Zeek tap pada bridge S1-U/SGi, proxy HTTP CONNECT :18080 di netns UE
  (keluar lewat tun_srsue), dan keepalive ping dari UE.
  Di vm-obs: ClickHouse (database poc_latency, bind internal) + Grafana
  (bind 127.0.0.1) + sink Vector :6000.
  Di vm-emu: emulator Android (swiftshader_indirect, hw.keyboard=yes),
  x11vnc bind 127.0.0.1, http_proxy global ke vm-core-ran:18080.
TXT
info "Langkah ini sadar manual; skrip tidak menginstal stack aplikasi."

hdr "4. Kriteria sukses: UE attach"
info "Periksa log MME/AMF atau srsUE: registered / attach accept, IP PDN teralokasi."
info "Contoh (sesuaikan path container):"
echo "    gcloud compute ssh ${CORE} --zone=${ZONE} --tunnel-through-iap --command='sudo docker ps'"

hdr "5. Kriteria sukses: keepalive wajib"
info "Pastikan ping periodik dari netns l5g-ue berjalan (UE tidak boleh idle)."
info "Jika keepalive mati, sesi UE bisa lepas dan flow Zeek berhenti."

hdr "6. Kriteria sukses: Zeek melihat flow"
info "Dari ${CORE}, setelah trafik app (atau curl lewat proxy UE):"
echo "    # file conn.log / pktlat harus memuat flow S1-U (GTP-U) dan/atau SGi"
echo "    # bukan hanya trafik manajemen VM"

hdr "7. Kriteria sukses: latency p50 S1-U"
info "Jalankan generator singkat (mis. 60 dtk) lalu hitung p50 dari pktlat2/ClickHouse."
info "Catat juga skew chrony (tracking) di core, emu, dan obs pada saat run."

hdr "8. Kriteria sukses: Grafana tampil"
info "Buka tunnel lalu http://127.0.0.1:3000 :"
echo "    gcloud compute start-iap-tunnel ${OBS} 3000 --local-host-port=localhost:3000 --project=${PROJECT} --zone=${ZONE}"
info "Dashboard 80–89 harus menampilkan flow run yang baru saja dikirim Vector."

hdr "9. USULAN (opsional hari pertama): backhaul MPLS S1"
info "Tidak wajib untuk kriteria sukses baseline. Jalankan hanya di vm-core-ran."
echo "    sudo /opt/lab5g/scripts/mpls-backhaul.sh setup"
echo "    sudo /opt/lab5g/scripts/mpls-backhaul.sh verify"
info "verify harus menunjukkan LDP neighbor, BGP VPNv4, rute MPLS, ping CE dummy."
info "Lalu cek ulang UE attach + keepalive. Injeksi: netem set p1 delay 20ms"
info "Zeek: tap pe1-ce (ingress eNB) dan pe2-ce (egress SGW), plus S1-U lama."
info "Rollback: sudo /opt/lab5g/scripts/mpls-backhaul.sh rollback"

hdr "10. Akses VNC emulator (opsional untuk tes app)"
echo "    gcloud compute start-iap-tunnel ${EMU} 5900 --local-host-port=localhost:5900 --project=${PROJECT} --zone=${ZONE}"
info "Ketik dari keyboard laptop setelah fokus ke jendela emulator (hw.keyboard=yes)."

hdr "Ringkasan kriteria sukses test run"
cat <<'CRIT'
  [ ] UE attach (IP PDN teralokasi, state registered)
  [ ] Keepalive UE hidup (tidak idle)
  [ ] Zeek mencatat flow dari jalur UE (S1-U dan/atau SGi)
  [ ] Latency p50 S1-U terhitung untuk run_id yang sama
  [ ] Grafana menampilkan dashboard run tersebut
  [ ] (opsional MPLS) verify LDP/VPNv4/ping CE lulus, UE attach tetap OK
  [ ] (opsional MPLS) Zeek melihat flow di pe1-ce dan pe2-ce; p50 terurai per segmen
CRIT

info "Skrip ini adalah checklist, bukan orkestrator. Tandai lulus secara manual."
