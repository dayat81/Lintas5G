# Item 2 — Callback QOS_STATUS_CHANGED E2E ke sink (n5 lab, adapter 0.1.3)

Sink referensi: `tools/sink.py` di 127.0.0.1:8443 (TLS) dalam netns core; log hanya hash token. Probe UDP UE1→AS:18080 jalan agar AVAILABLE terkonfirmasi di N3.

| kasus | skenario | sessionId | callback diterima (urutan) | auth sink | hasil |
|---|---|---|---|---|---|
| c1 | DELETE setelah AVAILABLE | `7d14fdbd-6027-4fbc-8d59-6e41798d6573` | AVAILABLE → UNAVAILABLE/DELETE_REQUESTED | Bearer ACCESSTOKEN cocok | PASS |
| c2 | duration 10 s → kedaluwarsa | `47f0191c-4b9a-4b0f-8e71-7c9f1714c6ee` | AVAILABLE → UNAVAILABLE/DURATION_EXPIRED → (Δ AVAILABLE→EXPIRED 10.02 s) | Bearer ACCESSTOKEN cocok | PASS |
| c3 | policy gagal: template PCC 5QI 4 (QOS_L) UE1 dihapus (fault injection) → provisioning 412 | `8dd1cba9-a264-4c23-b689-5bb966af29ec` | UNAVAILABLE/NETWORK_TERMINATED | Bearer ACCESSTOKEN cocok | PASS |
| c4 | PCF-initiated terminate: sesi PDU UE1 dilepas (restart UE) → PCF Npcf notify /terminate | `e96f17e8-f89c-4546-be5a-1eb6ab608212` | AVAILABLE → UNAVAILABLE/NETWORK_TERMINATED | Bearer ACCESSTOKEN cocok | PASS |
| c5 | sinkCredential PRIVATE_KEY_JWT (token via client_assertion RS256 ke sink /token) | `d3864947-0292-461a-ba61-b63100ed7e43` | AVAILABLE → UNAVAILABLE/DELETE_REQUESTED | PKJWT token valid | PASS |

Detail: `c1..c5.json` (ringkasan per kasus), `per-session/<kasus>-<sessionId>.jsonl` (log sink teredaksi per sessionId), `c3-fault-inject.txt` + `c3-restore-provision.log` (template dipulihkan oleh `provision.sh apply`, drift 1 → 0).
Catatan c3: POST /sessions mengembalikan 201 dengan qosStatus UNAVAILABLE/NETWORK_TERMINATED lalu callback dikirim (adapter 0.1.3: emit callback pada kegagalan southbound).
Catatan c5: dijalankan saat config masih `jwks_uri: https://127.0.0.1:8080/...` (skema salah, adapter melayani HTTP); diperbaiki ke `http://` pukul 10:24 WIB, adapter di-restart. jwksUri bersifat readOnly/informatif; verifikasi sink memakai JWKS yang sama.
Catatan c4: PCF mengirim terminate saat UE1 mendaftar ulang (konteks PDU lama dilepas), ±5,6 s setelah restart UE dimulai.

Hasil item 2: PASS (5/5 kasus; 4 jenis status: AVAILABLE, DELETE_REQUESTED, DURATION_EXPIRED, NETWORK_TERMINATED ×2 jalur)
- Exactly-once: seluruh log sink sesi ini 37 callback / 19 sessionId, 0 duplikat per (sessionId, status, statusInfo) → `duplicate-check.txt`.
