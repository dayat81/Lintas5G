#!/usr/bin/env bash
# Checklist test run hari pertama lab 5G latency PoC di GCP.
# Skrip ini tidak mendeploy Terraform dan tidak menyentuh lab on-prem.
# Jalankan dari laptop yang sudah punya gcloud, setelah terraform apply.
# Stack aplikasi dijalankan di VM dengan skrip infra/gcp/day1/ (sebagai root).
set -euo pipefail

PROJECT="${PROJECT:-}"
ZONE="${ZONE:-asia-southeast2-a}"
CORE="vm-core-ran"
EMU="vm-emu"
OBS="vm-obs"
# auto = cek apakah vm-obs ada. Hari 1 memakai enable_obs=false.
ENABLE_OBS="${ENABLE_OBS:-auto}"

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

if [[ "${ENABLE_OBS}" == "auto" ]]; then
  if gcloud compute instances describe "${OBS}" --project="${PROJECT}" --zone="${ZONE}" >/dev/null 2>&1; then
    ENABLE_OBS=true
  else
    ENABLE_OBS=false
  fi
fi

hdr "1. VM dan bootstrap (Docker + chrony)"
HOSTS=("${CORE}" "${EMU}")
if [[ "${ENABLE_OBS}" == "true" ]]; then
  HOSTS+=("${OBS}")
else
  skip "vm-obs tidak dicek (enable_obs=false, profil 12 vCPU)"
fi
for h in "${HOSTS[@]}"; do
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

hdr "3. Deploy stack Hari 1 (manual, sebagai root di VM)"
cat <<'TXT'
  Salin infra/gcp/day1/ ke vm-core-ran dan vm-emu, lalu jalankan sebagai root.

  vm-core-ran, urutan:
    1. core-install.sh
       Open5GS 2.8.0 EPC (PPA) + MongoDB di 127.0.0.1.
    2. core-build-srsran.sh
       srsRAN_4G release_23_11 dari source, -DENABLE_ZEROMQ=ON.
       Paket PPA tidak membawa plugin ZMQ.
    3. core-config.sh
       PLMN 001/01. TAC eNB di rr.conf = 0x0001; TAC MME harus sama (0x0001).
       Subscriber diisi via mongosh. IMSI, KEY, dan OPC acak saat runtime,
       hanya di /root/lab5g-sub.env (0600). Jangan salin file itu ke repo.
    4. core-run.sh
       srsenb + srsue (ZMQ), netns ue1.
    5. core-ping.sh
       Pasang default route netns UE secara manual:
         ip netns exec ue1 ip route replace default via 10.45.0.1 dev tun_srsue
       core-config.sh dan core-run.sh tidak memasang route ini.
    6. core-iperf.sh lalu core-iperf-dl.sh
    7. core-proxy.sh
       Default sejak 18 Nov (sudah dites): gost v3 + veth/DNAT + DNS cache.
       Trafik emulator keluar lewat tun_srsue.
       Fallback Hari 1: core-proxy-tinyproxy.sh (tinyproxy + socat).

  vm-emu, urutan:
    1. emu-start.sh
    2. emu-baseline.sh
    3. emu-proxy-test.sh
       http_proxy global ke vm-core-ran:18080.

  Jika enable_obs=true, observability/ (Zeek, Vector, ClickHouse, Grafana)
  tetap langkah terpisah dan tidak bagian dari lulus Hari 1 di atas.
TXT
info "Langkah ini sadar manual; checklist tidak menginstal stack aplikasi."

hdr "4. Kriteria sukses: UE attach"
info "core-run.sh: log MME attach/session, dan tun_srsue di netns ue1 punya alamat 10.45.0.0/16."
info "PLMN harus 001/01 dan TAC eNB serta MME harus 0x0001."
echo "    gcloud compute ssh ${CORE} --zone=${ZONE} --tunnel-through-iap --command='systemctl is-active lab5g-enb lab5g-ue'"

hdr "5. Kriteria sukses: ping dan route netns UE"
info "Setelah core-ping.sh memasang default route manual:"
info "  ping UE ke UPF (10.45.0.1): rata-rata 30,2 ms, 100 paket, 0% loss (Hari 1)."
info "  ping UE ke 8.8.8.8: rata-rata 30,6 ms, 100 paket, 0% loss (Hari 1)."
info "Keepalive ping dari netns ue1 harus tetap hidup."

hdr "6. Kriteria sukses: iperf dan jalur internet UE"
info "iperf Hari 1: UL 18,9 Mbit/s, DL 30,8 Mbit/s (TCP 10 dtk, UE <-> UPF)."
info "Internet emulator lewat UE terbukti dari pcap ogstun (bukan hanya NAT host)."
info "TTFB HTTP Hari 1: sekitar 190 ms lewat UE, sekitar 39 ms langsung."
info "CPU steal 0%. Log ZMQ tanpa late/underflow."

hdr "7. Zeek dan Grafana (hanya jika enable_obs=true)"
if [[ "${ENABLE_OBS}" == "true" ]]; then
  info "Zeek di ${CORE} harus melihat flow S1-U/SGi, bukan hanya trafik manajemen."
  info "Grafana lewat IAP, lalu http://127.0.0.1:3000 :"
  echo "    gcloud compute start-iap-tunnel ${OBS} 3000 --local-host-port=localhost:3000 --project=${PROJECT} --zone=${ZONE}"
else
  skip "vm-obs tidak ada pada profil Hari 1; Zeek/Grafana tidak wajib untuk lulus attach."
fi

hdr "8. USULAN (bukan kriteria Hari 1): backhaul MPLS"
info "enable_mpls default false. Jangan jalankan topologi lama di dalam vm-core-ran."
info "Jika enable_mpls=true: mpls-backhaul.sh di vm-mpls, lalu mpls-ce-tunnels.sh di vm-core-ran."
info "Uji 17 Nov: modul dan GRE PASS. L3VPN e2e FAIL (LDP neighbor tidak terbentuk)."

hdr "9. Akses VNC emulator"
info "VNC bind ke loopback. start-iap-tunnel tidak menjangkaunya."
echo "    gcloud compute ssh ${EMU} --project=${PROJECT} --zone=${ZONE} --tunnel-through-iap -- -L 5900:127.0.0.1:5900"
info "Lalu buka klien VNC ke localhost:5900. noVNC memakai -L 6080:127.0.0.1:6080."

hdr "Ringkasan kriteria sukses test run"
cat <<'CRIT'
  [ ] UE attach (PLMN 001/01, TAC eNB dan MME 0x0001, IP PDN di tun_srsue)
  [ ] Default route netns UE dipasang manual (via 10.45.0.1 dev tun_srsue)
  [ ] Ping UE ke UPF dan ke 8.8.8.8, 0% loss
  [ ] iperf UL/DL terukur
  [ ] Proxy gost (atau fallback tinyproxy) di netns UE; pcap ogstun menunjukkan internet emulator
  [ ] CPU steal 0%, ZMQ tanpa late/underflow
  [ ] (hanya enable_obs) Zeek mencatat flow dan Grafana menampilkan run
  [ ] (opsional MPLS) jangan diharapkan L3VPN e2e; LDP neighbor masih known issue
CRIT

info "Skrip ini adalah checklist, bukan orkestrator. Tandai lulus secara manual."
