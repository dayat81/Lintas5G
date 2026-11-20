# Kriteria gate Fase 1 — r4 dan seterusnya (FROZEN v1.1, pre-registration)

Status: draft untuk disetujui; belum berlaku sampai ditandai "FROZEN" dengan tanggal dan commit sebelum run r4 pertama.
Ruang lingkup: hanya r4 dan seterusnya. r3 di whitepaper (v0.7.2) tetap dinilai dengan kriteria lama. Analisis r3 saat AVAILABLE (`r3-avail/r3-avail.md`) hanya informasi.
Perubahan lain: qos-provisioning (71 skenario) dipindah ke Fase 2.
Aturan pre-registration: kriteria, definisi metrik, skrip analisis, dan jumlah ulangan ditulis dan di-commit sebelum run. Setelah FROZEN, perubahan hanya lewat revisi bernomor dengan alasan, dan run yang sudah dilihat tidak dinilai ulang dengan revisi itu. Semua angka dilaporkan, termasuk yang gagal.

## Definisi bersama
- **Window**: dari `t_booster` (aplikasi booster mulai meminta sesi) sampai `t_booster_finish` (permintaan berhenti), dicatat di `times`. (Usulan; r3 memakai window dari AVAILABLE pertama ke DELETE terakhir. Definisi baru ini perlu disetujui karena memengaruhi cakupan.)
- **AVAILABLE**: interval dari callback QOS_STATUS_CHANGED=AVAILABLE sampai UNAVAILABLE/DELETE (sink adapter, cap waktu server), dipotong ke window.
- **Loss DL YouTube**: metode T4-loss: paket DL YouTube (:443) N6→UE dicocokkan N3 ↔ UE (GTP-U), dikaitkan ke interval menurut waktu kirim N3.
- **Share byte**: byte IP YouTube DL di QFI ≠ 1 / total, per paket, pada interval yang sama (metode T2).
- **Cakupan sesi** = detik AVAILABLE / detik window.
- Minimum data: interval dinilai hanya bila ≥1.000 paket YouTube DL; kalau kurang, ditulis "tidak cukup data", bukan lulus.
- Ulangan: minimal 2 run YouTube per konfigurasi (A dan PA); gate lulus bila semua run lulus. Hasil per run dilaporkan.

## G1. YouTube (item 7)
| ID | Kriteria |
|---|---|
| G1a | Loss DL YouTube saat AVAILABLE ≤ 5% per run. Loss sepanjang window dan di luar AVAILABLE tetap dilaporkan (bukan gate). Loss bulk bukan gate. |
| G1b | Share byte YouTube di QFI boost saat AVAILABLE ≥ 80% per run. |
| G1c | Cakupan sesi ≥ 90% dari window per run. |
Catatan: r3 menunjukkan cakupan 38–71% akibat celah DELETE→CREATE 34–52 s; G1c hanya bisa lulus bila kebijakan delete/recreate booster diubah.

## G2. Conformance (item 1)
- File `.feature` resmi CAMARA r4.3 (QoD dan qos-profiles) dieksekusi **tanpa diubah** (hash file dicatat) lewat `behave`, dengan laporan per skenario (JUnit/JSON).
- Step definitions dan environment kita sendiri; dipublikasikan atau dijelaskan.
- Lulus: semua skenario lulus, atau tiap kegagalan/skip diberi alasan tertulis yang diterima (mis. di luar cakupan profil). Jumlah lulus/gagal/skip dilaporkan.
- Skenario qos-provisioning (71): Fase 2, tidak masuk gate ini.

## G3. Callback (item 2)
Callback QOS_STATUS_CHANGED diterima oleh sink untuk: AVAILABLE, DELETE (UNAVAILABLE/DELETE_REQUESTED), DURATION_EXPIRED (UNAVAILABLE/DURATION_EXPIRED), NETWORK_TERMINATED (kegagalan policy/N5/PFCP). Bukti: log sink dengan sessionId, status, statusInfo, cap waktu; satu kasus uji per jenis; callback tepat satu per transisi per sessionId.

## G4. Trace (item 3)
Satu sesi diambil dengan artefak yang berkorelasi waktu: N5 (adapter→PCF) → N7 (PCF→SMF) → PFCP (SMF→UPF) → NGAP (PDU session modify) → paket DL/UL pertama dengan QFI baru. Lulus: kelima titik terlihat untuk sessionId yang sama, dengan latensi antar titik dilaporkan. Artefak tanpa IP/IMSI nyata.

## G5. Adapter tertutup (item 4)
Bukti config: instans tanpa external IP; aturan firewall deny ingress dari luar VPC/sumber yang tidak diizinkan (IaC dan output `gcloud` terekam). Bukti scan: `nmap` dari VPC internal (host non-izin) dan dari netns UE; hasil menunjukkan port adapter tertutup/difilter dari sumber yang tidak diizinkan, dan terbuka hanya dari sumber yang diizinkan. Scan dari internet publik tidak dilakukan (VM tanpa IP publik); batasan ini diungkapkan.

