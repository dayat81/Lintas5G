# Fase 1 – gap list adapter QoD vs CAMARA quality-on-demand v1.2.0 (QualityOnDemand r4.3)

Menggantikan `fase1-camara-qod-v1.1.0-gap.md` (v1.1.0 / r3.2). Draf, belum di-commit. Dibuat 2026-11-19 (WIB).

Keputusan user 2026-11-19 15:38 WIB (lewat Open Lab PM): "Pindah ke CAMARA QoD v1.2.0 (r4.3)". Test_definitions r4.3 jadi gate konformansi. Arahan "follow ETSI and improve" (15:15 WIB) tetap berlaku: ETSI OOP(26)003008 = basis kompatibel, perbaikan Lintas5G = ekstensi non-breaking (lihat `docs/design/qod-adapter-etsi-v1.2.0.md`).

## Versi acuan (FAKTA)
| Item | Versi | Sumber |
|---|---|---|
| quality-on-demand | **1.2.0** | [release-metadata r4.3](https://github.com/camaraproject/QualityOnDemand/blob/r4.3/release-metadata.yaml), [spec](https://github.com/camaraproject/QualityOnDemand/blob/r4.3/code/API_definitions/quality-on-demand.yaml) |
| qos-provisioning | **0.4.0** (pasangan di repo yang sama) | [spec](https://github.com/camaraproject/QualityOnDemand/blob/r4.3/code/API_definitions/qos-provisioning.yaml) |
| qos-profiles | **1.2.0**, rilis **r1.2** di repo **QoSProfiles** (2026-11-15). Tidak ada lagi di repo QualityOnDemand sejak r4.3 (terakhir di sana: 1.1.0 di r3.2, rc 1.2.0-rc.3 di r4.1) | [release-metadata r1.2](https://github.com/camaraproject/QoSProfiles/blob/r1.2/release-metadata.yaml), [spec](https://github.com/camaraproject/QoSProfiles/blob/r1.2/code/API_definitions/qos-profiles.yaml), [CHANGELOG](https://github.com/camaraproject/QoSProfiles/blob/r1.2/CHANGELOG/CHANGELOG-r1.md) |
| Commonalities | r4.4 (0.9.0) (sebelumnya r3.3 / 0.6.0) | [CHANGELOG-r4](https://github.com/camaraproject/QualityOnDemand/blob/r4.3/CHANGELOG/CHANGELOG-r4.md) |
| Identity and Consent Management | r4.2 (0.5.0) (sebelumnya 0.4.0 / r3.3) | idem |
| Test_definitions | [QoD r4.3](https://github.com/camaraproject/QualityOnDemand/tree/r4.3/code/Test_definitions): 96 skenario QoD + 71 qos-provisioning; [QoSProfiles r1.2](https://github.com/camaraproject/QoSProfiles/tree/r1.2/code/Test_definitions): 31 skenario | hitung tag `@...` di file `.feature` |

Catatan: `code/Test_definitions/README.md` r4.3 masih memuat catatan usang ("nonexistent QoS Profile: 400 INVALID_ARGUMENT is proposed"). Yang berlaku adalah CHANGELOG dan feature `createSession_404.1_non_existent_qos_profile` (404 NOT_FOUND). Diff lengkap v1.1.0 → v1.2.0 ada di bagian bawah.

## FAKTA: kondisi skeleton `adapters/qod-af/` (dari gap list v1.1.0, tidak diverifikasi ulang hari ini)
openapi.yaml v0.0.1, FastAPI, base path `/quality-on-demand/v0/sessions`, bearer auth, qosStatus REQUESTED/AVAILABLE/UNAVAILABLE, backend N5 + stub Rx, `profiles.yaml` QOS_E/S/M/L. Lab Fase 0 memakai API lab `qod-tc.py` (bukan CAMARA).

## Evaluasi ulang G1–G13 terhadap v1.2.0
Kolom "Δ" = perubahan terhadap gap list v1.1.0. Skenario = tag di [Test_definitions r4.3](https://github.com/camaraproject/QualityOnDemand/tree/r4.3/code/Test_definitions) (awalan `quality_on_demand_` dihilangkan; CS = createSession, GS = getSession, DS = deleteSession, EX = extendQosSessionDuration, RS = retrieveSessionsByDevice).

| # | Area | Spec v1.2.0 (FAKTA) | Δ vs v1.1.0 | Skenario r4.3 |
|---|---|---|---|---|
| G1 | Base path | `{apiRoot}/quality-on-demand/v1` + `/sessions`, `/sessions/{sessionId}`, `/sessions/{sessionId}/extend`, `/retrieve-sessions` | tetap | semua `Background` (`resource "/quality-on-demand/v1/sessions"`) |
| G2 | Required field | CreateSession: `applicationServer`, `qosProfile`, `duration` (int32, min 1; **tanpa maximum di schema**, batas efektif = `maxDuration` profil → 400 `QUALITY_ON_DEMAND.DURATION_OUT_OF_RANGE`) | tetap; batas atas schema dihapus (aturan lewat profil) | CS_01, CS_400.9_invalid_duration |
| G3 | device & token | `device` opsional: phoneNumber / networkAccessIdentifier / ipv4Address (publicAddress + privateAddress atau publicPort, **publicPort ≥ 1**) / ipv6Address. 2-legged: wajib (422 MISSING_IDENTIFIER). 3-legged: dilarang (422 UNNECESSARY_IDENTIFIER, meski perangkatnya sama). Juga 422 UNSUPPORTED_IDENTIFIER, SERVICE_NOT_APPLICABLE, 404 IDENTIFIER_NOT_FOUND | `device` pada response hanya untuk disambiguasi multi-identifier; batas panjang eksplisit | CS_03_3_legged_missing_device, CS_C01.01–C01.07, RS_C01.01–C01.07 |
| G4 | applicationServer | **oneOf**: `{ipAddresses: [≤16 IP tunggal v4/v6, unik, ≥1]}` ATAU `{ipv4Address, ipv6Address}` berupa subnet (CIDR). Properti lain ditolak | **BARU**: bentuk list `ipAddresses` | CS_04_1_application_server_subnets_provided, CS_04_2_application_server_list_provided, CS_400.11–400.16 |
| G5 | Ports | `devicePorts`, `applicationServerPorts` = PortsSpec {ranges[{from,to}] ≤65536, ports[] ≤65536}; port ≥ 1 | port 0 sekarang invalid; maxItems eksplisit | CS_400.5_out_of_range_port |
| G6 | qosProfile | `QosProfileName` (pattern `^[a-zA-Z0-9_.-]+$`, panjang dibatasi). Nama sesuai pattern tapi tidak ada → **404 NOT_FOUND** (sebelumnya 400). Tidak sesuai pattern → 400 INVALID_ARGUMENT. Ada tapi INACTIVE/DEPRECATED → 422 `QUALITY_ON_DEMAND.QOS_PROFILE_NOT_APPLICABLE` | **UBAH**: 404 untuk profil tidak ada | CS_404.1_non_existent_qos_profile, CS_400.8_non_compliant_qos_profile_name, CS_422.1_session_qos_profile_not_applicable |
| G7 | Notifikasi | `sink` (https, ≤2048) + `sinkCredential`: **ACCESSTOKEN atau PRIVATE_KEY_JWT** (PLAIN dan REFRESHTOKEN dihapus). `accessToken`, `accessTokenType` **write-only** (tidak dikembalikan). CloudEvent `org.camaraproject.quality-on-demand.v1.qos-status-changed`, `data{sessionId, qosStatus(AVAILABLE/UNAVAILABLE), statusInfo}`; header `Authorization: Bearer …`, `Content-Type: application/cloudevents+json`. Penerima bisa membalas 410 GONE | **UBAH + BARU** (lihat G15, G24) | CS_02_1_sinkcredential_provided, CS_02_2_event_received, CS_400.6_unsupported_sink_credential_type, CS_400.7_sink_credential_invalid_token, DS_02_event_notification |
| G8 | Lifecycle | 201 REQUESTED lalu event AVAILABLE atau UNAVAILABLE+NETWORK_TERMINATED. **201 boleh langsung UNAVAILABLE + NETWORK_TERMINATED** bila jaringan sudah tahu tidak sanggup. Auto-delete ≥360 s setelah NETWORK_TERMINATED. Event DURATION_EXPIRED, DELETE_REQUESTED | **BARU**: 201 UNAVAILABLE langsung (lihat G17) | GS_02_get_recent_unavailable, CS_409.1_session_conflict, DS_01 |
| G9 | Operasi | POST `/sessions/{id}/extend` (`requestedAdditionalDuration`, dicap `maxDuration`, hanya saat AVAILABLE; else 409 `QUALITY_ON_DEMAND.SESSION_EXTENSION_NOT_ALLOWED`); POST `/retrieve-sessions` (maks 100 hasil, array kosong bila tidak ada) | batas 100 hasil; 400 hanya INVALID_ARGUMENT/OUT_OF_RANGE per operasi | EX_01, EX_02_exceed_max_duration, EX_409.1_session_not_available, RS_01, RS_02 |
| G10 | Response | SessionInfo wajib `sessionId`, `duration`, `qosStatus`; `startedAt`, `expiresAt`, `statusInfo` opsional | tetap; `sinkCredential` tidak dikembalikan dengan nilai rahasia | CS_01, GS_01 |
| G11 | Error & header | ErrorInfo {status, code, message}. Daftar kode per operasi **dipersempit**: GS/DS 400 hanya INVALID_ARGUMENT; RS 404 hanya IDENTIFIER_NOT_FOUND; `x-correlator` pattern `^[a-zA-Z0-9-_:;.\/<>{}]{0,256}$`, dikembalikan sama di response | **UBAH**: kode dipersempit; validasi x-correlator wajib | semua `*_invalid_x-correlator`, `*_400.1`, `*_401.1–401.3`, `*_404.1` |
| G12 | qos-profiles | Pasangan **v1.2.0** (QoSProfiles r1.2): `POST /retrieve-qos-profiles` (operationId **`retrieveQosProfiles`**, sebelumnya `retrieveQoSProfiles`), `GET /qos-profiles/{name}`, scope `qos-profiles:read`, `Duration.value` maks 99999, ≤100 profil, status ACTIVE/INACTIVE/DEPRECATED | **UBAH**: repo pindah, rename operationId, batas schema | [qos-profiles-getQosProfile.feature, qos-profiles-retrieveQosProfiles.feature @ r1.2](https://github.com/camaraproject/QoSProfiles/tree/r1.2/code/Test_definitions) (31 skenario), termasuk `retrieveQosProfiles_02b_filter_by_name_not_found` (200 array kosong) |
| G13 | Conformance | Gate = Test_definitions **r4.3** (QoD 96 skenario) + QoSProfiles r1.2 (31) + qos-provisioning r4.3 (71) | versi gate naik; skenario baru 429, x-correlator, strictness, list app server, PRIVATE_KEY_JWT | seluruh `.feature` |

## Gap baru (v1.2.0)
| # | Area | Spec v1.2.0 (FAKTA) | Skenario r4.3 |
|---|---|---|---|
| G14 | Request body strictness | Properti tak dikenal di level mana pun → 400 INVALID_ARGUMENT (bagian "Request body strictness" di info.description). FastAPI/pydantic default mengabaikan properti ekstra, jadi perlu `extra="forbid"` | CS_400.17, EX_400.6, RS_400.4 |
| G15 | PRIVATE_KEY_JWT | `sinkCredential.credentialType=PRIVATE_KEY_JWT` butuh JWK Set yang sudah di-share out-of-band; bila tidak ada → 422 `PRIVATE_KEY_JWT_NOT_CONFIGURED`. Tipe PLAIN/REFRESHTOKEN ditolak (400) | CS_02_3_private_key_jwt_sink_credential, CS_422.2, CS_400.6 |
| G16 | 429 | Semua operasi punya skenario 429 (TOO_MANY_REQUESTS / QUOTA_EXCEEDED) → perlu rate limiter di gateway/adapter | CS_429.1, GS_429.1, DS_429.1, EX_429.1, RS_429.1 |
| G17 | Create langsung UNAVAILABLE | `createSession` 201 dengan `qosStatus=UNAVAILABLE`, `statusInfo=NETWORK_TERMINATED` bila N5/PCF langsung menolak (mis. PCC rule belum ada, BSF tidak menemukan binding) | GS_02_get_recent_unavailable (tidak ada skenario khusus create; perilaku MAY) |
| G18 | Kepemilikan sesi | Retrieve/extend/delete: token harus dari API client yang sama dan (3-legged) subject yang sama dengan saat create → 403 PERMISSION_DENIED | GS_403.2, DS_403.2, EX_403.2_session_token_mismatch |
| G19 | Scope OAuth2 | `quality-on-demand:sessions:create`, `:read`, `:update`, `:delete`, `:retrieve-by-device` (tidak berubah, tetap diuji) dan `qos-profiles:read` | *_403.1_missing_access_token_scope, *_401.x |
| G20 | Batas input | Panjang/rentang eksplisit: `sink` ≤2048, `sessionId` 36, x-correlator 256, port ≥1, list ≤16, retrieve ≤100. Validasi harus 400, bukan 500 | CS_400.1–400.5, *_400.1 |
| G21 | Callback ke sink | Event ke penerima: Bearer, `application/cloudevents+json`; respons 410 GONE dari sink didokumentasikan | CS_02_2_event_received, DS_02_event_notification |
| G22 | qos-provisioning 0.4.0 (opsional untuk Fase 1, dibutuhkan jalur ETSI) | `/qos-assignments`, `/qos-assignments/{id}`, `/retrieve-qos-assignment`; sinkCredential sama (ACCESSTOKEN/PRIVATE_KEY_JWT); event `org.camaraproject.qos-provisioning.v0.status-changed` dengan `data.status` | [qos-provisioning-*.feature @ r4.3](https://github.com/camaraproject/QualityOnDemand/tree/r4.3/code/Test_definitions) (28+19+11+13 skenario) |
| G23 | Tooling | Generator kode dan linter (Spectral, Gherkin runner) harus memakai operationId `retrieveQosProfiles` dan skema Commonalities r4.4 | n/a |

## USULAN urutan kerja Fase 1
1. **Northbound v1.2.0**: ganti base path ke `/quality-on-demand/v1`, model pydantic `extra=forbid`, `oneOf` applicationServer, error catalogue r4.4, x-correlator (G1–G6, G10, G11, G14, G20).
2. **State machine + scheduler**: REQUESTED→AVAILABLE/UNAVAILABLE, 201 UNAVAILABLE langsung, expiry, auto-delete ≥360 s (G8, G17).
3. **Notifier CloudEvents**: ACCESSTOKEN dulu, PRIVATE_KEY_JWT menyusul (butuh JWKS); handle 410 (G7, G15, G21).
4. **qos-profiles v1.2.0** dari `profiles.yaml` (+ min/maxDuration, status) (G12).
5. **Token**: 2-legged dulu untuk lab; 3-legged + consent di Keycloak setelah itu (G3, G18, G19).
6. **Rate limit** 429 (G16).
7. **CI gate**: Gherkin r4.3 (QoD + QoSProfiles), subset 2-legged dulu, Spectral untuk spec sendiri (G13, G23).
8. qos-provisioning 0.4.0 menyusul bersama jalur Mongo bridge ETSI (G22).

## Lampiran: diff v1.1.0 (r3.2) → v1.2.0 (r4.3) yang berdampak ke desain
Ringkasan ada di `docs/design/qod-adapter-etsi-v1.2.0.md` §2. Sumber utama: [CHANGELOG-r4.md](https://github.com/camaraproject/QualityOnDemand/blob/r4.3/CHANGELOG/CHANGELOG-r4.md), [CHANGELOG.md r3.2](https://github.com/camaraproject/QualityOnDemand/blob/r3.2/CHANGELOG.md), dan diff `r3.2..r4.3` pada `code/API_definitions/*.yaml` serta `code/Test_definitions/*.feature`.
