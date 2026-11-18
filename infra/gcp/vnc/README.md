# Remote GUI emulator (VNC / noVNC)

Paket ini dipakai untuk sesi remote GUI emulator Android (vm-emu) di lab GCP Lintas5G.
Isinya full stack: EPC Open5GS dan srsRAN_4G ZMQ di vm-core-ran, dengan internet emulator lewat UE.
Default (`gui_emu_egress=ue-l3`): SEMUA trafik emulator (TCP, UDP/QUIC, ICMP) dirutekan L3 lewat GRE ke netns UE,
tanpa proxy aplikasi. Emulator default: Android 16 (API 36) `google_apis_playstore` + translasi ARM64, tablet Pixel C,
framebuffer 1920x1080.

- **FAKTA:** stack ini sudah diuji di lab pada 18 Nov 2026, termasuk noVNC lewat tunnel SSH IAP,
  Quick Tunnel publik, attach ulang UE oleh watchdog, dan bukti internet emulator lewat UE.
- **USULAN:** `vnc-deploy.sh` merangkai langkah-langkah yang sudah teruji itu, tapi belum dijalankan
  utuh dalam satu kali run.

## Arsitektur

```
Laptop --(gcloud ssh --tunnel-through-iap, -L 6080/-L 5900)--> vm-emu 127.0.0.1:6080 (noVNC) / 127.0.0.1:5900 (x11vnc, password VNC)
                                                                 |
          emulator (docker0 172.17/16) --ip rule iif docker0 -> table 201--> gre-core 10.201.0.2 (SNAT)
             ==GRE proto 47 (lab5g-allow-internal)==> vm-core-ran gre-emu 10.201.0.1 --ip rule iif gre-emu -> table 201-->
             veth-ueh -> netns ue1 (MASQUERADE ke IP UE 10.45.x) -> tun_srsue -> srsENB (ZMQ) -> SGW-U/UPF -> SGi -> Cloud NAT
          fail-closed: GRE down -> table 201 "unreachable" + filter LAB5G-EMU REJECT (tidak pernah bocor ke Cloud NAT langsung)
          mode ue-proxy (lama): emulator --HTTP proxy--> vm-core-ran:18080 (DNAT) -> gost di netns ue1

OPT-IN publik: browser --https--> *.trycloudflare.com (Cloudflare Quick Tunnel) --> cloudflared (vm-emu)
               --> caddy 127.0.0.1:6081 (basic auth user `lab`) --> noVNC 127.0.0.1:6080 --> password VNC
```

- **VNC:** port 5900, 6080, dan 5555 di container `budtmo/docker-android` hanya bind ke `127.0.0.1`.
  VM tidak punya IP publik, dan firewall hanya membuka akses dari rentang IAP `35.235.240.0/20`.
- **Akses utama:** SSH tunnel via IAP. `gcloud compute start-iap-tunnel vm-emu 6080` **tidak bisa**
  (error 4003) karena port-nya hanya listen di localhost.
- **Password VNC:** dibuat acak di VM dan disimpan di `/opt/lab5g/vnc-password.txt` (root, 0600).
  Container membacanya lewat `--env-file`, lalu x11vnc memakai `-rfbauth`. Hasil cek RFB: security type
  hanya [2], artinya VNC auth wajib.
- **Watchdog UE:** `lab5g-watchdog.timer` jalan tiap 60 s dan menjalankan `/opt/lab5g/ue-watchdog.sh`.
  Kalau eNB/UE/keepalive mati, tun_srsue tanpa IP, atau ping UE gagal, watchdog menjalankan
  `core-run.sh` untuk attach ulang dan memastikan gost hidup. Log di `/var/log/lab5g/watchdog.log`.
  Hasil uji di lab: pulih dalam sekitar 66 s.
- **Keepalive:** `lab5g-keepalive` menjalankan ping 1 s dari netns UE, karena UE tidak boleh idle.
- **Public tunnel (opt-in):** `novnc-public-setup.sh` memasang caddy dan cloudflared dari repo apt resmi
  masing-masing. Password basic auth dibuat acak di VM dan disimpan di
  `/opt/lab5g/novnc-web-password.txt` (root, 0600). Service `lab5g-cloudflared` (Restart=always)
  menulis URL aktif ke `/opt/lab5g/public-url.txt`. Tidak ada firewall rule atau IP publik baru.

