# Radio uplift: Fase 0 (offline) hasil dan rencana tes lab Fase 1-2

Status 19 Nov 2026 (WIB). Semua offline, lokal, tanpa push. Tidak ada apply, tidak ada akses ke state Terraform atau VM.
Keputusan user (via PM, 19 Nov 08:02 WIB): target radio 120-170 Mbit/s; core diuji dengan beban non-radio; split 8+4 vCPU, emulator mati saat sesi radio-only; mulai Fase 0 offline; naikkan batas biaya harian untuk fase lab; UE Amarisoft diabaikan; prioritas radio uplift dulu (Sesi E sesudahnya). Budget tetap 12 vCPU, tanpa kenaikan kuota.
Label: **FAKTA** = ada di repo/hasil tes offline. **USULAN** = rencana atau estimasi.

## 1. Yang dikerjakan di Fase 0 (FAKTA)
| Area | Perubahan |
|---|---|
| Terraform `variables.tf` | validasi `core_machine_type` menerima `n2-custom-<2..12>-<MB>` selain n2-standard (split 8+4 sudah sah); variabel baru `emu_enabled` (default true), `nr_pairs` (1..3, default 1), `nr_exclude_zmq_from_n3_tap`, `vcpu_budget` (12) |
| Terraform `compute.tf` | `emu` memakai `count` + blok `moved` (alamat state lama otomatis dipindah, default tanpa diff); metadata `nr-pairs` dan `nr-n3-tap-bpf-only` hanya ditambahkan bila `nr_pairs > 1`; precondition `nr_pairs>1` hanya untuk `sa-srsran`; `check "vcpu_budget"` memperingatkan bila total vCPU VM > 12 |
| Terraform `outputs.tf`, `terraform.tfvars.example` | output `vm-emu` kondisional + `vcpu_total`; contoh profil P1/P2/P3 |
| `infra/gcp/sa/` | `gnb-pair.yaml.tmpl`, `ue-pair.conf.tmpl`, `nr-pairs-config.sh` (render 1-3 pasang + provisioning subscriber Open5GS untuk pasangan 2..N), `nr-pairs-run.sh` (start/stop/status, taskset per pasangan, keepalive ping 1/s per UE, pin NF Open5GS ke CPU core), `nr_cpu_plan.py`, `nr-iperf-run.sh` + `nr_summary.py` (iperf3 per pasangan + agregat, sampler CPU, verdict PASS/FAIL), `core-load-ueransim.sh` + `core_load_plan.py` (Fase 4) |
| `sa/sa-up.sh` | bila metadata `nr-pairs` > 1 dan `sa-srsran`: pakai nr-pairs-config/run, bukan sa-run.sh (default tidak berubah) |
| `sesi-d/zeek-taps.sh` | BPF N3 dibangun dari `ENB_IPS` (banyak gNB bind) + `N3_EXCLUDE_ZMQ=1` (default) menolak `tcp portrange 2000-2299`; perilaku lama untuk 1 gNB setara |
| `tests/radio/` | 14 unit test Python + `run-all.sh` (bash -n, shellcheck, terraform validate di salinan dengan `-backend=false`, uji console variabel) |

Skema pasangan i: ZMQ 2000+10(i-1) (tx) / +1 (rx), bind N2/N3 127.0.1.i, PCI i, gnb_id 410+i, netns `ue<i>`, tun `tun_srsue` (i=1) / `tun_srsue<i>`, IMSI 00101+MSIN acak per pasangan (kredensial di `/root/lab5g-pairs.env` 0600, tidak pernah dicetak). Pasangan 1 = profil lama (ue1, tun_srsue, 127.0.1.1) sehingga Zeek tap, QoD, dan sesi-d tetap jalan.

Tes (FAKTA, dijalankan 19 Nov): `tests/radio/run-all.sh` -> ALL OK: bash -n, shellcheck -S warning bersih, 14 test Python lulus, `terraform fmt -check` + `validate` sukses, `nr_pairs=4` ditolak, 8+4 dan custom-12 dengan emu mati dihitung 12 vCPU.

