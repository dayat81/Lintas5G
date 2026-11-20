# Item 4 — Adapter 0.1.3: bind internal + PRIVATE_KEY_JWT

- Bind: image `lintas5g/qod-adapter:0.1.3` default `QOD_BIND=127.0.0.1`; di lab adapter berjalan di netns core (n5-lab) → 127.0.0.1:8080 (API) dan 127.0.0.99:9999 (notify PCF). Sink referensi 127.0.0.1:8443. Bukti: `ss-ltnp-n5-lab.txt` (satu-satunya listener TCP non-loopback adalah *:4043 = server rfsim gNB untuk nrUE, bukan adapter).
- Scan: `nmap-from-ue-netns.txt` (UE1 & UE2, via oaitun) dan `nmap-from-other-container.txt` (container lain di bridge docker + gateway host): 8080/8090/8443 **closed** dari semua titik. Kontrol positif: listener sementara 0.0.0.0:18099 terlihat **open** dari UE1 dan dari container lain → scan valid.
- 8090 = backend booster (tidak berjalan di lab n5; tetap closed).
- PRIVATE_KEY_JWT: JWKS lokal `GET /.well-known/sink-jwks.json` (RS256, kid sink-assertion-1); client pre-shared di `sink_auth.private_key_jwt.preshared`. Bukti E2E stack nyata: `../callback/c5b.json` (201 + jwksUri, assertion valid di sink /token, callback auth valid); conformance: `../conformance/results/run4/pkjwt-check.json` (termasuk 422 PRIVATE_KEY_JWT_NOT_CONFIGURED untuk client tanpa pre-shared).
- Konsekuensi: booster di UE tidak bisa lagi memanggil adapter langsung (<AS_IP>:8080 closed) — harus lewat backend (model r4).
