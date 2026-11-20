# Fase 1 closeout r4 — PROGRESS (offline di box, tanpa GCP/push)

Acuan: `GATES-r4.md` FROZEN v1.1 (`GATES-r4.sha256`). Semua waktu WIB (UTC+7).

## Kejadian
- **09:46 WIB box restart.** Hilang: docker engine + SEMUA image lokal (core 2.8.0-qosrel, gNB slice-qosrel4, adapter 0.1.x), volume DB subscriber `n5-mongo-db`, ch-test (ClickHouse), venv, `oai-n5-test/build/`. Workspace dipulihkan dari snapshot 09:46 (satu file adapter terpotong: `qod_adapter/__init__.py`, sudah diperbaiki 10:06).
- Pemulihan (sudah diapprove sebagai lab offline): docker.io 26.1.5 + tshark + nmap dipasang; venv dibangun ulang; `lintas5g/n5-core-base:tmp` dibangun ulang dari resep `srsfix/img` (Open5GS 2.8.0~jammy5, sama versi) → `lintas5g/open5gs:2.8.0-qosrel` dari overlay (`oai-n5-test/lab/img-open5gs`); gNB `v3.0.0-slice-qosrel4` dibangun ulang dari OAI v3.0.0 + `patches/oai-v3.0.0-slice-qosrel4-combined.diff` (`build/build-gnb.sh`); subscriber DB dibuat ulang lewat IaC (item 0). Izin file secret dipulihkan ke 600/700 (snapshot memulihkannya 644).

## Status per item
| Item | Status | Bukti |
|---|---|---|
| 0 Provisioning IaC | **PASS** — `FRESH=1 lab-up.sh up` membangun ulang lab dari volume DB kosong dalam 32 s (core, subscriber, PCC 5QI 69 + template 5QI 2/3/4/7/80, PCF qos_profiles, slice.conf, gNB, 2 UE + keepalive, adapter, sink), cek akhir drift 0; apply ke-2 drift 0 | `provision/`, `provision/evidence/lab-up-full-fresh.log`, `provision-apply-2nd.log` |
| 1 Conformance (behave) | **PASS** 127/127, 0 FAIL, 0 SKIP (mock backend) | `conformance/results/run4/` |
| 2 Callback | **PASS** 5/5 (AVAILABLE, DELETE_REQUESTED, DURATION_EXPIRED 10,02 s, NETWORK_TERMINATED via policy gagal & via PCF terminate, + PKJWT) | `callback/CALLBACKS.md`, `callback/per-session/` |
| 3 Trace | **PASS** 3 ulangan; median N5→PFCP 2,97 ms, →NGAP 4,17 ms, →paket QFI sesi pertama 31,3 ms, →AVAILABLE di sink 37,6 ms | `trace/TIMELINE.md`, `trace/timeline-{1,2,3}.json` (pcap mentah hanya di box) |
| 4 Adapter 0.1.3 tertutup + PKJWT | **PASS** — bind 127.0.0.1; nmap 8080/8090/8443 closed dari UE1, UE2, container lain, gateway host (kontrol positif open); PKJWT di stack nyata | `adapter-exposure/`, `callback/c5b.json` |
| 5 Multi-UE | **PASS** — 3× A/B + 3× paralel: loss sesi median 0,000% / maks 0,114%; p99 UE QoD 34–36 ms vs UE tanpa QoD 5,45–5,88 s (−99,4%); goodput flow sesi 15,0 Mbit/s (150% target GBR 10, 99,9% offered); isolasi QFI 0 paket bocor; callback per sessionId benar. RAN ter-patch (slice-qosrel4) diungkapkan | `multiue/MULTIUE.md`, `multiue/res/` |
| 6 Grafana | **PASS** (lingkup item 6) — ch-test + Grafana 11.3 lokal, dashboard booster-qod.json tanpa perubahan, data adapter + multi-UE + N3 dimuat, 2 screenshot headless. Bagian 'screenshot app booster' dari G8 menunggu E2E booster | `obs/README.md`, `obs/screenshots/` |

## Log
- 10:16–10:20 WIB: gNB slice-qosrel4 selesai dibangun (929 s). Rebuild pertama gagal di UE (exit 139: `ue*.conf` 600 milik box tidak terbaca oleh root nrUE dengan `--cap-drop ALL`; `lab.sh` juga salah melapor "attached"). Perbaikan: conf 640 grup root (tetap tidak world-readable), `lab.sh start_ue` kini gagal bila tidak ada IP, `lab-up.sh` berhenti bila attach gagal + opsi `FRESH=1` (hapus volume DB). Rebuild dari nol: OK.
- 10:24 WIB: `jwks_uri` adapter dikoreksi `https://` → `http://` (adapter melayani HTTP di loopback); adapter di-restart lewat `lab-up.sh adapter`.
- 10:24 WIB: fault injection c3 (hapus template 5QI 4 UE1) dipulihkan oleh `provision.sh apply` (drift 1 → 0).
- 10:31–10:39 WIB: item 5 (pilot + 3 A/B + 3 paralel). Pcap mentah dipindah ke `/workspace/fase1-raw/` (700, di luar pohon artefak).
- 10:40–10:55 WIB: item 6. Bridge docker baru (f1-obs) diblok oleh tabel iptables-legacy lama (FORWARD DROP) → Grafana dijalankan di netns ch-test (tanpa mengubah firewall).

## E2E booster.5.1 (n5, offline) — PARTIAL
- FAKTA: APK sha256 cocok; marker T_BOOSTER/T_BOOSTER_FINISH ada di dex; body /16 app r4 → 201 di adapter 0.1.3 (client lain 400, /15 400); parser window + fallback t_back/t_end lulus selftest. `booster-e2e/`.
- Keterbatasan: tidak ada Android/adb/emulator di box, tidak ada jalur internet UE lewat 5G (default route eth0), image emulator lama tanpa YouTube, CPU box penuh RAN. E2E dipindah ke sesi GCP r4.
## r4
- Kesiapan + estimasi biaya: `r4/READINESS.md`; runbook: `r4/RUNBOOK-r4.md`. GCP belum di-apply, tidak ada push.

- 20 Nov 11:47 WIB: GCP r4 dijalankan (apply 11:07, destroy 11:45, audit bersih). Berhenti setelah smoke: YouTube minta re-verify akun Google (butuh noVNC, di luar izin). Hasil: `r4/RESULTS-r4.md`. A×3/N×3 belum dijalankan.
- 20 Nov 14:59 WIB: r4v selesai. Login YouTube via noVNC, arsip sesi disimpan ulang, run headless: A1–A3 lulus G1a/b/c, N×3. Destroy dan audit bersih. Lihat `r4/RESULTS-r4.md` §r4v.
