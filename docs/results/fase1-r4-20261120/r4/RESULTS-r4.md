# GCP r4 (20 Nov 2026), hasil: DIHENTIKAN setelah smoke karena blocker akun YouTube; lab di-destroy dan diaudit

Persetujuan: user "gcp approved" (pt351u, 10:10 WIB). Kriteria: `GATES-r4.md` FROZEN v1.1, sha256
`d396a72e91619609e97f4c1a81fb2cb6365088ff9b96083e80ea7544ad451f5e`. Hash cocok saat pre-flight 11:07:36 WIB
(`booster-e2e-r4/ev/preflight-hash.txt`). Baris 3 file ("Status: draft…") adalah label lama yang sudah diketahui. Yang berlaku adalah
hash FROZEN di atas, dan file tidak diubah. Skrip analisis G1 `r4/r4gate.py` (sha256 8f05ea1a…) ditulis sebelum run, tetapi belum dipakai karena tidak ada run A/N.

## Kronologi (WIB, FAKTA, dari `booster-e2e-r4/times.log`)
- Persiapan lokal: `booster-e2e-r4/` berisi deploy4.sh, rep4.sh, r4.tfvars (= r3), bundle (APK booster.5.1 sha fb0136da…3b274637,
  image adapter 0.1.3 dan config, provisioning port `provision/lab-qos-gcp.yaml` + `booster-up.sh provision`, emu-run4.sh).
- Plan 168 resource (sama dengan r3). Apply 11:07:42–11:09:20. Push 11:09:41.
- Core 11:17:45. Provisioning statis (PCF qos_profiles in_sync; PCC: api-prio 5QI 69 + template 2/3/4/7/80 ditulis, lalu check drift 0;
  slice in_sync). RAN up, UE attach dalam 1 percobaan, keepalive aktif. Adapter 0.1.3 healthz ok di 127.0.0.1:8080. Backend :8090/:8443.
- Emulator boot 11:22:32. APK booster.5.1 terpasang (versionCode 15). Lab siap 11:23.
- Smoke s0 11:23–11:28.
- Diagnosis 11:29–11:40, termasuk `adb reboot` emulator 11:31–11:35.
- G5 scan 11:40. Destroy 11:41:57–11:45:52 (168 dihancurkan, state 0).

## Blocker (FAKTA, screenshot `ev/live-yt2.png`, `ev/live-yt3.png`, privat)
- Setelah emulator di-reboot, YouTube menampilkan "There was a problem signing in to your account" (kunci gembok), sama dengan r3.
  Sesi akun di `emu/session-api36-pixelc.tar.zst` (disimpan 07:10 WIB setelah re-verify r3v) tidak lagi valid. Video tidak pernah PLAYING.
- Memulihkannya butuh re-verify Google dengan password user lewat noVNC. noVNC dan tunnel publik tidak termasuk izin r4, jadi langkah itu tidak dilakukan.
- Akibatnya A×3 dan N×3 tidak dijalankan. Tanpa video, interval akan <1.000 paket YouTube DL ("tidak dinilai"), dan kebijakan idle-delete booster membuat cakupan tidak bermakna.

## Smoke s0 (FAKTA, `booster-e2e-r4/ev/s0/`)
- Sel: DL UDP 200M, UE tetap attach, bad-counts 0. CPU core: nr-uesoftmodem ≈273%, nr-softmodem ≈154%, idle ≈34%.
- Adapter 0.1.3 + /16: body app `{"ipAddresses":["<BACKEND_IP>","<google>/16","<google>/16"]}` proto both diterima (201 → AVAILABLE, 2 CREATE / 2 DELETE).
  Baris "cdn subnets rejected": 0.
- Paket YouTube/Google :443 selama boost: 94,9% byte di QFI boost. Volumenya kecil (0,03 Mbit/s, layar error, bukan video), jadi tidak bisa dinilai.
- window.py: T_BOOSTER ada. T_BOOSTER_FINISH **tidak ada**, jadi dipakai fallback `t_back` dengan flag `FINISH_MISSING`; window 99,5 s.
  Penyebab: setelah restore sesi, jendela app di emulator tidak ter-render (hitam) dan app ANR ("Input dispatching timed out, no focused window"), sehingga KEYCODE_BACK tidak diproses.
