# Evaluasi ganti UE emulator: OAI nrUE (rfsim/vrtsim) vs srsUE 23.11 (ZMQ) — offline di box, 19 Nov 2026

Status: eksperimen OFFLINE di box (tanpa GCP, tanpa commit/push). Persetujuan: "coba ganti ue emulator" (19 Nov 2026, 12:13 WIB).
Log lengkap: `/workspace/oai-eval` di box (tidak di-commit). IMSI/K/OPc dibangkitkan acak, file 0600, tidak dicetak.

## Ringkasan

- **FAKTA:** OAI v3.0.0 (gNB `nr-softmodem` + `nr-uesoftmodem`, image resmi) berhasil attach ke Open5GS di box:
  NG Setup, RRC connected, Registration, PDU session, dan ping (RTT 5–7 ms). 256QAM (tabel MCS 1, Qm 8) dan MIMO 2x2 (CSI RI 2, SRS UL-RI 2) **jalan**, padahal di srsUE 23.11 keduanya crash. Selama semua tes rfsim: BLER DL/UL 0 dan tidak ada RLF.
- **FAKTA, soal waktu rfsim:** rfsim **tidak di-pacing ke jam dinding**. Frame counter gNB maju 2,7–5,1 detik-simulasi per detik wall-clock (1 UE), jadi angka iperf wall-clock **terinflasi** sebesar rasio itu dibanding radio nyata. Contoh: (b) 20 MHz FDD 64QAM 1x1 mendapat TCP DL 202 Mbit/s wall-clock, padahal kapasitas fisik carrier itu ~80–90 Mbit/s. Sebagai pembanding, srsRAN ZMQ di box diukur dengan cara yang sama: rasio **0,90** (sedikit lebih lambat dari real-time), jadi angka srsUE **tidak** terinflasi.
- **FAKTA, perbandingan jujur** (throughput per detik-simulasi = wall / rasio, per UE):
  - srsUE 20 MHz 64QAM: ~52 Mbit/s wall, setara ~58 air.
  - OAI 20 MHz 64QAM:
    - vrtsim (di-pacing): ~78 Mbit/s air-equivalent.
    - rfsim: 54 UDP DL air.
  - OAI 40 MHz TDD 2x2 256QAM, 1 UE: UDP DL **103** air.
  - 3 UE 2x2 di 8 vCPU (rasio ~1, sudah batas CPU): TCP UL agregat 83, TCP DL 90 (2 UE terukur).
- **USULAN:** OAI layak menggantikan srsUE: secara jujur kenaikannya ~1,8x per UE (≈100 vs ≈55 Mbit/s), berkat MIMO 2x2 dan 256QAM. Target agregat 120–170 **jujur** (real-time) belum terbukti di box 8 vCPU. Itu perlu VM dengan scheduler RT (GCP) dan mode vrtsim real-time (lihat Integrasi).

## Lingkungan (FAKTA)

| Item | Nilai |
|---|---|
| Box CPU | Intel Xeon family 6 model 207 (Emerald Rapids, AVX-512 + FP16), 8 vCPU, 15 GB |
| Budget | Semua tes ≤ 8 vCPU (cpuset 0-7), jadi sudah di bawah budget 12 vCPU. Box tidak bisa meniru 12 vCPU. |
| vs GCP | Per core lebih cepat daripada Cascade Lake/Ice Lake (n2). Angka rasio di GCP akan lebih rendah. |
| Real-time | Box **tidak mendukung SCHED_FIFO** (chrt EPERM, docker `--cpu-rt-runtime` tidak didukung kernel), jadi OAI berjalan tanpa prioritas RT (`--cap-drop ALL`). |
| OAI | `oaisoftwarealliance/oai-gnb:v3.0.0` `sha256:170b4878a790…cbd`, `oai-nr-ue:v3.0.0` `sha256:b482191d636d…10f` (build banner: commit 6f89078, 9 Okt 2026) |
| Core | Open5GS (paket PPA) di container test `srs-lab` + mongo, PLMN 001/01, TAC 1, SST 1, AMBR 1 Gbps |
| N2 tanpa SCTP | Shim LD_PRELOAD `sctp2tcp` v2 (lihat di bawah) di AMF dan gNB |
| srsRAN pembanding | gNB 24.10.1 + srsUE 23.11, ZMQ tcp, n3 FDD 20 MHz (setup box sebelumnya) |