## File

| File | Dijalankan di | Fungsi |
|---|---|---|
| `vnc-deploy.sh` | laptop/box | Merangkai semua langkah. Pakai `PROJECT_ID`/`ZONE` atau gcloud config. Tambah `--public` untuk tunnel publik |
| `gui-core-up.sh` (`core-bringup-vnc.sh` = alias) | vm-core-ran | Bring-up sesi GUI: tanpa QoD/Zeek, MTU/MSS fix, gost GUI, watchdog, collector |
| `gui-emu-up.sh`, `emu-dashboard-setup.sh`, `emu-collector.py`, `lab.html` | vm-emu | Dashboard side-by-side + emulator + egress |
| `core-collector.py`, `install-collector.sh`, `gui-net-fix.sh`, `core-proxy-gui.sh` | vm-core-ran | Collector 8099, MTU/MSS, gost GUI |
| `emu-egress-policy.sh`, `install-emu-egress.sh` | vm-emu | Kebijakan egress emulator (ue-l3: GRE + policy routing, filter atomik, timer self-heal 30 s) |
| `core-gre-emu.sh` | vm-core-ran | Sisi core GRE: `iif gre-emu` -> netns UE, MASQUERADE ke IP UE, clamp MSS (dipanggil bring-up + watchdog) |
| `emu-gpu-setup.sh` | vm-emu | OPT-IN GPU: driver NVIDIA + container toolkit, tulis `/opt/lab5g/gpu.env` |
| `emu-image/Dockerfile`, `emu-image-build.sh` | vm-emu | Image `lab5g/android:<API>-<type>` = budtmo emulator_14.0 + system image API 35/36 Play Store |
| `usability-core.sh`, `usability-emu.sh` | VM | Uji gate Emulator Usability |
| `ue-watchdog.sh`, `install-watchdog.sh` | vm-core-ran | Watchdog attach ulang UE, berupa systemd timer |
| `emu-vnc-start.sh` | vm-emu | Emulator (image/device/layar/RAM/core lewat env), password VNC acak, port hanya di 127.0.0.1; recreate hanya bila spec berubah |
| `emu-proxy-ue.sh` | vm-emu | Proxy HTTP Android: on (`ue-proxy`) atau dihapus (`ue-l3`, satu jalur transparan) |
| `novnc-public-setup.sh` | vm-emu | OPT-IN: cloudflared Quick Tunnel (butuh caddy dari `emu-dashboard-setup.sh`) |
| `novnc-public-toggle.sh` | vm-emu | `off`, `on` (URL baru), atau `status` |
| `verify-public.py` | laptop/box | Cek WebSocket `/websockify` lewat URL publik (401 tanpa auth, 101 dengan auth, RFB type 2) |

## Langkah

1. Siapkan infrastruktur:
   ```bash
   cd infra/gcp/terraform && terraform apply
   ```
2. Jalankan deploy:
   ```bash
   PROJECT_ID=<PROJECT_ID> ZONE=asia-southeast2-a bash infra/gcp/vnc/vnc-deploy.sh
   ```
   Tambahkan `--public` hanya jika memang perlu URL publik.

## Sesi GUI otomatis (gui_session=true), USULAN dan belum diverifikasi lewat fresh apply

Set `gui_session = true` di tfvars, lalu jalankan `terraform apply`. Startup script mengambil `sesi-c/` dan `vnc/` dari
`gs://<bucket>/gui/`, lalu memasang unit systemd yang enabled sehingga ikut jalan lagi setelah reboot:

- **vm-core-ran:** `lab5g-gui-core.service` menjalankan `gui-core-up.sh`. Urutannya:
  1. collector `lab5g-collector` (status.json di IP internal, port 8099);
  2. install Open5GS + srsRAN (boot pertama, sekitar 12 menit);
  3. config EPC;
  4. hapus shaping QoD/HTB Sesi C;
  5. attach dan keepalive;
  6. `gui-net-fix.sh` (MTU tun_srsue 1400 + clamp TCPMSS 1360);
  7. `core-proxy-gui.sh` (gost: LimitNOFILE 65536, Restart=always, resolver 8.8.8.8 + 1.1.1.1);
  8. `core-gre-emu.sh` (GRE dari vm-emu -> netns UE);
  9. watchdog timer 60 s (attach ulang + MTU/MSS fix + GRE re-apply setiap tick).
