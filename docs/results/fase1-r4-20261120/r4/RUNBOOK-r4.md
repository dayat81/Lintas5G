# Runbook GCP r4 — Fase 1 closeout (DRAFT siap-pakai, BELUM di-apply)

Status: draft 20 Nov 2026 ~11:10 WIB. User sudah approve sesi GCP r4 (10:10 WIB), tetapi apply menunggu dispatch terpisah dari parent. Tanpa push/PR/tag.
Acuan gate: `../GATES-r4.md` FROZEN v1.1, sha256 `d396a72e91619609e97f4c1a81fb2cb6365088ff9b96083e80ea7544ad451f5e` (cek ulang langkah 0). Dasar: `/workspace/booster-e2e-r3/RUNBOOK.md` (deploy3.sh/rep3.sh, sizing r1/r3).
Batas: cap harian USD 40 (lapor di ~35); IAM/firewall/tunnel/VNC hanya yang ada di IaC r2/r3; secret tidak dicetak; tidak menyentuh build-vm-01/<proyek-lain>/booster.

## 0. Pra-flight (box, sebelum apply)
1. `cd /workspace/fase1-closeout && sha256sum -c <(cut -d' ' -f1-3 GATES-r4.sha256)` → OK. Kalau beda: STOP (gate tidak boleh berubah setelah r4 mulai).
2. Bundle r4 = salinan `booster-e2e-r3/bundle` dengan pengganti: APK `booster-app/out/booster-poc-examine-v0.10.2-booster.5.1-rebuild.apk` (sha256 fb0136da…3b274637); adapter `lintas5g/qod-adapter:0.1.3` (docker save, sha ddda3f91…) + `qod-adapter-013/config` (as_cidr_in_list on, as_cidr_min_prefix 16, as_cidr_clients [booster-client], pcc_templates provisioned, PKJWT); gNB `v3.0.0-slice-qosrel4`; provisioning `fase1-closeout/provision/{lab-qos.yaml,render.py,provision_db.py,provision_subs.py}`; tools `booster-e2e/window.py`, `multiue/`, `trace/`, `tools/sink.py`.
3. Port wajib (belum dikerjakan): `provision.sh` saat ini memakai container docker box (n5-lab/n5-mongo); di VM GCP panggil `render.py`/`provision_db.py` dari `booster-up.sh` (netns `ue1/ue2`, mongo lokal). Bind adapter: `QOD_BIND` = loopback/IP internal di netns core; backend booster (8090) jalan di VM core yang sama dan memanggil adapter lewat loopback.
4. `terraform plan -var-file=r4.tfvars` (r4.tfvars = r3.tfvars: vm-core-ran n2-standard-8 + vm-emu n2-standard-4 = 12 vCPU, kuota CPUS_ALL_REGIONS 12) → simpan `plan-r4.log`, cek jumlah resource ≈ r3 (168 add). Catat jam mulai (WIB) untuk audit biaya.

## 1. Bring-up (≈25 menit)
`deploy3.sh apply` → `push` (bundle r4) → `wait` (UE attach + boot emulator) → `core` (`MIMO=2 booster-up.sh all`, secret via stdin IAP) → provisioning r4 (`provision check` harus drift 0 sebelum UE attach; jalankan apply, lalu check lagi; simpan log) → `emu` (install APK booster.5.1, appkey via pipe) → `check`.
Wajib sebelum run: UE attach + keepalive ping 1 s per UE (UE tidak boleh idle); adapter `/healthz` versi 0.1.3; log startup `pcc_templates: provisioned, private_key_jwt: true`; preflight `booster-e2e/preflight.py` di VM core → /16 body 201, /15 400.

## 2. Smoke s0 (≈7 menit)
1 run pendek: examine VPN (baris 1 BOOSTER5_1_READY) → YouTube play di bawah beban → BoosterActivity (baris 2, `--es cdnprefix 16 --es cdnminprefix 16`, proto both, `--es onesession off`) → 60 s → `adb shell input keyevent KEYCODE_BACK` saat BoosterActivity di depan (JANGAN force-stop).
Lulus smoke: logcat ada `T_BOOSTER start ... version=0.10.2-poc-booster.5.1` dan `T_BOOSTER_FINISH ... reason=activity_finish final_delete=http_204`; TIDAK ada "cdn subnets rejected"; QFI boost terlihat di N3; CPU core <85%; YouTube PLAYING. Bila YouTube tidak mulai 2× → laporkan, stop.

## 3. Run utama (≈8 menit/run, berselang-seling A1,N1,A2,N2,A3,N3)
- **A×3 (wajib):** `rep3.sh A<n> ext 90 <boost> 15 <RATE>` dengan booster.5.1; window = `t_booster` → `t_booster_finish` (logcat). Akhiri dengan KEYCODE_BACK; harness menulis `t_back`/`t_end` di `times`.
- **N×3** (baseline tanpa booster, jendela waktu sama) bila sisa waktu/budget cukup; kalau tidak **N×2** dan batasannya ditulis.
- PA opsional (tidak dijadwalkan kecuali sisa > 20 menit).
- Per run: `window.py logcat.txt times <run>` → flags. `FAILED_SETUP_CDN_REJECTED` = run setup gagal (dilaporkan, tidak dinilai, boleh diulang 1×). `FINISH_MISSING` = pakai fallback t_back/t_end dan **ditandai di laporan**.
- Gate per run (G1, FROZEN v1.1): loss DL YouTube saat AVAILABLE ≤5%; share byte YouTube di QFI boost ≥80%; cakupan AVAILABLE ≥90% window; interval <1.000 paket DL YouTube = "tidak dinilai". time-to-AVAILABLE dilaporkan.
- G5 di GCP (≈10 menit): `gcloud compute instances describe` (tanpa external IP), aturan firewall dari IaC, `nmap` 8080/8090/8443 dari host VPC non-izin + dari netns UE, plus kontrol positif dari sumber yang diizinkan.
- G8: screenshot app booster (adb screencap) + Grafana untuk run A yang sama (ingest `obs/f1_ingest.py` versi r4).

## 4. Agregasi & transfer (≈10 menit)
`aggregate.py` → `out/r4-results.{csv,md}`; artefak teredaksi (tanpa IMSI/IP publik/secret) → box `fase1-closeout/r4/results/`; pcap mentah hanya ke bucket state/box `/workspace/fase1-raw/r4/`, tidak ke repo.

## 5. Destroy + audit biaya (≈8 menit)
1. `terraform destroy -var-file=r4.tfvars` → `destroy-r4.log`.
2. Audit: state 0 resource; `gcloud compute instances list` hanya build-vm-01; disk/network/address/firewall hanya <proyek-lain>/default; bucket runs & SA lab r4 hilang.
3. Biaya: jam apply→destroy × USD 0,82/jam (8+4 vCPU, FAKTA r1) + egress/storage; cek di Billing report (filter label/proyek, hari ini) bila tersedia; catat di `r4/COST.md`.

## 6. Risiko
YouTube tidak PLAYING di emulator 4 vCPU (r1–r3); Wi-Fi AVD putus (watchdog, deviasi); CDN di luar 2×/16 → G1b bisa gagal (laporkan apa adanya, /16 = over-boost trafik Google lain, keputusan PM, lab-only); G1c bergantung kebijakan delete/recreate booster (`onesession off`, renew on).
