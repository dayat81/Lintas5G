# §7.5 deliverables (GCP r3, 20 Nov 2026)
- T1-playback.{csv,md}: per run and condition (pre-boost / boost or boost-window / post10 / after): window s, playing s and %, stall count, stall s, resolution (mode, mean), startup s.
- T2-qfi-bytes.{csv,md}: % of YouTube DL bytes on the boost QFI, whole boost window and while QoD AVAILABLE.
- T3-zeek-latency.{csv,md}: Zeek DL one-way p50/p95, W1 vs W2, plus W2 split by QoD on/off.
- T4-loss.{csv,md}: YouTube DL loss (total and worst flow) and throughput, pre vs boost window.
- T5-bad.{csv,md}: bad_total per run (all 0).
- F7-playing-stall.png, F8-zeek-p50-w1-w2.png, F9-A1-before-during-redacted.png (player not started under load vs playing with QoD; comments redacted, no account shown).
- VALIDITY.md: deviations, cross-run and same-session results, byte-gap causes, small n, MGLT exclusion, static config.
- r3-results.{csv,md}: full per-phase table (all metrics, incl. smoke runs). evidence/: static-config-r3.json, zeek-split.json.
- r3-19nov-aborted-summary.md: the 19 Nov attempt stopped by the YouTube sign-in blocker.
