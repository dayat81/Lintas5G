# Claim -> evidence map and gaps

## Update whitepaper v0.7.2: GCP round 3 (r3, 2026-11-20)
Paper: `paper/lintas5g-qod-booster-whitepaper-v0.7.2.{md,pdf}`. Data: `data/r3/` (T1-T5, r3-results, VALIDITY, static-config, zeek-split). Figures: `figures/F7`, `F8`, `F9`. Setup: saturated cell (200 Mbit/s bulk UDP vs ~104-109 Mbit/s cell), 8 runs (4 with QoD), Zeek in two ~63 s windows only. Percentiles: nearest-rank.

| Gate / claim | r3 result | Verdict |
|---|---|---|
| Playback with QoD > without QoD | 4/4 QoD runs better (41-94% playing vs 0-13%) | PASS |
| Byte share on boost QFI while QoD active | 75.6-96.5% | PASS |
| Byte share on boost QFI over whole window | 60.7-80.1% | FAIL (< 80% criterion) |
| Zeek downlink p50 latency reduction | lower in 3 of 4 QoD runs (~4-5x); see VALIDITY.md for the exception | PARTIAL |
| Loss <= 5% | 7-15% | FAIL |
| Startup | QoD active only after 112-134 s; no startup speed-up claim | PARTIAL |
| "No manual configuration" (claim replaced by approved wording) | one-time static provisioning required (static PCC 5QI 69, gNB slice policy, PCF qos_profiles, patched UPF, 5QI 4 template in DB) | FAIL; disclosed. Allowed wording: "No per-session or per-app manual configuration; one-time static provisioning is disclosed." |

Caveats: small n, QoD session gaps of 34-52 s (booster re-creates sessions), MGLT-Zeek excluded. The rows below are the earlier (round 1/2) state; the YouTube and loss gaps are superseded by r3 as above.

| Whitepaper claim | Evidence in repo | Status |
|---|---|---|
| Architecture CAMARA QoD v1.2.0 -> BSF -> N5 -> QFI | CAMARA QoD r4.3 spec (upstream), `data/qos-profiles.yaml`; adapter source not published (private); `lab/offline/api-prio.py`, `lab/scenarios/qod_boost.py` | Adapter source not published (private); **architecture diagram to be drawn (F1)** |
| Conformance 126 passed / 0 failed / 1 skipped | `data/conformance/summary-0.1.2.json` (126/0/1 plus 16/16 lab extensions; adapter 0.1.2, private source) | OK. Skip = `PRIVATE_KEY_JWT` (documented deviation) |
| Offline results: scenarios a1/c1/b2/m3/m4 | `data/vpn/*`, `lab/scenarios/RESULT.md` | OK for gate verdicts; a2/b2 TCP anomaly under CPU contention is documented, not re-run on isolated CPU |
| Offline robustness (soak, parallel, no crash/release) | `data/offline/SOAK50-q4`, `SOAKPAR20-q4` | OK. Caveats: 9 NULL-TBS errors and 2 self-recovering UL failures remain; N2 path not exercised |
| API priority (5QI 69) cuts create latency | `data/offline/n5-q4p*`, `data/gcp-round1/RESULT-round1.md` (r3b) | Offline OK (43-54 ms vs 3.5-4 s earlier; earlier figure from run notes, raw data not copied). GCP: partial, "no-rule" comparison for CREATE under load not measured |
| GCP round 1: MGLT p99 5476 -> 1547.5 ms (-72%) | `data/gcp-round1/summary.csv`, `RESULT-round1.md`, `data/gcp-round1/zeek-r0-r2/mglt.log` | OK for the MGLT reflector flow only. n=14 boosted vs n=68 reference window |
| YouTube improvement (round 2) | none | **GAP**: round 2 stopped 2026-11-19 21:20 WIB, no valid result. Round 1 YouTube: stall_count 0 during boost, but no playing baseline, most YouTube DL stayed on QFI 1 (CDN IP rotation vs 3-IP limit) |
| >= 80% YouTube bytes on boost QFI (approved criterion) | none | **GAP**: tooling written, not measured validly |
| Target loss <= 5% | none | **GAP**: no per-flow loss counter in round 1 |
| Evidence "Grafana/logcat" | logcat/Grafana not included (raw, may carry device data) | **GAP** by sanitization policy; summaries only |

## Other gaps for a partner-reproducible package
- No pcap in repo (policy). Re-capture with `tcpdump` as in the scripts; QFI timeline tools: `lab/offline/qfi_timeline.py`, `lab/gcp-round1/qfi_flows.py`.
- UE confs/subscriber DB, adapter client secrets, signing key, SUCI keys: partners generate their own (steps in REPRODUCE.md).
- Booster APK and its source are not in this repo (sha256 only).
- Raw offline results for N2S-*, c*, q* experiments are not copied (only the 50/20-cycle soaks, n5-q4p*, VPN gates).
- Open5GS overlay and base image snapshot are excluded on purpose.
- Adapter RESULT.md (design + deviations D1..D12) not copied; consider adding after review.