### Shim sctp2tcp v2 (khusus tes, bukan untuk VM lab)
OAI gNB menunggu notifikasi `SCTP_COMM_UP` di sisi client sebelum mengirim NGSetupRequest, dan juga memakai `sctp_getpaddrs` dan `SCTP_STATUS`. Shim v1 (dari srsfix) tidak menyediakannya, jadi v2 menambahkan:
- Frame HELLO dari server saat accept (hanya jika `SCTP2TCP_HELLO=1` di AMF). Client menerjemahkannya menjadi `SCTP_COMM_UP`.
- `sctp_getpaddrs`/`sctp_getladdrs`/`free*`.
- `SCTP_STATUS` (2/2 stream).

srsRAN gNB juga jalan dengan v2 (diuji). Sumber kode: `/workspace/oai-eval/shim/sctp2tcp2.c`.

## Soal waktu rfsim vs ZMQ (FAKTA + mekanisme)

1. **Apa yang diukur iperf:** interval iperf3 adalah jam sistem (wall-clock, 1 s). Angka itu memang dilihat aplikasi **di dalam emulator ini**.
2. **Waktu radio di emulator:** rfsim (OAI) dan ZMQ (srsRAN) sama-sama bertukar sampel IQ tanpa jam hardware. Waktu "udara" maju secepat CPU memproses slot:
   - OAI: baris `Frame.Slot` dicetak setiap 128 frame (1,28 s simulasi). Saat idle 128 frame selesai dalam ~0,13 s wall (≈10x). Saat trafik penuh rasionya 2,7–5,1x untuk 1 UE 1x1, 1,2–2,2x untuk 2x2, dan 0,6–1,0 untuk 3 UE 2x2.
   - srsRAN ZMQ: log MAC `[SFN.slot]` vs timestamp wall: 21,6 s simulasi dalam 24,1 s wall, jadi **rasio 0,90** saat UDP DL ~52 Mbit/s.
3. **Akibatnya:** throughput wall = (throughput per detik-simulasi) × rasio.
   - Jika rasio > 1, angka wall **lebih tinggi daripada yang bisa dibawa radio real-time**. Buktinya, (b) 20 MHz 1x1 64QAM menghasilkan TCP DL 202 / UL 219 Mbit/s, di atas batas fisik ~80–90.
   - Jika rasio ≤ 1, emulator sudah terbatas CPU: angka wall ≤ kapasitas radio, dan tetap jujur sebagai batas bawah.
4. **Pembanding jujur:** pakai **throughput per detik-simulasi** (wall / rasio) untuk OAI rfsim jika rasio > 1, atau angka wall jika rasio ≤ 1. srsUE (rasio 0,90) memakai angka wall atau /0,90.
   - Cek silang lewat vrtsim (shared-memory, di-pacing): timescale 1,0 di box menghasilkan "late decode" lalu RLF (tidak ada RT). Timescale 0,5 terkunci tepat di rasio 0,50; UDP DL stabil di 39,2 Mbit/s wall = **~78 Mbit/s air-equivalent** (20 MHz 64QAM, MCS 21–24). Setelah itu UL terkena RLF (PUSCH DTX), jadi stabilitas real-time di box tidak terjamin.
   - Catatan: wall/rasio adalah throughput yang **terkirim** per detik-simulasi. Jika beban tidak menjenuhkan radio (TCP dibatasi RTT simulasi, atau UDP drop di hulu karena UPF userspace dan iperf3 client 100% CPU), angkanya di bawah kapasitas radio.

