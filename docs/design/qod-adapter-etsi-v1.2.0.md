# Desain adapter QoD Lintas5G: basis ETSI OOP(26)003008, CAMARA QoD v1.2.0

Draf, belum di-commit. 2026-11-19 (WIB). Arahan user: "follow ETSI and improve supaya lebih mudah diterima pasar"; keputusan user 15:38 WIB: CAMARA QoD v1.2.0 (QualityOnDemand r4.3). Pasangan: qos-profiles v1.2.0 (QoSProfiles r1.2), qos-provisioning v0.4.0 (QualityOnDemand r4.3). Gap list: `docs/backlog/fase1-camara-qod-v1.2.0-gap.md`.

Konvensi: **FAKTA** = ada sumbernya (link) atau sudah terbukti di lab. **USULAN** = belum diuji/diputuskan.

## 1. Versi dan sumber (FAKTA)
| API | Versi | Rilis | Link |
|---|---|---|---|
| quality-on-demand | 1.2.0 | QualityOnDemand r4.3 | [spec](https://github.com/camaraproject/QualityOnDemand/blob/r4.3/code/API_definitions/quality-on-demand.yaml) |
| qos-provisioning | 0.4.0 (initial public) | QualityOnDemand r4.3 | [spec](https://github.com/camaraproject/QualityOnDemand/blob/r4.3/code/API_definitions/qos-provisioning.yaml) |
| qos-profiles | 1.2.0 | **QoSProfiles r1.2** (repo terpisah) | [spec](https://github.com/camaraproject/QoSProfiles/blob/r1.2/code/API_definitions/qos-profiles.yaml) |
| Commonalities | r4.4 (0.9.0) | | [CHANGELOG-r4](https://github.com/camaraproject/QualityOnDemand/blob/r4.3/CHANGELOG/CHANGELOG-r4.md) |
| ICM | r4.2 (0.5.0) | | idem |
| Basis ETSI | OOP(26)003008, Salkintzis/Lenovo, 22 Jul 2026, "For Information" | | [PDF](https://docbox.etsi.org/SDG/OOP/05-CONTRIBUTIONS/2026/2026_07_23_PL_OOP%233/OOP(26)003008_A_QoD_Transformation_Function_for_Open5GS.pdf) |

Catatan: ETSI TF memakai profil statis `conversational-voice`, `conversational-video`, `ims-signalling`, `standard-data`, `low-latency` (nama di slide); versi spec CAMARA yang dipakai ETSI tidak disebut di slide (tidak diverifikasi).

## 2. Perubahan v1.1.0 → v1.2.0 yang berdampak ke desain (FAKTA)
Sumber: [CHANGELOG r4.3](https://github.com/camaraproject/QualityOnDemand/blob/r4.3/CHANGELOG/CHANGELOG-r4.md) dan diff [r3.2..r4.3](https://github.com/camaraproject/QualityOnDemand/compare/r3.2...r4.3).

**Breaking (formal)**
1. `sinkCredential.credentialType`: hanya `ACCESSTOKEN` dan `PRIVATE_KEY_JWT`. `PLAIN`, `REFRESHTOKEN` dan skemanya dihapus. Konsumen yang mengikuti teks 1.1.0 tidak terdampak (teks sudah mewajibkan ACCESSTOKEN; enum schema 1.1.0 masih memuat PLAIN).
2. qos-profiles: operationId `retrieveQoSProfiles` → `retrieveQosProfiles` (stub hasil generate dan tag tes berubah). `Duration.value` maks 99999 (sebelumnya int32 penuh). 400 tanpa `OUT_OF_RANGE`; 404 `retrieveQosProfiles` hanya `IDENTIFIER_NOT_FOUND`. Sumber: [QoSProfiles CHANGELOG r1.2](https://github.com/camaraproject/QoSProfiles/blob/r1.2/CHANGELOG/CHANGELOG-r1.md).
3. qos-profiles pindah repo (QualityOnDemand → QoSProfiles); jalur gate tes dan spec berubah.

**Perubahan perilaku (tidak ditandai breaking, tetap berdampak)**
4. `qosProfile` valid-format tapi tidak ada → **404 NOT_FOUND** (sebelumnya 400). INACTIVE/DEPRECATED → 422 `QUALITY_ON_DEMAND.QOS_PROFILE_NOT_APPLICABLE` (sudah ada sejak 1.1.0).
5. `createSession` boleh 201 dengan `qosStatus=UNAVAILABLE`, `statusInfo=NETWORK_TERMINATED`.
6. `applicationServer` jadi `oneOf`: `ipAddresses` (≤16 IP tunggal, unik) atau subnet `ipv4Address`/`ipv6Address`.
7. Request body strictness: properti tak dikenal → 400 INVALID_ARGUMENT.
8. Batas input eksplisit (Commonalities r4.4): x-correlator ≤256, sessionId 36, sink ≤2048, port ≥1 (0 ditolak), list port ≤65536, `retrieve-sessions` ≤100 hasil. `duration` dan `requestedAdditionalDuration` hanya dibatasi int32; batas efektif = `maxDuration` profil.
9. `accessToken` dan `accessTokenType` pada `sinkCredential` write-only (tidak muncul di response).
10. Kode error dipersempit per operasi: GS/DS 400 hanya INVALID_ARGUMENT; RS 404 hanya IDENTIFIER_NOT_FOUND.
11. Notifikasi mengikuti model CloudEvents Commonalities (`QosNotificationEvent`); tipe event tetap `org.camaraproject.quality-on-demand.v1.qos-status-changed`; sink bisa membalas 410 GONE.
12. Klarifikasi: retrieve/extend/delete wajib token dari API client yang sama dan subject yang sama (3-legged).
13. Bahasa: "developer" → "API consumer"; "QoS Profile" didefinisikan lewat nama (`QosProfileName`).

**Tidak berubah**: base path `/quality-on-demand/v1`; operasi (`createSession`, `getSession`, `deleteSession`, `extendQosSessionDuration`, `retrieveSessionsByDevice`); scope `quality-on-demand:sessions:{create,read,update,delete,retrieve-by-device}`; aturan 2-legged wajib `device`, 3-legged dilarang `device` (422 MISSING_IDENTIFIER / UNNECESSARY_IDENTIFIER); enum qosStatus (REQUESTED/AVAILABLE/UNAVAILABLE) dan statusInfo (DURATION_EXPIRED/NETWORK_TERMINATED/DELETE_REQUESTED); auto-delete ≥360 s setelah NETWORK_TERMINATED; `duration` wajib; endpoint extend dicap `maxDuration`.

**Tambahan Test_definitions**: 96 skenario QoD di r4.3 (r3.2: 72). Baru: 429 di semua operasi, `invalid_x-correlator`, request strictness, `application_server_*` (list/subnet/duplikat/terlalu besar), PRIVATE_KEY_JWT, 404 profil tidak ada. Dua tag diganti nama (`400.6_invalid_sink_credential` → `400.6_unsupported_sink_credential_type`; `400.8_non_existent_qos_profile` → `400.8_non_compliant_qos_profile_name`). Tipe event di tes dikoreksi dari `org.camaraproject.qod.v1…` ke `org.camaraproject.quality-on-demand.v1.qos-status-changed` (r4.3, #649).

## 3. Basis ETSI (FAKTA, dari slide)
- **Bentuk**: QoD Transformation Function (TF), aplikasi FastAPI dalam container; melayani 3 API: qos-profiles, qos-provisioning, quality-on-demand; callback CloudEvents; federasi opsional; berjalan di Open5GS biasa tanpa NEF.
- **Alur QoD**: sesi QoD → `Npcf_PolicyAuthorization` Create (N5). BSF (`Nbsf_Management`) menemukan PCF yang melayani PDU session UE. Hasilnya network-initiated PDU Session Modification dan QoS flow baru.
- **Batasan PCF Open5GS**: `qosReference` dipetakan ke 5QI lalu PCF mencari PCC rule yang sudah di-provision untuk UE. Tanpa rule, Create gagal. Solusi ETSI: **Mongo Bridge** (REST ke MongoDB Open5GS) yang dipakai API qos-provisioning untuk menulis PCC rule.
- **Profil**: statis di TF, tanpa interaksi ke jaringan.
- **Keamanan**: OAuth2 2-legged (client credentials, token tidak memuat identitas perangkat) dan 3-legged (auth code/CIBA, token memuat identitas; API gateway memetakan `sub` ke perangkat); consent untuk GDPR. Implementasi ETSI saat ini 2-legged, 3-legged sedang dikerjakan.
- **Pelajaran**: TF butuh IP privat UE (resolve dari MSISDN/IP publik); CAMARA tidak menyebut protokol, jadi kirim flow description untuk semua protokol.
- **Tidak dibahas**: penjadwalan di RAN.

## 4. Arsitektur adapter (USULAN, mengikuti ETSI)
```
App/AS ──(CAMARA, OAuth2)──> Gateway (verifikasi JWT, scope, rate-limit 429, x-correlator)
   │                              │ (2-legged: device di body | 3-legged: device dari sub)
   ▼                              ▼
 TF: /quality-on-demand/v1   /qos-profiles (v1.2.0)   /qos-provisioning (v0.4.0)
   │   state machine + scheduler + notifier (CloudEvents)
   ├─ Resolver identitas: MSISDN/NAI/IP publik+port → IP privat UE (+ sesi PDU)
   ├─ Mongo Bridge (REST) ── MongoDB Open5GS: tulis/hapus PCC rule (5QI dari profil)
   ├─ BSF: GET /nbsf-management/v1/pcfBindings?ipv4Addr=<UE> → endpoint PCF
   └─ PCF: POST /npcf-policyauthorization/v1/app-sessions (medComponents: qosReference, fDescs semua protokol)
```
Status uji N5 di Open5GS 2.8.0 (alur Mongo → BSF → N5 → QFI di N3): lihat `/workspace/oai-n5-test/RESULT.md` (masih berjalan saat dokumen ini ditulis, belum ada verdict). Desain ini tidak mengklaim hasil N5 sebelum hasil itu selesai.

### 4.1 Pemetaan API CAMARA v1.2.0 → backend (USULAN)
| Operasi | Aksi backend |
|---|---|
| `createSession` | validasi (strict body, profil ACTIVE, durasi ≤ maxDuration) → resolve IP privat UE → pastikan PCC rule untuk 5QI profil ada (Mongo Bridge) → BSF → N5 Create (fDescs TCP+UDP+lainnya, port dari `devicePorts`/`applicationServerPorts`, AS dari `ipAddresses` atau subnet) → 201 REQUESTED; event AVAILABLE saat PCF/SMF sukses, atau UNAVAILABLE+NETWORK_TERMINATED. Jika N5 gagal sinkron → 201 UNAVAILABLE+NETWORK_TERMINATED (perilaku MAY di v1.2.0) |
| `getSession`, `retrieveSessionsByDevice` | baca state adapter (filter client_id + subject; maks 100) |
| `extendQosSessionDuration` | hanya AVAILABLE (else 409 `QUALITY_ON_DEMAND.SESSION_EXTENSION_NOT_ALLOWED`); cap `maxDuration`; geser timer |
| `deleteSession` | N5 Delete (`/app-sessions/{id}/delete`), event DELETE_REQUESTED |
| expiry | timer → N5 Delete → event DURATION_EXPIRED |
| terminasi jaringan | notifikasi PCF/SMF (`notifUri`) → NETWORK_TERMINATED; sesi dihapus otomatis ≥360 s |
| `retrieveQosProfiles`, `getQosProfile` | dari `profiles.yaml` (statis, ala ETSI) + `status`, `minDuration`, `maxDuration` |
| qos-provisioning 0.4.0 | assignment → PCC rule di Mongo (ala ETSI); event `…qos-provisioning.v0.status-changed` |

### 4.2 Keamanan (USULAN, selaras ETSI + ICM r4.2)
- 2-legged dulu untuk lab/enterprise; 3-legged + consent (Keycloak, auth code/CIBA) untuk pelanggan individu. Aturan device: 2-legged wajib `device`; 3-legged dilarang (422), sesuai spec v1.2.0.
- Kepemilikan sesi: simpan `client_id` dan subject; retrieve/extend/delete dari client/subject lain → 403.
- Notifikasi: Bearer ACCESSTOKEN dahulu; PRIVATE_KEY_JWT setelah ada JWK Set pre-shared (422 `PRIVATE_KEY_JWT_NOT_CONFIGURED` bila tidak ada).
- Tanpa consent di luar demo = tidak boleh untuk pelanggan nyata (poin ETSI).

## 5. Ekstensi Lintas5G ("improve"), non-breaking (USULAN)
Prinsip: tidak mengubah skema atau perilaku API CAMARA/ETSI. Ekstensi berada di (a) API terpisah `lintas5g-*`, (b) konfigurasi internal backend, atau (c) field/event opsional dengan prefiks `x-lintas5g` yang diabaikan konsumen standar. Catatan kompatibilitas: v1.2.0 menolak properti tak dikenal di request, jadi ekstensi **tidak boleh** menambah field ke body CAMARA. Konfigurasi per sesi lewat profil atau API ekstensi.

| # | Ekstensi | Isi | Status bukti |
|---|---|---|---|
| E1 | Hook slice DL / PRB (FlexRIC) | Setelah sesi AVAILABLE, adapter memanggil xApp untuk mengaktifkan slice DL UE tersebut; dilepas saat sesi berakhir. Gagal hook ≠ gagal sesi (QFI tetap) | Slicing/FlexRIC masih dievaluasi; **belum terbukti**. Hasil Fase 0: QoD efektif dalam satu UE (p99 4980→113 ms); antar-UE tidak ada beda tanpa slicing |
| E2 | MBR + shaping / fallback tc | Karena UPF 2.8.0 tidak menegakkan MBR QER, tc HTB di `ogstun` (qod-tc.py) dipakai sebagai penegak MBR/GBR cadangan, dipicu oleh adapter yang sama | FAKTA: Sesi A (UPF tidak menegakkan MBR), Sesi B–D (tc dipakai). Integrasi ke adapter belum |
| E3 | Flow description multi-protokol | N5 fDescs TCP+UDP (+ICMP bila perlu) dan DL+UL otomatis, sesuai pelajaran ETSI; opsi protokol per profil (di luar body CAMARA) | N5 TCP+UDP: bagian uji N5 (berjalan) |
| E4 | Resolusi IP→sesi | Resolver MSISDN/NAI/IP publik+port → IP privat UE, lewat Open5GS (UDM/SMF/BSF) atau tabel NAT; cache dengan TTL | Belum diuji; ETSI mengakui kebutuhan ini tanpa solusi rinci |
| E5 | Observabilitas Zeek | Tag sesi (`sessionId`, 5QI, QFI) ditulis ke log adapter, dimuat batch ke ClickHouse/Grafana berdampingan dengan data Zeek (UE/N3/N6); Zeek tidak diubah | FAKTA: tap Zeek UE/N3/N6 dan batch ke ClickHouse jalan di lab; tag sesi belum |
| E6 | Radio-quality | API baca-saja `lintas5g-radio-quality/v0` + event `radio-quality-changed` (`qualityLevel`, `recommendedMaxBitrateKbps`, `validForSeconds`) dari telemetri xApp; dipetakan juga ke `signalStrength` dan meets/unable Connectivity Insights bila ditawarkan. Laju awal 1 event/5 s/sesi (perlu kalibrasi) | Usulan; telemetri xApp belum diuji. Review: `docs/backlog/camara-telemetry-apis-review.md` |
| E7 | Callback tambahan opsional | event "QoS fulfilled/degraded" dari telemetri, sebagai tipe event baru di API ekstensi (bukan di enum CAMARA) | Usulan |
| E8 | Tooling konformansi | Gate CI Gherkin r4.3 + QoSProfiles r1.2 + Spectral; laporan hasil tiap PR | Usulan |

## 6. Tabel penyimpangan dan perbaikan terhadap ETSI
| # | Aspek | ETSI TF (FAKTA slide) | Lintas5G (USULAN) | Jenis | Dipaksa Open5GS 2.8.0? |
|---|---|---|---|---|---|
| 1 | Versi CAMARA | tidak disebut di slide | QoD 1.2.0, qos-profiles 1.2.0, qos-provisioning 0.4.0 (Commonalities r4.4) | selaras + eksplisit | tidak |
| 2 | Tiga API | ya | ya, qos-provisioning menyusul (Fase 1 akhir) | selaras | tidak |
| 3 | Mongo Bridge + PCC | ya | ya, pola sama | selaras | ya (PCF butuh PCC rule yang sudah ada) |
| 4 | BSF → N5 | ya | ya | selaras | tidak |
| 5 | Profil | statis di TF | statis di `profiles.yaml`, nama bisa dipetakan 1:1 ke profil ETSI; tambah status/min/maxDuration | selaras + tambah | tidak |
| 6 | OAuth2 | 2-legged jalan, 3-legged sedang dikerjakan | 2-legged dahulu, 3-legged+consent sebelum pelanggan nyata | selaras | tidak |
| 7 | Flow multi-protokol | kirim semua protokol | sama; protokol per profil | selaras + perbaikan | tidak |
| 8 | Penegakan MBR | tidak dibahas | tc HTB fallback di N6 (E2) | perbaikan | ya (UPF tidak menegakkan MBR QER) |
| 9 | Radio | tidak dibahas | hook FlexRIC slice DL/PRB (E1), telemetri (E6) | ekstensi | tidak (RAN OAI) |
| 10 | Resolusi IP | dicatat sebagai tantangan | resolver terdokumentasi (E4) | perbaikan | sebagian (Open5GS tidak menyediakan MSISDN→IP lewat N5) |
| 11 | Observabilitas | tidak dibahas | tag sesi + Zeek + ClickHouse (E5) | ekstensi | tidak |
| 12 | Federasi | ya | di luar Fase 1 | gap vs ETSI | tidak |
| 13 | Konformansi | tidak dibahas | gate Test_definitions r4.3 (E8) | perbaikan | tidak |
| 14 | Event tambahan | CloudEvents standar | tetap standar; tipe tambahan hanya di API ekstensi | ekstensi non-breaking | tidak |

## 7. Risiko dan hal terbuka
- Mapping `qosProfile` → 5QI di PCF Open5GS 2.8.0 (`pcf.qos_profiles`) dan PCC rule yang harus ada: hasil uji N5 menentukan (USULAN sampai selesai).
- Perilaku "QFI baru" untuk satu UE sudah terbukti di GCP (QFI 2 lewat PCC statis), tetapi on-demand lewat N5 belum.
- Test README r4.3 usang soal 404 vs 400 (lihat gap list); ikuti feature file + CHANGELOG.
- Skeleton `adapters/qod-af/` (v0.0.1) tidak diverifikasi ulang hari ini.
