# Rencana: naikkan kapasitas radio mendekati kapasitas core (budget 12 vCPU)

Status: RENCANA saja. Tidak ada apply, perubahan GCP, atau push. Disusun 19 Nov 2026 (WIB).
Permintaan user (via Open Lab PM, 19 Nov 07:54 WIB): "Naikkan kapasitas radio sampai maximal mendekati kapasitas core".
Batasan user (19 Nov 07:55 WIB): "Pertahankan budget 12vcpu" -> tanpa kenaikan kuota.
Label: **FAKTA** = repo/file/ukuran/query read-only/dokumen publik. **USULAN** = estimasi atau proposal saya.

## 1. Titik awal (FAKTA)
- Lab: vm-core-ran n2-standard-4 + vm-emu n2-standard-8 = 12 vCPU. `CPUS_ALL_REGIONS` 12/12 terpakai (query read-only). Kuota per-keluarga: N2 32, C3 8, C2 0, C2D 32, tapi batas global 12 yang mengikat, jadi pindah ke c3/c2 pun tidak membantu.
- Radio 4G: 1 eNB LTE 10 MHz SISO (`n_prb=50`, `nof_antennas=1`) + 1 srsUE ZMQ: DL 30,8 / UL 18,9 Mbit/s (laporan PM, ~84% puncak teoretis).
- Profil 5G SA (`infra/gcp/sa`): srsRAN Project gNB, band 3 FDD, SCS 15 kHz, default `SA_BW_MHZ=20` (106 PRB, 23,04 Msps), opsi 10 MHz. UE `nof_antennas=1`. Prebuild: `srsran-release_24_10_1` (gNB) + srsUE `release_23_11`.
- Core: UERANSIM -> UPF 487-511 Mbit/s (1 core 100%, kemungkinan batas UERANSIM); Open5GS UPF publik ~1,3 Gbit/s. Beban baseline lab: CPU 60-70% saat iperf; Zeek 1 worker maks 75% pada 15 kpps.
- Emulator: 1 AVD Android 16 = qemu 4 core, RSS 7,3 GiB, di n2-standard-8 Cascade Lake (nested virt). n2 Cascade Lake punya AVX512, jadi LDPC/Polar srsRAN yang dioptimasi AVX2/AVX512 jalan penuh. Tidak perlu c3 untuk itu.

