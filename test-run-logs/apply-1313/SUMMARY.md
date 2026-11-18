# Fresh apply 18-11-2026 13:13 WIB, verifikasi YouTube + jalur UE (tanpa GPU)

Konfigurasi: gui_session=true, gui_emu_egress=ue-l3, Android 16 (API 36 google_apis_playstore x86_64 + libndk_translation), Pixel C 1920x1080, swiftshader.
Apply 1m28s (13:15 WIB). Destroy 14:54-14:58 WIB (102 resource). Biaya sesi ~1j45m x ~$0.80/j ≈ $1.4 (plus egress/GCS kecil).

| Uji | Hasil | Bukti |
|---|---|---|
| T1 Android 16 / Play Store / ARM | PASS: SDK 36, abilist x86_64,arm64-v8a, boot 88 s | yt-first.png |
| T2 seluruh trafik emulator via UE | PASS: conntrack core NAT ke IP UE di netns ue1, LAB5G-EMU reject 0, flow langsung 0 | emu-logs/usability/egress-check.txt |
| T3 QUIC udp/443 via UE | PASS | |
| YouTube | PASS setelah login akun Google tes (tanpa login: bot-check "confirm you're not a bot" karena IP Cloud NAT GCP). App YouTube di-update ke 21.45 (versi bawaan image memaksa update). Uji manual user: PASS | yt-*.png, video-hls-t*.png |
| K2 ping 30 menit + iperf | PASS: loss 0%, avg 32.9 ms, max gap 1.07 s, reattach 0; TCP DL 10.1 / UL 14.4 Mbit/s | k2-core/ |
| K3 download 100 MB x3 | PASS (run ulang): 24.8 / 28.8 / 28.9 Mbit/s, variasi 14.8% (run1 tumpang tindih dengan K2) | emu-logs/usability/ |
| T5 dashboard + noVNC publik | PASS: 401/200, websocket 101 (cloudflared perlu `--http1.1`) | dashboard-live.png |
| K4 | tidak dijalankan otomatis, diganti uji manual user | |
| Simpan sesi user | PASS: arsip zstd 3.2 GB + sha256 + manifest di bucket privat (di luar terraform, tetap ada setelah destroy) | |
| Restore sesi | **BELUM TERVERIFIKASI**: uji 1 accounts=0 (bug budtmo is_initialized -> -wipe-data; diperbaiki patch-cli.py). Uji 2 dihentikan karena timebox: `docker cp` 3.2 GB >7 menit. Usulan: extract ke direktori host + bind mount volume | vnc/README.md |

Catatan: semua egress berbagi IP Cloud NAT yang sama, jadi IP publik tidak bisa membedakan jalur; bukti jalur UE diambil dari conntrack/NAT di core.
