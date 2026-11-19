# Rencana tes YouTube + QoD + MGLT v2.1 (Sesi D)

Status: **skrip siap di worktree lokal**. Lab sudah di-destroy. **Belum di-apply, belum di-push.** Angka di bawah yang bukan dari run kemarin bertanda **USULAN** atau **FAKTA (kode/run 17 Nov)**.

Video default: Big Buck Bunny, `VIDEO_ID=aqz-KE-bpKQ` (Blender Foundation, ~10 menit). Kualitas opsional `VIDEO_QUALITY=hd720` (parameter `vq=`; aplikasi YouTube sering mengabaikannya — ABR tetap risiko).

## 1. Skenario

Di vm-core-ran, `run-youtube-qod.sh <emu_ip>`:

1. Pastikan pkthash 3 tap, pasang reflector `10.99.9.20:9000` (echo MGLT v1) dan `:9001` (sink v2.1) di ogstun, plus instance pktlat2 v2.1 pada veth ber-VLAN.
2. SSH ke vm-emu: install APK, `appops set … ACTIVATE_VPN allow`, start examine (`--es apps com.google.android.youtube`, `quic fwd`, `deproxy off`, `dns 8.8.8.8`, `probeport 9001`). VPN tetap hidup selama run.
3. Ukur skew jam core vs emulator (read-only, n=15, RTT terkecil) → `/var/log/lab5g/pktlat/skew.cfg`.
4. Untuk tiap ulangan (default 3) dan kondisi `idle`, `load`, `load+qod` (masing-masing 180 s):
   - health/RLF + keepalive UE (watchdog tidak dimatikan kecuali re-attach).
   - `load`: iperf3 TCP DL 4 + UL 1, start 8 s sebelum fase (sama `run-quic.sh`).
   - `load+qod`: POST QoD port 443 GBR 5 Mbit/s, plus POST port 9001 GBR 500 kbit/s (probe).
   - Restart YouTube di awal fase (startup bisa dibanding), sampel `media_session` tiap 1 s.
   - Tulis baris `phases.tsv`: `run_id cond rep t_start t_end`.
   - Hapus sesi QoD, hentikan beban, `force-stop` YouTube (VPN tetap).
5. Analisis offline + (opsional) batch ClickHouse.

Egress emulator tetap **ue-l3 GRE** (keputusan user: "Pertahankan"). YouTube mengabaikan HTTP proxy Android; jalur L3 sudah diperbaiki di Sesi D.

## 2. Integrasi Magnon examine v0.9.1

**FAKTA kode / run 17 Nov (emulator API 33, lab sebelumnya):**

- APK `magnon-poc-examine-v0.9.1.apk`, package `id.magnon.poc.examine`, versionName `0.9.1-poc`, sha256 `586720f4…35dd6`.
- Mode examine: forwarder userspace (bukan encapsulasi). QUIC udp/443 diteruskan apa adanya lewat socket `protect()` ke tujuan asli. Probe MGLT v2.1 (hash md5 64 B pertama payload, `t_ue`) dikirim ke **`10.99.9.20:9001`** (hardcoded `MARK_HOST`; extra hanya `probeport`, bukan host).
- Marker v1 ke `:9000` (echo) tetap, per-flow, bukan per paket.
- TUN `10.111.0.2`, route `0/0`, **MTU 1400**, MSS 1360.
- Intent kemarin (YouTube): `am start -n id.magnon.poc.examine/.MainActivity --es apps com.google.android.youtube --es pktlog on --es logpkt off --es probe on --es dns 8.8.8.8`.
- Consent VPN headless: `appops set $PKG ACTIVATE_VPN allow` berhasil di API 33.
- Overhead probe generator QUIC live (q-ue-20261117-174218): **13 % dari byte UL** (12,8 % UL+DL). Sesi Chrome H3 pendek bisa jauh lebih tinggi di UL karena volume kecil + kirim ulang.

**Adaptasi lab GCP (USULAN skrip, belum diukur):**