## Hasil (60 s per tes, 1 UE kecuali disebut; 3 UE 40 s)

Kolom: wall = iperf3 wall-clock (agregat); rasio = detik-simulasi/detik-wall; air = wall/rasio. Semua dalam Mbit/s.

| Konfigurasi | UDP DL wall / rasio / air | UDP UL wall / rasio / air | TCP DL wall / rasio / air | TCP UL wall / rasio / air | MCS (tabel) | CPU gNB / UE (% 1 core) | box busy |
|---|---|---|---|---|---|---|---|
| (a) n78 TDD 30 kHz 106 PRB (40 MHz), 1x1 64QAM | 164 / 2,67 / 61 | 95 / 3,77 / 25 | 140 / 4,27 / 33 | 125 / 3,72 / 34 | 28 (0) | 170–290 / 150–320 | 61–69% |
| (b) n1 FDD 15 kHz 106 PRB (20 MHz, 23,04 Msps), 1x1 64QAM | 188 / 3,51 / 54 | 125 / 2,61 / 48 | 202 / 5,09 / 40 | 219 / 2,85 / 77 | 26–28 (0) | 180–300 / 110–290 | 62–71% |
| (b) vrtsim paced 0,5x | 39,2 wall → **~78 air** (plateau) | RLF | – | – | 21–24 (0) | 34 / 44 | 24% |
| (d) = (a) + 256QAM (uecap) | 232 / 2,88 / **80** | 114 / 3,65 / 31 | 161 / 4,63 / 35 | 172 / 3,85 / 45 | 25–27 (**1**, Qm 8) | 180–300 / 150–280 | 61–70% |
| (c) = (a) + 2x2 + 256QAM (RI 2) | 121 / 1,18 / **103** | 84 / 1,65 / 51 | 108 / 2,15 / 50 | 168 / 1,85 / **91** | 27 (1) | 200–300 / 120–220 | 60–70% |
| (b) 3 UE | 3×33,8 = 101 / 1,79 / 57 | 76 / 1,52 / 50 | 3×54,6 = **164** / 2,38 / 69 | 137 / 2,17 / 63 | 27–28 (0) | 160–260 / 3×55–110 | 64–77% |
| (c) 3 UE | 2 UE: 100 / 0,74 / (CPU-bound) | 28 / 0,63 | 2 UE: 90 / 0,99 / 91 | 3×27,7 = **83** / 0,99 / 84 | 27 (1) | 140–250 / 3× | 60–80% |
| srsUE 23.11 ZMQ (box, run ini) | ~52 wall (offered 80) / 0,90 / ~58 | – | (iperf control error) | – | 28 (64QAM) | – | – |
| srsUE referensi sebelumnya (box) | 1 pasang TCP DL 51,4 (UDP 56,5); 3 pasang agregat 107 | | | | | | |

Stabilitas: BLER 0 dan tidak ada RLF/out-of-sync di semua tes rfsim. Pada (c) 3 UE, satu UE gagal di tes DL karena error kontrol iperf3 ("server busy"/"unable to read"), bukan RLF; data UL ketiga UE lengkap.

### Pembacaan (USULAN/analisis)
- **Angka wall rfsim jangan dipakai sebagai "kapasitas radio".** Untuk laporan PoC, pakai kolom air, atau tes dengan rasio ≤ 1.
- **Per UE jujur:** srsUE ~55–58. OAI 20 MHz 1x1 ~54–78 (setara; 78 saat di-pacing). OAI 40 MHz 256QAM 80. OAI 40 MHz 2x2+256QAM **~100** (UDP DL), dengan UL 2x2 TCP ~90.
- **Agregat jujur di 8 vCPU box:** 3 UE 2x2 mentok CPU di rasio ~1: ~83–90 per arah. Jadi 120–170 real-time belum tercapai di box. Kapasitas radio (c) per sel sebenarnya ~200+ Mbit/s DL (40 MHz, 2 layer, 256QAM); yang membatasi adalah CPU.
- **CPU:** OAI memakai ~4–5,5 core untuk 1 pasang, lebih berat daripada srsRAN per pasang, tetapi membawa throughput per detik-simulasi lebih tinggi. Per core box lebih cepat daripada n2 GCP, jadi di GCP rasionya akan lebih rendah.

