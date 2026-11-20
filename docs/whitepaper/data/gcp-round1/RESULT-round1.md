# Booster E2E di lab GCP: Fase 1 (2026-11-19)

Persetujuan: "A, apply GCP sekarang" (18:04 WIB).
Apply 18:10:49 → destroy selesai 19:10:23 WIB.

## Stack (FAKTA)
- Core: Open5GS 2.8.0-qosrel, overlay terpatch (hash upfd/pcfd cocok dengan overlay).
  - qos_profiles PCF QOS_E/S/M/L(/7) → 5QI 80/2/3/4/7 ditulis skrip provisioning (`booster-up.sh core` → add_qos_profiles), bukan ditambah tangan.
- gNB: OAI `v3.0.0-slice-qosrel3` (mode `sa-oai`). Config slice di-hot-reload.
  - qod_5qi awal 80,4,7,1; setelah steering menjadi **80,4,69,7,1** (log reload qod_5qi_n=4 → 5).
- Adapter CAMARA QoD 0.1.1 (healthz ok). Reflector mode D443 di 192.0.2.20:443/9000/9001.
- Backend booster di core: 0.0.0.0:8090, TOKEN_MODE=passthrough, FLOW_PROTOCOL_FORWARD=on, APP_KEYS emu1.
  - Secret hanya dikirim lewat SSH/IAP ke VM, tidak pernah ke GCS.
- UE nrUE: attach dalam 3 s. Keepalive ping 1/s aktif sepanjang sesi (tidak ada release atau idle).
- Zeek pktlat2 (MGLT_D443) berjalan paralel. Log dan pcap ada di penyimpanan state privat.
- Aplikasi: sha256 APK 4a13017c…d867ce terverifikasi, versi 0.10.2-poc-booster.3.
  - `adb uninstall` dijalankan lebih dulu (paket memang belum ada), lalu install_apk.
  - Peluncuran: probehost/markhost 192.0.2.20, probeport/markport 443; extras BoosterActivity backend/appkey/sni/p99 80/onesession/newattach.
- Beban: iperf3 UDP DL 400 Mbit/s ke UE → diterima ≈89–92 Mbit/s, loss ≈76–78% (sel kongestif).

## Run (FAKTA)
| Run | Isi | Hasil kunci |
|---|---|---|
| r0b-base | tanpa booster, beban dari +35 s | YouTube tidak pernah PLAYING. MGLT idle p50 34,9 / p99 200,8 ms (n=53). Di bawah beban p50 4908,7 / p99 5011,9 ms (n=29) |
| r1-boost | onesession on, durasi 60 s, beban dari +60 s | CREATE terjadi sebelum beban: backend 201 dalam 180 ms, adapter 52 ms, QFI 2 teramati 329 ms setelah API. MGLT di bawah beban + boost p50 969,6 / **p99 1547,5** (n=14) vs beban tanpa boost p50 4802 / **p99 5476** (n=68). YouTube PLAYING sejak ±+29 s, stall_count 0 |
| r2-multi | onesession off | CREATE 201 (backend 18,5 ms, AVAILABLE 37,7 ms). YouTube tidak mulai. Sesi ke-3 (di luar run) mencapai ACTIVE di aplikasi lalu di-DELETE. Tiga sesi per attach di adapter tanpa error |
| r3-apiprio | PCC statis 5QI 69 ARP 1 untuk 192.0.2.20:8090/TCP | gNB "created new DRB 2 for QFI 2 (5QI 69)". Booster `create -> 400 LOCAL_NO` 7 s setelah up. Tidak ada entri create di backend, jadi ini penolakan lokal di aplikasi: flow target YouTube belum ada |
| r3b-apiprio | sama dengan r3, YouTube dibuka 35 s sebelum booster, beban dari +25 s | **CREATE di bawah beban: dilihat aplikasi 1,95 s** (CREATE 592,44 → 201 594,40), di backend 66,4 ms. Adapter AVAILABLE QFI 3 (5QI 4) dalam 11 ms. Trafik 8090 di N3 **QFI 2** (UL 93 / DL 63 paket saat beban). 0 timeout/RST 8090 di logcat. YouTube tetap tidak PLAYING |

Semua run: bad-counts 0 (tidak ada Error Indication, release, atau crash NF).

## Verdict kriteria Fase 1 (FAKTA)
1. **Sel kongestif: LULUS.** Loss 76–78% pada beban 400M; MGLT p99 naik ke ≈5,0–5,5 s.
2. **Booster mendeteksi flow dan memanggil adapter (API saja): LULUS.** CREATE → 201 → AVAILABLE di r1/r2/r3b.
   - Catatan: AS dibatasi 3 IP (reflector + 2 IP CDN), IP lain DROPPED.
3. **p99/stall target turun ≥50%: LULUS untuk flow reflector/MGLT, TIDAK TERBUKTI untuk YouTube.**
   - p99 MGLT 5476 → 1547,5 ms (−72%).
   - YouTube hanya diamati di r1 (stall 0 saat boost). Sebagian besar DL YouTube tetap di QFI 1 (DL 5245 paket QFI 1 vs 55 QFI 2) karena rotasi IP CDN di luar daftar 3 IP. Tidak ada baseline YouTube yang playing di bawah beban, jadi pembanding tidak tersedia.
