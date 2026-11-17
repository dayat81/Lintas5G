# tests/qod — uji feasibility QoD

Rencana lengkap: [docs/qod-feasibility-test.md](../../docs/qod-feasibility-test.md). Semua nilai **placeholder**.

| Berkas | Fungsi |
|---|---|
| `env.example` | Salin ke `.env` (tidak di-commit) |
| `app-session-create.json`, `app-session-patch.json` | AppSessionContext N5 (envsubst) |
| `app-sessions.sh create\|get\|patch\|delete` | (a) Npcf_PolicyAuthorization manual ke PCF |
| `tc-setup.sh` / `tc-rollback.sh` | (c) Bottleneck HTB 20 Mbit, kelas EF/AF41 vs best-effort fq_codel, netem 10 ms |
| `iperf-matrix.sh <before\|after\|after-delete>` | Trafik latar 10/18/25 Mbit × N run |
| `aar-rx.template` | Varian 4G: AVP Rx AAR ke PCRF |
| `evaluate.py data.csv` | Kriteria K1–K5 (PASS/FAIL) |

Butuh: `curl` dengan HTTP/2, `envsubst` (gettext), `iproute2`, `iperf3`, Python 3.