## Cara reproduksi (box)

```
# core (container test srs-lab + srs-mongo), AMF dengan shim v2 + HELLO
sudo docker start srs-lab srs-mongo; sudo docker exec srs-lab bash /opt/oaishim/core-up-oai.sh
# subscriber OAI (acak, 0600) -> /workspace/oai-eval/secrets/ (lihat langkah mongosh di log run)
cd /workspace/oai-eval
./runcfg.sh <tag> gnb-a-n78-106.conf "-E" "-E -r 106 --numerology 1 -C 3319680000" 1                      # (a)
./runcfg.sh <tag> gnb-b-n1-fdd15k-106.conf "-E" "-E -r 106 --numerology 0 --band 1 -C 2120450000" 1     # (b)
./runcfg.sh <tag> gnb-d-n78-106-256qam.conf "-E" "-E -r 106 --numerology 1 -C 3319680000 --uecap_file /opt/up/uecap_ports1.xml" 1   # (d)
./runcfg.sh <tag> gnb-c-n78-106-2x2.conf "-E" "-E -r 106 --numerology 1 -C 3319680000 --uecap_file /opt/up/uecap_ports2.xml --ue-nb-ant-rx 2 --ue-nb-ant-tx 2" 3  # (c) 3 UE
./vup.sh gnb-b-n1-fdd15k-106.conf "-E" "-E -r 106 --numerology 0 --band 1 -C 2120450000" 0.5            # vrtsim paced
python3 ratio.py res/<tag>            # rasio simulasi/wall OAI;  srs: python3 srs_ratio.py gnb.log t_start t_end
```

Poin penting konfigurasi:
- gNB di netns `srs-lab` (`--network container:srs-lab`, `LD_PRELOAD` shim), sedangkan UE di netns docker sendiri (`NET_ADMIN`, `/dev/net/tun`) supaya route pool IP UE tidak bentrok dengan antarmuka tun UPF.
- Untuk 256QAM, `--uecap_file` wajib, karena tanpa file itu UE mengirim capability kosong dan gNB memakai tabel 64QAM.
- 2x2 butuh `pdsch_AntennaPorts_XP=2`, `pusch_AntennaPorts=2`, `nb_tx/nb_rx=2`, `do_CSIRS=1`, `do_SRS=periodic`, serta UE `--ue-nb-ant-rx/tx 2`.
- (b) adalah template band 1 mu0 yang diperluas ke 106 PRB. SSB diletakkan di tengah carrier pada raster sync, CORESET0 index 7, dan `min_rxtxtime=6` (kalau tidak, UE assert K2).

## Integrasi ke infra/gcp (USULAN saja, belum dikerjakan)

1. **Prebuild:** tidak perlu build. Pull image OAI v3.0.0 **by digest** di VM core (sekitar 1 GB total). Opsional: mirror ke bucket prebuild agar tidak bergantung pada Docker Hub.
2. **Terraform:**
   - Tetap n2-custom-12, sebaiknya dengan `core_min_cpu_platform` Ice Lake atau lebih baru.
   - Kernel VM GCP punya SCTP, jadi shim **tidak dipakai** di lab.
   - Tambahkan variabel `ran_impl = srsran|oai` (default srsran).
