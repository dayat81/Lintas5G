# srsRAN 5G SA attach: perbaikan offline + re-run radio uplift Fase 1/2a/2b (19 Nov 2026, WIB)

**Verdict:** attach SA **diperbaiki** (FAKTA: NG setup, RRC connected, PDU session, `tun_srsue` ber-IP, ping, iperf3 di box dan di GCP Cascade Lake). Target throughput Fase 2 (≥50 Mbit/s per pasangan, agregat ≥150) **tidak tercapai**: radio ZMQ srsRAN terikat-proses (processing-bound), maksimal ~54 Mbit/s agregat DL di 12 vCPU. Lab sudah destroy, audit bersih, tidak ada commit/push.

## 1. Akar masalah (FAKTA, direproduksi di box)
1. **UE macet di "Attaching UE..." = deadlock ZMQ REQ/REP**, bukan versi atau `ue.conf`. Prebuild lama (gNB 24.10.1 + srsUE 23.11) attach normal di box bila gNB start duluan. Deadlock terjadi bila (a) srsUE start sebelum gNB bind port ZMQ tx, atau (b) hanya satu sisi yang restart (systemd `Restart=on-failure`, restart UE manual). Gejala identik dengan lab: gNB `zmq:tx Waiting for request` / `zmq:rx ... 0 of 11520`, UE `NAS5G DEREGISTERED/PLMN-SEARCH`, PHY-SA `IDLE` (thread PHY terblokir di recv pertama, `plmn_search` tidak pernah dipanggil). Di lab: `sa-run.sh` hanya `sleep 5` lalu start UE (log: "NG setup not yet confirmed", stdout gNB juga ter-buffer), lalu restart UE manual memperparah.
2. **QoS flow ke-2 memutus UE**: rule PCC statis (5QI 7/QFI 2) memicu PDU Session Modification, srsUE 23.11: `Configuring SDAP: only UL headder is supported ... number of QoS flows must be 1` → RRC reconfiguration failure → RRC Release.
3. **SIGILL Cascade Lake**: `AUTO_DETECT_ISA=OFF` tidak cukup; kedua proyek tetap menambah `-march=native` (srsRAN_Project `MARCH`, srsRAN_4G `GCC_ARCH`). Tarball v1: ~20 rb instruksi AVX512 di 570 fungsi generik.

## 2. Perbaikan (file berubah, belum commit)
- `infra/gcp/sa/zmq-pair-lib.sh` (baru): start berurutan gNB → tunggu `==== gNB started` + port ZMQ tx listen → UE (`BindsTo` gNB), tanpa auto-restart per proses, retry seluruh pasangan (3x). Dipakai `sa-run.sh` dan `nr-pairs-run.sh` (stdout via `stdbuf -oL`).
- `sa-config.sh`, `nr-pairs-config.sh`: PCC statis opt-in `SA_STATIC_PCC=1` (default 0). `sa-qfi-proof.sh`: catatan butuh UE multi-flow.
- `nr-pairs-run.sh`: default `NR_PIN=0` (CPU RAN dibagi bersama; pinning per proses menurunkan throughput, lihat §4), `NR_HEAVY`, perbaikan panggilan `status`. `nr_cpu_plan.py`: opsi `heavy` (default gnb). `nr_summary.py`: abaikan proses zombie.
- `infra/gcp/prebuild/build-srsran.sh`: `-DMARCH/-DMTUNE`, `-DGCC_ARCH`, gerbang ISA (tanpa `-march=native`; AVX512 hanya di kernel `*avx512*` yang dipilih runtime oleh `cpu_architecture_info`). `box-sctp2tcp.c`: shim LD_PRELOAD SCTP→TCP khusus uji di box (kernel box tanpa SCTP), tidak dipakai di VM.
- `terraform/variables.tf`: deskripsi `ran_prebuild_object` / `core_min_cpu_platform` (default kosong cukup).
- Tes: `tests/radio/run-all.sh` **ALL OK** (17 tes, + shellcheck `zmq-pair-lib.sh`, `sa-run.sh`).

## 3. Prebuild baru (FAKTA)
`srsran-release_24_10_1-release_23_11-x86-64-v3-jammy-x86_64.tar.zst`, sha256 `d267186f48b21128e6d5eb39a9c1b92113ab37733e33cf00f923446e2e274a27` (box: `/workspace/prebuild-out/`). objdump: gnb AVX512 generik 0 (1129 hanya di kernel `*_avx512` ber-dispatch runtime), srsue/libsrsran_rf_zmq 0. **Terbukti jalan di GCP `Intel Cascade Lake`** tanpa `min_cpu_platform`.

