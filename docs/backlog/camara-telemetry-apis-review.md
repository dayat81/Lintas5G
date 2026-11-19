# Review API CAMARA untuk telemetri RAN live (xApp FlexRIC) dan app adaptif

Tanggal: 19 Nov 2026 (WIB). Status: riset saja, tanpa perubahan lab, tanpa GCP, belum di-commit.
Sumber: GitHub `camaraproject` (GitHub API releases + file YAML pada tag rilis). Semua kutipan di bawah dibaca langsung dari tag tersebut pada sesi ini.

## 1. Ringkasan

- **FAKTA:** tidak ada API CAMARA rilis yang mengembalikan metrik radio mentah per UE (PRB share, MCS/CQI, BLER, antrian RLC, latency per DRB). Yang ada hanya jawaban "memenuhi/tidak memenuhi profil", skor 0-100, atau nilai tunggal (max media rate).
- **FAKTA:** jalur paling dekat dengan kebutuhan app adaptif: `session-insights` 0.2.0 (skor kualitas via notifikasi), `connectivity-insights-subscriptions` 0.7.0 (event kualitas berbasis profil + `signalStrength` kasar), dan `media-streaming-rate` 0.1.0-alpha.1 (bitrate maksimum untuk ABR).
- **USULAN:** implementasi standar dulu: `application-profiles` + `connectivity-insights` + `-subscriptions` + `quality-on-demand` (event `qos-status-changed`). Telemetri xApp diterjemahkan ke jawaban standar (enum "meets/unable", `signalStrength`, skor). Ekstensi Lintas5G dipisah (API terpisah, namespace event sendiri), tidak mengubah schema CAMARA.

## 2. FAKTA: per API

Nama meta-release (Fall25/Spring26/Fall26) **tidak saya verifikasi**: halaman release GitHub hanya menyebut nomor `rX.Y` dan basis Commonalities r4.4 (0.9.0). README ReleaseManagement hanya menyebut proses otomatis dimulai di Spring26. Karena itu saya tulis tag `rX.Y` dan tanggal rilis. Maturity: versi `0.x` = initial/pra-stabil (rilis CAMARA menyebutnya "initial public version"); `>=1.0.0` = stabil.