3. **sa scripts:**
   - `sa-config.sh`: mode `sa-oai` membuat `gnb.conf` dari template (a)/(c)/(d) dan `nr-ue.conf` per UE dari subscriber yang ada (0600).
   - `sa-run.sh`/`nr-pairs-run.sh`: unit systemd `docker run` gNB/UE, dengan `--cap-add SYS_NICE --ulimit rtprio=99` (RT tersedia di VM penuh). Urutannya gNB dulu, lalu UE (pola `zmq_pair_up` dipakai ulang).
   - Tes PoC real-time: **vrtsim timescale 1.0** (1 gNB : 1 UE). Untuk multi-UE, rfsim plus laporan rasio wajib (`ratio.py`).
   - `nr_summary.py`: tambahkan rasio simulasi/wall dan kolom air.
4. **Tes:** `tests/radio` diberi tes template config OAI, rasio ≤ 1 (atau dilaporkan), dan keepalive UE (UE tidak boleh idle).
5. **Risiko:**
   - Stabilitas real-time tanpa RT belum terbukti; di box, vrtsim 1,0 RLF.
   - Image `develop`-based (v3.0.0 banner commit 6f89078).
   - CPU 4–5 core per pasang 2x2, jadi di 12 vCPU dengan core Open5GS kemungkinan maksimal 2 pasang 2x2 real-time.

## Kesimpulan
- **FAKTA:** OAI memecahkan blocker srsUE (256QAM dan MIMO jalan, attach stabil, BLER 0).
- **FAKTA:** rfsim membuat angka wall-clock terinflasi 1,2–5x; srsRAN ZMQ tidak (rasio 0,90).
- **USULAN:** pakai OAI 2x2+256QAM (~100 Mbit/s per UE jujur, ~1,8x srsUE). Ukur ulang di GCP 12 vCPU dengan vrtsim real-time (RT aktif) sebelum menjanjikan target 120–170.

## GCP sa-oai (19 Nov 2026, 13:58–14:40 WIB) — OAI 2x2 + 256QAM di n2-custom-12 Ice Lake

Persetujuan: pt242u. Bukti teredaksi: `docs/results/oai-gcp-20261119/` (summary/ratio/rlf/n3drop/gNB stats per tes; log mentah dengan IMSI hanya di box).

### FAKTA — integrasi
- `ran_mode = "sa-oai"` (Terraform + `infra/gcp/sa/oai-config.sh`, `oai-run.sh`, `oai_conf.py`): image resmi OAI v3.0.0 dipull **by digest** (gnb `sha256:170b48…cbd`, nr-ue `sha256:b48219…10f`, sama dengan eval), file upstream dipin sha256, SCTP native (tanpa shim), 2x2 + 256QAM via `--uecap_file uecap_ports2.xml`, 1..3 UE, urutan gNB → UE (BindsTo), keepalive per UE, Ice Lake otomatis (`gfni`/`avx512_vnni` terverifikasi), SCHED_FIFO aktif (`rt=1`, `--cap-add SYS_NICE --ulimit rtprio=99`).
- Bring-up otomatis dari boot: 3 UE dapat IP ~4 s setelah gNB NG-setup; ping internet via UE OK.
- `nr_summary.py`: kolom `sim_ratio` (dari baris `Frame.Slot` gNB) + `air_mbps` (= wall/ratio bila ratio > 1) di setiap tes; UDP iperf3 3.9 (jammy) kini dihitung goodput = offered × (1 − loss).
- vrtsim v3.0.0 multi-UE: server perlu `--vrtsim.num_ues N` + `--vrtsim.ue_config.[k].antennas 2x2` (tanpa itu UE assert `ue.tx_ant == tx_num_channels`), UE `--vrtsim.ue_id k`.
- Validasi offline di box dulu (skrip yang sama + hook uji, shim SCTP): attach 1 UE, TCP DL 140 wall / ratio 2.16, UDP UL 99.7 / ratio 2.0.

### FAKTA — hasil (60 s per arah, Mbit/s; ratio = sim-detik per wall-detik)

