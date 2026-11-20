# Lintas5G: Product Roadmap

> Status per 18 Nov 2026 07:57 WIB. Tanggal setelah Fase 0 adalah **estimasi**.
> Label: **[Fakta]** = bersumber dan link dicek; **[Asumsi]** = belum divalidasi; **[Keputusan]** = sudah diputuskan; **[Dilaporkan PoC Architect]** = belum diverifikasi independen.

Status Fase 0: [fase0-status.md](fase0-status.md). **Fase 1 CLOSED 20 Nov 2026**: [fase1-status.md](fase1-status.md).

## Visi

**Misi: democratize 5G.** Developer, startup, dan kampus bisa meminta slice, QoS on demand, dan steering trafik ke edge lewat API standar [CAMARA](https://camaraproject.org/quality-on-demand/), di atas core 5G terbuka yang bisa mereka amati sampai ke PCF, SMF, dan UPF. Kontrolnya berbasis policy: PCRF di 4G, PCF di 5G SA.

| | |
|---|---|
| **North Star** | Developer aktif bulanan yang berhasil membuat perubahan jaringan terukur lewat API (sesi QoD, slice, atau steering dengan efek latensi/throughput terverifikasi) |
| **Metrik pendukung** | Time-to-first-API-call, developer aktif, API calls per API, skenario komunitas, efek before/after terverifikasi |

## Konteks pasar

| Label | Temuan | Sumber |
|---|---|---|
| [Fakta] | API keamanan/anti-fraud masih dua pertiga deployment komersial GSMA Open Gateway (H1 2025), turun dari lebih dari 80% di 2024 | [Telco Magazine, ringkasan laporan GSMA Intelligence H1 2025](https://telcomagazine.com/news/gsma-open-gateway-2025-global-api-adoption-insights) |
| [Fakta] | QoD menyumbang 25% peluncuran API baru di H1 2025, naik dari kurang dari 10% di 2024 | Sumber sama |
| [Fakta] | Vodafone meluncurkan QoD di Jerman, 7 Sep 2026 | [Vodafone](https://www.vodafone.com/news/newsroom/technology/vodafone-launches-quality-on-demand-in-germany) |
| [Fakta] | MasOrange: early access QoD di Spanyol, Juli 2026, profil High dan Medium | [Orange Developer](https://developer.orange.com/blog/masorange-to-launch-quality-on-demand-api-in-july-2026-with-traffic-prioritization-in-early-access/) |
| [Fakta] | Elisa + Nokia + Elmo Cars: QoD untuk remote driving, tercatat sebagai proof of concept, bukan peluncuran komersial | [GSMA Open Gateway State of the Market H2 2024](https://eu-assets.contentstack.com/v3/assets/blt23eb5bbc4124baa6/blt85b8246f902c5786/6761e86ae2ba1d6d60f7629b/111224-Open-Gateway-State-of-the-Market-H2-2024.pdf) |
| [Asumsi] | Belum ada API QoS/slicing dari operator Indonesia; API CAMARA lokal yang diumumkan fokus keamanan/identitas | Riset web terbatas |

## Tema per horizon

| Horizon | Tema | Fase | Hasil yang dicari |
|---|---|---|---|
| Now | Buktikan efeknya, lalu buka QoD | Fase 0, Fase 1 | Diferensiasi terukur dan API QoD yang bisa dipakai developer mitra |
| Next | Slicing dan skala komunitas | Fase 2 | Slice lewat API, program kampus, skenario komunitas |
| Later | Edge dan self-service | Fase 3, Fase 4 | Traffic steering ke edge, NEF, sandbox publik, portal developer |

## Timeline

| Fase | Nov 26 | Des | Jan 27 | Feb | Mar | Apr | Mei | Jun | Jul | Agu | Sep | Okt 27 | Label |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Fase 0 Feasibility | ■ | | | | | | | | | | | | Keputusan: 18–19 Nov 2026, toleransi s.d. 20 Nov |
| Fase 1 QoD MVP | | ■ | ■ | | | | | | | | | | Estimasi |
| Fase 2 Slicing + kampus | | | | ■ | ■ | ■ | | | | | | | Estimasi |
| Opsi: API identitas tiruan | | | | | □ | □ | | | | | | | Opsi, estimasi |
| Fase 3 Traffic Influence | | | | | | | ■ | ■ | ■ | | | | Estimasi |
| Fase 4 NEF + sandbox publik | | | | | | | | | | ■ | ■ | ■ | Estimasi |

## Fase

### Fase 0 — Feasibility (18–19 Nov 2026, toleransi sampai 20 Nov) [Keputusan]

- **Horizon:** Now
- **Tujuan:** membuktikan bahwa QoS yang diminta lewat API menghasilkan diferensiasi terukur di bawah beban, sebelum investasi besar.
- **Deliverable:**
  - Lab di GCP lewat IaC: Open5GS 5GC SA + srsRAN Project gNB (ZMQ) + UERANSIM + srsUE
  - Observability: Zeek (`pktlat2.zeek`) → Vector → ClickHouse → Grafana
  - Bottleneck `tc` agar perebutan sumber daya terjadi dan diferensiasi terlihat
  - PR pertama (branch `init/iac-lab5g`): IaC, observability, script tes, skeleton adapter QoD
- **API CAMARA:** belum ada API publik; jalur PCC/QoS diuji langsung
- **Gate / kriteria keluar:** di bawah beban, p99 latensi flow prioritas turun ≥50%; goodput GBR ≥95%; konsisten di 3 ulangan
- **KPI:** ketiga kriteria lulus; biaya tetap dalam USD 15–25
- **Dependensi:** akun GCP; image Open5GS/srsRAN; script `tc`
- **Risiko:** UPF Open5GS dinilai tidak memprioritaskan per QFI [Dilaporkan PoC Architect, belum diverifikasi], sehingga hasil bergantung pada bottleneck `tc`

### Fase 1 — QoD MVP (Des 2026 – Jan 2027, estimasi)

> **[Fakta] CLOSED 2026-11-20** (lebih awal dari estimasi untuk lingkup lab/PoC): gate r4 FROZEN v1.1 G1–G8 lulus, G9 tidak dilakukan. Detail dan disclosure: [fase1-status.md](fase1-status.md). Private beta developer mitra belum dimulai.

- **Horizon:** Now
- **Tujuan:** developer mitra bisa memanggil CAMARA QoD dan melihat efeknya pada demo game dan video.
- **Deliverable:**
  - Gateway CAMARA QoD + QoS Profiles (basis kandidat [FRONT camara-QoD](https://github.com/FRONT-research-group/camara-QoD))
  - Adapter tipis sebagai AF tepercaya → N5 `Npcf_PolicyAuthorization` → PCF Open5GS [Keputusan]
  - Backend Rx/PCRF 4G sebagai jembatan untuk EPC [Keputusan]
  - Dashboard before/during/after: game (p50/p95/p99 RTT, jitter, loss) dan video (bitrate, rebuffering)
  - Private beta dengan developer mitra
- **API CAMARA:** Quality on Demand v1.1.0, QoS Profiles v1.1.0 [Fakta: [rilis r3.2](https://github.com/camaraproject/QualityOnDemand/releases/tag/r3.2)]
- **Gate / kriteria keluar:** kriteria Fase 0 terulang lewat panggilan API (bukan konfigurasi manual); trace N5 → N7 → PFCP terlihat; adapter tidak terjangkau dari luar jaringan internal
- **KPI:** time-to-first-API-call developer mitra; tingkat sukses sesi QoD; efek before/after terverifikasi
- **Dependensi:** Fase 0 lulus. Estimasi effort [Dilaporkan PoC Architect]: adapter N5 2–3 minggu, backend Rx +1–2 minggu, `tc` <1 minggu, dashboard <1 minggu
- **Risiko:** jalur Rx Open5GS v2.8.0 terbatas QCI 1/2/5; adapter tanpa auth sendiri (mitigasi: auth OAuth dan rate limit di gateway, adapter hanya di jaringan internal)

### Fase 2 — Slicing S-NSSAI + program kampus (Feb – Apr 2027, estimasi)

- **Horizon:** Next
- **Tujuan:** aplikasi bisa menempatkan perangkat ke slice lewat API; kampus memakai lab untuk praktikum dan riset.
- **Deliverable:**
  - Beberapa S-NSSAI (mis. eMBB dan low-latency) dengan DNN/UPF per slice
  - Network Slice Assignment (tetapkan dan lepas perangkat dari slice)
  - Dashboard multi-user: kuota per kelas, instruktur per grup
  - Opsi: API identitas/anti-fraud tiruan sebagai on-ramp developer
- **API CAMARA:** Network Slice Booking v0.2.0 dan Network Slice Assignment v0.1.0, status Initial [Fakta: [rilis r2.3](https://github.com/camaraproject/NetworkSliceBooking/releases/tag/r2.3)]
- **Gate / kriteria keluar:** perangkat berpindah slice lewat API dengan efek terukur; program kampus pertama berjalan; biaya per jam-lab terukur
- **KPI:** developer dan mahasiswa aktif; skenario komunitas pertama
- **Dependensi:** Fase 1; kampus mitra; konfigurasi NSSF/UDM untuk S-NSSAI
- **Risiko:** spesifikasi slice masih bisa berubah; slice booking dinamis butuh orkestrasi sendiri

### Fase 3 — Traffic Influence / edge (Mei – Jul 2027, estimasi)

- **Horizon:** Later
- **Tujuan:** trafik aplikasi bisa diarahkan ke UPF dan server edge terdekat lewat API.
- **Deliverable:** UPF edge dan instance aplikasi edge di lab; adapter Traffic Influence ke PCF/SMF; demo latensi edge vs pusat
- **API CAMARA:** Traffic Influence v0.10.0, status Initial, belum disarankan untuk produksi [Fakta: [rilis r1.3](https://github.com/camaraproject/TrafficInfluence/releases/tag/r1.3)]
- **Gate / kriteria keluar:** steering terbukti lewat API dengan selisih latensi edge terukur
- **KPI:** API calls Traffic Influence; skenario edge komunitas
- **Dependensi:** Fase 2; dukungan SMF Open5GS untuk pemilihan UPF/ULCL [Asumsi, belum diverifikasi]
- **Risiko:** belum terlihat implementasi terbuka Traffic Influence untuk Open5GS; kompleksitas mobilitas

### Fase 4 — NEF + sandbox publik + portal developer (Agu – Okt 2027, estimasi)

- **Horizon:** Later
- **Tujuan:** developer eksternal mendaftar sendiri dan memakai API lewat jalur yang sesuai 3GPP.
- **Deliverable:**
  - NEF sungguhan ([OAI](https://github.com/openairinterface/oai-cn5g-nef) atau [free5GC](https://github.com/free5gc/nef)) menggantikan adapter AF
  - Portal developer: pendaftaran, kredensial OAuth, dokumentasi, contoh kode
  - Freemium dan katalog skenario komunitas
  - Opsi: API identitas/anti-fraud tiruan di portal bila belum dibuat di Fase 2
- **API CAMARA:** semua API di atas lewat NEF
- **Gate / kriteria keluar:** NEF lulus uji interop dan keamanan; review hukum PDP dan lisensi; model harga tervalidasi
- **KPI:** developer aktif bulanan; time-to-first-API-call self-service; API calls per bulan
- **Dependensi:** Fase 1–3; pilihan NEF; operasi dan dukungan
- **Risiko:** OAI NEF tanpa TLS/mTLS dan berlisensi CSSL v1.0 [Fakta: [security guide](https://github.com/openairinterface/oai-cn5g-nef/security)]; biaya operasional sandbox publik

## Ringkasan fase

| Fase | Waktu | API CAMARA | Gate keluar |
|---|---|---|---|
| Fase 0: Feasibility | 18–19 Nov 2026, toleransi 20 Nov | — (jalur PCC/QoS langsung) | p99 turun ≥50%, goodput GBR ≥95%, 3 ulangan |
| Fase 1: QoD MVP | Des 2026 – Jan 2027 (estimasi) | QoD v1.1.0, QoS Profiles v1.1.0 | Kriteria Fase 0 lewat API; trace N5 → N7 → PFCP; adapter tidak terekspos |
| Fase 2: Slicing + kampus | Feb – Apr 2027 (estimasi) | Network Slice Booking v0.2.0, Slice Assignment v0.1.0 | Pindah slice lewat API terukur; program kampus berjalan |
| Fase 3: Traffic Influence / edge | Mei – Jul 2027 (estimasi) | Traffic Influence v0.10.0 | Steering ke edge terbukti dan terukur |
| Fase 4: NEF + sandbox publik | Agu – Okt 2027 (estimasi) | Semua via NEF | NEF lulus interop/keamanan; review hukum; harga tervalidasi |

## Opsi: API identitas/anti-fraud tiruan sebagai on-ramp

Status: **opsi, belum diputuskan.** Menyediakan API tiruan (mis. Number Verification, SIM Swap) dengan data sintetis agar developer yang mengenal kategori API paling populer mudah masuk, lalu diarahkan ke QoD dan slicing.

| Pertimbangan | Isi |
|---|---|
| Mengapa masuk akal | Kategori keamanan/identitas mendominasi deployment komersial [Fakta, lihat konteks pasar] |
| Risiko | Mengalihkan fokus dari pembeda utama (QoS/slicing nyata); API tiruan tidak punya nilai jaringan nyata |
| Usulan [Asumsi] | Hanya mock dengan data sintetis, tanpa data pelanggan; ditempatkan di Fase 2 atau Fase 4 |

## Log keputusan

### 17 Nov 2026

- [x] Nama inisiatif Lintas5G; misi democratize 5G lewat telco API CAMARA untuk slicing dan traffic steering berbasis policy
- [x] Stack: Open5GS 5GC SA + srsRAN Project gNB ZMQ + UERANSIM + srsUE
- [x] Observability: Zeek (`pktlat2.zeek`) → Vector → ClickHouse → Grafana
- [x] RIC ditunda; OAI/free5GC hanya untuk interop
- [x] Fase awal: adapter tipis sebagai AF tepercaya ke PCF via N5; basis kandidat FRONT camara-QoD
- [x] NEF ditunda sampai sandbox publik; backend Rx/PCRF 4G sebagai jembatan
- [x] Demo pertama: game (latensi) dan video (bitrate), dengan bottleneck `tc`
- [x] Feasibility 2 hari di GCP mulai 18 Nov 2026, budget USD 15–25, dengan kriteria lulus Fase 0
- [x] PR pertama di branch `init/iac-lab5g`; kode baru Apache-2.0, patch upstream terpisah di bawah AGPL

### 18 Nov 2026

- [x] Kuota GCP tetap 10–12 vCPU
- [x] PR #1 di-merge setelah verdict Fase 0
- [x] Zeek wajib berjalan paralel dengan emulator di setiap sesi; ClickHouse/Grafana dimuat batch setelah tes (tidak real-time); log disimpan di GCS
- [x] Urutan Sesi A → B → C; Sesi A mulai 18 Nov 07:57 WIB (apply disetujui)
- [x] RAN UERANSIM untuk tes (a)(b)(c); srsRAN Project gNB sebagai bonus
- [x] Fase 0 boleh molor sampai 20 Nov 2026

Catatan: penilaian bahwa UPF Open5GS tidak memprioritaskan per QFI dan semua estimasi effort **dilaporkan PoC Architect** dan belum diverifikasi.

## Pertanyaan terbuka

1. Bila Fase 0 tidak lulus (p99 tidak turun 50% atau GBR di bawah 95%), apakah lanjut dengan bottleneck `tc` sebagai fitur sandbox, atau evaluasi UPF/scheduler lain?
2. Siapa developer mitra dan kampus pertama untuk private beta Fase 1 dan program Fase 2?
3. Game seperti apa yang didemokan (cloud gaming atau multiplayer dengan server sendiri), dan target angka apa yang ingin ditunjukkan ke partner?
4. Apakah opsi API identitas tiruan diambil, dan di fase mana?
5. NEF mana untuk Fase 4: OAI (CSSL v1.0) atau free5GC (Apache-2.0)?
6. Siapa yang mendanai dan mengoperasikan sandbox publik setelah Fase 4?

## Referensi

- CAMARA: [Quality on Demand](https://camaraproject.org/quality-on-demand/) · [Network Slice Booking](https://camaraproject.org/network-slice-booking/) · [Traffic Influence](https://camaraproject.org/traffic-influence/)
- [FRONT camara-QoD](https://github.com/FRONT-research-group/camara-QoD)
- [Open5GS](https://github.com/open5gs/open5gs)
