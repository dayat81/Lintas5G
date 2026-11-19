# Status Fase 0 — Feasibility

> Per **18 Nov 2026 17:58 WIB** (penutupan Fase 0). Angka **[Dilaporkan PoC Architect]**, hasil ukur lab GCP, belum diverifikasi independen.
> Roadmap lengkap: [roadmap.md](roadmap.md). PR #1 sudah di-merge (`503199e`).
> Verdict: [Sesi C](results/2026-11-18-sesi-c-verdict.md) dan [penutupan Sesi D / verdict v2](results/2026-11-18-sesi-d-closeout.md).

## Ringkasan

| | |
|---|---|
| Item selesai | 12 / 12 item awal; penutupan: 5 / 6 (QFI 2 end-to-end 5G SA masih terbuka, butuh Sesi E) |
| Sesi | Hari 1–2, Sesi A, B, C, D selesai; semua resource di-destroy dan diaudit setelah tiap sesi |
| Biaya GCP | Sekitar USD 5–6 (estimasi; Sesi D ~2,0, hari ini ~3,4; cek billing) dari budget USD 15–25 [Dilaporkan PoC Architect] |
| Kriteria lulus | p99 flow prioritas turun ≥50% (ping/TTFB 72–97%, QUIC 74–78%), goodput GBR ≥95% (UDP 99,9–100%, TCP DL 100%, TCP UL 99% dengan pacing kernel), konsisten di 3 ulangan: **PASS** |

## Tracker work item

Legenda: ✅ selesai · ⏳ berjalan · ⬜ belum mulai · 🔶 terbuka (Fase 0 lanjutan / Fase 1)

| # | Item | Status | Sesi | Catatan [Dilaporkan PoC Architect] |
|---|---|---|---|---|
| 1 | PR #1: IaC, observability, script tes, skeleton adapter QoD | ✅ merged | – | `503199e` |
| 2 | Sizing GCP | ✅ | – | 12 vCPU, steal 0% |
| 3 | Commit script Hari 1 | ✅ | – | `07f99e0` |
| 4 | Subscriber tes 5G SA | ✅ | A | IMSI acak, KEY/OPC hanya di VM (0600) |
| 5 | Baseline 4G EPC + srsRAN ZMQ | ✅ | Hari 1 | ping ~30 ms; UL 18,9 / DL 30,8 Mbit/s; TTFB proxy 101 ms (floor ~89 ms) |
| 6 | Bring-up 5GC SA + PCF + UERANSIM | ✅ | A | 11 NF, UE registered |
| 7 | Tes (a) N5 | ✅ | A | 201 / 200 / 204 |
| 8 | Tes (b) N7 / PFCP / QFI | ✅ control-plane / 🔶 data-plane | A | QFI 2 di N3 = 0 paket dengan UERANSIM |
| 9 | Varian Rx/PCRF | ✅ | B | AAR → RAR → Create Bearer QCI 2 |
| 10 | `tc` HTB + Zeek paralel | ✅ | B–D | capture_loss 0% |
| 11 | Tes (c) p99 di bawah beban | ✅ | C | p99 −72…−97%, 3 ulangan |
| 12 | Batch ClickHouse/Grafana + verdict + merge PR #1 | ✅ | C | merged |
| 13 | Zeek pktlat per paket (UE/N3/N6) + QUIC idle/beban/QoD | ✅ | D | QUIC p99 −74…−78%; cakupan tap 100% |
| 14 | RCA TCP UL GBR 75% | ✅ | D | artefak `iperf3 -b`; pacing kernel 99% |
| 15 | STR ×10 di bawah beban + stabilitas ZMQ | ✅ | D | 10/10 STA, filter 6→0, 0 RLF |
| 16 | K2/K4 headless, restore sesi emulator | ✅ | D | restore 25–27 s; adbkey ikut arsip; YouTube headless PASS; K7 N/A |
| 17 | QFI 2 end-to-end 5G SA (srsRAN Project gNB + srsUE) | 🔶 | E | IaC `ran_mode=sa-srsran` + prebuild siap; belum di-apply |
| 18 | Verdict v2 + dokumen | ✅ | D | [verdict v2](results/2026-11-18-sesi-d-closeout.md) |

## Catatan

| Catatan | Isi |
|---|---|
| Known issue | Uji end-to-end MPLS L3VPN gagal (LDP); opsional dan tidak memblokir Fase 0 |
| Baseline TTFB | 101 ms sedikit di atas target 100 ms; batas bawah sekitar 89 ms datang dari 2× RTT ZMQ, bukan dari core |
| Asumsi kunci | UPF Open5GS 2.8 tidak memolisi MBR QER (terbukti Sesi A), sehingga enforcement QoD di SGi lewat `tc` |
| Temuan Sesi D | Kenaikan RTT di bawah beban terjadi di antrean tc SGi, di luar segmen tap UE↔N6; UL radio p99 naik 42 → 114 ms dan tidak diperbaiki QoD |
| Sesi emulator | Arsip sesi akun tes (termasuk adbkey) di bucket privat ber-versi; SENSITIF, tidak pernah di repo/log |

## Batasan metodologi

- UE simulasi (UERANSIM untuk tes a/b/c; srsRAN Project gNB sebagai bonus).
- Radio lewat ZMQ dengan RTT sekitar 30 ms, bukan RF over-the-air.
- Zeek berbagi CPU dengan emulator; `capture_loss.log` dipantau (0% di semua sesi).
- Probe QUIC = paket long-header + Version Negotiation, bukan handshake HTTP/3 penuh.
- Sesi D headless (tanpa VNC/tunnel publik); satu kali noVNC sementara (AP1a, disetujui user) untuk otorisasi adb.
- ClickHouse/Grafana dimuat batch setelah tes, bukan real-time; log mentah disimpan di GCS.

## Keputusan terkait Fase 0 (18 Nov 2026)

- [x] Kuota GCP tetap 10–12 vCPU
- [x] PR #1 di-merge setelah verdict Fase 0
- [x] Zeek wajib paralel dengan emulator di setiap sesi; ClickHouse/Grafana batch setelah tes; log ke GCS
- [x] Urutan Sesi A → B → C; Sesi A mulai 18 Nov 2026 07:57 WIB
- [x] RAN UERANSIM untuk tes (a)(b)(c); srsRAN Project gNB sebagai bonus
- [x] Toleransi jadwal Fase 0 sampai 20 Nov 2026
- [x] Sisa tes Fase 0 headless; K7 N/A; YouTube via sesi tersimpan di bucket privat
- [ ] Sesi E (5G SA QFI 2 end-to-end) — butuh approval