| Tes | TCP DL | TCP UL | UDP DL | UDP UL | ratio (DL/UL) | jujur TCP DL |
|---|---|---|---|---|---|---|
| 1 UE rfsim | 106.8 | 122.3 | 244.9 | 128.6 | 1.46 / 1.37 (UDP 1.07 / 1.41) | **73.4** (UDP DL 229.7) |
| 1 UE vrtsim 1.0 | **102.8** | 87.0 | 158.1 | 88.5 | 1.00 | **102.8** |
| 3 UE rfsim | 96.8 (33.4/32.9/30.6) | 54.9 | 169.5 | 71.4 | 0.61 / 0.62 | 96.8 (batas bawah; per sim-detik ~159) |
| 3 UE vrtsim 1.0 | **118.2** (45.7/35.3/37.2) | 88.2 | 221.2 (75.8/72.7/72.7) | 106.3 | 1.00 | **118.2** |

- MCS/RI/BLER: TCP semua tes MCS 27 Qm 8 (256QAM) DL dan UL, CQI 15, RI 2, UL-RI 2, BLER 0.
- RLF 0, N3 drop 0 % di semua tes. Keepalive aktif untuk 1 dan 3 UE.
- CPU (% dari 1 vCPU) dan VM busy: 1 UE vrtsim TCP DL nr-uesoftmodem 187 / nr-softmodem 139, busy 27 %. 3 UE vrtsim UDP DL 565 / 269, busy 79 % (maks 81 %).
- vrt10 UDP DL (offered 300M): goodput 158 (loss ~47 %). HARQ retx 4756/2014/610, 147 dlsch_errors, PUCCH DTX 6921 (SNR PUCCH tidak valid), artinya UE (385 % CPU) melewatkan deadline HARQ-ACK real-time saat overload. TCP (beban adaptif) bersih: retx 20/22, DTX 20.
- 5 baris late/underflow di vrt10: di segmen gNB selama iperf ada 0 baris. Sumbernya (gNB di luar jendela iperf atau log UE) tidak bisa diatribusi karena log UE sudah dirotasi oleh start berikutnya. Tidak ada RLF.
- Angka rlf 3 / late 319 di rf1 adalah false positive pola srsRAN pada log OAI ("RRC Released RLC entity" saat shutdown, "cumuLATEd bad DCI"). Sudah diperbaiki: `nr-health.sh` memakai pola khusus OAI, dan log dirotasi per start.

### FAKTA — perbandingan vs srsUE Ice Lake (TCP DL, run 4)
- 1 pair: srsUE 52.5 → OAI vrtsim real-time 102.8 (**1.96×**); rfsim jujur 73.4 (1.40×).
- 3 pair/UE: srsUE 79.3 → OAI vrtsim 118.2 (**1.49×**); rfsim 96.8 (1.22×, batas bawah).

### FAKTA — biaya dan audit
- vm-core-ran hidup ~40.5 menit (apply 13:59:56, destroy selesai 14:40:23 WIB) ≈ USD 0.55 (estimasi tarif list). Kumulatif ≈ **USD 12.05** (< 13).
- Destroy 165/165. State 0. Sisa: build-vm-01 (TERMINATED, tidak disentuh), resource netprobe/booster, bucket state + cloudbuild (pra-ada). Bucket runs terhapus. Tidak ada perubahan IAM/VNC/tunnel.

### USULAN
1. Default PoC: `ran_mode = "sa-oai"`, `oai_rf = "vrtsim"` (real-time, ratio 1.00 terverifikasi untuk 1 dan 3 UE), `oai_mimo = 2`. rfsim hanya untuk debugging, selalu dilaporkan dengan ratio.
2. Uji UDP pakai offered ≤ ~150M/UE (1 UE) atau ~75M/UE (3 UE) agar UE tidak overload HARQ. Bila perlu throughput lebih, pin nr-uesoftmodem ke core terpisah dari gNB.
3. Simpan log UE per tes (jangan hanya rotasi .1) supaya baris late/underflow bisa diatribusi.