## 4. Hasil (FAKTA). TCP iperf3 60 s kecuali disebut; CPU = % satu vCPU
| Fase | Mesin | Pasangan | DL per UE | DL agregat | UL agregat | CPU gNB / UE per pasangan | Busy VM | RLF | N3 drop |
|---|---|---|---|---|---|---|---|---|---|
| Box | 8 vCPU box | 1 | UDP 56,5 / TCP 51,4 | - | - | 182 / 135 | - | 0 | - |
| Box | 8 vCPU box | 3 (pin 1+1) | 35,6-35,9 | 107,2 | 110,0 | 100 / 84 | 73% | 0 | - |
| F1 | n2-standard-8 (CL) + emu n2-4 | 1 | 35,5 (UDP 40,9) | 35,5 | 29,2 | 232 / 255 | 64% | 0 | 0% |
| F2a pin | n2-standard-8, emu stop | 2 | 16,2 / 12,0 | 28,2 | 35,6 | 165 / 80 | 64% | 0 | 0% |
| F2a shared | n2-standard-8 | 2 | 18,9 / 19,0 | 37,9 | 37,6 | 130 / 128 | 69% | 0 | - |
| **F2b** | **n2-custom-12 (CL)** | **3** | **17,8-18,0** | **53,8** | **54,1** | 127 / 130 | 68% | **0** | **0%** |

Sweep 1 pasangan (GCP 8 vCPU, UDP 20 s): (a) baseline FDD n3 20 MHz 106 PRB 64QAM: DL 39,8 / UL 36,7 / TCP DL 34,9; gNB MAC 59 Mbit/s, MCS 28, BLER 0%; UDP 45M/55M ditawarkan → diterima 39,5/39,9 (batas sisi pemrosesan UE). (b) qam256: gNB menolak dengan DCI fallback; dengan DCI 1_1 srsUE crash. (c) sudah FDD n3; TDD tidak diuji (arahan user). (d) PRB 106 + MCS 28 + BLER 0 sudah maksimal; srsUE `nof_phy_threads=6` crash. (e) ZMQ `ipc://`: gNB 24.10 menolak ("does not describe a valid TCP socket"), tetap tcp. MIMO 2x2 (2 kanal ZMQ): gNB menolak `Nof. DL antennas 2 ... fallback DCI`, dan DCI 1_1 membuat srsUE crash → tidak layak dengan srsUE 23.11.
**Konfigurasi terbaik (default template):** FDD n3, 20 MHz, 64QAM, DCI fallback, ZMQ tcp, `NR_PIN=0`, PCC off.

Interpretasi (USULAN): VM tidak jenuh (busy ~68%) tetapi throughput tidak naik linear; rantai ZMQ lock-step gNB↔UE terikat latensi pemrosesan per slot (srsUE stack/PHY), Cascade Lake 2,8 GHz ~30% lebih lambat dari box. Batas 12 vCPU dengan srsUE: ~54 Mbit/s DL agregat (3 pasangan) vs 35 (1 pasangan), +52%.

## 5. Biaya dan audit
Lab hidup 11:18-12:08 WIB: core 8 vCPU ~0,65 jam + 12 vCPU ~0,17 jam + emu 4 vCPU ~0,18 jam ≈ 7,9 vCPU-jam ≈ **USD 0,55-0,6**; kumulatif hari ini **~USD 10,8** (< 13). Destroy 163 resource rc=0, state 0. Sisa di project hanya milik non-lab: `build-vm-01` (TERMINATED) + disk + snapshot-nya, bucket state, alamat/firewall netprobe/booster, firewall default. Bucket runs dan SA lab terhapus. Tidak ada perubahan IAM/VNC/tunnel di luar Terraform lab.

## 6. Bukti
`docs/results/radio-uplift-20261119-run2/` (summary/rlf/n3drop JSON per fase, cuplikan attach, penolakan config gNB, times.log). Log lengkap di box: `/workspace/radio-uplift/logs/run2/radio-logs.tgz` (tidak di-commit).

## 7. Langkah berikutnya (USULAN, butuh persetujuan)
1. Jika target 120-170 Mbit/s tetap wajib: UE lain (mis. UERANSIM tidak memodelkan radio; Amarisoft/OAI nrUE rfsim mendukung 256QAM/MIMO) atau LTE srsRAN_4G 2x2 (Fase 3).
2. Commit/PR perubahan ini setelah review user.