- **vm-emu:** `lab5g-gui-emu.service` menjalankan `gui-emu-up.sh`. Urutannya:
  1. iperf3 server :9000 (internal) + kebijakan egress `lab5g-emu-egress` (+ `lab5g-emu-gre.timer`) DULUAN, fail-closed;
  2. caddy + dashboard (`emu-dashboard-setup.sh`) + `lab5g-emu-collector`;
  3. build image emulator sekali (`emu-image-build.sh`, unduh system image ~1,5 GB, perkiraan 5-10 menit, BELUM diukur)
     lalu emulator (`gui_emu_api`, `gui_emu_device`, `gui_emu_screen`) dengan password VNC;
  4. proxy Android: dihapus di `ue-l3`, ke core:18080 di `ue-proxy`;
  5. Quick Tunnel opsional (`gui_public_tunnel=true`).

### Halaman default `/`: emulator di kiri, dashboard lab di kanan

Bisa dibuka lewat IAP (`-L 6081:localhost:6081`, lalu `http://localhost:6081/`) atau lewat URL Quick Tunnel.
Basic auth user `lab`, dan password VNC diminta di iframe noVNC.

- **Sumber data core (`/api/core.json`, diteruskan caddy ke `<core-ip>:8099`):**
  - `keepalive.log` (ping UE ke 8.8.8.8, 60 sampel terakhir);
  - IP/MTU tun_srsue;
  - counter `/sys/class/net/ogstun` (DL = tx, UL = rx);
  - `watchdog.log`;
  - `systemctl is-active` untuk enb/ue/keepalive/gost/mme/sgwc/sgwu/smf/upf/hss;
  - `/proc/stat` (CPU/steal) dan loadavg;
  - probe proxy core → gost.
- **Sumber data emu (`/api/emu.json`):**
  - CPU/steal/load vm-emu;
  - status container dan boot_completed;
  - `http_proxy` Android;
  - probe vm-emu → core:18080 (jalur emulator);
  - estimasi biaya = uptime × tarif/jam.
- **Latensi data:** collector tiap 2 s, probe proxy tiap 10 s, refresh halaman tiap 3 s. Umur data
  maksimum sekitar 5 s (probe proxy sekitar 13 s). Banner "basi" muncul kalau core.json lebih tua dari 15 s.
- **Keamanan:** tidak ada IMSI/KEY/OPC/password di JSON (IMSI di log watchdog diredaksi). Port 8099 hanya
  dibuka di firewall internal 10.10.0.0/16.

### Kebijakan egress emulator (`gui_emu_egress`)

- `ue-l3` (default): semua trafik container emulator lewat GRE -> netns UE (TCP, UDP/QUIC, ICMP), tidak butuh
  kerja sama aplikasi. Perbaikan RCA "YouTube cannot play video" (app YouTube/ExoPlayer/Cronet mengabaikan proxy
  global Android dan memakai QUIC). Fail-closed: kalau GRE putus, trafik ditolak (unreachable/REJECT), tidak keluar
  langsung lewat Cloud NAT. Pengecualian langsung: 10.10.0.0/16, DNS metadata 169.254.169.254, 172.16/12.
- `ue-proxy`: perilaku lama, hanya proxy HTTP Android ke gost; app yang mengabaikan proxy GAGAL (terlihat, bukan bypass).
- `quic-block`: hanya UDP/443 yang ditolak (trafik lain langsung Cloud NAT, tidak lewat UE).
- `off`: tanpa kebijakan (langsung Cloud NAT, tidak lewat UE).
- **Uji offline (box, 18 Nov 2026):** topologi netns (emu/core/ue1/inet/container, veth pengganti GRE karena kernel
  box tanpa modul ip_gre): TCP 200 dan UDP/443 sampai ke "internet" dengan source = IP UE 10.45.0.2; re-run
  idempotent (1 rule/NAT, 9 rule filter); link GRE down -> "could not connect after 0 ms" (unreachable, tidak bocor);
  self-heal `ROUTES_ONLY=1` memulihkan; `ue-proxy` menolak; `off` bersih. TCPMSS tidak teruji (modul tidak ada di
  box). BELUM teruji di GCP (GRE asli, docker asli).

