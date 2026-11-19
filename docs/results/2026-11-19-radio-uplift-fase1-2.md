# Radio uplift Fase 1+2: hasil 19 Nov 2026 (WIB)

**Verdict: INCOMPLETE / BLOCKED.** Tidak ada satu pun angka throughput. srsUE NR SA tidak pernah attach, jadi Fase 1, 2a, resize, 2b tidak dijalankan. Lab sudah di-destroy dan audit bersih. Tidak ada commit atau push.

## Garis waktu (box clock WIB)
| Waktu | Kejadian |
|---|---|
| 09:50 | Prakondisi terpenuhi: matriks selesai dan destroy, state kosong, tidak ada proses atau lock Terraform |
| 09:52-09:54 | Apply P1 (core n2-standard-8 + emu n2-standard-4 = 12 vCPU, `sa-srsran`, `nr_pairs=1`): 162 resource dibuat. Tarball prebuild di-upload ke bucket runs dalam ~1 menit setelah bucket dibuat |
| 09:55-09:59 | Install SA (Open5GS, Zeek, prebuild) selesai; **gNB SIGILL** |
| 10:01-10:03 | Perbaikan: `core_min_cpu_platform = Intel Ice Lake` (apply in-place hanya core, stop/start ~70 s) |
| 10:03-10:17 | gNB hidup dan N2 NG Setup ke AMF berhasil, tetapi **UE tidak pernah mulai cell search** |
| 10:18-10:21 | Destroy: 162 resource dihapus, rc=0 |

## Temuan (FAKTA)
1. **Prebuild srsRAN (gNB 24.10.1) crash SIGILL di Cascade Lake.** gdb: `vpopcntq zmm` di `cpu_architecture_info::discover_cpu_architecture()`, yaitu AVX512 VPOPCNTDQ yang hanya ada di Ice Lake+. Binary dibangun di host berprosesor Ice Lake+ walau `-march=x86-64-v3`. Perbaikan di IaC: variabel `core_min_cpu_platform` (default kosong, tidak mengubah perilaku lama). `Intel Ice Lake` tersedia di asia-southeast2-a. Setelah itu gNB berjalan stabil (~135% CPU idle di 20 MHz) dan terhubung ke AMF.
2. **srsUE 23.11 (prebuild) tidak memulai cell search di SA.** Gejala:
   - NAS5G masuk `DEREGISTERED / PLMN-SEARCH`, lalu tidak ada tindakan apa pun. PHY-SA tetap `state=IDLE`. Tidak ada log RRC, SYNC, atau Cell Search.
   - Breakpoint gdb pada `phy_nr_sa::start_cell_search` dan `rrc_nr::plmn_search` tidak pernah tercapai selama 20 detik.
   - Terjadi juga dengan gNB mati, urutan start UE dulu atau gNB dulu, dan dengan `ssb_nr_arfcn`, `dl_nr_arfcn`, dan `slicing` eksplisit.
   - Konfigurasi UE sama dengan tutorial srsRAN Project (`[rat.eutra] nof_carriers=0`, `[rat.nr] bands=3, nof_carriers=1, 106 PRB`, `release=15`, `ue_category=4`, `srate` dan `base_srate=23.04e6`).
   - Link ZMQ terbentuk (kedua soket ESTAB), tetapi gNB hanya menampilkan `Waiting for request` dan `Waiting for reading samples 0 of 11520`.
3. Ini pertama kalinya SA srsUE dijalankan di lab. Sebelumnya prebuild hanya divalidasi di box (config terparse, plugin ZMQ aktif). Catatan srsRAN: ekstensi 5G di srsUE tidak lagi aktif dikembangkan.

## Deviasi dan isu
- Apply menyimpang dari rencana: ditambah satu apply in-place untuk `min_cpu_platform` (Ice Lake). Tidak ada recreate jaringan atau IAM.
- Fase 1 (1 pasang + AVD), 2a, resize `n2-custom-12`, 2b tidak dijalankan. Blok `moved` untuk `emu` diterapkan saat apply awal tanpa recreate (plan hanya "create" karena state kosong; perilaku di state hidup belum teruji).
- Log ke GCS `logs/radio-uplift/20261119/` **tidak** disimpan: bucket runs adalah bagian dari lab dan dihapus saat destroy (`bucket_force_destroy=true`); bucket persisten user tidak disentuh. Log tersimpan di box: `/workspace/radio-uplift/logs/` dan salinan terredaksi di `docs/results/radio-uplift-20261119-logs/ev/`.
- Tes `tests/radio/run-all.sh` ALL OK sebelum apply (16 test).

## Biaya
Lab hidup ~09:54-10:21 (27 menit, 12 vCPU, ~USD 0,8/jam) = **~USD 0,4**; total hari ini ~USD 10,1-10,2 (dasar USD 9,7). Jauh di bawah USD 13 dan USD 15.

## Destroy audit
- `terraform destroy`: 162 resource, rc=0; `terraform state list` kosong; tidak ada lock atau proses.
- gcloud: instance tersisa hanya `build-vm-01` (TERMINATED, tidak disentuh); disk hanya `build-vm-01`; jaringan hanya `default`; router 0; resource-policy 0; bucket `lab5g-*` 0; service account lab (`lab5g-core-ran`, `lab5g-emu`) tidak ada.
- Tidak ada perubahan VNC, tunnel publik, atau IAM di luar yang dikelola Terraform lab. netprobe/magnon tidak disentuh.

## Langkah berikutnya (USULAN, butuh persetujuan)
1. Diagnosis offline (nol biaya): bangun srsRAN_4G `release_23_11` lokal dan tinjau jalur SA (`ue_stack_lte`, `nas_5g`, `rrc_nr`) untuk memahami kenapa `plmn_search` tidak dipanggil; cek apakah `srate` tetap dan `base_srate` memerlukan opsi lain, atau apakah tag atau commit perlu diganti (mis. master srsRAN_4G).
2. Bangun ulang prebuild dengan ISA tetap (hindari AVX512 VPOPCNTDQ, `-mno-avx512*`), supaya tidak bergantung pada Ice Lake.
3. Alternatif jalur radio terbukti: LTE (srsRAN_4G eNB+UE, opsi a) 20 MHz, 2 pasang bila cukup CPU; butuh build srsRAN_4G dengan eNB.
4. Apply ulang hanya setelah UE NR attach terbukti di box (mis. uji loopback gNB+UE+Open5GS lokal bila memungkinkan).
