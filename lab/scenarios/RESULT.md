# Uji QoD on-demand lewat VPN booster-app (examine) — box, offline, USD 0

Tanggal 2026-11-19, 16:20–17:30 WIB. Scope: box saja, tanpa GCP/emulator-host, tanpa commit/push/PR, tanpa ubah repo the booster-app repo maupun this repo. `/workspace/fase0-closeout` dan `/workspace/radio-uplift` tidak disentuh. Tidak ada IMSI/K/OPc/token di hasil (UE IP disamarkan `<UE>`).

## 0. Verdict (ringkas)

**Gerbang go/no-go: LOLOS untuk varian (a) full-tunnel via relay dan varian examine-only (c), DL dan UL. Varian (b) split-tunnel LOLOS di jaringan, tetapi deteksi berbasis kepemilikan socket harus diperbaiki (lihat §6).**

- **FAKTA:** QFI 2 di N3 hanya dipakai flow target (server:port yang diminta di N5). Semua flow bulk dari UE yang sama (TCP up/down, UDP echo, ICMP keepalive) tetap QFI 1, DL dan UL. `non_target_pkts_on_QFI2 = 0` di semua run valid.
- **FAKTA:** relay memakai tujuan asli (IP:port asli) → filter N5 `permit in <p> from <UE> to <AS> <port>` cocok. Header/ukuran paket tidak berubah (tidak ada trailer): UDP 228 B, TCP maks 1500 B dengan MTU/MSS relay 1500/1460, 1400/1360 untuk v0.10.2. Yang berubah hanya **port sumber sisi UE** (relay membuka socket sendiri, port ephemeral baru per flow); itu tidak masalah karena filter UL tidak memuat port UE.
- **FAKTA (latensi):** API→paket QFI 2 pertama di N3 ≈ 20–50 ms (DL), UL 30–110 ms; DELETE→QFI 1 kembali 32–48 ms. **Tidak ada penurunan RTT** target saat boost (sel tidak padat, scheduler gNB `qosrel` tidak memberi prioritas). Jadi bukti "stall/p99 turun ≥50%" **belum** dibuktikan di sini; itu butuh sel padat + gNB slicing (eval `/workspace/oai-slicing-eval`, image `-slice`).
- **APK asli TIDAK dijalankan.** Dipakai **stand-in**: forwarder native (kode asli lwIP milik booster-app, dimodifikasi minimal) di TUN. Detail dan yang tidak tercakup di §2.

## 1. Tiga langkah (alur user: examine deteksi flow → info CAMARA untuk boost → terbukti di jaringan)

| Langkah | Implementasi di uji | Bukti |
|---|---|---|
| 1. Examine mendeteksi flow target, turunkan applicationServer IP/port + device IP | `detect_boost.py`: mode `relay` membaca baris `FLOW` (= baris NAT forwarder = flow di TUN examine) dan mencocokkan aturan media (198.51.100.1:18080, stand-in untuk klasifikasi DNS/SNI); mode `owner` memakai `ss -p` pada proses `targetapp` (stand-in `getConnectionOwnerUid`). Device IP = alamat `oaitun_ue1`. | `res/<tag>/detect.out`, `relay.log` |
| 2. Deteksi memicu QoD lewat N5 | `qod_boost.py` → Mongo bridge (PCC QOS_7, 5QI 7) → BSF → N5 Create (TCP+UDP, DL+UL), PCC dihapus dari DB setelah 201, lalu DELETE setelah 28 s. Adapter CAMARA `/workspace/qod-adapter` hanya ada spec/container `qa-*` milik task lain, **tidak dipakai**. | `res/<tag>/events.jsonl` |
| 3. Bukti jaringan: QFI 2 hanya flow target + latensi sebelum/sesudah | N3 `tcpdump -i lo udp 2152` + `qfi_flow.py` (tabel QFI per flow, CSV, PNG) + `rtt_sum.py` | `res/<tag>/<tag>_{flows.csv,bins.csv,gate.json,qfi.png}`, `qfi.txt`, `n3.pcap` |

Trafik per run (70 s): bulk dari UE yang sama ke AS kedua 198.51.100.2 (TCP up 5201 6 Mbit/s, TCP down 5202 6 Mbit/s, UDP echo 5203 300 pps×1000 B) + keepalive ping 1 s sejak attach; target ke 198.51.100.1:18080 (UDP echo 50 pps + fetch TCP 150 KB/s) mulai detik 15; Create ≈ detik 25 (hold baseline 10 s); DELETE 28 s kemudian.

## 2. Versi dan cara VPN booster-app meneruskan trafik (FAKTA, dari sumber)