- Reflector `10.99.9.20/32` di ogstun + ACCEPT POSTROUTING agar tidak ikut Cloud NAT. Tanpa ini probe hilang (host sink tidak bisa diubah tanpa rebuild APK).
- `--es deproxy off`: default de-proxy APK menunjuk `<OLD_LAB_PROXY>` (lab sebelumnya), bukan proxy lab ini.
- pktlat2 v2.1 **tidak di-fork**. Fan-in `pktlat-mirror.py` menandai ulang paket: VLAN 102=N3 (`s1u`), 105=UE tap (`s5s8` — **bukan** S5/S8; Open5GS satu box tidak punya tap S5/S8 terpisah), 109=N6 (`sgi`, tempat probe diproses). `vlan_fivetuple` wajib agar 3 salinan 5-tuple tidak digabung.
- Skew: `skew_s = t_core − t_emu` (setara rumus kemarin `off_vm − off_emu`), diukur lewat SSH+adb (ketidakpastian lebih besar daripada coproc di host yang sama).

## 3. Kompatibilitas API 36 (FAKTA manifest + risiko)

APK v0.9.1:

| Item | Nilai | Implikasi di Android 16 (API 36) |
|---|---|---|
| `minSdk` / `targetSdk` | 29 / **33** | Tidak menarget 34+; banyak aturan FGS/VPN masih mode kompat |
| `foregroundServiceType` | **tidak ada** | `startForeground(id, notif)` tanpa tipe. Di API 34+ bisa `MissingForegroundServiceTypeException` walau target 33 — **belum diuji di API 36** |
| Izin FGS | `FOREGROUND_SERVICE` saja (bukan `_SPECIAL_USE`) | Mungkin cukup untuk target 33 |
| `<queries>` | hanya `com.android.chrome` | `addAllowedApplication(youtube)` tidak membutuhkan ini; nama paket di logcat uid mungkin `uidXXXX` |
| `VpnService.prepare()` | tetap dipanggil di MainActivity | Jika `appops` tidak membuat `prepare()` bernilai null, dialog izin muncul — **headless tidak bisa klik** |

Skrip memasang `appops` / `cmd appops` lalu memeriksa `tun0`. Jika `VPN_CONSENT=needed`, runner berhenti. Itu keputusan user (satu kali klik, mirip "Always allow" adb), **bukan** membuka VNC dari skrip ini.

## 4. QoD vs lalu lintas yang di-forward VPN (FAKTA kode)

Forwarder examine **bukan** terowongan GRE/IPsec. Paket di kawat (UE/N3/N6) tetap **UDP atau TCP ke IP tujuan asli, port 443**, sumber IP UE. Filter tc SGi `remote:any port 443` proto 6 dan 17 **tetap cocok**.

Yang tidak cocok tanpa langkah tambahan: probe `udp/9001`. Skrip menambah sesi QoD kedua (lihat README).

## 5. MTU (FAKTA + risiko)

Rantai: TUN examine 1400 → GRE emu `ue-l3` 1400 (clamp MSS 1360) → GTP-U N3 (~+36 B). Probe v2.1 dibatasi 1332 B agar tidak terfragmentasi GTP (desain v0.9.1). Payload QUIC mengikuti MTU 1400.

Risiko: setelah GRE, sisa ruang untuk UDP+GTP bisa mendorong fragmentasi IP di N3 (ditemukan di fase 2b untuk TCP 1460). Perlu dipantau `pktlat_stats` / fragment. Jangan naikkan MTU TUN tanpa ukur.

## 6. Overhead probe vs GBR 5 Mbit/s

**FAKTA 17 Nov:** 13 % UL pada generator 1200 B. YouTube UL umumnya ACK + probe, jadi **persentase UL bisa lebih tinggi** walau byte absolut kecil. Probe **bersaing di kelas bulk** jika `QOD_PROBE=0`.