## 8. Rerun CPU lebih cepat: Ice Lake vs Cascade Lake (19 Nov 2026 12:14-12:39 WIB, persetujuan user "setuju usulan")
**Setup (FAKTA):** `vm-core-ran` n2-custom-12-49152, `core_min_cpu_platform="Intel Ice Lake"`, cpuPlatform terverifikasi "Intel Ice Lake", lscpu "Intel(R) Xeon(R) CPU @ 2.60GHz", 12 vCPU, flag avx512f + avx512_vpopcntdq (kernel AVX512 srsRAN aktif via runtime dispatch). Emulator tidak dibuat (`emu_enabled=false`), total 12 vCPU, tanpa kenaikan kuota. Prebuild portabel x86-64-v3 yang sama. Config terbaik: FDD n3 20 MHz, 64QAM, ZMQ tcp, `NR_PIN=0`, PCC off, zmq-pair-lib. Keepalive UE aktif.
Keluarga lebih baru (c3/n4) tidak dipakai: validasi Terraform `core_machine_type` hanya mengizinkan n2, dan c3 tidak punya bentuk 12 vCPU. Uji 4 pasangan tidak dijalankan: `nr-pairs-config.sh` membatasi N=1..3 (mengubahnya = perubahan template di luar scope).

| Uji | Platform | Pasangan | DL per UE | DL agregat | UL per UE | UL agregat | CPU gNB / UE per pasangan (DL) | Busy VM | RLF | N3 drop | MCS / BLER |
|---|---|---|---|---|---|---|---|---|---|---|---|
| 1 pasangan TCP 60 s | Ice Lake 12 vCPU | 1 | **52,5** | 52,5 | **53,9** | 53,9 | 179 / 174 | 32% | 0 | 0% | DL 28 / 0%, UL 28 / 0% |
| 1 pasangan UDP 20 s @60M | Ice Lake 12 vCPU | 1 | **55,9** | 55,9 | **58,3** | 58,3 | 179 / 172 | - | 0 | - | sama |
| 1 pasangan TCP (pembanding) | Cascade Lake 8 vCPU (F1) | 1 | 35,5 (UDP 39,8-40,9) | 35,5 | 29,2 (UDP 36,7) | 29,2 | 232 / 255 | 64% | 0 | 0% | DL 28 / 0% |
| **3 pasangan TCP 60 s** | **Ice Lake 12 vCPU** | 3 | **25,6-26,0** | **77,5** | **26,4-26,8** | **79,8** | 128 / 131 | 68% | 0 | 0% | UL 28 / 0% (pair1) |
| 3 pasangan (F2b pembanding) | Cascade Lake 12 vCPU | 3 | 17,8-18,0 | 53,8 | 17,9-18,1 | 54,1 | 127 / 130 | 68% | 0 | 0% | - |

**Perbandingan (FAKTA):** 1 pasangan DL +48% (35,5→52,5), UL +85% (29,2→53,9), dengan CPU per proses lebih rendah (gNB 232→179%, UE 255→174%). 3 pasangan agregat DL +44% (53,8→77,5), UL +47% (54,1→79,8); per UE ~18→~26 Mbit/s. late/underflow 0, RLF 0, N3 drop 0% di semua uji.
**Interpretasi (USULAN):** throughput srsRAN ZMQ terikat latensi pemrosesan per slot single-thread (gNB/srsUE lock-step), bukan jumlah vCPU: Ice Lake + AVX512 dispatch memberi ~+45% pada vCPU yang sama, sedangkan busy VM tetap ~68% di 3 pasangan. 1 pasangan di Ice Lake ≈ box (51-56 Mbit/s), jadi ini mendekati plafon per UE srsUE 23.11 (MCS 28, 106 PRB, 64QAM, SISO ≈ 59 Mbit/s MAC). Rekomendasi: jadikan `core_min_cpu_platform="Intel Ice Lake"` default untuk sesi radio (USULAN, butuh persetujuan; biaya sama dengan n2 lain).

**Biaya dan audit:** lab hidup 12:14-12:39 WIB (~0,42 jam × 12 vCPU + 48 GB) ≈ **USD 0,35-0,45**; kumulatif hari ini **~USD 11,2** (< 13). Destroy 162 resource rc=0, state 0. Sisa di project hanya non-lab: `build-vm-01` (TERMINATED) + disk + snapshot, bucket state + netprobe + cloudbuild, alamat/firewall netprobe/booster, firewall default. Tidak ada perubahan IAM/VNC/tunnel, tidak ada commit/push.
**Bukti:** `docs/results/radio-uplift-20261119-run3/` (summary/rlf/n3drop JSON, cuplikan metrik gNB, p3.tfvars.redacted, times.log; IMSI/IP/project disamarkan). Log lengkap di box: `/workspace/radio-uplift/logs/run3/radio-logs.tgz` (tidak di-commit).