- Setelah `adb reboot`, uji BACK (tanpa beban): T_BOOSTER_FINISH `reason=activity_finish` muncul 0,5 s setelah KEYCODE_BACK. Harness end-by-BACK terbukti jalan bila UI sehat.
- Booster setelah reboot: CREATE → `CamaraResult{0 NETWORK}` (BACKOFF). Jalur emulator → backend <BACKEND_IP>:8090 belum pulih setelah reboot. Belum didiagnosis karena YouTube sudah terblokir.

## Gate r4 (FAKTA per item; tidak ada run A/N)
| Gate | Status r4 |
|---|---|
| G1a/b/c (A×3) | **tidak dijalankan**: blocker akun YouTube. time-to-AVAILABLE, cakupan, loss, dan share: tidak ada data run yang sah. |
| G2 conformance | di luar sesi GCP ini (dinilai offline di box) |
| G3 callback | di luar sesi ini (box: 5/5 PASS, `callback/CALLBACKS.md`) |
| G4 trace | di luar sesi ini (box: `trace/TIMELINE.md`) |
| G5 adapter tertutup | **bukti terkumpul** (`ev/g5/`): VM lab tanpa external IP; firewall lab = IAP 22/3000, internal <LAB_SUBNET>/16 port tertentu, deny-all 65534. nmap dari vm-emu (VPC): 8080/8090/8443 *filtered*. nmap dari netns UE: 8080 *closed* (adapter hanya 127.0.0.1); 8090/8443 backend *open* (by design, API booster); **22/tcp core terbuka dari netns UE** (temuan, bukan port adapter). |
| G6 multi-UE | di luar sesi ini (box: `multiue/MULTIUE.md`) |
| G7 tanpa konfigurasi manual | provisioning statis lewat skrip (`booster-up.sh provision` + `lab-qos-gcp.yaml`), tanpa langkah per sesi. Daftar langkah run: hanya rep4.sh. |
| G8 bukti tampilan | **sebagian**: screenshot app booster.5.1 dari GCP (redaksi IP publik/prefix CDN/hostname) `ev/g8/booster-5.1-gcp-r4-redacted.png`. Grafana untuk run yang sama: tidak ada, karena tidak ada run A. |
| G9 rilis | tidak dilakukan (tidak ada push/PR/tag) |

## Biaya (estimasi, tarif r1 USD 0,82/jam untuk 8+4 vCPU)
- VM 11:09–11:46 ≈ 37 menit → **≈ USD 0,5–0,7** (termasuk NAT, disk, dan transfer bucket intra-region yang kecil).
- Kumulatif hari ini tidak bisa dibaca dari billing API. Dari catatan r3/r3v perkiraannya jauh di bawah USD 35 dan cap 40.

## Audit pasca-destroy (FAKTA, 11:46 WIB, `ev/audit-post-destroy.txt`)
- Instance: hanya build-vm-01 (TERMINATED, tidak disentuh). Disk: hanya build-vm-01. Network: default. Router 0, resource-policy 0.
- Address dan firewall yang tersisa milik <proyek-lain>/default, sama dengan baseline. Bucket = baseline (state, <bucket-lain-1>, <bucket-lain-2>, _cloudbuild); bucket runs lab hilang.
- SA lab5g yang tersisa hanya <sa-terraform> (pra-ada). Snapshot hanya build-vm-01 (15 Nov, pra-ada). `terraform state list` = 0.
- Tidak ada perubahan VNC, tunnel publik, IAM, atau firewall di luar IaC yang sudah ada. Tidak ada push/PR.

## Yang dibutuhkan untuk r4 ulang (USULAN)
1. Re-verify akun Google di emulator. Butuh user dan noVNC (izin baru), lalu simpan ulang `emu/session-api36-pixelc.tar.zst`.
   Alternatif: akun uji khusus lab.
2. Sesudah restore sesi: `adb reboot` emulator sebelum run (render hitam / ANR terlihat di r4), lalu pulihkan jalur ke backend (jalankan ulang `booster-up.sh net` + cek CREATE).
3. Harness r4 siap dipakai ulang tanpa perubahan: `booster-e2e-r4/{deploy4.sh,rep4.sh}`, `fase1-closeout/r4/r4gate.py`.

---
# r4v (20 Nov 2026, 13:10–14:58 WIB): login YouTube via noVNC, lalu A×3 + N×3 headless. Lab di-destroy dan diaudit