### Emulator: Android terbaru + layar besar (`gui_emu_api`, `gui_emu_img_type`, `gui_emu_device`, `gui_emu_screen`)

- Tag budtmo berhenti di `emulator_14.0` (API 34, `google_apis`, tanpa Play Store; abilist emulator_13.0 di lab =
  x86_64 saja, jadi app/game ARM-only tidak bisa dipasang).
- `emu-image/Dockerfile` memakai budtmo emulator_14.0 sebagai basis (noVNC/x11vnc/CLI tetap) lalu `sdkmanager`
  memasang `system-images;android-36;google_apis_playstore;x86_64` (default; 35 opsional), mendaftarkan 15.0/16.0/17.0 di
  CLI budtmo, dan membuat `-writable-system` opt-in (`EMULATOR_WRITABLE_SYSTEM=1`; image Play Store tidak mendukungnya).
  Patch sed sudah diuji terhadap `cli/src/device/emulator.py` upstream (py_compile OK); build image BELUM dijalankan.
- Default AVD `Pixel C` (tablet), framebuffer 1920x1080, RAM 8 GB, 6 core, data 16 GB (n2-standard-8: 8 vCPU / 32 GB).
- Render default (`gui_emu_gpu=none`): `swiftshader_indirect` (CPU). Video realistis; game 3D berat lambat.

### Varian GPU (`gui_emu_gpu = "t4"`), USULAN, belum di-apply

- vm-emu jadi `n1-standard-8` + 1x `nvidia-tesla-t4`, `min_cpu_platform = Intel Skylake` (N1 di Jakarta maks Skylake),
  `on_host_maintenance = TERMINATE` (VM GPU tidak bisa live-migrate), nested virtualization tetap aktif.
  Precondition: zona harus asia-southeast2-a/b (T4 hanya di a dan b), tidak boleh digabung `emu_spot`.
- `emu-gpu-setup.sh` (dipanggil `gui-emu-up.sh` bila metadata `gui-emu-gpu != none`): driver
  `nvidia-headless-570-server` + `libnvidia-gl-570-server` (GL/EGL/Vulkan, tanpa Xorg), nvidia-container-toolkit,
  `nvidia-ctk runtime configure --runtime=docker`. Idempoten; reboot maksimal sekali kalau modul belum termuat.
  Hasil di `/opt/lab5g/gpu.env`.
- Container: `--gpus all -e NVIDIA_DRIVER_CAPABILITIES=all`, `EMULATOR_GPU=host`, emulator dijalankan lewat
  `vglrun -d egl0` (VirtualGL 3.1.5 back end EGL: GLX emulator -> GPU tanpa X server 3D; frame dibaca balik ke Xvfb ->
  x11vnc/noVNC). Tanpa GPU / toolkit -> otomatis `swiftshader_indirect`.
- Dashboard: baris "GPU" (nama, mode, util, mem, suhu dari nvidia-smi) dan "Renderer Android"
  (`dumpsys SurfaceFlinger` GLES; hijau bila NVIDIA/Tesla T4).
- Kuota (18 Nov 2026): NVIDIA_T4_GPUS asia-southeast2 = 0, GPUS_ALL_REGIONS = 0; permintaan ke 1 ditolak otomatis.
  Harus diajukan lewat console sebelum `gui_emu_gpu = "t4"`.
- Estimasi biaya: sekitar USD 1,14-1,19/jam (n1-standard-8 0,511 + T4 ~0,35-0,40 + n2-standard-4 0,261 + disk ~0,013 +
  NAT ~0,008). Estimasi harga list, bukan tagihan.
- `gui_emu_api = "budtmo"` = fallback ke image budtmo asli (tanpa build).

### Sesi user emulator persisten (`gui_emu_userdata_uri`), SENSITIF

YouTube memblok IP Cloud NAT GCP ("Sign in to confirm you're not a bot"); solusinya login akun Google **tes** di emulator.
Agar tidak login ulang tiap apply, userdata emulator (`/home/androidusr/emulator` + `.android/avd`) bisa disimpan ke bucket privat.

