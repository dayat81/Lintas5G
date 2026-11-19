# Fase 0 close gate: OAI multi-UE dalam 1 sel + dedicated QoS flow di GCP (sa-oai, vrtsim real-time). 19 Nov 2026

Status: run GCP run6, lab sudah **di-destroy dan diaudit bersih**. Tanpa commit/push/PR, tanpa perubahan IAM/VNC/tunnel, lab lain tidak disentuh.
Persetujuan: user "approved proceed" (19 Nov 2026, 14:49 WIB), setelah uji offline lolos (`/workspace/oai-multiue/RESULT.md` di box).
Bukti teredaksi: `docs/results/multiue-qos-gcp-20261119/` (start, t1, qfi, ab-runs, times, skrip uji). Log mentah gNB/UE (IMSI sudah diredaksi) hanya di box: `/workspace/mq-gcp/logs/`.

## Verdict
**Fase 0: LOLOS, bisa ditutup.**
- **Multi-UE:** 3 UE dalam 1 sel, real-time (rasio 1,00), masing-masing dengan PDU session sendiri dan keepalive aktif.
- **Dedicated QoS flow:** end-to-end (NAS, DRB, QFI 2 di N3 dua arah) untuk 1 dan 2 UE paralel, terisolasi.
- **A/B di sel penuh:** QoD membuat flow aplikasi tetap usable (p99 RTT 113 ms vs 4980 ms, TCP 20,5 vs 0,3 Mbit/s).
- **Catatan untuk gate Fase 1:** diferensiasinya terjadi **di dalam UE** (DRB QoD vs bearer default UE yang sama). **Antar-UE** scheduler OAI v3.0.0 tetap membagi rata, dan 5QI/GBR tidak menambah porsi PRB.

## Lingkungan (FAKTA)
| Item | Nilai |
|---|---|
| VM | vm-core-ran `n2-custom-12-49152`, min CPU platform Intel Ice Lake (otomatis untuk sa-oai), tanpa emulator |
| RAN | OAI v3.0.0 gNB + 3 nrUE (image by digest), n78 TDD 30 kHz 106 PRB (40 MHz), MIMO 2x2, 256QAM (uecap_ports2) |
| RF | **vrtsim, timescale 1.0, RT aktif** (`rt=1`, SYS_NICE + rtprio), core Open5GS di CPU 0-1, RAN di CPU 2-11 |
| Core | Open5GS 5GC (lab), PLMN 001/01, DNN internet; N3 di lo |
| tfvars | `ran_mode=sa-oai`, `nr_pairs=3`, `oai_rf=vrtsim`, `oai_mimo=2`, `emu_enabled=false` (`p6.tfvars.redacted`) |
| PCC statis (mongo, sebelum RAN start) | UE1: 5QI 7, ARP 6, SDF tcp/udp port 18080. UE2: 5QI 1 GBR/MBR 20/20 Mbit/s, ARP 5, SDF tcp/udp port 18081. UE3: tanpa PCC. (`pcc.sh`) |

## Hasil

### (1) 3 UE attach + TCP DL serentak 60 s (`t1.txt`, `start.txt`)
- Attach: gNB NG setup 3 s; IP UE1/UE2/UE3 setelah 3/4/4 s. Tiap UE punya PDU session dan IP sendiri (hash IP berbeda: b5340c / 85f9b1 / 166e83).
- Keepalive (`lab5g-nr<i>-keepalive`, ping 1/s) **aktif di ketiga UE dari attach sampai destroy** (`keepalive_active: 3` di setiap cek).

| UE | TCP DL (Mbit/s) | CQI / RI | DL MCS (tabel) | DL BLER |
|---|---|---|---|---|
| UE1 | 43,2 | 15 / 2 | 27 (256QAM) | 0,003 |
| UE2 | 40,9 | 15 / 2 | 27 (256QAM) | 0,001 |
| UE3 | 40,3 | 15 / 2 | 17–27 (256QAM) | 0,003 |
| **Agregat** | **124,4** | | | |

