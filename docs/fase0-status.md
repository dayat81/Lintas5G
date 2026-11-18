# Status Fase 0 — Feasibility

> Per **18 Nov 2026 07:57 WIB**. Semua angka **[Dilaporkan PoC Architect]** dan belum diverifikasi ulang secara independen.
> Roadmap lengkap: [roadmap.md](roadmap.md).
> Status Sesi C: verdict usulan adalah merge [PR #1](https://github.com/dayat81/Lintas5G/pull/1). Lihat [verdict](results/2026-11-18-sesi-c-verdict.md).

## Ringkasan

| | |
|---|---|
| Item selesai | 4 / 12 (3 berjalan, 5 belum mulai) |
| Sedang berjalan | Sesi A (mulai 18 Nov 2026 07:57 WIB); urutan Sesi A → B → C |
| Jadwal | Rencana 18–19 Nov 2026; toleransi sampai 20 Nov 2026 |
| Biaya GCP sejauh ini | Sekitar USD 2–2,5 dari budget USD 15–25 [Dilaporkan PoC Architect] |
| Kriteria lulus | Di bawah beban: p99 latensi flow prioritas turun ≥50%, goodput GBR ≥95%, konsisten di 3 ulangan |

## Tracker work item

Legenda: ✅ selesai · ⏳ berjalan · ⬜ belum mulai

| # | Item | Status | Sesi | Catatan [Dilaporkan PoC Architect] |
|---|---|---|---|---|
| 1 | PR #1: IaC, observability, script tes, skeleton adapter QoD | ✅ PR open | – | Merge setelah verdict Fase 0 ([PR #1](https://github.com/dayat81/Lintas5G/pull/1)) |
| 2 | Sizing GCP | ✅ | – | 12 vCPU, steal 0% |
| 3 | Commit script Hari 1 | ✅ | – | Commit `07f99e0` masuk PR #1 |
| 4 | Subscriber tes 5G SA | ⏳ | – | – |
| 5 | Baseline 4G EPC + srsRAN ZMQ | ✅ | – | Attach OK; ping 0% loss, sekitar 30 ms; iperf UL 18,9 / DL 30,8 Mbit/s; TTFB HTTP via proxy 101 ms (target ≤100 ms; batas bawah sekitar 89 ms karena 2× RTT ZMQ) |
| 6 | Bring-up 5GC SA + PCF + UERANSIM | ⏳ | A | Mulai 18 Nov 2026 07:57 WIB |
| 7 | Tes (a) N5 | ⏳ | A | – |
| 8 | Tes (b) N7 / PFCP / QFI | ⏳ | A | – |
| 9 | Varian Rx/PCRF | ⬜ | B | – |
| 10 | `tc` HTB + Zeek paralel | ⬜ | B | – |
| 11 | Tes (c) p99 di bawah beban | ⬜ | B | Kriteria: p99 turun ≥50%, goodput GBR ≥95%, 3 ulangan |
| 12 | Batch load ClickHouse/Grafana + verdict + merge PR #1 | ⬜ | C | – |

## Catatan

| Catatan | Isi |
|---|---|
| Known issue | Uji end-to-end MPLS L3VPN gagal (LDP); opsional dan tidak memblokir Fase 0 |
| Baseline TTFB | 101 ms sedikit di atas target 100 ms; batas bawah sekitar 89 ms datang dari 2× RTT ZMQ, bukan dari core |
| Asumsi kunci | UPF Open5GS dinilai tidak memprioritaskan per QFI, sehingga bottleneck `tc` dipakai agar diferensiasi terlihat [Dilaporkan PoC Architect, belum diverifikasi] |

## Batasan metodologi

- UE simulasi (UERANSIM untuk tes a/b/c; srsRAN Project gNB sebagai bonus).
- Radio lewat ZMQ dengan RTT sekitar 30 ms, bukan RF over-the-air.
- Zeek berbagi CPU dengan emulator; `capture_loss.log` dipantau untuk memastikan capture tidak kehilangan paket.
- ClickHouse/Grafana dimuat batch setelah tes, bukan real-time; log mentah disimpan di GCS.

## Keputusan terkait Fase 0 (18 Nov 2026)

- [x] Kuota GCP tetap 10–12 vCPU
- [x] PR #1 di-merge setelah verdict Fase 0
- [x] Zeek wajib paralel dengan emulator di setiap sesi; ClickHouse/Grafana batch setelah tes; log ke GCS
- [x] Urutan Sesi A → B → C; Sesi A mulai 18 Nov 2026 07:57 WIB
- [x] RAN UERANSIM untuk tes (a)(b)(c); srsRAN Project gNB sebagai bonus
- [x] Toleransi jadwal Fase 0 sampai 20 Nov 2026