Batas yang harus dipahami (FAKTA/jujur):
- **Belum ada uji di lab.** Semua skrip lab dieksekusi hanya dengan `DRY_RUN`/render offline. Perilaku srsRAN 3 gNB ke satu AMF, SCTP bind 127.0.1.i, dan UERANSIM multi-proses belum terbukti.
- Opsi "keluarkan ZMQ dari tap N3" = filter BPF (kernel menolak paket non-GTP-U di socket tap) + opsi `N3_EXCLUDE_ZMQ`. Aliran I/Q tetap melewati `lo`; isolasi penuh (ZMQ lewat veth/netns terpisah) belum dikerjakan, jadi USULAN eksperimen di Fase 1 bila drop N3 > 5%.
- Tap Zeek `ue` hanya untuk `ue1` (pasangan 1). Latency per segmen MGLT multi-UE tidak dicakup; sesi radio-only mengukur throughput.
- VM UE terpisah (P2 dengan 2 VM) tidak ada IaC; semua pasangan jalan di satu VM core (n2-standard-8 lalu n2-custom-12).

## 2. Kalibrasi ulang QoD HTB (USULAN, dari `sesi-c/qod-tc.py`)
FAKTA: satu bottleneck R per arah (HTB 1:1 pada `ogstun` untuk DL, `ifb0` untuk UL), kelas QoD 1:10 prio 0 (rate = max(30% R, sum GBR), maks 80% R), bulk 1:20 prio 1, `r2q 10`, pfifo `--depth`. Uji lama memakai R DL 15 / UL 8 Mbit/s.
Saat radio naik ke 55-170 Mbit/s:
1. **R harus tetap di bawah kapasitas radio** supaya antrean terbentuk di SGi (inti uji QoD): R_DL ~ 0,85 x DL agregat terukur (mis. 3 pasangan 165 -> `--dl 140mbit`; 1 pasangan 57 -> 48mbit), R_UL ~ 0,85 x UL agregat. Ukur dulu (tanpa shaper), baru setel.
2. **`r2q`**: quantum HTB = rate/8/r2q; pada R >= 100 Mbit/s dengan `r2q 10` quantum > 60 KB (peringatan HTB, ketidakadilan). Naikkan `r2q` ke 100-200 atau set `quantum 6000` eksplisit di kelas.
3. **Kedalaman pfifo** ~ BDP: depth(paket) ~ R x RTT_target / 1500 B (R=140 Mbit/s, 50 ms -> ~580 paket; default 100 terlalu kecil -> drop dini, terlalu besar -> bufferbloat yang justru diukur).
4. **Banyak UE**: filter QoD per `ueIpv4`; semua sesi berbagi 1 kelas 1:10, jadi jumlah sesi GBR = floor(0,8 R / (1,1 GBR)) (mis. R 140, GBR 5 -> 20 sesi). Tes QoD multi-UE: tetapkan UE mana yang mendapat QoD; UE lain = beban bulk.
5. Zeek tap `sgiq` (mirror nft dup) memproses beban lebih tinggi: pantau capture loss; pada >100 Mbit/s agregat 1 worker Zeek (~0,8-1 Gbit/s) cukup tapi CPU-nya bersaing dengan RAN (lihat alokasi).
6. Jalankan QoD hanya pada profil P1 (ada emulator + tap lengkap). Sesi radio-only P2/P3 tanpa QoD/shaper (ukur kapasitas bersih).

## 3. Rencana tes lab Fase 1-2 (USULAN)
Prasyarat: matriks v0.10.2 selesai dan lab lama destroy; persetujuan apply dari user dengan kata-katanya; nilai batas biaya harian yang disetujui. Satu sesi apply berurutan (menghemat boot):