## G6. Multi-UE satu sel (item 5)
Skenario: ≥2 UE dalam satu sel padat, satu dengan QoD dan satu tanpa; sesi paralel per device.
- Median loss UE dengan QoD ≤ 1% dan maksimum ≤ 5% per sesi.
- p99 latensi UE dengan QoD turun ≥ 50% dibanding tanpa QoD (sel yang sama, pada saat yang sama).
- Goodput UE dengan QoD ≥ 95% dari goodput referensi (UE tunggal, sel tidak padat, atau target yang diminta sesi; tentukan sebelum run).
- 3 ulangan penuh.
- Isolasi: QFI sesi tiap UE terpisah (tidak ada paket UE A pada QFI milik UE B) dan callback diterima per sessionId yang benar tanpa tertukar.
- Diungkapkan: pemisahan antar-UE bergantung pada modifikasi RAN (gNB ter-patch) bila dipakai.

## G7. Tanpa konfigurasi manual
"No per-session or per-app manual configuration; one-time static provisioning is disclosed." Lulus bila: tidak ada langkah manual per sesi atau per aplikasi selama run (diperiksa dengan daftar langkah run); provisioning statis (mis. subnet/SDF, binding device) dibuat lewat IaC/skrip yang di-commit dan diungkapkan di paper.

## G8. Bukti tampilan (item 6)
Tangkapan layar aplikasi booster dan dashboard Grafana untuk run yang sama (sesi, QFI, status), dengan waktu yang cocok dengan log; sumber data dashboard tercatat.

## G9. Rilis (item 8)
Push/PR hasil Fase 1 setelah gate dinilai; butuh approval user langsung. Scan data sensitif sebelum push (IMSI, MSISDN, IP live, akun).

## Penutupan
Fase 1 ditutup bila G1–G8 lulus pada run yang dijadwalkan di bawah kriteria FROZEN. Kegagalan dilaporkan apa adanya; kriteria tidak diubah setelah melihat hasil.

## Poin terbuka untuk keputusan
1. Definisi window (G1): dari `t_booster`–`t_booster_finish` (usulan) atau definisi r3.
2. Jumlah ulangan YouTube (usulan ≥2 per konfigurasi) dan minimum 1.000 paket.
3. Referensi goodput G6 (95% dari apa).
4. Apakah skenario conformance yang tidak relevan untuk profil kita boleh dicatat "skip dengan alasan".

---
## Keputusan final (2026-11-20 09:42 WIB) — FROZEN v1.0
Kriteria disetujui user langsung (09:39 WIB, "approved & proceed"). Detail di bawah diputuskan bersama Open Lab PM.
1. **Window** = `t_booster` → `t_booster_finish`. `t_booster` = saat booster ditap/dibuka, dicatat di log app. Metrik wajib:
   - time-to-AVAILABLE (s): dilaporkan, tidak dinilai;
   - cakupan AVAILABLE ≥90% dari window: **gate**.
2. **YouTube:** A×3 wajib. N×3 kalau muat di sesi GCP yang sama; kalau tidak, N×2 dengan batasan ditulis. PA opsional. Interval dengan <1.000 paket DL YouTube dilaporkan sebagai "tidak dinilai".
3. **Goodput multi-UE** ≥95% dari target profil yang diminta (GBR atau maxBitrate). Untuk profil non-GBR, target = min(target, offered load). Patch slice di gNB (`qod_max_pct`) wajib diungkapkan sebagai modifikasi RAN di CLAIMS dan paper.
4. **Conformance:** skip ≤5% dari total, hanya untuk skenario yang terdaftar di §Skip-list. Skip-list dibekukan sebagai v1.1 (hash baru) **sebelum** run conformance, lalu dipublikasikan bersama CLAIMS.
5. **Aturan umum:** r3 tetap dinilai dengan kriteria lama. qos-provisioning masuk Fase 2. Dokumen ini tidak boleh diubah setelah r4 mulai; perubahan apa pun = versi baru dengan hash baru, dicatat sebelum run.

### Skip-list (conformance) — FROZEN v1.1 (2026-11-20, ditulis sebelum run behave pertama)
- **Isi: kosong (0 dari 127 skenario; batas 5% = 6).** Semua skenario QoD r4.3 (96) dan qos-profiles r1.2 (31) dijalankan dan dinilai; tidak ada yang boleh SKIP.
- Alasan: satu-satunya SKIP di runner lama (`createSession_02_3`, PRIVATE_KEY_JWT) sekarang diimplementasikan di adapter 0.1.3 (JWKS lokal), dan skenario 3-legged/429/IPv6/NAI punya fixture lab (token 3-legged simulasi, client throttled, 422 UNSUPPORTED_IDENTIFIER) yang diungkapkan.
- Target run: adapter 0.1.3, backend mock (perangkat sintetis 10.99.0.x), file `.feature` resmi tanpa diubah (sha256 dicocokkan ke tag upstream `r4.3`), step library `fase1-closeout/conformance/behave/features/steps/`. Hitungan dilaporkan per skenario (127) dan per baris Examples (162).
- Perubahan v1.0 → v1.1: hanya judul dan bagian Skip-list ini.