**Baseline user = PoC `booster-poc-examine-v0.10.2`** (APK `/workspace/poc-latency/phase2/booster-poc-examine-v0.10.2.apk`, sha256 `fcc5e8a7…622c`, sumber Java `/workspace/poc-latency/phase2/app/src/id/booster/poc/examine/`, dibaca read-only). Ini **bukan** the booster-app repo. Tiga implementasi dibandingkan:

| Aspek | PoC v0.10.2 (`ExamineVpnService.java`) | booster-app `main` (`BoosterVpnService.kt`) | booster-app branch `cursor/examine-android-d5ab` (@9e91a26) |
|---|---|---|---|
| Forwarding | **Ya**, tingkat koneksi di Java: TCP diterminasi di TUN (state machine kecil), `SocketChannel` `protect()`+`bindSocket(underlying)` ke **tujuan asli**; UDP: `DatagramSocket` per flow, `connect()` ke tujuan asli | **Tidak**: black-hole, paket dibaca lalu dibuang (`Os.read` + sink) | Ya: forwarder native C (`booster_forward.c`) + **lwIP 2.2.1** terminasi TCP, NAT table, socket upstream ke tujuan asli (JNI `jni_open`, `protect()`) |
| IP/port tujuan | Dipertahankan; port sumber di upstream = ephemeral baru | – | Dipertahankan; port sumber ephemeral baru |
| Remote tunnel / tun2socks | Tidak ada tunnel jauh; keluar langsung lewat jaringan fisik/UE. Ada "de-proxy" `CONNECT host:443` ke proxy emulator (khusus lab) | – | Tidak ada |
| TUN | 1400 MTU (MSS 1360), alamat `/32`, route `0.0.0.0/0`, DNS 192.0.2.20 (UDP DNS lewat forwarder) | MTU 1500, 10.111.222.1/32, `0.0.0.0/0`+`::/0` | MTU 1500, 10.111.222.1/32, DNS 10.111.222.2 |
| Per-app / split tunnel | `addAllowedApplication` (app sendiri + Chrome via extra `apps`); app lain **di luar** TUN (langsung) | Hemat: allow-list; Darurat: `addDisallowedApplication`; `examineOne`: hanya target di TUN | `examineOne` (hanya target di TUN) dan varian Hemat/Darurat+Examine |
| "Timestamp examine" | **Bukan trailer di paket app.** Marker **MGLT v1 60 B = datagram UDP terpisah** ke reflector 192.0.2.20:9000 (event syn/est/data/fin/udp, 5-tuple asli di ekstensi), lewat jalur UE yang sama; juga probe v2.1 :9001 per paket QUIC. Payload TLS/TCP tidak diubah. | – | Hanya pengukuran lokal (RTT connect TCP, RTT QUIC Initial); tidak ada byte disisipkan |
| QUIC | Diteruskan (sejak v0.9.1) | – | Diteruskan sebagai UDP |
| IPv6 | v0.10.1+: marker/probe IPv4 saja | rute `::/0` | didukung |

**Konsekuensi untuk QoD (FAKTA + USULAN):**
1. Flow app target dipertahankan (IP:port tujuan asli) → N5 per server:port bekerja.
2. **Marker MGLT adalah flow UDP terpisah ke reflector (192.0.2.20:9000/9001).** Kalau QoD hanya mencakup server target, marker tetap QFI 1 dan MGLT mengukur bearer **tanpa boost** (m3). Agar bukti before/after MGLT mencerminkan boost, reflector harus ikut di filter QoD (m4: marker QFI 2). Spesifikasi QoD v1.2.0 (spec di `/workspace/qod-adapter/spec`): `applicationServer` = **daftar `ipAddresses`** *atau* satu subnet IPv4/IPv6; jadi target + reflector bisa dikirim sebagai daftar IP. Port di spec diberikan per permintaan (bukan per IP) → port reflector harus masuk daftar port yang berlaku untuk semua IP (superset). Perlu dikonfirmasi saat membangun adapter.

## 3. APK asli vs stand-in