Dengan `QOD_PROBE=1`, GBR kelas 1:10 ≈ 5,5 Mbit/s (masih < 80 % dari 15/8). 720p biasanya 2–5 Mbit/s DL; 1080p+ bisa melebihi 5 Mbit/s dan tetap mengantri meski ada QoD. Itu salah satu alasan ABR menyembunyikan latency.

## 7. Metrik pemutaran: yang bisa vs tidak

| Bisa diandalkan | Best-effort | Tidak dari media_session |
|---|---|---|
| state, posisi (ekstrapolasi PLAYING), maju, startup, stall setelah play mulai | width/height/bitrate/itag dari `dumpsys media.metrics` atau logcat ExoPlayer | RTT HTTP/3, alasan rebuffer, CDN, QUIC vs TCP (pakai Zeek/MGLT) |

Parser mendukung `state=3` dan `state=PLAYING(3)` (perbaikan K4).

## 8. Kriteria lulus (USULAN)

Lihat `obs/yt-qod-analyze.py` / `obs/yt-qod-queries.sql`.

- P1 — transport QUIC (udp/443) di semua fase; jika fallback TCP, run ditandai dan P1 gagal/catat.
- P2 — `stall_count` dan `stall_s` pada load+qod ≤ idle.
- P3 — `startup_s` load+qod ≤ 1,5× idle (atau idle+2 s).
- P4 — posisi maju ≥ 80 % durasi pada load+qod.
- P5 — p99 one-way DL di N6 (sgi) pada load+qod ≤ 50 % fase beban (jika n cukup).
- P6 — cakupan match MGLT ≥ 95 %.

Throughput vs bitrate dilaporkan jika bitrate ada; **bukan gerbang wajib** (ABR). Enforcement tetap di tc SGi; antrean shaper bisa di luar segmen N6 (temuan Sesi D).

## 9. Estimasi

Sekitar **USD 2**, **±1,5 jam**. Budget kumulatif hari ini sudah ~USD 3,4; hard stop jika tembus USD 12. Watchdog UE tetap; sesi emulator tidak ditulis ulang oleh skrip ini.

## 10. Keputusan yang perlu dari user

1. **Apply lab** untuk run ini (~USD 2) — belum diminta; skrip hanya disiapkan.
2. Jika `appops` gagal di API 36: izinkan satu kali klik izin VPN (headless tidak bisa), atau rebuild APK (targetSdk 36 + `foregroundServiceType`, host probe bisa dikonfigurasi). **Rebuild tidak dilakukan** di paket ini.
3. Push/PR dokumen+IaC (AP5) tetap ditahan sesuai "Stop dulu, jangan apply atau push".
4. Opsional: `VIDEO_QUALITY`, `QOD_PROBE=0`, bersihkan binding IAM usang (bukan bagian tes ini).


---

## 11. APK v0.10.0 (lokal, 18 Nov 2026) — FAKTA build di box

Dibangun dari `phase2/app` (snapshot v0.9.1 di `app-v0.9.1-src/`), toolchain JDK17 + build-tools 36.0.0 + `platforms;android-36`, ditandatangani keystore debug yang sama (alias `poc`, cert SHA-256 `8e8049e0…826ac6c`).

- File: `/workspace/poc-latency/phase2/magnon-poc-examine-v0.10.0.apk`
- sha256: `9783a2fa4b266e495f6869fd66b96bdf5301ebcc27b5820db85f437e08bcbb43`
- versionName `0.10.0-poc`, versionCode 11, minSdk 29, **targetSdk/compileSdk 36**
- Izin baru: `FOREGROUND_SERVICE_SPECIAL_USE`, `POST_NOTIFICATIONS`
- Service: `foregroundServiceType=specialUse` (0x40000000) + property `PROPERTY_SPECIAL_USE_FGS_SUBTYPE=dummy-vpn-latency-probe`. Bukan `systemExempted` (izin itu tidak diberikan ke app biasa).
- Extra intent: `probehost` / `markhost`, `probeport` (default 9001), `markport` (default 9000). Host default tetap `10.99.9.20`. Format kawat MGLT v2.1 tidak diubah.
- `POST_NOTIFICATIONS` diminta di MainActivity secara non-blocking; start VPN tidak menunggu hasil. Headless: `pm grant`.
- Consent dilaporkan ke logcat: `VPN_CONSENT=ok|needed` (tag `MAGNON_EXAMINE`).
- `am start-foreground-service` didukung (service `exported=true`; bind tetap `BIND_VPN_SERVICE`).
- **Belum di-smoke-test di emulator API 36** (tidak ada system image/emulator di box; lihat laporan).