## 9. Uji 4 pasangan + Ice Lake default (19 Nov 2026 12:42-12:58 WIB, persetujuan user "Approved" t240u)
**Perubahan template (FAKTA, belum commit; `tests/radio/run-all.sh` ALL OK, 20 test python):**
- `terraform/variables.tf` + `compute.tf`: `core_min_cpu_platform` default `null` = otomatis → `"Intel Ice Lake"` bila `ran_mode=sa-srsran`, default GCP untuk mode lain (tidak ada diff untuk lab default `epc-srsran4g`); `""` = paksa default GCP. `nr_pairs` 1..4.
- `sa/nr-pairs-config.sh` N=1..4 (kredensial pair 4 ditambahkan ke `/root/lab5g-pairs.env` lama tanpa mengubah pair 2..3; ZMQ pair 4 = 2030/2031, PCI 4); `sa/nr_cpu_plan.py` 1..4; `sa/nr-pairs-run.sh` unit 1..4 + **perbaikan celah bootstrap**: `start N` merender config per pasangan bila ada yang hilang (dulu `nr_pairs=1` boot lewat sa-run.sh → `pair<i>/gnb.yaml was not readable`); `sa/nr_summary.py` ambang agregat 4 pasangan 170 Mbit/s (batas atas target PM).
- `tests/radio/`: plan 4 pasangan, render 4 pasangan, N=5 ditolak, uji celah bootstrap, ambang 4 pasangan, cek platform terraform (sa-srsran → Ice Lake, default → GCP, `""` → GCP), `nr_pairs=5` ditolak.

**Setup GCP (FAKTA):** n2-custom-12-49152, platform Ice Lake dari default baru (tanpa set var), "Intel(R) Xeon(R) CPU @ 2.60GHz", emulator tidak dibuat, `nr_pairs=4` → keempat pasangan attach otomatis saat boot (gNB siap 3-5 s, UE IP 3-6 s), keepalive 4/4. Config terbaik sama (FDD n3 20 MHz, 64QAM, ZMQ tcp, NR_PIN=0, PCC off).

| Uji (sesi sama) | Pasangan | DL per UE | DL agregat | UL per UE | UL agregat | CPU gNB / UE per pasangan (DL; UL) | Busy VM | MCS / BLER | RLF | N3 drop | late/underflow |
|---|---|---|---|---|---|---|---|---|---|---|---|
| TCP 60 s | **4** | 18,7-18,9 | **75,1** | 18,1-18,4 | **73,0** | 95 / 89-92; 110-112 / 72-75 | 65% | - | 0 | 0% | 0 |
| UDP 20 s @40M/UE | **4** | 23,3-23,7 | **93,9** | 20,3-20,7 | **81,9** | - | 71% / 67% | DL 28 / 0%, UL 27,6 / 0% (4 pasangan) | 0 | - | 0 |
| TCP 60 s (baseline) | 3 | 26,2-26,6 | **79,3** | 26,7-26,8 | **80,2** | 130-131 / 130-132; 152-154 / 101-106 | 69% | - | 0 | 0% | 0 |
| TCP 60 s (run3, VM lain) | 3 | 25,6-26,0 | 77,5 | 26,4-26,8 | 79,8 | 128 / 131 | 68% | DL/UL 28 / 0% | 0 | 0% | 0 |

**Kesimpulan (FAKTA):** 4 pasangan tidak menaikkan agregat TCP (75,1 vs 79,3 DL, 73,0 vs 80,2 UL; -5%/-9%) dan per UE turun 26 → 19 Mbit/s; busy VM tetap ~65-70%, MCS 28 dan BLER 0% (bukan batas radio). UDP 4 pasangan memberi 93,9 DL agregat (lebih tinggi dari TCP karena tanpa kendali kongesti TCP), tidak ada pembanding UDP 3 pasangan di sesi ini.
**Interpretasi (USULAN):** plafon 12 vCPU dengan srsUE/ZMQ ≈ 80 Mbit/s TCP agregat; 3 pasangan adalah titik optimal (per UE ~26 Mbit/s). Pasangan ke-4 hanya membagi waktu proses yang sama (setiap gNB/UE turun ke ~1 vCPU). Rekomendasi default: `nr_pairs=3` di Ice Lake; 4 pasangan hanya bila butuh lebih banyak UE, bukan throughput.

**Biaya dan audit:** lab hidup 12:42-12:58 WIB (~0,27 jam, 12 vCPU + 48 GB) ≈ **USD 0,25-0,3**; kumulatif hari ini **~USD 11,5** (< 13). Destroy 162 resource rc=0, state 0. Sisa hanya non-lab: `build-vm-01` (TERMINATED) + disk + snapshot, bucket state/netprobe/cloudbuild, alamat/firewall netprobe/booster, firewall default, SA pra-ada. Tidak ada perubahan IAM/VNC/tunnel, tidak ada commit/push.
**Bukti:** `docs/results/radio-uplift-20261119-run4/` (summary/rlf/n3drop JSON, metrik gNB, boot 4 pasangan, p4.tfvars.redacted, times.log; IMSI/IP/project disamarkan). Log lengkap di box: `/workspace/radio-uplift/logs/run4/radio-logs.tgz`.
