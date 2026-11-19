# Fase 1 – gap list adapter QoD vs CAMARA quality-on-demand v1.1.0 (r3.2)

Keputusan user 2026-11-18 20:57 WIB: "yang kita develop harus align dgn itu" (CAMARA QoD v1.1.0 r3.2 + qos-profiles v1.1.0; 1.2.0 rc jangan diadopsi).
Sumber spec: camaraproject/QualityOnDemand r3.2 `code/API_definitions/quality-on-demand.yaml` (info.version 1.1.0).
Dibandingkan dengan `adapters/qod-af/` di main (openapi.yaml v0.0.1, FastAPI app/, 54 baris test).

## FAKTA: yang sudah ada di skeleton
- POST/GET/DELETE sessions, bearer auth, qosStatus enum REQUESTED/AVAILABLE/UNAVAILABLE, field sink, applicationServerPorts, duration.
- Backend Npcf_PolicyAuthorization (N5) app-session + stub Rx (501), profiles.yaml (QOS_E/S/M/L -> 5QI/QCI/GBR/MBR/DSCP).
- Catatan: tes lab Fase 0 (sesi-b/c/d) memakai API lab `qod-tc.py` (POST /qod {ueIpv4,remote,port,gbrKbps}), BUKAN API CAMARA.

## Gap (semua perlu dikerjakan; tidak ada yang conform penuh)
| # | Area | Spec v1.1.0 (FAKTA) | Skeleton saat ini (FAKTA) |
|---|---|---|---|
| G1 | Base path | `{apiRoot}/quality-on-demand/v1` + `/sessions` | `/quality-on-demand/v0/sessions` |
| G2 | Required field | CreateSession: applicationServer, qosProfile, **duration** (int32 >=1, dibatasi maxDuration profil) | device, applicationServer, qosProfile; duration opsional max 86400 |
| G3 | device | phoneNumber / networkAccessIdentifier / ipv4Address (public+private atau public+publicPort) / ipv6Address; opsional, aturan 2-legged wajib device, 3-legged dilarang device (422 bila salah) | hanya ipv4Address, selalu wajib |
| G4 | applicationServer | ipv4Address / ipv6Address (boleh subnet) | ipv4Address string saja |
| G5 | Ports | devicePorts + applicationServerPorts = PortsSpec {ranges[{from,to}], ports[]} | hanya applicationServerPorts.ports |
| G6 | qosProfile | QosProfileName string (pattern), divalidasi via qos-profiles API | enum statis QOS_E/S/M/L |
| G7 | Notifikasi | sink (https) + sinkCredential (ACCESSTOKEN); CloudEvents `org.camaraproject.quality-on-demand.v1.qos-status-changed`, statusInfo DURATION_EXPIRED / NETWORK_TERMINATED / DELETE_REQUESTED | sink string tanpa kredensial; tidak ada pengirim event; `/notify` internal saja |
| G8 | Lifecycle | 201 REQUESTED lalu event AVAILABLE/UNAVAILABLE; auto-delete >=360 s setelah NETWORK_TERMINATED; duration expiry -> DURATION_EXPIRED | status langsung dari backend, tidak ada state machine/timer |
| G9 | Operasi | + POST /sessions/{id}/extend (requestedAdditionalDuration, dicap maxDuration), + POST /retrieve-sessions (by device) | tidak ada |
| G10 | Response | SessionInfo wajib sessionId, duration, qosStatus; startedAt/expiresAt; statusInfo | sebagian |
| G11 | Error & header | ErrorInfo {status, code, message} + kode CAMARA (mis. QUALITY_ON_DEMAND.DURATION_OUT_OF_RANGE, IDENTIFIER_NOT_FOUND, 409 CONFLICT); header x-correlator | HTTPException FastAPI default, tanpa x-correlator |
| G12 | qos-profiles v1.1.0 | GET /qos-profiles/{name}, POST /retrieve-qos-profiles; atribut (min/maxDuration, latency, jitter, throughput, status) | profiles.yaml internal, tanpa API |
| G13 | Conformance | Test_definitions Gherkin r3.2 sebagai gate | 54 baris unit test sendiri |

## USULAN rencana Fase 1
1. Evaluasi FRONT camara-QoD (Apache-2.0) sebagai northbound; pertahankan backend N5/Rx milik kita di balik interface `backends.py`.
2. Implementasi state machine + scheduler (expiry, auto-delete 360 s) + CloudEvents sender ber-sinkCredential.
3. qos-profiles API dari profiles.yaml (tambah min/maxDuration, latency target).
4. Pipeline CI: jalankan Gherkin r3.2 (subset yang relevan untuk 2-legged lab) sebagai gate PR.
5. Mapping enforcement: QoD -> N5 -> PCF -> UPF/RAN (temuan Sesi D: enforcement tc SGi di luar segmen tap), jadi validasi latency tetap via Zeek + probe MGLT.