- **FAKTA:** APK asli tidak bisa jalan di box: kernel 6.12 tanpa binder/binderfs (redroid tidak mungkin), tidak ada JDK/Android SDK/emulator, dan APK PoC sebelumnya dijalankan di emulator host `emulator-host` (di luar scope).
- **Stand-in (diberi label jelas):** `fwd/booster_relay` = **kode asli `booster_forward.c` + `booster_pkt.c` dari branch examine @9e91a26 + lwIP 2.2.1** (build host, `-DBOOSTER_HOST_TEST`) dengan 3 perubahan: `jni_open` membuka socket upstream sungguhan ke IP:port asli (`protect()` digantikan karena TUN berada di netns lain), log `FLOW` saat membuat baris NAT, dan `main()` yang membuka TUN di netns `appnsN` lalu kembali ke netns UE (`diff` terhadap aslinya: `fwd/booster_forward.orig.c`). Varian `booster_relay_v0102`: TCP_MSS 1360, netif MTU 1400 (meniru v0.10.2).
- **Tidak tercakup vs APK v0.10.2 asli:** Java forwarder-nya sendiri (state machine TCP, flow-control window, `bindSocket(underlying)`), de-proxy CONNECT, QUIC/probe MGLT v2.1, DNS 192.0.2.20, `getConnectionOwnerUid` Android, perilaku Chrome nyata, VpnService/netd. Marker MGLT v1 ditiru oleh `mglt_marker.py` (60 B, layout `Mglt.java`, dikirim dari luar TUN, event syn/est/data/fin/udp); bukan jam/Zeek asli. Aplikasi = skrip Python (`app_client.py`), bukan Chrome/YouTube.
- Dampak: klaim "flow tetap terlihat dan QoD tetap tepat sasaran" berlaku untuk **pola forwarding** (terminasi + upstream ke tujuan asli), yang sama di v0.10.2 dan stand-in. Belum diverifikasi pada perangkat/emulator nyata.

## 4. Hasil gerbang per varian (FAKTA)

Semua dengan gNB OAI v3.0.0 + patch `qosrel` (kecuali a1: stok), core Open5GS 2.8.0, rfsim. Konkurensi: task lain menjalankan gNB/RAN bersamaan pada sebagian run (kolom Catatan) → CPU dibagi.

| Run | Varian | Detail | Gerbang DL+UL | API→QFI2 pertama DL / UL (ms) | DELETE→QFI1 DL (ms) | Catatan |
|---|---|---|---|---|---|---|
| **a1** | (a) full-tunnel, target+bulk di TUN, relay 1500 | gNB stok (tanpa DELETE) | **PASS** | 48,1 / 47,6 | – | QFI2: target UDP+TCP saja; bulk 5201/5202/5203 + ICMP QFI1 |
| **c1** | (c) examine-one: target di TUN, bulk langsung | | **PASS** | 42,0 / 41,7 | 42,3 | |
| **a2** | (a) | UE2, QFI 3 (sesi kedua) | PASS | 33,7 / 109,4 | 32,3 | **Anomali:** fetch TCP target gagal ±25 s sesudah Create (UDP target normal, QFI3), pulih setelah DELETE; flow TCP bulk 5201 reset di pra-fase. Tidak terulang di a1/c1/m3/m4 → diduga gangguan RAN/CPU (3 gNB jalan bersamaan). Perlu pengulangan. |
| **b1** | (b) split-tunnel: target langsung (deteksi via `ss`), bulk di TUN | deteksi hanya TCP | **FAIL (bukan karena jaringan)** | 475 | 8,5 | Socket UDP target tidak `connect()` → `ss` tak punya peer → protokol UDP tidak diminta → UDP target tetap QFI1. Perbaikan: selalu minta TCP+UDP |
| **b2** | (b) setelah perbaikan (selalu 6,17) | UE2 baru | **PASS** | 37,2 / 30,8 | tidak terukur | fetch TCP gagal sebagian (12) saat 3 gNB berjalan → anomali seperti a2 |
| **m3** | (c) **meniru v0.10.2** (MTU 1400/MSS 1360 + marker MGLT) — QoD hanya server target | marker→reflector 198.51.100.3:9000 | **PASS** | 20,3 / 54,8 | 47,8 | marker UL/DL tetap **QFI 1** |
| **m4** | sama, QoD **server target + reflector** | | **PASS** (reflector diizinkan) | 407 / 407 (burst TCP 1/s menentukan paket pertama; UDP lebih cepat) | 37,6 | marker UL 108 / DL 108 pkt di **QFI 2** |
| a3, a4 | – | – | **TIDAK VALID** | – | – | gNB `qosrel` abort `seq_arr_free: Assertion arr->data != NULL` saat membuang UE context lama setelah GTP Error Indication → PDU release (ketiga RAN berjalan bersamaan); dibuang, perlu dilaporkan ke task patch gNB |

Hitungan paket per flow (contoh m4, fase "on" = QFI2): DL UDP target 1400, DL TCP target 2969, UL UDP target 1399, UL TCP target 2296; marker 109 UL + 109 DL. Flow bulk (TCP 5201/5202, UDP 5203, ICMP) 100% QFI 1. Tabel penuh: `res/<tag>/<tag>_flows.csv`.

