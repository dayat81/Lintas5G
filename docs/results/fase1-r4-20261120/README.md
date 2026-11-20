# Artefak Fase 1 close-out (20 Nov 2026)

Ringkasan: [`../2026-11-20-fase1-closeout-r4.md`](../2026-11-20-fase1-closeout-r4.md).

| Path | Isi |
|---|---|
| `GATES-r4.md`, `GATES-r4.sha256*` | Kriteria gate FROZEN v1.1 (verbatim; sha256 d396a72e…). `GATES-r4.sha256.v1.0` = hash v1.0 historis |
| `PROGRESS.md` | Log progres close-out (box offline + r4/r4v) |
| `provision/` | IaC provisioning statis (subscriber, PCC/PCF, slice) + evidence log |
| `conformance/` | Harness behave CAMARA QoD r4.3 + hasil run4 (127/127) |
| `callback/` | Uji callback c1–c5 per sessionId |
| `trace/` | Korelasi N5→N7→PFCP→NGAP→QFI (timeline teredaksi) |
| `adapter-exposure/` | nmap/ss: adapter tidak terjangkau |
| `multiue/` | Multi-UE A/B + paralel (`res/*/result.json`) |
| `obs/` | Ingest ClickHouse + screenshot Grafana |
| `r4/` | Readiness, runbook, skrip gate `r4gate.py`, hasil G1 (`r4-g1*.csv`, `RESULTS-r4.md`) |
| `img/` | Screenshot app booster run A1 (teredaksi) |

Tidak disertakan (sengaja): pcap mentah, state/tfvars Terraform, arsip sesi emulator, secret (kunci, password, token, K/OPc, config klien adapter), source adapter QoD (private), data mentah per-UE multi-UE (`*.probe.csv`, `*.be.json`, `*.qf.json`), input JSONL ingest Grafana (`obs/in*/`), plugin/node_modules, screenshot tak teredaksi.
Path `/workspace/...` di skrip merujuk ke workspace lab; skrip yang memakai `UE_POOL_PREFIX`/`MOCK_DEVICE_NET` butuh env tersebut diisi nilai lab.
