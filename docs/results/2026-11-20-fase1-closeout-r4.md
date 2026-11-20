# Fase 1 close-out (20 Nov 2026): offline item 0–6 + GCP r4/r4v (booster.5.1 E2E)

Status: **Fase 1 CLOSED 2026-11-20** (lihat [fase1-status.md](../fase1-status.md)). Semua waktu WIB (UTC+7).
Kriteria: [`GATES-r4.md`](fase1-r4-20261120/GATES-r4.md) **FROZEN v1.1**, sha256
`d396a72e91619609e97f4c1a81fb2cb6365088ff9b96083e80ea7544ad451f5e` (file disalin byte-per-byte, cek: `sha256sum GATES-r4.md`).
Artefak lengkap: [`fase1-r4-20261120/`](fase1-r4-20261120/README.md).

## Ringkasan (FAKTA)

| Item / gate | Hasil | Bukti |
|---|---|---|
| 0 Provisioning IaC (G7) | PASS: lab dibangun ulang dari DB kosong dalam 32 s, drift 0; apply ke-2 drift 0 | `provision/` |
| 1 Conformance CAMARA QoD r4.3 (G2) | PASS 127/127, 0 FAIL, 0 SKIP (mock backend, `.feature` resmi tanpa diubah) | `conformance/results/run4/` |
| 2 Callback (G3) | PASS 5/5 (AVAILABLE, DELETE_REQUESTED, DURATION_EXPIRED 10,02 s, NETWORK_TERMINATED ×2, + PRIVATE_KEY_JWT) | `callback/CALLBACKS.md` |
| 3 Trace (G4) | PASS 3 ulangan; median N5→PFCP 2,97 ms, →NGAP 4,17 ms, →paket QFI pertama 31,3 ms, →AVAILABLE di sink 37,6 ms | `trace/TIMELINE.md` |
| 4 Adapter tertutup (G5) | PASS: adapter 0.1.3 bind 127.0.0.1; 8080 closed dari UE/container lain | `adapter-exposure/`, `r4/RESULTS-r4.md` |
| 5 Multi-UE (G6) | PASS: p99 UE QoD 34–36 ms vs UE tanpa QoD 5,45–5,88 s (−99,4%); loss sesi median 0,000% / maks 0,114%; 0 paket bocor QFI | `multiue/MULTIUE.md` |
| 6 Grafana (G8) | PASS: dashboard `booster-qod.json` tanpa perubahan, data adapter + multi-UE + N3 | `obs/` |
| G1 E2E booster.5.1 (GCP r4v) | **PASS** A×3 (G1a ≤5% loss, G1b ≥80% cakupan, G1c ≥90% share QFI boost) | `r4/RESULTS-r4.md` §r4v |
| G9 rilis | **tidak dilakukan** (lihat keterbatasan) | – |

### G1 per run (r4v, window T_BOOSTER → T_BOOSTER_FINISH dari logcat)

| Run | Window | time-to-AVAILABLE | Cakupan AVAILABLE | Loss DL YT saat AVAILABLE | Share byte QFI boost | Stall YouTube | G1 |
|---|---|---|---|---|---|---|---|
| A1 | 154,1 s | 5,4 s | 95,7% | 1,15% | 95,8% | 6 / 32 s | lulus |
| A2 | 155,3 s | 5,2 s | 94,8% | 0,47% | 99,5% | 7 / 17 s | lulus |
| A3 | 153,1 s | 5,3 s | 95,0% | 0,07% | 99,8% | 3 / 6 s | lulus |

Pembanding tanpa booster: N1 loss 26,8% (stall 145 s), N2 23,6% (stall 133 s), N3 23,9% tetapi hanya 681 paket → **tidak dinilai** (<1.000 paket, sesuai definisi FROZEN).

Bukti tampilan G8 (run A1): app booster [`img/booster-A1-end-redacted.png`](fase1-r4-20261120/img/booster-A1-end-redacted.png), Grafana [`obs/screenshots/grafana-r4-A1.png`](fase1-r4-20261120/obs/screenshots/grafana-r4-A1.png).

## Disclosure dan keterbatasan (FAKTA)

1. **Modifikasi RAN:** gNB OAI v3.0.0 memakai patch slice (`slice-qosrel4`, kebijakan DL slice per 5QI). Ini modifikasi RAN, bukan OAI stok.
2. **UPF tidak menegakkan MBR:** Open5GS 2.8.0 UPF tidak membatasi MBR per QoS flow; diferensiasi berasal dari penjadwalan RAN + QFI, bukan policing UPF.
3. **G5 temuan:** port **22/tcp VM core terjangkau dari netns UE** (bukan port adapter). Adapter 8080 closed; 8090/8443 backend open by design (API booster).
4. **G7:** provisioning statis lewat skrip, tanpa langkah per sesi/per app. Satu-satunya langkah manual: **login akun YouTube sekali** di emulator (lewat noVNC sementara, tunnel dimatikan sebelum run).
5. **GATES-r4.md baris 3** masih bertuliskan "Status: draft…". Ini label lama yang diketahui; yang berlaku adalah status FROZEN v1.1 dan hash di atas. File sengaja tidak diubah agar hash tetap cocok.
6. **G9 tidak dilakukan:** tidak ada tag/rilis. PR ini hanya publikasi hasil.
7. **N3 tidak dinilai** (<1.000 paket YouTube DL).
8. **Biaya estimasi** (bukan billing API): r4 pagi ≈ USD 0,5–0,7, r4v ≈ USD 1,5–1,8, total ≈ USD 2,0–2,5 (tarif USD 0,82/jam untuk 8+4 vCPU).
9. Source adapter QoD tetap private; repo ini hanya memuat hasil, skrip uji, dan analisis.
10. Redaksi: IP lab/publik diganti placeholder (`<AS_IP>`, `<BACKEND_IP>`, `<UE_POOL>`, `<MOCK_DEVICE_NET>`, `<GCP_IAP_RANGE>`, `<LAB_SUBNET>`), nama resource/bucket proyek lain diganti `<proyek-lain>`/`<bucket-lain-N>`, nama aplikasi internal → "booster". IP yang tersisa hanya loopback (127.0.0.x), 0.0.0.0, dan alamat dokumentasi RFC 5737 (198.51.100.x).

## Lanjutan (USULAN)

- Tutup akses 22/tcp dari pool UE ke VM core (firewall/nftables di core) dan uji ulang G5.
- Policing MBR: evaluasi UPF alternatif atau `tc` per QFI bila MBR dibutuhkan.
- G9 (tag/rilis) dengan persetujuan terpisah.
- Implementasi TCP per-packet (desain sudah ada di whitepaper v0.1).