Latensi target (RTT UDP echo 50 pps, ms; sebelum → saat boost), sel tidak padat:
- a1: p50 17,5→13,9; p99 47,7→138 | c1: p50 11,5→9,7; p99 25,7→58,9 | m3: p50 18,0→14,2; p99 42,2→40,1 | m4: p50 20,3→16,1; p99 45,1→53,5.
- Marker MGLT RTT (m3 tanpa boost / m4 dengan boost): p50 19,4→17,8 / 18,9→15,9; p99 43,9→43,8 / 52,8→104,9.
- **FAKTA:** tidak ada perbedaan bermakna; selisih p50 ±3 ms ada di dalam derau (RAN bersama dengan task lain). **USULAN:** bukti latensi untuk demo harus memakai sel padat + gNB slicing.

## 5. Keepalive, restore, state box

- Keepalive: ping 1 s di bearer default tiap UE sejak attach (`run-ran.sh`, `run-ue.sh`); UE tidak pernah idle selama run valid.
- Restore (17:30 WIB): PCC di DB uji = 0 rule (`subs_with_pcc=0`); container `mq-gnb/mq-ue1/mq-ue2/mq-mongo/mq-lab`, volume `mq-mongo-db`, image `lintas5g/mq-lab:tmp`, netns `appns*`, dan image `alpine:latest` (saya tarik) dihapus. Container task lain (`n5-*`, `qa-*`, `srs-*`, `n5-build*`) **tidak** diubah/dihentikan. Yang tersisa: `/workspace/booster-qod-test/` (kode, hasil, ±200 MB pcap).

## 6. Temuan dan rekomendasi untuk demo booster (USULAN kecuali dinyatakan FAKTA)

1. **Deteksi app (FAKTA dari uji):** deteksi lewat TUN examine memberi 5-tuple asli (tujuan asli) pada flow pertama; deteksi lewat `getConnectionOwnerUid`/`ss` (split tunnel) **tidak melihat UDP tak-terhubung** dan butuh 5-tuple lengkap dari paket. → pakai TUN examine (varian c/a) sebagai sumber deteksi, `getConnectionOwnerUid` hanya untuk memetakan flow→paket app, dan DNS/SNI/QUIC Initial untuk mengklasifikasi flow media (domain→IP).
2. **Selalu minta TCP dan UDP** untuk server:port yang terdeteksi (CAMARA tidak menyebut protokol; QUIC/UDP 443 pada YouTube). Terbukti: b1 gagal tanpa UDP.
3. **applicationServer:** gunakan `ipAddresses` (daftar) bukan subnet bila CDN beragam; masukkan **reflector MGLT** agar before/after MGLT terukur di bearer yang di-boost; port berlaku per permintaan → superset port.
4. **Mode TUN:** `examineOne` (hanya app target di TUN, bulk app lain langsung) adalah varian paling bersih (c1, m3, m4). Full-tunnel (a) juga lolos bila bulk ikut di TUN.
5. **Split tunnel** hanya cadangan: lolos di jaringan (b2) tapi kehilangan data latency examine untuk app yang dikecualikan dan deteksi UDP sulit.
6. **MTU/MSS:** relay tidak mengubah ukuran paket di N3 selain batas MTU TUN; tidak ada trailer. Tidak ada risiko cocok-filter karena ukuran.
7. **Risiko gNB (FAKTA):** DELETE/penggantian QoS flow di bawah beban atau konkurensi RAN memicu GTP Error Indication → PDU release; sekali gNB `qosrel` abort (`seq_arr_free`). Laporkan ke task patch gNB; hindari DELETE saat UL berat; cek ulang a2/b2 anomali TCP di RAN yang tidak berbagi CPU.
8. **Belum dibuktikan:** penurunan stall/p99 ≥50% (butuh sel padat + `-slice`), APK/emulator nyata, adapter CAMARA (spec saja), uji >1 target app, QUIC nyata.

## 7. Berkas

- Kode: `fwd/` (relay + lwIP, `build.sh`), `run_variant.sh`, `run_m.sh`, `detect_boost.py`, `qod_boost.py`, `as_server.py`, `app_client.py`, `mglt_marker.py`, `qfi_flow.py`, `rtt_sum.py`, `run-ran.sh`, `run-ue.sh`, `batch*.sh`.
- Sumber acuan yang diambil: `ref/` (`booster_forward.c`, `booster_pkt.c`, `TunPlan.kt`, `ExamineFlow.kt`, `ExamineNative.kt`, `network-analysis.md`), `BoosterVpnService.kt` (main).
- Hasil: `res/{a1,a2,b1,b2,c1,m3,m4}/` (+ `res/old-noreflector/m1,m2` = run tanpa reflector hidup, gerbang PASS tapi marker tidak terjawab, tidak dihitung; `res/a3,a4` tidak valid).
