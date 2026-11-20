# Figure list (whitepaper v0.1)

| # | Figure | Source data | Status |
|---|---|---|---|
| F1 | Architecture: app -> CAMARA QoD v1.2.0 adapter -> BSF/PCF (N5 Npcf_PolicyAuthorization) -> SMF -> UPF -> gNB QFI/DRB | adapter source not published (private); see API contract/spec; diagram to be drawn | TODO (PM) |
| F2 | Sequence: detect -> CREATE -> 201 -> QFI active -> DELETE | `data/vpn/q4-a1/q4-a1_gate.json` | TODO |
| F3 | QFI timeline per scenario (pre / on / post) | `data/vpn/*/*_flows.csv`, `data/vpn/q4-*/*_bins.csv` | data ready, plot TODO |
| F4 | Conformance summary 126/0/1 by feature | `data/conformance/summary-0.1.2.json` | data ready |
| F5 | Soak: 50 cycles full load, loss per session | `data/offline/SOAK50-q4/delivery.jsonl` | data ready |
| F6 | GCP round 1: MGLT p50/p99 baseline vs boost (-72% p99) | `data/gcp-round1/RESULT-round1.md`, `data/gcp-round1/summary.csv` | data ready |
| F7 | YouTube round 2 (before/after) | none | **GAP**, see CLAIMS.md |
