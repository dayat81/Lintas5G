# Sanitized result data

Only summaries (CSV/JSON/text). No pcap, no raw NF logs, no session data. IPs are documentation addresses.

| Dir | Content | Origin |
|---|---|---|
| `offline/SOAK50-q4/`, `offline/SOAKPAR20-q4/` | `checks.txt` (crash/release/Error Indication counters, keepalive), `delivery.jsonl` (per-session loss), `qfi-cycles.json`, `smf-lat.json` | offline lab, gNB `slice-qosrel4`, 50 cycles single / 20 cycles x 2 UE parallel |
| `offline/n5-q4p1..p5-*` | `report.json/.txt`, `qfi_timeline.txt`, `keepalive.txt`: adapter E2E with API-priority rule (5QI 69), loads light/150M | offline lab, adapter 0.1.1 |
| `vpn/{a1,c1,b2,m3,m4}/` | gate JSON + per-flow packet counts per phase (pre/on/post) | booster examine VPN scenarios, qosrel / stock gNB |
| `vpn/q4-{a1,a3,a4,b2}/` | same, re-run on `slice-qosrel4` | |
| `gcp-round1/` | `RESULT-round1.md` (sanitized report), `summary.csv`, `runs/<run>/{times,iperf-bulk.txt,bad-counts.txt,qfi-flows.txt}`, `zeek-r0-r2/{mglt.log,pktlat_stats.log}` | GCP booster E2E round 1 (2026-11-19) |

GCP round 2 (YouTube) was stopped by the user at 21:20 WIB without a valid result: **no round 2 data is included**.