- **Rasio sim/real = 1,00**, jadi throughput udara jujur = wall = 124,4 Mbit/s. Pembanding: run5 vrtsim 3 UE 118,2; offline box rfsim 106,6.
- CPU: VM busy rata-rata 54% (maks 73%). nr-uesoftmodem total 369%, nr-softmodem 245%, upfd 17% (100% = 1 vCPU).
- N3 drop 0% (924k paket). Re-establishment 0, UL failure 0, RRC Release 0, late/underflow 0.
- `nr_summary` verdict "FAIL" hanya karena ambang lama (agregat < 150); itu bukan kegagalan radio.
- Health `rlf_events: 1` = satu peringatan gNB `RLC: UE 2414 RLF detected, but no callable RLF handler registered`, 0,7 s setelah UE2 attach. Tidak ada efek: RNTI ketiga UE (7381/2414/55d8) tetap sama sampai akhir dan tidak ada re-establishment.

### (2) Dedicated flow UE1 (5QI 7): NAS, DRB, QFI di N3 (`start.txt`, `qfi.txt`, `qfi2.txt`)
- **gNB:** `PDUSESSIONModify` → `created new DRB 2 for QFI 2 (5QI 7)` untuk UE1 dan `(5QI 1)` untuk UE2. UE3 hanya DRB 1 (5QI 9). Tidak ada RRC Release.
- **nrUE:** `Received PDU Session Modification Command, QoS Rule 2: op=1 qfi=2 ... nb_pf=4` → `CREATE new QoS rule 2 with QFI 2` → `PduSessionModificationComplete` (UE1 dan UE2 masing-masing 1×; UE3 0×).
- **N3 GTP-U (tcpdump lo:2152, parser PDU Session Container `qfi.py`):**

| UE | Trafik | DL QFI (paket) | UL QFI (paket) |
|---|---|---|---|
| UE1 | tcp 18080 | **2** (2335) | **2** (2169) |
| UE1 | udp 18080 | **2** (1411) | **2** |
| UE1 | tcp 5201 (default) | 1 (1568) | 1 (720) |
| UE1 | ICMP | 1 | 1 |
| UE2 | tcp 18081 | **2** (735 / 1580) | **2** (1489 / 702) |
| UE2 | udp 18081 | **2** (1415) | **2** |
| UE2 | tcp 18080 (bukan SDF-nya) | 1 (1566) | 1 (702) |
| UE3 | tcp 18080 / 18081 / 5203 | 1 / 1 / 1 | 1 / 1 / 1 |
| semua | ICMP keepalive | 1 | 1 |

**QFI 2 end-to-end dua arah = PASS.** UE lain tetap di QFI 1, termasuk untuk port QoD milik UE lain.
Catatan: field tshark `gtp.ext_hdr.pdu_ses_cont.*` tidak valid di versi tshark VM. Yang dipakai adalah parser Python, yang sudah divalidasi offline.

### (3) Dua UE QoD paralel (UE1 5QI 7, UE2 5QI 1 GBR 20M): isolasi (`ab-runs.txt` c1, capture N3 40 s)
- Saat sel penuh (bulk BE di 3 UE), N3 menunjukkan:
  - UE1: tcp/udp 18080 = QFI 2 (DL 71,8k + 2000 paket, UL 26,5k + 2000).
  - UE2: tcp/udp 18081 = QFI 2 (DL 51,1k + 2000, UL 19,0k + 2000).
  - Bulk 5211/5212/5213 dan ICMP semuanya QFI 1 (~385k paket per UE).
- **Tidak ada kebocoran QFI antar-session**, dan masing-masing UE memakai DRB 2 sendiri.
- Kedua flow QoD tetap dengan RTT rendah bersamaan: p99 114 ms (UE1) dan 138 ms (UE2), loss < 1%. Tanpa re-establishment.