| Langkah | Konfigurasi | Isi | Kriteria lulus | Waktu | vCPU aktif | Biaya |
|---|---|---|---|---|---|---|
| S0 apply + boot | core n2-standard-8 + emu n2-standard-4 (12), `ran_mode=sa-srsran`, `nr_pairs=1`, prebuild srsRAN | bring-up, attach SA | UE IP didapat, ping ok, `vcpu_total=12` | 0,4 jam | 12 | 0,31 |
| F1 | sama, 1 pasangan + AVD | iperf3 dl/ul 60 s x3 (nr-iperf-run.sh), YouTube 5 menit di AVD (4 core), CPU sampler | DL >= 50 / UL >= 50 Mbit/s; late/underflow ~0; CPU < 85%; AVD stall 0 dan tidak RLF; jika AVD gagal di 4 core -> catat, lanjut tanpa AVD | 0,75 jam | 12 | 0,59 |
| F2a | stop vm-emu (`gcloud compute instances stop`, bukan terraform); core 8 vCPU; `nr_pairs=2` | 2 pasangan, iperf3 paralel | tiap pasangan >= 50, agregat DL >= 100, CPU < 85%, RLF 0 selama 5 menit, keepalive aktif | 0,5 jam | 8 | 0,26 |
| R resize | `emu_enabled=false`, core `n2-custom-12-49152`, `nr_pairs=3` (apply terarah ke core; ~5 menit stop/start) | | `vcpu_total=12`, core hidup | 0,2 jam | 0 (core stop) | ~0,0 |
| F2b | 3 pasangan, 12 vCPU, emulator tidak ada | iperf3 dl/ul 60 s x3 + sesi 5 menit stabilitas | tiap pasangan >= 50, agregat DL >= 150, UL agregat >= 150, CPU < 85%, RLF 0, drop tap N3 < 5% | 0,6 jam | 12 | 0,47 |
| S9 destroy + audit | | destroy, audit resource, build-vm-01/netprobe tak tersentuh | audit bersih | 0,2 jam | ~0 | 0,05 |

Total Fase 1+2 (USULAN, estimasi): **~2,65 jam, ~USD 1,8 (+0,1 disk/NAT/snapshot) = ~USD 1,9**. Dasar harga: n2 ~USD 0,065/vCPU-jam (12 vCPU ~USD 0,78-0,80/jam); disk dan egress tidak dihitung rinci. Dengan kontingensi 50% (pengulangan, debugging srsUE, resize): **~USD 2,9, ~4 jam**.
Fase 3 (LTE 2x2): +~USD 1,6-2 / 2 jam (belum disiapkan). Fase 4 (beban core UERANSIM): ~USD 1,2 / 1,5 jam, hari terpisah.
Jika F2b gagal (CPU > 85% atau pasangan < 50): turun ke 2 pasangan sebagai hasil final dan catat per-pasangan CPU; target 120-170 tetap tercapai di batas bawah (2 pasangan ~110-115, tidak sepenuhnya 120: dilaporkan jujur).

Eksekusi tiap langkah: `nr-pairs-run.sh start <N>`, `nr-iperf-run.sh <N> <outdir> both` (JSON per pasangan + `summary.json` verdict), ambil hasil, lalu `nr-pairs-run.sh stop`. Peringatan kritis: UE tidak boleh idle: keepalive (ping 1/s per netns) distart otomatis; cek `nr-pairs-run.sh status`.

## 4. Biaya hari ini dan batas harian yang disarankan (USULAN)
- Pengeluaran hari ini (angka dari parent/PM): ~USD 7,2 + matriks v0.10.2 yang sedang berjalan ~USD 2,5 = **~USD 9,7** dari batas lama USD 12 (sisa ~2,3, tidak cukup untuk kontingensi Fase 1+2).
- Rekomendasi: **batas harian USD 15 untuk hari ini** (9,7 + 2,9 rencana dengan kontingensi + ~2,4 buffer), hard stop di 15 dan laporan ke user di USD 13. Fase 3 dan 4 dijalankan di hari berbeda dengan batas USD 12 biasa, atau naikkan ke 15 bila user ingin digabung (Fase 1+2+4 = ~USD 4,1 + 9,7 = 13,8, muat di 15 tanpa kontingensi penuh).
- Angka final batas adalah keputusan user.

## 5. Keputusan yang masih dibutuhkan dari user
1. Setuju batas harian USD 15 (hari ini) untuk Fase 1+2?
2. Waktu mulai (setelah matriks v0.10.2 selesai dan destroy) dan persetujuan apply eksplisit.
3. Boleh mengubah ukuran core ke `n2-custom-12-49152` (stop/start core sekitar 5 menit) pada langkah R? Alternatif: lewati 3 pasangan, final di 2 pasangan (8 vCPU).
4. Boleh menurunkan emulator ke 4 vCPU di F1, dengan risiko AVD tidak stabil (diukur, bukan diasumsikan)?