> **SENSITIF:** arsip berisi token sesi akun Google. Jangan commit ke repo, jangan taruh di log/evidence, jangan share.
> Pakai akun tes khusus, bukan akun pribadi. Cabut sesi dari myaccount.google.com > Security > Devices bila arsip bocor.

Setup bucket (sekali, di luar terraform agar tidak ikut `terraform destroy`):

```bash
gcloud storage buckets create gs://<bucket-privat> --location=asia-southeast2 \
  --uniform-bucket-level-access --public-access-prevention
gcloud storage buckets update gs://<bucket-privat> --versioning
# hanya owner + SA lab yang boleh akses; hapus binding projectViewer/projectEditor bawaan
```

- Simpan (di vm-emu, setelah login): `sudo EMU_USERDATA_URI=gs://<bucket-privat>/emu/session-api36-pixelc.tar.zst bash /opt/lab5g/vnc/emu-session-save.sh`
  (sync, stop emulator, `docker cp`, strip snapshot/lock, manifest `lab5g-session.json`, zstd, upload `.tar.zst` + `.sha256` + `.json`, start lagi).
  Butuh `roles/storage.objectAdmin` untuk SA `lab5g-emu` di bucket itu, diberikan manual.
- Restore: set `gui_emu_userdata_uri` di tfvars. Terraform memberi SA `lab5g-emu` `roles/storage.objectViewer` di bucket itu dan mengisi metadata `gui-emu-userdata-uri`.
  `emu-vnc-start.sh` lalu memanggil `emu-session-restore.sh` di antara `docker create` dan `docker start`: verifikasi sha256, cocokkan manifest
  (api/img_type/device) dengan container. Kalau tidak cocok atau gagal, muncul peringatan dan emulator boot fresh (tidak fatal).
- Arsip terikat pada image/API/device. Ganti `gui_emu_api`/`gui_emu_device` berarti login ulang lalu simpan ulang.

**Known issue:** CLI budtmo (`is_initialized`) membandingkan "Pixel C" dengan `hw.device.name=pixel_c`, jadi selalu False.
Akibatnya AVD dibuat ulang dan `-wipe-data` jalan di setiap start, sehingga sesi hasil restore terhapus. `vnc/emu-image/patch-cli.py`
memperbaiki regex ini (case-insensitive, bentuk `pixel_c`). Lihat hasil verifikasi restore di `test-run-logs/apply-1313/SUMMARY.md`.
Status restore: **BELUM TERVERIFIKASI**. Uji ke-2 (image dengan patch-cli.py) dihentikan karena melewati timebox:
download + extract ~1 menit, lalu `docker cp -a` 3.2 GB ke container berjalan >7 menit (writeback disk standar, load ~6).
Arsip asli (diambil sebelum wipe, accounts=1) tetap aman di bucket.
**Usulan perbaikan:** jangan pakai `docker cp`. Extract langsung ke direktori host (mis. `/var/lib/lab5g/emu-userdata`,
chown 1300:1301) dan mount sebagai volume (`-v /var/lib/lab5g/emu-userdata:/home/androidusr/emulator`). Restore jadi cukup sekali
extract tanpa copy kedua, dan sesi tetap ada walau container dibuat ulang. Pertimbangkan pula disk pd-balanced/pd-ssd untuk vm-emu.

### Uji Emulator Usability (sesi fresh apply)

- `usability-core.sh`: ping UE 30 menit (loss, p95 per 5 menit, gap), reattach, iperf3 TCP DL/UL ke
  vm-emu:9000 (retransmit).
- `usability-emu.sh`: loop page load 30 menit + Chrome via adb, 3× download 100 MB (variasi), cek jalur egress.
  Mode `ue-l3`: curl dijalankan dari container sementara di docker0 (jalur L3 yang sama dengan emulator) + cek
  delta byte `gre-core` > 0 dan QUIC/HTTP3; mode `ue-proxy`: curl lewat CORE_PROXY.
- Log ditulis ke `/var/log/lab5g/usability/*.json`.

## Konek dari laptop

1. **Prasyarat:** Google Cloud SDK terpasang, `gcloud auth login` dengan akun yang ada di
   `my_iap_users`, lalu `gcloud config set project <PROJECT_ID>`. Opsional, `pip install numpy`
   supaya tunnel IAP lebih cepat.