4. **Tidak ada stall dalam 10 s setelah boost berakhir: LULUS (r1).** Berakhir 786 → tetap PLAYING sampai 882, di bawah beban, stall 0.
5. **QFI ≠ 1 di N3: LULUS.** Reflector:443 di QFI 2 (r1) atau QFI 3 (r3b) saat boost, QFI 1 di luar boost. Bulk selalu di QFI 1.
6. **Loss target ≤5%: TIDAK DIUKUR LANGSUNG.** Tidak ada penghitung loss per flow target. MGLT dan YouTube tidak menunjukkan gap. Ditandai OPEN.
7. **MGLT before/after: LULUS** (angka di atas).
8. **Events JSONL adapter terkumpul: LULUS** (lihat artefak).
9. **Steering "API high prio": SEBAGIAN.**
   - PCC statis 5QI 69 ARP 1 aktif dan persisten lewat provisioning (`api-prio.py`). 69 masuk daftar slice. Trafik 8090 terbukti di QFI 2 di bawah beban, dan CREATE di bawah beban berhasil (1,95 s di aplikasi, 0 timeout).
   - Pembanding "tanpa rule" untuk CREATE di bawah beban tidak diukur. Bukti tidak langsung: tanpa rule (r1/r2) panggilan aplikasi→8090 di bawah beban mengalami SocketTimeoutException, dan POLL macet.

## Biaya dan audit (FAKTA)
- **Biaya:** ≈60 menit × ≈USD 0,82/jam ≈ **USD 0,85** untuk run ini, termasuk ≈6 menit reset core.
  - Kumulatif hari ini ≈ **USD 13,3** (estimasi). Ambang 13 terlewati sekitar 18:52 WIB. Tidak menyentuh batas 15.
- **Destroy:** 168 resource dihancurkan, `terraform state list` = 0.
- **Audit:**
  - Instance hanya VM build (TERMINATED). Disk hanya VM build lain.
  - Network hanya `default`. Router 0, resource-policy 0, image custom 0.
  - Alamat dan firewall hanya milik milik pihak lain yang sudah ada.
  - Penyimpanan runs lab hilang. SA lab hilang.
  - Tidak ada secret di GCS.
- **Lokal:** sec.tar.gz dan screenshot private dihapus.

## Artefak
- Lokal (sudah diredaksi: tanpa IP UE, IMSI, proyek/bucket, IP publik): `docs/results/booster-e2e-gcp-20261119/`.
  - `core/runs/<run>/`: times, *.win.log, bad-counts, iperf-bulk, qfi-flows.txt (r1, r3b).
  - `core/runs/zeek-r0-r2/`: mglt, pktlat_stats.
  - `core/zeek-r3/`, `core/adapter-events/events-*.jsonl`, `core/backend-data/*.jsonl`, `core/backend.log`, `core/up.log`.
  - `emu/<run>/`: logcat-booster.txt, yt.tsv/json, am-*.txt.
- Bucket state privat `<state-store>/booster-e2e/20261119/`: core-evidence.tgz (termasuk n3.pcap dan pktlat.log mentah) dan emu-evidence.tgz.

## Deviasi (FAKTA)
- Mode `sa-oai`. Pemeriksaan digest image lokal dilewati (image di-load dari tar). ID image gNB di VM 28792b3dd7ed berbeda dengan box b33894a3ea86 (representasi docker load).
- `cp -a` overlay membuat /usr dimiliki uid 1000 sehingga SSH OS Login gagal. Core di-reset 2× dengan prelude chown, dan skrip sudah diperbaiki.
- Emulator 4 vCPU: ada satu ANR SystemUI, dan YouTube lambat atau tidak mau mulai (r0b, r2, r3b tidak PLAYING).
- Akun YouTube error masuk, jadi dijalankan `pm clear` dan pemutaran dilakukan signed-out.
- Beban 150M tidak membuat kongesti, jadi dinaikkan ke 400M.
- Restart Zeek menimpa log, sehingga log r0b–r2 disalin dulu.
- onesession off hanya teruji sebagian lewat aplikasi.
- VM obs tidak dijalankan (waktu/budget). Data ada di bucket state dan box.
- Pembanding CREATE di bawah beban tanpa rule tidak diukur (lihat kriteria 9).
- r3b memakai urutan "YouTube dulu, booster kemudian" (env PLAYFIRST).

## OPEN / untuk Booster App Dev
1. Aplikasi macet setelah POLL pertama (r1, r2, r3b): AVAILABLE tidak pernah dicatat, lalu DELETE berakhir NETWORK error.
2. Trafik API aplikasi lewat bearer default VPN examine sehingga timeout di bawah beban tanpa rule 5QI 69.
3. Batas 3 IP AS tidak mencakup rotasi CDN YouTube, sehingga praktis hanya reflector yang di-boost.
4. `400 LOCAL_NO` ketika booster di-trigger sebelum flow target ada (r3). Perlu retry/backoff, bukan menyerah.
5. Loss per flow target belum ada metriknya.

## USULAN
- Batas flow berbasis subnet atau SNI (bukan IP), atau anggaran flow yang lebih besar, agar CDN YouTube ikut ter-boost.
- Perbaiki loop POLL: timeout dan retry per request, serta lanjut ke event stream.
- Pertahankan PCC statis 5QI 69 untuk API backend sebagai default provisioning lab. Ukur pembanding tanpa rule di run berikutnya dengan urutan PLAYFIRST yang sama.
- Emulator 8 vCPU dan video lokal/cached untuk baseline YouTube yang stabil.
- Tambahkan penghitung loss per flow di pktlat2 atau qfi_flows.