Persetujuan user langsung: "siapkan vnc untuk login youtube" (13:10), "done login youtube" (13:44), "Headless emulator to save resources" (13:46).
Kriteria: `GATES-r4.md` FROZEN v1.1, sha256 d396a72e91619609e97f4c1a81fb2cb6365088ff9b96083e80ea7544ad451f5e (dicek ulang 14:54, cocok, tidak diubah).
Analisis: `r4gate.py` tidak diubah, sha256 8f05ea1ae8f9cf5e… (sama dengan sebelum run). Data: `r4/r4-g1.csv`, `r4/r4-g1-sessions.csv`, `r4/r4-g1-out.txt`.

## Kronologi (WIB, FAKTA, `booster-e2e-r4/times.log`)
- Apply r4v 13:10:57–13:12:33. Isinya r4.tfvars ditambah `gui_vnc=true` dan `gui_public_tunnel=true` (pola r3v), 168 resource.
  Satu-satunya perubahan firewall: rule IAP (<GCP_IAP_RANGE>) mendapat port 5900/6080, persis seperti plan r3v. IAM tidak diubah. Core dan provisioning siap 13:27, emulator 13:27, APK 5.1 13:28.
- noVNC publik (Cloudflare quick tunnel, basic auth `lab` + password VNC) siap 13:29, dengan auto-off 15:28.
  13:37 ANR YouTube/GMS ditangani dengan BACK + force-stop/relaunch YouTube saja. User login 13:44.
- Verifikasi: video Big Buck Bunny PLAYING (`ev/live-v-play.png`, privat).
- Arsip sesi disimpan ulang 13:46–13:50 (sha256 bf7647c8…, 3,43 GB) lewat bucket runs lab (SA lab sudah objectAdmin lewat IaC), lalu disalin server-side ke `gs://<state>/emu/` dengan kredensial box.
  Tidak ada grant IAM manual (r3v masih memakai grant manual). Isi arsip tidak dibuka atau dicetak. Tunnel publik OFF 13:50 (`lab5g-cloudflared` inactive, URL dikosongkan).
- Headless 13:50–13:52: container emulator dibuat ulang dengan `EMU_VNC=0` dan args `-no-window -no-snapshot-save`, userdata mount sama.
  Hasilnya qemu-system-x86_64-headless, akun 2, render normal, video PLAYING (`ev/live-headless-play.png`).
  Batasan: image budtmo tetap menjalankan Xvfb dan x11vnc di dalam container. Port tidak dipublikasikan dan tidak ada window.
- `booster-up.sh net` diulang. Smoke s1 13:54–13:59: CREATE 201 → AVAILABLE, FINISH dari logcat (`activity_finish`, final DELETE 204), "cdn subnets rejected" = 0.
- Run (base 90 s, boost 150 s, after 15 s, DL UDP 200M; parameter sama dengan A r3): A1 13:59, N1 14:10, A2 14:17, N2 14:28, A3 14:39, N3 14:46–14:53.
  Keepalive UE aktif sepanjang run, UEOK=1 di semua run.
- G5 14:54. Destroy 14:55:53–14:58:38 (168 resource), state 0.

## G1 per run (FAKTA, r4gate.py; window = T_BOOSTER → T_BOOSTER_FINISH logcat, finish_source=logcat, tanpa flag di A1–A3)
| Run | Window (s) | time-to-AVAILABLE (s) | Sesi AVAILABLE | Cakupan AVAILABLE | Loss DL YT saat AVAILABLE | Share byte QFI boost saat AVAILABLE | Paket YT DL (AVAILABLE) | G1a ≤5% | G1b ≥80% | G1c ≥90% |
|---|---|---|---|---|---|---|---|---|---|---|
| A1 | 154,1 | 5,4 | 2 | 95,7% | 1,15% | 95,8% | 17.428 | lulus | lulus | lulus |
| A2 | 155,3 | 5,2 | 4 | 94,8% | 0,47% | 99,5% | 9.528 | lulus | lulus | lulus |
| A3 | 153,1 | 5,3 | 3 | 95,0% | 0,07% | 99,8% | 9.588 | lulus | lulus | lulus |
Info (bukan gate): loss sepanjang window A1/A2/A3 = 1,44 / 0,50 / 0,30%. Di luar AVAILABLE (5,4–7,9 s, termasuk awal window) loss 33,5 / 7,1 / 34,9%, share 0%, <1.000 paket ("tidak dinilai").
Beberapa interval AVAILABLE akhir (A2 s3–s4, A3 s3) berisi 0 paket YouTube karena buffer video penuh. Interval itu tetap dihitung ke cakupan, sesuai definisi FROZEN.