2. **Buka tunnel** dan biarkan terminal ini tetap terbuka:
   ```bash
   gcloud compute ssh vm-emu --project=<PROJECT_ID> --zone=asia-southeast2-a --tunnel-through-iap -- -N -L 6081:localhost:6081 -L 6080:localhost:6080 -L 5900:localhost:5900
   ```
3. **Buka di browser** `http://localhost:6081/` untuk emulator + dashboard (basic auth `lab`), atau `http://localhost:6080/vnc.html` untuk noVNC saja. Lalu masukkan password VNC.
4. **Alternatif klien VNC biasa** (TigerVNC/RealVNC): pakai tunnel yang sama ke `localhost:5900`.

## Membaca password

Baca password langsung dari VM. Jangan ditempel ke chat atau di-commit.

```bash
gcloud compute ssh vm-emu --project=<PROJECT_ID> --zone=asia-southeast2-a --tunnel-through-iap -- sudo cat /opt/lab5g/vnc-password.txt
# hanya jika public tunnel dinyalakan (user basic auth: lab)
gcloud compute ssh vm-emu --project=<PROJECT_ID> --zone=asia-southeast2-a --tunnel-through-iap -- sudo cat /opt/lab5g/novnc-web-password.txt
gcloud compute ssh vm-emu --project=<PROJECT_ID> --zone=asia-southeast2-a --tunnel-through-iap -- cat /opt/lab5g/public-url.txt
```

Cek URL publik tanpa menampilkan password:

```bash
URL=$(gcloud compute ssh vm-emu --project=<PROJECT_ID> --zone=asia-southeast2-a --tunnel-through-iap -- cat /opt/lab5g/public-url.txt)
WEBPW=$(gcloud compute ssh vm-emu --project=<PROJECT_ID> --zone=asia-southeast2-a --tunnel-through-iap -- sudo cat /opt/lab5g/novnc-web-password.txt)
WEBPW="$WEBPW" python3 infra/gcp/vnc/verify-public.py "$URL"; unset WEBPW
```

## Risiko public tunnel (opt-in, default mati)

- Quick Tunnel (`trycloudflare.com`) tidak punya SLA dan tidak butuh akun. Cloudflare bisa membatasi
  atau memutusnya kapan saja. URL berubah setiap kali service atau VM restart.
- TLS diputus di Cloudflare, jadi Cloudflare bisa melihat trafik HTTP dan noVNC. Password VNC tetap
  jadi lapisan kedua.
- Basic auth tidak punya rate limit atau lockout. Siapa pun yang tahu URL bisa mencoba login, jadi
  keamanannya bergantung pada panjang password acak.
- Kalau butuh URL tetap atau kontrol akses yang lebih kuat, pakai named tunnel dengan Cloudflare Access.
  Ini USULAN dan belum diimplementasikan.
- Mematikan tunnel:
  ```bash
  gcloud compute ssh vm-emu --project=<PROJECT_ID> --zone=asia-southeast2-a --tunnel-through-iap -- sudo /opt/lab5g/novnc-public-toggle.sh off
  ```

## Catatan

- Mode `ue-l3`: tidak ada proxy aplikasi; semua trafik container lewat UE. Trafik host vm-emu sendiri (apt, docker
  pull, cloudflared) tetap lewat Cloud NAT (rule hanya `iif docker0`).
- Sesi GUI tidak memasang shaping HTB Sesi C (dihapus oleh `gui-core-up.sh`).

## Biaya dan teardown

- **Perkiraan biaya: sekitar USD 0,80/jam** untuk n2-standard-8 (0,5224) + n2-standard-4 (~0,2612)
  + pd-standard 180 GB (~0,013) + Cloud NAT (~0,008), di asia-southeast2. Belum termasuk NAT data
  processing USD 0,045/GiB dan egress.
  - Sumber: harga list GCP via instancefinder.com/usage.ai (N2), gcloud-compute.com (disk), dan
    cloud.google.com/nat/pricing. Angka ini estimasi, bukan tagihan.
- Lab jangan dibiarkan hidup tanpa dipakai. Teardown:
  ```bash
  cd infra/gcp/terraform && terraform destroy
  ```
  Password, tunnel publik, dan URL ikut hilang bersama VM.
