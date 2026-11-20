# Kesiapan r4 (20 Nov 2026 ~11:10 WIB)

| Hal | Status |
|---|---|
| GATES-r4 | **FROZEN v1.1**, sha256 `d396a72e…ad451f5e` = isi `GATES-r4.sha256` (dicek 11:00 WIB). Skip-list v1.1 kosong (0/127), dibekukan 10:05 WIB sebelum behave pertama. v1.0 disimpan di `GATES-r4.sha256.v1.0`. |
| Catatan dokumen | Baris 3 GATES masih berbunyi "Status: draft untuk disetujui…" padahal judul FROZEN v1.1 — tidak diubah (perubahan = versi baru + hash baru). Usul: biarkan; keputusan final di §Keputusan final yang berlaku. |
| Offline (item 0–6) | PASS, lihat `../PROGRESS.md`. |
| E2E booster.5.1 offline | PARTIAL: validasi offline PASS, E2E BLOCKED (tanpa Android/jalur YouTube) → `../booster-e2e/STATUS.md`. |
| Runbook | `RUNBOOK-r4.md` (A×3 wajib, N×3 atau N×2, smoke, G5, G8, destroy + audit biaya). |
| Gap sebelum apply | (1) port provisioning IaC ke layout VM GCP (netns, bukan container), (2) bundle r4 (APK 5.1 + adapter 0.1.3 image/config), (3) r4.tfvars = salinan r3.tfvars. Semua lokal, tanpa apply. |

## Estimasi biaya (USULAN, dari FAKTA r1: 8+4 vCPU ≈ USD 0,82/jam)
| Fase | Menit |
|---|---|
| Bring-up + provisioning | 25 |
| Smoke s0 | 7 |
| A×3 + N×3 (≈8 menit/run) | 48 |
| G5 bukti + G8 screenshot | 10 |
| Agregasi/transfer | 10 |
| Destroy + audit | 8 |
| **Total** | **≈108 menit ≈ 1,8 jam → ≈ USD 1,5** |
Rentang: N×2 ≈ 1,7 jam (USD 1,4); 1 ulang smoke/run gagal-setup ≈ 2,5 jam (USD 2,1). Ditambah egress/storage kecil. Jauh di bawah cap USD 40/hari.