| API | Versi rilis terbaru (tag, tanggal) | Maturity | Repo / file |
|---|---|---|---|
| connectivity-insights | 0.7.0 (r4.3, 18 Nov 2026) | initial (0.x) | [r4.3](https://github.com/camaraproject/ConnectivityInsights/releases/tag/r4.3), [yaml](https://github.com/camaraproject/ConnectivityInsights/blob/r4.3/code/API_definitions/connectivity-insights.yaml) |
| connectivity-insights-subscriptions | 0.7.0 (r4.3) | initial (0.x), ada breaking change vs 0.6.0 | [yaml](https://github.com/camaraproject/ConnectivityInsights/blob/r4.3/code/API_definitions/connectivity-insights-subscriptions.yaml) |
| session-insights | 0.2.0 (r2.3, 17 Nov 2026) | initial (0.x) | [r2.3](https://github.com/camaraproject/SessionInsights/releases/tag/r2.3), [yaml](https://github.com/camaraproject/SessionInsights/blob/r2.3/code/API_definitions/session-insights.yaml) |
| quality-on-demand | 1.2.0 (r4.3, 19 Nov 2026) | stabil (>=1.0) | [r4.3](https://github.com/camaraproject/QualityOnDemand/releases/tag/r4.3), [yaml](https://github.com/camaraproject/QualityOnDemand/blob/r4.3/code/API_definitions/quality-on-demand.yaml) |
| qos-provisioning | 0.4.0 (r4.3) | initial (0.x) | [r4.3](https://github.com/camaraproject/QualityOnDemand/releases/tag/r4.3) |
| qos-profiles | 1.2.0 (repo baru [QoSProfiles](https://github.com/camaraproject/QoSProfiles) r1.2, 15 Nov 2026); 1.1.0 terakhir di QoD r3.2 (16 Sep 2025) | stabil | [r1.2](https://github.com/camaraproject/QoSProfiles/releases/tag/r1.2) |
| application-profiles | 0.6.0 (r2.3, 22 Okt 2026) | initial (0.x) | [r2.3](https://github.com/camaraproject/ApplicationProfiles/releases/tag/r2.3) |
| qos-booking / qos-booking-and-assignment | 0.2.0 (r2.3, 18 Nov 2026) | initial (0.x) | [r2.3](https://github.com/camaraproject/QoSBooking/releases/tag/r2.3) |
| network-slice-booking / -assignment | 0.2.0 / 0.1.0 (r2.3, 4 Jun 2026; basis Commonalities 0.8.0) | initial (0.x) | [r2.3](https://github.com/camaraproject/NetworkSliceBooking/releases/tag/r2.3) |
| media-streaming-rate (DeviceMediaStreamingRate) | 0.1.0-alpha.1 (r1.1, pre-release, 14 Sep 2026) | alpha | [r1.1](https://github.com/camaraproject/DeviceMediaStreamingRate/releases/tag/r1.1), [yaml](https://github.com/camaraproject/DeviceMediaStreamingRate/blob/r1.1/code/API_definitions/media-streaming-rate.yaml) |
| network-health-assessment / network-traffic-analysis (NetworkInsights) | 0.1.0 (r1.3, 25 Jun 2026) | initial (0.x) | [r1.3](https://github.com/camaraproject/NetworkInsights/releases/tag/r1.3) |
| connected-network-type (+subscriptions) (DeviceStatus) | 0.1.0 (r2.2, rilis 2025-03-14) | initial (0.x) | [r2.2](https://github.com/camaraproject/DeviceStatus/releases/tag/r2.2) |
| population-density-data | 1.0.0 (r4.3, 6 Nov 2026) | stabil, pertama | [r4.3](https://github.com/camaraproject/PopulationDensityData/releases/tag/r4.3) |
| predictive-connectivity-data | 0.2.0 (r2.3, 16 Nov 2026) | initial (0.x) | [r2.3](https://github.com/camaraproject/PredictiveConnectivityData/releases/tag/r2.3) |
| device-data-volume (+subscriptions) | 0.2.0-rc.3 (r2.3, pre-release) | release candidate | [r2.3](https://github.com/camaraproject/DeviceDataVolume/releases/tag/r2.3) |

Catatan: repo `NetworkQuality` tidak ada (404). Pengganti nama itu adalah ConnectivityInsights (`/check-network-quality`). Repo `ConnectivityQualityManagement` ada tetapi tanpa rilis (sub project working repo). `DedicatedNetworks` (r2.4) dan `HighThroughputElasticNetworks` (0.1.0-alpha) ada tetapi tidak saya baca isinya (tidak terkait telemetri).

### 2.1 connectivity-insights 0.7.0
- **Endpoint:** `POST /check-network-quality` (server `/connectivity-insights/v0.7`).
- **Input:** `applicationProfileId` (dari ApplicationProfiles), `applicationServer` (IP/port), `device` (hanya untuk 2-legged), opsional `monitoringTimeStamp` (waktu masa depan = prediktif).
- **Output:** per KPI (`packetDelayBudget`, `targetMinDownstreamRate`, `targetMinUpstreamRate`, `packetlossErrorRate`, `jitter`) berisi enum `meets the application requirements` / `unable to meet the application requirements`. Plus `additionalKPIs`: `signalStrength` (`excellent|good|fair|poor|no signal`) dan `connectivityType` (`5G-SA|5G-NSA|4G|3G`).
- **Metrik terukur?** Tidak. Hanya jawaban biner per KPI dan dua indikator kasar. Deskripsi spec: "the likelihood that an application's networking requirements can be met".
- **Callback:** tidak di API ini; lewat `-subscriptions`.
- **Relasi:** wajib pakai ApplicationProfiles; spec menyebut developer bisa lanjut ke QoD atau mengubah resolusi video.
- **Auth:** 2-legged (device di body) atau 3-legged (device dari token; kirim `device` memicu `422 UNNECESSARY_IDENTIFIER`). 3-legged wajib bila data pribadi dengan opt-in/opt-out.

### 2.2 connectivity-insights-subscriptions 0.7.0
- **Endpoint:** `POST/GET /subscriptions`, `GET/DELETE /subscriptions/{subscriptionId}`.
- **Event:** satu tipe, `org.camaraproject.connectivity-insights-subscriptions.v0.network-quality`, plus lifecycle `subscription-started/updated/ended`. Notifikasi CloudEvents ke `sink` (credential `ACCESSTOKEN`/`PRIVATE_KEY_JWT`).
- **Payload event:** `NetworkQualityInsight` = `applicationProfileId` + enum meets/unable per KPI + `additionalKpis`. Sama dengan sinkron, tanpa angka.
- **Config:** `subscriptionExpireTime`, `subscriptionMaxEvents` (1..1.000.000), `initialEvent` (event segera saat subscribe), `subscriptionDetail`.
- **Frekuensi/latensi:** spec **tidak** mendefinisikan interval, ambang, atau kapan event dipicu (saya cek schema; tidak ada field itu). Itu urusan implementasi provider. Tidak ada jaminan near-real-time di spec.
- **Scope OAuth contoh:** `connectivity-insights-subscriptions:org.camaraproject.connectivity-insights-subscriptions.v0.network-quality:create`.
- **Breaking vs 0.6.0:** `GET /subscriptions` kini paginated, id jadi `id`.

### 2.3 session-insights 0.2.0 (paling dekat ke app adaptif)
- **Endpoint:** `POST /sessions`, `GET/DELETE /sessions/{sessionId}`, `POST /retrieve-sessions`, `POST /sessions/{sessionId}/metrics` (app kirim metrik yang diamatinya: delay, jitter, loss, bitrate; balasan 204).
- **Output:** event asinkron `quality-score`: `score` integer 0-100, dan bila turun plus akar masalah `proposedResolution` (`resolutionType`: `NETWORK_QOS|APPLICATION_CONFIG|OTHER`, `description` teks). Event `session-ended` (alasan: `NETWORK_TERMINATED|SESSION_EXPIRED|ACCESS_TOKEN_EXPIRED|SESSION_DELETED`).
- **Metrik terukur?** Skor gabungan 0-100, bukan metrik mentah. Operator menggabungkan telemetri jaringannya dengan metrik dari app. Spec: notifikasi tidak harus dikirim setiap submit metrik.
- **Sink wajib** (langganan implisit saat sesi dibuat). Pakai ApplicationProfiles untuk ambang. Spec menyarankan lanjut ke QoD bila degradasi dari akses jaringan.
- **Frekuensi:** tidak ditentukan spec.

### 2.4 quality-on-demand 1.2.0 (+qos-profiles 1.2.0, qos-provisioning 0.4.0)
- **Endpoint QoD:** `POST /sessions`, `GET/DELETE /sessions/{sessionId}`, `POST /sessions/{sessionId}/extend`, `POST /retrieve-sessions`.
- **Event:** satu tipe `org.camaraproject.quality-on-demand.v1.qos-status-changed` dengan `qosStatus` `REQUESTED|AVAILABLE|UNAVAILABLE` dan `statusInfo` (mis. `NETWORK_TERMINATED`, `DELETE_REQUESTED`, durasi habis).
- **Metrik terukur?** Tidak ada metrik. Hanya status sesi QoS. Sesi `NETWORK_TERMINATED` dipertahankan minimal 360 detik agar bisa dipoll.
- **qos-profiles:** profil (`QOS_S/M/L/E` atau nama lain) dengan parameter QoS (kebutuhan latency/throughput/prioritas). Statis, bukan telemetri.
- **Relasi:** QoD adalah aksi "boost"; Connectivity/Session Insights adalah pemicu keputusan.

### 2.5 application-profiles 0.6.0
- **Endpoint:** `POST /application-profiles`, `GET/PUT?/DELETE /application-profiles/{id}` (operationId: create/update/get/deleteApplicationProfile).
- **Isi:** ambang jaringan (`packetDelayBudget`, `targetMinDownstreamRate`, `targetMinUpstreamRate`, `packetlossErrorRate`, `jitter`) dan kebutuhan komputasi (CPU/memori/GPU/storage).
- **Metrik terukur?** Tidak, ini definisi kebutuhan. Dipakai Connectivity Insights dan Session Insights.

### 2.6 media-streaming-rate 0.1.0-alpha.1
- **Endpoint:** `POST /retrieve-maximum-downstream-media-rate`.
- **Output:** `maxDownstreamMediaBitRateSupported` (int, 0..1024) + `unit` (`bps..Tbps`). Satu angka per device.
- **Metrik terukur?** Angka bitrate maksimum dari jaringan (estimasi provider), cocok untuk ABR. Spec memberi alur: ambil manifest, panggil API, pilih rendisi.
- **Callback:** tidak ada. Hanya polling. 2-legged atau 3-legged. Masih alpha, bisa berubah.

### 2.7 API lain
- **qos-booking 0.2.0:** pesan QoS di muka (REQUESTED, SCHEDULED, ACTIVATED, ...), notifikasi CloudEvent status booking. Bukan telemetri.
- **network-slice-booking 0.2.0:** booking slice. Bukan telemetri (isi detail tidak saya baca).
- **network-health-assessment 0.1.0:** skor kesehatan 0-100 per **jaringan/modul** (`NET`, `NET_WIRELESS`, `NET_TRANSPORT`, `NET_CORE`), teragregasi tanpa identitas device, 2-legged. Cocok untuk dashboard ops, bukan per UE.
- **connected-network-type 0.1.0:** teknologi akses (2G/.../5G) per device, retrieve + subscription.
- **population-density-data 1.0.0:** kepadatan penduduk per area/waktu. Tidak relevan ke radio per UE.
- **predictive-connectivity-data 0.2.0, device-data-volume 0.2.0-rc.3:** tidak saya baca detail. Tidak diasumsikan menyediakan metrik radio.

## 3. FAKTA: matriks untuk use case "app adaptif" (ABR, buffer, kapan minta QoD)

| API | Nilai terukur per device? | Push (subscription/CloudEvents)? | Granularitas | Cocok untuk app adaptif |
|---|---|---|---|---|
| connectivity-insights | tidak (meets/unable + `signalStrength` 5 level) | tidak (polling `POST`) | per KPI, per profil | sedang: gerbang "boleh naik bitrate?" |
| connectivity-insights-subscriptions | tidak (sama) | ya, event `network-quality`, interval tidak ditentukan | per profil | baik sebagai pemicu |
| session-insights | skor 0-100 + saran teks | ya (sink wajib) | per sesi aplikasi | **paling cocok** (app kirim metrik, dapat skor/resolusi) |
| media-streaming-rate | satu angka bitrate maks | tidak | per device | baik untuk ABR, tapi alpha |
| quality-on-demand | tidak | ya, `qos-status-changed` | per sesi QoS | aksi, bukan sensor |
| connected-network-type | teknologi akses | ada subscription | per device | tambahan kecil |
| network-health-assessment | skor jaringan | tidak | agregat jaringan | bukan untuk app |

Kesimpulan FAKTA: latensi/frekuensi push **tidak diatur spec** (tidak ada field interval); 3-legged dengan consent berlaku untuk data device. Tidak ada API yang memberi RLC queue, PRB, BLER, atau MCS.

## 4. FAKTA vs batas verifikasi
- **Tidak diverifikasi:** nama meta-release tiap rilis; isi penuh `network-slice-booking`, `predictive-connectivity-data`, `device-data-volume`; daftar lengkap `resolutionType` dll di luar yang dikutip; implementasi operator mana yang sudah menjalankan API ini.
- **Tidak diverifikasi di sesi ini:** perilaku Android (`TelephonyManager`, `SignalStrength`, `NetworkCapabilities.getLinkDownstreamBandwidthKbps`, `TelephonyCallback`). Itu dari pengetahuan umum, perlu dicek di developer.android.com sebelum desain final.
- Dokumen ETSI OOP(26)003008 hanya mencakup QoD (qos-profiles, qos-provisioning, QoD) dan tidak membahas insights/telemetri (sesuai pembacaan sebelumnya). Jadi API insights tidak punya acuan ETSI, dan ekstensi di sini tidak bisa melanggar ETSI selama jalur QoD tidak diubah.

## 5. Use case: app adaptif

Tujuan: aplikasi mobile (mis. ABR video: pilih bitrate, ukuran buffer, kapan minta QoD) menyesuaikan diri dengan kondisi radio hampir real-time.

### 5.1 Tiga jalur, dibandingkan

| Jalur | Latensi/frekuensi | Granularitas | Consent/privasi | Catatan |
|---|---|---|---|---|
| A. On-device (USULAN; belum diuji): app/VPN magnon-app membaca `TelephonyManager` / `SignalStrength` / `NetworkCapabilities` dan throughput player | sub-detik s/d detik, tanpa jaringan | RSRP/RSRQ/SINR, tipe jaringan, estimasi bandwidth, buffer player | data tetap di device, izin OS (`READ_PHONE_STATE`/lokasi tergantung versi) | tidak melihat sisi gNB (PRB, antrian RLC, slice). Sinyal tanpa tahu beban sel tidak cukup |
| B. CAMARA standar (FAKTA: spec; pemakaian operasional belum diuji) | polling/event dengan interval ditentukan implementasi; kasar | enum, skor 0-100, bitrate maks | 3-legged + consent untuk data device | portabel antar-operator, app sudah paham API |
| C. Push Lintas5G (USULAN) dari xApp | detik (xApp KPM bisa lebih cepat; sampling dan batas laju kita yang atur) | level kualitas kasar + bitrate rekomendasi | sama dengan B, plus batas laju dan agregasi | ekstensi, harus terpisah dari schema CAMARA |

### 5.2 Rekomendasi arsitektur (USULAN)
1. **Pada device (jalur A) untuk reaksi cepat:** ABR memakai sinyal lokal (throughput player, buffer, SignalStrength). Jangan menunggu jaringan.
2. **Jaringan sebagai penasihat lambat (jalur B/C):** backend app atau app (3-legged) membuat langganan sekali. Event datang hanya saat level berubah. Hasilnya mengatur batas atas bitrate dan keputusan minta QoD.
3. **Keputusan QoD:** event `degraded` atau `unable to meet` selama N detik, lalu `POST /sessions` QoD (profil dari qos-profiles), tunggu `qos-status-changed=AVAILABLE`, naikkan batas bitrate. Setelah `UNAVAILABLE`, turunkan.
4. **xApp sebagai sumber:** xApp FlexRIC (KPM/MAC/RLC) menulis telemetri per UE ke store internal. Service "insights adapter" menurunkan: `signalStrength` (dari CQI/MCS), `meets/unable` per KPI (dari throughput DL, BLER, latency vs profil), skor 0-100 (gabungan), dan level kasar plus bitrate rekomendasi untuk ekstensi.

### 5.3 Pemetaan telemetri xApp ke API standar (USULAN; ambang perlu dikalibrasi di lab)
| Telemetri xApp | Tujuan | Keluaran standar |
|---|---|---|
| CQI/MCS rata-rata, SINR | `signalStrength` | `excellent/good/fair/poor/no signal` |
| throughput DL terukur vs `targetMinDownstreamRate` | KPI downstream | `meets/unable` |
| latency RLC/GTP vs `packetDelayBudget`, BLER vs `packetlossErrorRate` | KPI delay/loss | `meets/unable` |
| PRB share + antrian RLC + BLER | akar masalah | `proposedResolution.resolutionType = NETWORK_QOS` + teks |
| gabungan di atas | skor | `session-insights` `score` 0-100 |
| mode radio | `connectivityType` | `5G-SA` (lab OAI SA) |

Karena field tipe `enum`/`integer` skor tidak punya angka mentah, kepatuhan terjaga selama hanya mengisi field yang ada.

### 5.4 Ekstensi Lintas5G yang tetap kompatibel (USULAN)
Aturan: jangan menambah properti ke schema CAMARA (request ditolak bila ada properti tak dikenal, "request body strictness"). Buat API **terpisah**.
- **`lintas5g-radio-quality/v0` (subscription):** meniru pola subscription CAMARA (`POST/GET/DELETE /subscriptions`, CloudEvents, sink + credential, `subscriptionExpireTime`, `subscriptionMaxEvents`, `initialEvent`).
- **Event `com.lintas5g.radio-quality.v0.radio-quality-changed`** (reverse-DNS milik sendiri, bukan `org.camaraproject.*`). Payload kecil:
  - `qualityLevel`: `excellent|good|fair|poor|no_signal` (dipilih sama dengan enum `signalStrength` supaya mudah dipetakan)
  - `recommendedMaxBitrateKbps`
  - `qosStatusHint`: `qod_recommended` atau `none`
  - `validForSeconds`, `measuredAt`, `sessionId` (opsional, mengaitkan ke sesi QoD/insights)
  - opsional dengan consent tambahan: `prbShareBucket`, `rlcQueueBucket` (bucket, bukan nilai mentah)
- **Histeresis:** kirim event hanya saat level berubah dan bertahan minimal T detik, agar tidak flapping.
- **Metrik mentah per UE/slice/DRB:** tidak dibuka ke developer app. Tetap internal (ClickHouse/Grafana, dashboard ops), sesuai arahan sebelumnya.
- **Kompatibilitas ETSI OOP(26)003008:** jalur QoD (qos-profiles, qos-provisioning, quality-on-demand lewat TF ke N5) tidak diubah. Ekstensi hidup di API dan namespace event lain.
- **Opsi usulan ke CAMARA:** event kualitas dengan bitrate rekomendasi bisa diajukan sebagai issue/PR ke ConnectivityInsights atau SessionInsights. Itu keputusan nanti, belum dikerjakan.

### 5.5 Privasi dan batas laju (USULAN; angka awal perlu keputusan)
- **Privasi:** data kualitas per device adalah data pribadi. Wajib 3-legged + consent. Kebijakan: tidak mengirim ID sel, lokasi, atau nilai mentah ke app. Hanya level dan bucket. `sinkCredential` wajib (ACCESSTOKEN atau PRIVATE_KEY_JWT sesuai spec).
- **Retensi:** telemetri per UE disimpan terbatas (mis. 7 hari), agregat lebih lama. Perlu disetujui.
- **Batas laju (awal):** maksimum 1 event / 5 detik / sesi; minimal 30 detik antar event untuk level yang sama; maksimum 5 langganan aktif per device; `POST /check-network-quality` maksimum 1 / 5 detik / device; respons `429` sesuai CAMARA.
- **Biaya baterai/data di app:** event push lebih murah dari polling; jangan polling lebih cepat dari 5 detik.

## 6. Rekomendasi urutan implementasi (USULAN)
1. **Standar dulu:** `application-profiles` (statis, 2-3 profil: video ABR, call, game) + `connectivity-insights` `POST /check-network-quality` + `-subscriptions` (event `network-quality`) + QoD (ikuti ETSI). Isi `signalStrength`/`meets-unable` dari telemetri xApp. Kerja: kira-kira beberapa hari setelah xApp telemetri berjalan.
2. **Menyusul:** `session-insights` 0.2.0 untuk skor 0-100 dan `proposedResolution` (app mengirim metrik buffer/bitrate). Ini paling sesuai dengan ABR.
3. **Opsional/alpha:** `media-streaming-rate` untuk bitrate maksimum (alpha; antisipasi perubahan).
4. **Ekstensi Lintas5G:** `lintas5g-radio-quality/v0` setelah (1), bila event standar tidak cukup untuk ABR.
5. **Paralel, tanpa tunggu jaringan:** jalur on-device di magnon-app (A). Perlu keputusan kapan dimulai.
6. **Syarat:** ambang xApp ke enum harus dikalibrasi di lab (A/B DL dengan slicing), karena saat ini belum ada data. Itu belum dikerjakan.

## 7. Sumber
- https://github.com/camaraproject/ConnectivityInsights/releases/tag/r4.3
- https://github.com/camaraproject/SessionInsights/releases/tag/r2.3
- https://github.com/camaraproject/QualityOnDemand/releases/tag/r4.3
- https://github.com/camaraproject/QoSProfiles/releases/tag/r1.2
- https://github.com/camaraproject/ApplicationProfiles/releases/tag/r2.3
- https://github.com/camaraproject/QoSBooking/releases/tag/r2.3
- https://github.com/camaraproject/NetworkSliceBooking/releases/tag/r2.3
- https://github.com/camaraproject/DeviceMediaStreamingRate/releases/tag/r1.1
- https://github.com/camaraproject/NetworkInsights/releases/tag/r1.3
- https://github.com/camaraproject/DeviceStatus/releases/tag/r2.2
- https://github.com/camaraproject/PopulationDensityData/releases/tag/r4.3
- https://github.com/camaraproject/PredictiveConnectivityData/releases/tag/r2.3
- https://github.com/camaraproject/DeviceDataVolume/releases/tag/r2.3
- https://github.com/camaraproject/ReleaseManagement
