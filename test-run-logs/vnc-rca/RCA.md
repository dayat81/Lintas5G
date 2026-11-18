# RCA: internet emulator "not stable" (sesi VNC, 18 Nov 2026)

Lab hidup 10:38–11:20 WIB, lalu di-destroy atas arahan user. Data ada di `rca-core/` dan `rca-emu/`.
Data mentah sudah di-redaksi: IMSI disamarkan dan URL trycloudflare diganti. File password tidak ikut disalin.

## FAKTA (terukur)

| Area | Hasil |
|---|---|
| ZMQ/srsRAN | Hanya ada 1 reattach (10:53, uji watchdog sengaja). Keepalive 1303 sampel sejak 10:53: loss 0, p50 30,1 ms, p95 40,3 ms, p99 41,7 ms, max 66,8 ms, gap maksimum 1,04 s. Ping 60 s: 0% loss. Tidak ada RLF di ue.stdout/MME. |
| gost | 212 koneksi setelah 10:54 dengan 0 error. Semua 62 error (network unreachable, resolver) terjadi 10:52:36–10:53:43, yaitu saat uji reattach. |
| Proxy dari vm-emu | 20/20 `generate_204` OK. TTFB 136–197 ms (p50 ~165 ms). Sampel ini pendek. |
| tc/QoD | HTB 15 Mbit DL / 8 Mbit UL (sisa Sesi C) masih aktif, burst 1600 B. Drop 0, tapi overlimits 6949 pada 5630 paket. Shaping aktif menahan burst. |
| MTU/MSS | ogstun MTU 1400, tun_srsue MTU 1500, dan tidak ada TCPMSS clamp. Path ke internet: frag-needed mtu 1460. DF 1400 lolos. |
| DNS netns UE | Query ke 8.8.8.8 butuh 94–114 ms, sekitar 3–4× RTT ping. Semua rcode 0. |
| Jalur emulator | Emulator punya jalur langsung: adb `ping 8.8.8.8` RTT ~2 ms via wlan0 → docker → Cloud NAT (bypass UE). DNS emulator lewat 169.254.169.254. Selama 25 s dengan Chrome/YouTube terbuka, tidak terlihat UDP/443 (QUIC) maupun TCP 80/443 langsung. |
| CPU | Core: srsue 77% + srsenb 68% (spin ZMQ), load ~2/4 vCPU, steal 0%. Emu: 97% idle, qemu ~92% dari 1 core, steal 0%. |
| Cloudflare/caddy | Tidak ada error atau reconnect di log cloudflared. Precheck QUIC dan HTTP/2 PASS. |

## Hipotesis root cause (belum ada reproduksi gejala selama sampel)

1. **MTU/MSS mismatch** (keyakinan sedang).
   - gost di netns UE mengiklankan MSS 1460 karena tun MTU 1500. Segmen downlink >1400 B kena MTU 1400 di ogstun, sehingga bergantung pada ICMP frag-needed sampai ke server (lewat MASQUERADE).
   - Kalau PMTUD terblokir, koneksi besar macet. Gejalanya halaman atau download "kadang hang", sementara ping dan request kecil tetap OK.
   - Ini konsisten dengan ping yang mulus tapi tetap ada keluhan.
2. **Shaping QoD Sesi C yang tertinggal** (keyakinan sedang).
   - HTB 15/8 Mbit dengan burst 1600 B membatasi throughput dan menahan burst halaman maupun video.
   - Tidak ada drop, tapi throughput yang dirasakan lebih rendah dan tidak rata.
3. **Jalur ganda emulator** (keyakinan rendah–sedang untuk "tidak stabil", tinggi untuk "tidak konsisten").
   - App yang mengabaikan proxy keluar langsung lewat NAT. Akibatnya perilaku antar-app berbeda, dan ini melanggar aturan "emulator via UE".
4. **DNS lewat UE ~100 ms per query.** Ini menambah latency pada domain baru saja. gost mem-cache 300 s. Ini bukan sumber ketidakstabilan.
5. **Persepsi lag VNC lewat Quick Tunnel** (belum diukur). Bisa jadi yang dimaksud "not stable" adalah stream VNC, bukan internet emulator.

## Belum terbukti

- Gejala tidak sempat terekam: tes panjang dihentikan dan lab di-destroy.
- Tidak ada tes throughput 100 MB, iperf3/retransmit, atau loop curl 10 menit.
- Tidak ada pengukuran rebuffer YouTube.
- Belum ada bukti langsung PMTUD blackhole, misalnya tcpdump frag-needed atau retrans pada segmen besar.

## RCA 2: "YouTube cannot play video" (18 Nov 2026 ~11:51 WIB)

- **FAKTA:** kebijakan `ue-only` (proxy-only) aktif. Counter `LAB5G-EMU` menolak 489 paket TCP + 142 lainnya dari
  container (koneksi langsung); log gost di core tidak berisi `googlevideo.com`; logcat: error `CronetUrlRequestContext`.
- **Root cause:** app YouTube (Cronet/ExoPlayer) tidak memakai proxy HTTP global Android dan mencoba QUIC/TCP langsung;
  `ue-only` menolaknya (sesuai desain fail-visible), sehingga video tidak bisa diputar. Chrome (yang memakai proxy) jalan.
- **Perbaikan di IaC (lokal, belum di-apply):** mode default baru `ue-l3`: GRE vm-emu <-> vm-core-ran + policy routing
  `iif docker0` -> GRE -> `iif gre-emu` -> netns ue1 -> MASQUERADE ke IP UE. Semua TCP/UDP/QUIC lewat UE tanpa proxy.
  Fail-closed (unreachable + REJECT), filter atomik (iptables-restore), self-heal timer 30 s, watchdog core re-apply.
  Diuji offline dengan netns (veth pengganti GRE): TCP + UDP/443 keluar dengan source IP UE; GRE down -> ditolak.
- **Terkait "latest app: video & game":** emulator 13.0 = x86_64 saja, tanpa Play Store. IaC sekarang membangun image
  Android 16 (API 36) `google_apis_playstore` (translasi ARM64), tablet Pixel C 1920x1080. Render tetap CPU (swiftshader).

## Status lab saat RCA 2 ditulis

- Lab sudah di-destroy (terraform state kosong; `terraform plan -refresh=false` = 101 to add, 0 to change, 0 to destroy).
- Sesuai instruksi user 12:01 WIB: tidak ada `terraform apply` dan tidak ada push.
