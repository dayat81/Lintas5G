# Status Fase 1 — QoD MVP

> **CLOSED — 2026-11-20** (WIB). Kriteria: [`GATES-r4.md`](results/fase1-r4-20261120/GATES-r4.md) FROZEN v1.1 (sha256 `d396a72e91619609e97f4c1a81fb2cb6365088ff9b96083e80ea7544ad451f5e`).
> Hasil lengkap: [results/2026-11-20-fase1-closeout-r4.md](results/2026-11-20-fase1-closeout-r4.md).

| Gate | Status | Ringkasan |
|---|---|---|
| G1 E2E booster.5.1 (A×3) | ✅ lulus | Cakupan AVAILABLE 94,8–95,7%, loss saat AVAILABLE 0,07–1,15%, share QFI boost 95,8–99,8%; time-to-AVAILABLE 5,2–5,4 s |
| G2 Conformance CAMARA QoD r4.3 | ✅ | 127/127 |
| G3 Callback | ✅ | 5/5 + PRIVATE_KEY_JWT |
| G4 Trace N5→QFI | ✅ | median 31,3 ms ke paket QFI pertama |
| G5 Adapter tertutup | ✅ (dengan temuan) | adapter bind loopback; **22/tcp VM core terjangkau dari UE** |
| G6 Multi-UE | ✅ | p99 34–36 ms vs 5,45–5,88 s |
| G7 Tanpa konfigurasi manual | ✅ (disclosed) | provisioning statis; login YouTube sekali |
| G8 Bukti tampilan | ✅ | screenshot app booster + Grafana run A1 |
| G9 Rilis | ⬜ tidak dilakukan | tanpa tag/rilis |

## Item terbuka / disclosure (dibawa ke Fase 2)

- G9 (tag/rilis) belum dilakukan; butuh persetujuan terpisah.
- 22/tcp VM core terjangkau dari netns UE (temuan G5): perlu ditutup dan diuji ulang.
- UPF Open5GS 2.8.0 tidak menegakkan MBR per QoS flow.
- gNB OAI memakai patch slice (`slice-qosrel4`): modifikasi RAN.
- GATES-r4.md baris 3 masih berlabel "draft" (label lama; status berlaku = FROZEN v1.1 per hash).
- N3 tidak dinilai (<1.000 paket). Biaya r4 ≈ USD 2,0–2,5 (estimasi).
- Private beta developer mitra (deliverable roadmap) belum dimulai.