## 2. Fakta publik tentang batas radio ZMQ (FAKTA, sumber di bagian 9)
- srsUE 5G ZMQ: maksimum 20 MHz. srsRAN gNB menjalankan 100 MHz dan MIMO sampai 4x4, tetapi srsUE NR tidak mendukung 100 MHz di ZMQ dan tidak mendukung MIMO (MIMO hanya di srsUE 4G).
- gNB 20 MHz FDD + srsUE: MCS 28, DL brate ~59 Mbit/s, UL ~74 Mbit/s di konsol gNB; iperf nyata ~50-59 Mbit/s DL (issue #700, discussion #350).
- 100 MHz TDD ZMQ hanya terbukti dengan UE Amarisoft (berlisensi): DL ~277 Mbit/s di satu laporan, 45-73 Mbit/s di laporan lain; MIMO malah menurunkan throughput ZMQ (<30 Mbit/s 4x4). Multi-UE Amarisoft membagi kapasitas sel (2 UE = masing-masing separuh).
- Amarisoft UE tidak bebas lisensi, lihat `docs/licensing.md`. Di luar cakupan tanpa keputusan lisensi.

## 3. Opsi dan estimasi radio
Semua angka throughput = USULAN/estimasi kecuali ada sitasi. vCPU per proses adalah perkiraan dari profil CPU 4G lab (belum diukur untuk NR).

| Opsi | Konfigurasi | Radio DL / UL (est.) | Status |
|---|---|---|---|
| a | LTE 20 MHz 2x2 MIMO 256QAM, srsENB+srsUE ZMQ (srsUE 4G mendukung MIMO) | DL ~90-150, UL ~40-60 Mbit/s (USULAN). Puncak teori 20 MHz 2x2 256QAM ~390 Mbit/s DL, tetapi ZMQ + srsUE 4G + broker 2x2 jarang melewati 100-an. UE 4G: cat. dan 256QAM perlu diverifikasi | Perlu spike; risiko sedang |
| b1 | NR n78/TDD 100 MHz + srsUE | Tidak mungkin: srsUE NR maks 20 MHz | **Di luar cakupan** (butuh UE Amarisoft berlisensi) |
| b2 | NR 20 MHz FDD SISO (profil SA saat ini) | DL ~55-59, UL ~55-74 (FAKTA publik, 1 UE) | Dasar; juga prasyarat Sesi E |
| b3 | NR 40/50 MHz + srsUE | Tidak didukung srsUE ZMQ (maks 20 MHz) | **Di luar cakupan** |
| b4 | NR 2x2 MIMO + srsUE | srsUE NR tanpa MIMO | **Di luar cakupan** |
| c | N pasangan gNB+srsUE NR 20 MHz, tiap pasang ZMQ port, PCI, IMSI, netns sendiri | N x (55-59 DL / ~55 UL), agregat linear selama CPU cukup (USULAN) | **Terbaik per vCPU** |
| c' | Campuran: 1 pasang LTE 20 MHz 2x2 (a) + pasang NR (c) | ~140-210 DL agregat | Lanjutan, setelah (a) lolos |
| d | Multi-UE di satu sel ZMQ | Tidak menambah kapasitas sel (UE berbagi PRB); broker GNU Radio untuk >1 UE hanya demo | Hanya untuk uji scheduler, bukan kapasitas |
| e | UERANSIM multi-proses | Bukan radio: beban core 0,5 -> ~1 Gbit/s | Pelengkap untuk menguji core; lihat 5 |

## 4. Alokasi 12 vCPU (USULAN)
Prinsip: radio ZMQ adalah real-time lunak dan CPU-bound; alihkan CPU dari emulator ke RAN saat uji kapasitas. UE tidak boleh idle (iperf/ping latar tetap jalan). Emulator dan Zeek bergantian, bukan bersamaan.

| Profil | VM | vCPU | Isi | Radio agregat est. |
|---|---|---|---|---|
| P0 baseline (sekarang) | core n2-4 + emu n2-8 | 4+8 = 12 | LTE 10 MHz + AVD + Zeek | 31 / 19 |
| P1 satu NR 20 MHz + emulator | core n2-8 + emu n2-4 | 8+4 = 12 | 1 pasang NR 20 MHz, AVD 4 core (turun dari 8, perlu uji kelayakan) , Zeek ringan | ~57 / ~60 |
| P2 radio-only, 2 pasang NR | RAN+core n2-8 + UE n2-4 (ZMQ lintas VM via TCP, atau semua di 1 VM custom 12) | 12 | 2 gNB+2 srsUE (~4 vCPU/pasang) + core+UPF 3-4; emulator MATI | ~115 / ~110-140 |
| P3 radio-only, 3 pasang NR | 1 VM n2-custom-12 (atau n2-8 + n2-4) | 12 | 3 pasang (~9-10 vCPU) + core minimal 2-3, Zeek MATI atau 1 tap | ~170 / ~165-200 (batas kasar; mungkin CPU-limited) |
| P4 opsi (a) LTE 20 MHz 2x2 | RAN+core n2-8 + UE n2-4 | 12 | eNB+srsUE 2x2 ~5-6 vCPU + core 2, emulator mati | ~90-150 / ~40-60 |
| X >12 vCPU | b1, b3, 6+ pasang NR, VM load-gen UERANSIM terpisah, multi-UPF | >12 | | **Di luar cakupan** |

Catatan teknis:
- Komponen yang dimatikan saat uji radio: emulator Android (P2-P4), pktlat2/mglt, build-vm-01 tetap tidak disentuh. Zeek hanya 1 tap (N6) untuk validasi throughput; Zeek 3 tap + emulator hanya di profil P0/P1.
- UERANSIM (opsi e) tidak bisa berjalan bersamaan dengan P3 karena CPU habis. Jalankan sebagai fase terpisah (bagian 5).
- `terraform` hanya menerima `n2-standard-(2|4|8|16)` untuk core/emu; n2-custom atau n2-standard-12 butuh perubahan validasi di `variables.tf` (belum dilakukan). Alternatifnya, kombinasi 8+4 sudah valid tanpa ubah validasi.

## 5. Target radio vs core (batas 12 vCPU)
Core terukur 490-511 Mbit/s (UERANSIM), referensi UPF 1,3 Gbit/s (tidak terukur di lab).

| Profil | Radio DL est. | % dari core 0,5 G | % dari 1,3 G |
|---|---|---|---|
| P0 baseline | 31 | 6% | 2% |
| P1 | ~57 | 11% | 4% |
| P2 | ~115 | 23% | 9% |
| P3 | ~170 | 34% | 13% |
| P4 | ~90-150 | 18-30% | 7-12% |
| P3 + P4 digabung | tidak muat 12 vCPU | - | - |

**Maksimum realistis dalam 12 vCPU (USULAN): agregat radio DL ~120-170 Mbit/s (3-5x baseline), sekitar 25-35% kapasitas core UERANSIM dan ~10% kapasitas UPF.** "Mendekati kapasitas core" lewat radio ZMQ srsUE tidak realistis di 12 vCPU: jaraknya ditentukan oleh CPU real-time ZMQ dan oleh batas UE (maks 20 MHz, tanpa MIMO NR), bukan oleh core. Untuk mengisi sisa kapasitas core gunakan beban N3/N6 non-radio (UERANSIM multi-proses atau generator GTP-U/iperf langsung ke UPF) di jendela uji terpisah. Itu mengukur core, bukan radio.

## 6. Biaya (asia-southeast2, on-demand, estimasi)
Dasar: n2 ~USD 0,065/vCPU-jam (n2-4 ~0,26; n2-8 ~0,52; angka dari README/PM). Semua profil 12 vCPU = ~USD 0,80/jam + disk/NAT kecil, jadi biaya per profil sama. Biaya naik karena durasi, bukan konfigurasi.

| Sesi | Durasi | Biaya (est.) |
|---|---|---|
| Spike (a) LTE 2x2 | 2 jam | ~USD 1,6-2 |
| P1 NR 20 MHz + AVD | 1,5 jam | ~USD 1,2 |
| P2 + P3 NR multi-pasang (satu sesi apply) | 3 jam | ~USD 2,4-3 |
| Fase beban core UERANSIM multi-proses | 1,5 jam | ~USD 1,2 |
| Total semua fase | ~8 jam | ~USD 6,5-8 (mengecil bila digabung dalam satu apply) |

Anggaran: total hari ini sudah ~USD 7,2 + matriks v0.10.2 berjalan (~USD 2-2,5); batas harian USD 12 belum cukup untuk seluruh rencana ini, jadi jalankan di hari lain atau naikkan batas.

## 7. Risiko
- **ZMQ non-real-time dan CPU-bound**: srsUE sering jadi bottleneck sebelum gNB; kehilangan sampel menyebabkan late/underflow, MCS turun, RLF. Mitigasi: pin CPU (taskset) per pasang, pantau `late/underflow`, batasi N pasang sampai CPU <80%.
- **srsUE NR**: eksperimental untuk SA; satu laporan publik menyebut hanya ~56-59 Mbit/s di 20 MHz, tidak ada MIMO. Banyak pasangan butuh port ZMQ, PCI, SCTP/N2 bind, dan IMSI berbeda; satu gNB per sel menambah AMF peer.
- **Emulator/VPN path**: AVD hanya bisa 1 UE; di P1 emulator turun dari 8 ke 4 vCPU (belum terbukti stabil; steal/FPS perlu diukur). Di P2-P4 emulator mati, jadi tidak ada YouTube/MGLT di sesi radio-only.
- **UE tidak boleh idle**: tiap UE perlu trafik latar (ping 1/s atau iperf rendah) selama sesi.
- **Dampak ke tap QoD/Zeek**: tap N3 di `lo` sudah rawan drop (I/Q ZMQ ikut lewat `lo`; BPF udp/2152 sudah ditambahkan). Lebih banyak pasang ZMQ di `lo` menambah banjir I/Q; pisahkan lewat netns/veth per pasang atau gunakan port berbeda dan BPF. QoD tc HTB (ogstun/ifb0) dikalibrasi untuk bottleneck kecil; kapasitas besar mengubah hitungan jumlah sesi GBR (floor(0,8R/(1,1 GBR))). Zeek 1 worker ~0,8-1 Gbit/s cukup, tapi CPU-nya bersaing dengan RAN.
- **TDD 100 MHz** (jika kelak dengan UE berlisensi) justru lebih rendah dari FDD di ZMQ dan melanggar batas 12 vCPU.
- **Kuota**: tidak ada perubahan. Jangan ubah `CPUS_ALL_REGIONS`.

## 8. Rencana bertahap dan kriteria uji (USULAN)
Semua fase: apply/destroy hanya dengan persetujuan eksplisit user; tunggu matriks v0.10.2 selesai; tidak ada push.
- **Fase 0 (offline, tanpa biaya)**: template gNB/UE multi-pasang (port ZMQ, PCI, IMSI, netns), parameter `SA_PAIRS`, validasi di `variables.tf` untuk split 8+4, perhitungan CPU per pasang dari log yang ada, uji replay offline. Kriteria: unit test hijau, `terraform validate/plan` lokal tanpa apply.
- **Fase 1 (P1, ~USD 1,2)**: 1 pasang NR 20 MHz + AVD pada 8+4. Lulus: attach SA, iperf DL >= 50 / UL >= 50 Mbit/s, late/underflow ~0, AVD 0 stall (kalau gagal -> AVD mati di sesi radio).
- **Fase 2 (P2->P3, ~USD 3)**: 2 lalu 3 pasang NR, emulator mati. Lulus: tiap pasang >= 50 Mbit/s, agregat DL >= 100 (2 pasang) / >= 150 (3 pasang), CPU <85%, tidak ada RLF 5 menit, UE tidak idle.
- **Fase 3 (a, ~USD 2)**: LTE 20 MHz 2x2 256QAM. Lulus: DL >= 90 Mbit/s stabil 5 menit. Kalau tidak, hentikan opsi (a).
- **Fase 4 (core, ~USD 1,2)**: UERANSIM multi-proses atau GTP-U generator untuk mengukur batas core dengan 12 vCPU; target > 500 Mbit/s. Jelas diberi label "beban core", bukan radio.
- **Fase 5**: laporan hasil, update Page kapasitas, perbarui rasio lab vs core.

## 9. Rekomendasi
Jalankan Fase 0 sekarang (offline), lalu Fase 1->2 (NR 20 MHz multi-pasang) sebagai jalur utama: throughput per vCPU terbaik, tanpa lisensi, tetap dalam 12 vCPU. Fase 3 (LTE 2x2) sebagai spike opsional. Sampaikan ke mitra bahwa target realistis ~120-170 Mbit/s agregat DL, bukan sejajar kapasitas core.

## 10. Keputusan yang dibutuhkan dari user
1. Setuju target realistis ~120-170 Mbit/s agregat (25-35% core) dan penutupan celah ke core lewat beban non-radio (Fase 4)?
2. Setuju repartisi 8+4 vCPU dan emulator dimatikan pada sesi radio-only (P2-P4)?
3. Setuju modifikasi `variables.tf` untuk n2-custom/VM 12 vCPU (opsional) dan template multi-pasang?
4. Anggaran: naikkan batas harian di atas USD 12 atau jadwalkan fase di hari lain (total ~USD 6,5-8)?
5. UE Amarisoft berlisensi (100 MHz) diabaikan? (menurut `docs/licensing.md` perlu keputusan lisensi)
6. Prioritas: Sesi E (QFI2 SA) dulu atau radio uplift dulu, karena keduanya memakai profil SA yang sama.

## Sumber (FAKTA publik)
- srsRAN Project #700 (50-68 Mbit/s DL 20 MHz, gNB MCS28 59M/74M): github.com/srsran/srsRAN_Project/issues/700
- #350 (20 MHz ~56 Mbit/s, config coreset0 12): github.com/srsran/srsRAN_Project/discussions/350
- #620 (MIMO hanya srsUE 4G): github.com/srsran/srsRAN_Project/discussions/620
- #425 (Amarisoft UE 100 MHz TDD 277 vs 45-73 Mbit/s, MIMO turun): github.com/srsran/srsRAN_Project/discussions/425
- Fitur srsRAN Project (100 MHz, QAM256, 4x4): docs.srsran.com/projects/project/en/latest/general/source/2_features_and_roadmap.html
- Kapasitas PM: Page "Lintas5G: Kapasitas Lab vs Jaringan Live".
