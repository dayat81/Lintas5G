# Remote GUI emulator (VNC / noVNC)

Paket ini dipakai untuk sesi remote GUI emulator Android (vm-emu) di lab GCP Lintas5G.
Isinya full stack: EPC Open5GS dan srsRAN_4G ZMQ di vm-core-ran, dengan internet emulator lewat UE
(proxy gost di netns UE).

- **FAKTA:** stack ini sudah diuji di lab pada 18 Nov 2026, termasuk noVNC lewat tunnel SSH IAP,
  Quick Tunnel publik, attach ulang UE oleh watchdog, dan bukti internet emulator lewat UE.
- **USULAN:** `vnc-deploy.sh` merangkai langkah-langkah yang sudah teruji itu, tapi belum dijalankan
  utuh dalam satu kali run.

## Arsitektur

```
Laptop --(gcloud ssh --tunnel-through-iap, -L 6080/-L 5900)--> vm-emu 127.0.0.1:6080 (noVNC) / 127.0.0.1:5900 (x11vnc, password VNC)
                                                                 |
                                         emulator Android --HTTP proxy--> vm-core-ran:18080 (DNAT) -> gost di netns ue1
                                                                 -> tun_srsue -> srsENB (ZMQ) -> SGW-U/UPF -> SGi -> Cloud NAT -> internet

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
| `core-bringup-vnc.sh` | vm-core-ran | Bring-up seperti Sesi C, tanpa Zeek |
| `ue-watchdog.sh`, `install-watchdog.sh` | vm-core-ran | Watchdog attach ulang UE, berupa systemd timer |
| `emu-vnc-start.sh` | vm-emu | Emulator dengan password VNC acak, port hanya di 127.0.0.1 |
| `emu-proxy-ue.sh` | vm-emu | Proxy HTTP Android diarahkan ke gost di netns UE (`CORE_IP=...`) |
| `novnc-public-setup.sh` | vm-emu | OPT-IN: caddy basic auth dan cloudflared Quick Tunnel |
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

## Konek dari laptop

1. **Prasyarat:** Google Cloud SDK terpasang, `gcloud auth login` dengan akun yang ada di
   `my_iap_users`, lalu `gcloud config set project <PROJECT_ID>`. Opsional, `pip install numpy`
   supaya tunnel IAP lebih cepat.
2. **Buka tunnel** dan biarkan terminal ini tetap terbuka:
   ```bash
   gcloud compute ssh vm-emu --project=<PROJECT_ID> --zone=asia-southeast2-a --tunnel-through-iap -- -N -L 6080:localhost:6080 -L 5900:localhost:5900
   ```
3. **Buka di browser** `http://localhost:6080/vnc.html`, klik Connect, lalu masukkan password VNC.
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

- Proxy hanya berlaku untuk aplikasi yang memakai proxy HTTP global Android, misalnya Chrome.
  Trafik aplikasi yang mengabaikan proxy, atau UDP/QUIC, keluar langsung lewat Cloud NAT dari vm-emu.
- Shaping HTB Sesi C (DL 15 / UL 8 Mbit/s) ikut aktif.

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