---

## 12. Perbaikan lokal v0.10.1 / TRANSPORT / sgiq (18 Nov 2026, WIB) — FAKTA kode, belum di-rerun

Status: **perbaikan hanya di worktree lokal**. Tidak ada `terraform apply`, tidak ada tulis gcloud, tidak ada commit/push/PR. Temuan yang memicu ubahan ini berasal dari run resmi `ytqod-20261118-134705` (lihat `2026-11-18-sesi-d-youtube-qod.md`).

### 12.1 APK examine v0.10.1

- Socket probe/marker MGLT dipaksa IPv4 (`Ipv4.resolve` + bind `0.0.0.0:0`) agar paket sampai `10.99.9.20:9001` lewat jalur UE dan tap IPv4. Format kawat v2.1 tidak berubah.
- Jalur start VPN resmi: `appops` + `pm grant` + `am start …/.MainActivity` (bukan `start-foreground-service`, ditolak `BIND_VPN_SERVICE`).
- YouTube: `play-start` memakai `&t=0`. Metrik resmi `advanced_s` = posisi PLAYING terakhir − pertama (`yt-playback.py`).
- Reflector: sink IPv6 opsional lewat `REFLECTOR_IP6` (default mati). `pktlat-mirror.py` merangkum frame IPv6 mentah jika ada.

### 12.2 TRANSPORT=auto|quic-only|tcp-only

Diterapkan di netns `ue1` (FORWARD+OUTPUT+INPUT, rantai `YTQOD-TRANSPORT`), dibersihkan pada EXIT. Analisis memakai `conn.log` n6 untuk porsi udp/443 vs tcp/443 per fase. P1 menyesuaikan mode (`tcp-only` lulus jika TCP mayoritas). pkthash sekarang juga meng-hash `tcp/443` (retransmit bisa berbagi hash — batasan yang didokumentasikan).

### 12.3 Tap sgiq / segmen sgi-queue

Penempatan (bukan ens4 egress untuk DL-before-shaping):

- DL di-shape di egress ogstun; AF_PACKET n6 melihat DL **setelah** HTB. Pre-shaper DL = tc `mirred`+`continue` prio 1 pada HTB root ogstun ke dummy `sgiq` (enqueue, sebelum qdisc; nft dup ke device tidak valid di family ip (continue wajib agar filter QoD tidak tertimpa). `clsact` di ogstun tidak dipakai (bentrok ingress qdisc `qod-tc`).
- UL di-shape di ifb0; n6 melihat UL **sebelum** ifb. Post-shaper UL = Zeek di ifb0 (TX setelah HTB).
- `ms_sgi_queue`: DL = t_n6 − t_sgiq; UL = t_sgiq − t_n6. Hanya di pkthash/SQL; pktlat2 tidak di-fork.

### 12.4 Estimasi rerun (USULAN, belum diminta)

Satu lab Sesi D + `TRANSPORT=auto` + destroy: sekitar **USD 1–2**, **±1,5 jam** (sama dengan run 18 Nov yang ~USD 1,1). Mode `quic-only` atau `tcp-only` tambahan ≈ +35 menit dan +USD 0,4–0,7 masing-masing. Hard stop kumulatif hari itu USD 12 tetap berlaku jika user menyetujui apply.

Keputusan yang perlu dari user: apakah mererun lab; TRANSPORT default untuk rerun itu (disarankan `auto` dulu untuk validasi probe IPv4 + sgi-queue); apakah mengaktifkan `REFLECTOR_IP6`; commit/push/PR tetap ditahan.