### (4) A/B di sel penuh, QoD dibatasi 40M (tidak pernah disaturasi)
Desain: tiap run 40 s. "App" = TCP DL iperf3 dibatasi `-b 40M`, plus probe RTT UDP aplikasi 50 pps (64 B, echo di 10.45.0.1) pada **port yang sama** dengan app. Pada QoD port itu masuk SDF → QFI 2; pada baseline di flow default.
"Bulk" = UDP DL 100M offered per UE (agregat 300M > kapasitas sel ~240), port 5211–5213 (QFI 1).
Rasio sim/real = **1,00** di semua run. RTT dihitung di flow aplikasi itu sendiri (bukan ICMP); reply > 5 s dihitung loss.

| Run | App UE1 (Mbit/s) | App UE2 | Bulk UE1 / UE2 / UE3 | RTT app p50 / p90 / **p99** / max (ms) | loss probe | VM busy |
|---|---|---|---|---|---|---|
| a0 baseline, app UE1 di default + bulk di semua UE | **0,3** | – | 78,9 / 78,5 / 79,1 | 3115 / 4683 / **4980** / 4999 | 63,6% | 75% |
| a1 **QoD**, app UE1 di QFI 2 + bulk di semua UE | **20,5** | – | 67,0 / 80,6 / 78,7 | 23 / 58 / **113** / 199 | 0,25% | 75% |
| b0 baseline, app UE1 di default, bulk hanya UE2/UE3 | 31,0 | – | – / 97,6 / 98,0 | 23 / 41 / **78** / 115 | 0,55% | 74% |
| b1 **QoD**, app UE1 di QFI 2, bulk hanya UE2/UE3 | 34,0 | – | – / 98,0 / 98,1 | 23 / 38 / **77** / 99 | 0,3% | 73% |
| c0 baseline, app UE1+UE2 di default + bulk semua | 0,2 | 0,3 | 80,1 / 76,5 / 72,7 | UE1 2862/4615/**4970**; UE2 1707/3921/**4977** | 64% / 74% | 76% |
| c1 **QoD**, UE1 (5QI 7) + UE2 (5QI 1 GBR) + bulk semua | 19,2 | 13,6 | 62,7 / 67,4 / 73,9 | UE1 24/64/**114**; UE2 25/67/**138** | 0,95% / 0,6% | 77% |

- CPU per run (100% = 1 vCPU): nr-uesoftmodem total 536–567%, nr-softmodem 266–276%, upfd 24–36%. VM busy 73–77% (maks 79,5%).
- MAC selama run bulk: CQI 15, RI 2, tabel 256QAM. Snapshot MCS DL 8–27 (adaptasi BLER), DL BLER 1–5% saat UDP DL saturasi (UE ~550% CPU melewatkan deadline HARQ; sama dengan temuan run5 untuk UDP berat). Re-establishment, UL failure, dan RRC Release: 0 di semua run. Keepalive 3/3 aktif.

**Pembacaan (FAKTA dari tabel):**
- **Intra-UE (a0 vs a1, c0 vs c1):** saat UE QoD sendiri juga membawa bulk BE (skenario realistis: download besar plus aplikasi sensitif latency di HP yang sama), flow QoD tetap usable.
  - p99 RTT: **113–138 ms vs ~4980 ms**.
  - Loss probe: < 1% vs 64–74%.
  - TCP app: 13,6–20,5 vs 0,2–0,3 Mbit/s.
  - Bulk BE di UE itu turun (78,9 → 67,0 dan 62,7), karena DRB 2 dilayani lebih dulu di dalam porsi UE tersebut.
- **Antar-UE (b0 vs b1):** jika UE QoD tidak membawa bulk sendiri, baseline dan QoD praktis sama (p99 78 vs 77 ms, TCP 31,0 vs 34,0). Bulk UE lain tidak berkurang (97,6/98,0 vs 98,0/98,1). **Scheduler OAI tidak memberi porsi PRB lebih untuk 5QI 7 atau GBR 5QI 1 antar-UE** (konsisten dengan temuan offline). GBR 20M UE2 "terpenuhi" hanya karena porsi PF per UE sudah > 20M, bukan karena reservasi.
- App TCP QoD tidak mencapai 40M di a1/c1 (20,5 / 19,2 / 13,6): porsi PF UE itu (~80–87 Mbit/s) dibagi antara DRB 2 dan bulk, dan TCP dibatasi RTT ~25–60 ms + jitter. Flow QoD tidak pernah disaturasi, jadi tidak ada starvation bearer default (berbeda dengan uji offline yang sengaja men-saturasi QoD).

## Biaya dan audit (FAKTA)
| Item | Nilai |
|---|---|
| Apply | 14:56:11–14:57:37 WIB, 165 resource, rc=0 |
| RAN siap (boot + install) | 15:05:40 WIB |
| Tes | 15:06 (PCC + start) – 15:23 WIB (A/B selesai), log diambil 15:25 |
| Destroy | 15:25:13–15:27:58 WIB, 165/165, rc=0, `terraform state list` = 0 |
| VM hidup | ~30,4 menit (apply selesai 14:57:37 sampai destroy selesai 15:27:58) |
| Biaya run ini (estimasi tarif list, skala run5: 40,5 menit ≈ USD 0,55) | **≈ USD 0,41** (target ≤ 1) |
| Kumulatif hari ini | **≈ USD 12,46** (< 13 batas laporan, < 15 hard cap). Estimasi, belum dicek ke billing. |

Audit gcloud setelah destroy:
- Instance hanya `build-vm-01` (TERMINATED, tidak disentuh). Disk hanya `build-vm-01`. Snapshot hanya milik build-vm-01 (pra-ada).
- Network hanya `default`. Router 0, resource-policy 0.
- Address hanya netprobe ×3 + magnon ×1 (pra-ada). Firewall hanya default-* + magnon/netprobe (pra-ada).
- Bucket: state + netprobe ×2 + cloudbuild (pra-ada). Bucket runs lab terhapus.
- Service account lab (`lab5g-core-ran`/`-emu`/`-obs`) tidak ada. Yang tersisa: SA terraform, netprobe, hermes, compute default (pra-ada).

**Audit bersih.** Tidak ada perubahan IAM di luar binding standar lab yang dibuat dan dihapus Terraform, tanpa VNC dan tanpa tunnel publik.

## Insiden kecil selama run (FAKTA)
- Langkah QFI pertama: tcpdump `timeout 40` habis sebelum urutan uji selesai, jadi bagian UE2-DL/UE3 tidak tertangkap. Diulang dengan capture 60 s (`qfi2.txt`), lengkap.
- Batch A/B pertama menggantung: `wait` ikut menunggu proses echo server di background. Dihentikan, `wait` diganti ke PID spesifik, lalu batch diulang. Biaya tambahan ~7 menit VM. Tidak ada efek pada lab.

## USULAN
1. **Tutup Fase 0.** Kriteria multi-UE (3 UE, 1 sel, real-time, keepalive) dan dedicated QoS flow (5QI 7 dan 5QI 1 GBR, QFI 2 di N3 dua arah, 2 UE paralel terisolasi) terpenuhi di GCP.
2. **Gate Fase 1 (QoD dengan CAMARA):** definisikan A/B sebagai **intra-UE** (aplikasi QoD vs bulk di UE yang sama), karena itu yang terbukti berbeda (p99 ~113 vs ~4980 ms). Untuk klaim **antar-UE** (UE QoD vs UE lain di sel padat) perlu salah satu:
   - (a) policy alokasi berbobot 5QI/GBR di scheduler OAI;
   - (b) slicing OAI/FlexRIC dengan QoD di slice sendiri;
   - (c) shaping BE di UPF/N6, dilabeli jujur sebagai QoS core, bukan RAN.
3. **Wajib di desain QoD:** MBR = GBR pada PCC dan shaping di sumber. Flow QoD yang disaturasi membuat bearer default UE itu kelaparan, lalu RLF (bukti offline).
4. **Berikutnya (offline dulu):** memicu flow secara runtime lewat PCF N5 (`npcf-policyauthorization`, jalur CAMARA QoD), bukan PCC statis saat attach.
5. Port skrip uji (`mq.sh`, `probe.py`, `pcc.sh`, `qfi.py`) ke `infra/gcp/sa` sebagai tes resmi: perlu persetujuan, belum di-commit.