**N (tanpa booster, pembanding; window harness t_booster → t_end ≈ 180 s, lebih panjang dari A karena tidak ada BACK):**
| Run | Loss DL YT | Share QFI boost | Paket | YouTube playing / stall |
|---|---|---|---|---|
| N1 | 26,8% | 0% | 1.802 | playing 69 sampel, 8 stall, 145 s stall |
| N2 | 23,6% | 0% | 1.473 | 60 sampel, 6 stall, 133 s |
| N3 | 23,9% | 0% | 681 (tidak dinilai, <1.000) | 0 sampel: BUFFERING terus (akun tetap login, layar video hitam/buffer, `ev/N3/.../shots`) |
A: playing 164 / 160 / 158 sampel, stall 6 / 7 / 3 (32 / 17 / 6 s), startup 54 / 76 / 92 s (startup di bawah beban, sebelum boost).
N3 memicu stop otomatis harness (playing=0) setelah run terakhir. Penyebabnya kemacetan tanpa QoD, bukan sign-in atau ANR, jadi N×3 lengkap.

## Gate lain (r4v)
| Gate | Status |
|---|---|
| G1 | **lulus**: A×3, ketiga run lulus G1a, G1b, G1c |
| G2 | di luar sesi GCP (offline di box, lihat PROGRESS) |
| G3 | di luar sesi (box: `callback/CALLBACKS.md`). Di r4v, callback sink AVAILABLE dan UNAVAILABLE/DELETE_REQUESTED terlihat per sesi (adapter.win.log) |
| G4 | di luar sesi (box: `trace/TIMELINE.md`) |
| G5 | **bukti** `booster-e2e-r4/ev/g5v/`. Tanpa external IP di VM lab. Firewall: IAP 22/3000/5900/6080 (pola r3v), internal <LAB_SUBNET>/16, deny-all. nmap vm-emu→core: 8080/8090/8443 filtered. nmap netns UE: adapter 8080 closed (listen 127.0.0.1 saja); 8090/8443 backend open (by design); 5900/6080/5555 closed di core dan filtered di vm-emu. Temuan: 22/tcp core terbuka dari netns UE |
| G6 | di luar sesi (box: `multiue/MULTIUE.md`) |
| G7 | provisioning statis lewat skrip (`booster-up.sh provision` + `lab-qos-gcp.yaml`), tanpa langkah per sesi atau per app. Langkah manual satu-satunya: login akun YouTube (sekali, diungkapkan) |
| G8 | **bukti** untuk run A1: app booster `booster-e2e-r4/ev/g8/booster-A1-end-redacted.png` (ACTIVE, cov 95%, rot 1; IP publik, prefix CDN, dan daftar flow diredaksi) dan Grafana `fase1-closeout/obs/screenshots/grafana-r4-A1.png` (run_id r4-A1, sesi 1d13… dan 16d7…, QFI 2/5, timeline event). Sumber data: `obs/r4_ingest.py` → ch-test, dari adapter events export (deviceKey hash), N3 pcap A1, dan logcat MGLT |
| G9 | tidak dilakukan (tanpa push/PR/tag) |

## Biaya (estimasi, USD 0,82/jam untuk 8+4 vCPU)
- r4v 13:11–14:59 ≈ 108 menit → ≈ USD 1,5–1,8 (termasuk NAT dan disk; upload arsip intra-region).
- r4 pagi ≈ USD 0,5–0,7. Total r4 hari ini ≈ USD 2,0–2,5, jauh di bawah ambang USD 35 dan cap USD 40. Billing API tidak tersedia, jadi angka ini estimasi.

## Audit pasca-destroy (FAKTA, 14:58 WIB, `ev/audit-post-destroy-v.txt`)
- Sama dengan baseline: instance dan disk hanya build-vm-01 (TERMINATED, tidak disentuh); network default; router dan resource-policy 0.
  Address dan firewall milik <proyek-lain>/default; bucket state, <bucket-lain-1>, <bucket-lain-2>, _cloudbuild; SA lab5g hanya <sa-terraform>; snapshot hanya build-vm-01 (15 Nov).
- Bucket runs lab terhapus bersama destroy. Arsip sesi baru ada di bucket state privat `emu/` (3 objek, versioning menyimpan versi lama).
- Tidak ada push/PR. Tunnel publik mati sebelum run.
