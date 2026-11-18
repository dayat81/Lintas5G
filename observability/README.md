# Observability: Zeek → Vector → ClickHouse → Grafana

| Path | Isi | Status |
|---|---|---|
| `zeek/pktlat2.zeek` | Korelasi latency per paket v2.1 (QUIC hash payload; TCP off) | FAKTA (lab on-prem) |
| `zeek/mglt.zeek`, `zeek/pktlat.zeek` | Dependensi (parser probe MGLT, crc32c; pktraw dimatikan) | FAKTA |
| `zeek/run-live.zeek` / `run-offline.zeek` | Entry point live (mirror VLAN) / offline `zeek -r` | FAKTA |
| `zeek/skew.cfg.example` | Config framework: `PKTLAT2::skew_s`, `PKTLAT2::run_id` | — |
| `vector/vector-agent.yaml` | vm-core-ran: tail `pktlat*.log` → vm-obs :6000 | USULAN (`vector validate` OK) |
| `vector/vector-aggregator.yaml` | vm-obs: :6000 → ClickHouse `pkt_latency`/`pktlat_stats` | USULAN (`vector validate` OK, remap diuji dengan sampel) |
| `clickhouse/init.sql` | DB `poc_latency`: `pkt_latency`, `mglt_markers`, `pktlat_stats` (ReplacingMergeTree, TTL 60 hari) | FAKTA |
| `clickhouse/loader/zeek2ch.py` | Loader alternatif tanpa Vector (SSH read-only + HTTP insert) | FAKTA (lab on-prem) |
| `grafana/dashboards/poc-pktlat.json` | Dashboard latency per paket | FAKTA |
| `docker-compose.yml` | ClickHouse + Grafana (127.0.0.1:3000) + Vector di vm-obs | USULAN |

## Jalankan Zeek (vm-core-ran)

```bash
cd observability/zeek && cp skew.cfg.example skew.cfg
# Live: interface mirror dengan VLAN per tap (102=s1u, 105=s5s8, 109=sgi; redef jika berbeda)
zeek -C -i <iface-mirror> run-live.zeek
# Offline
zeek -C -r capture.pcap run-offline.zeek PKTLAT2::skew_s=0.0
```

Sesuaikan `PKTLAT2::ue_net` (default pool UE Open5GS `10.45.0.0/16`), `MGLT::subnet_seg`, dan peta VLAN dengan `redef`.

## vm-obs

```bash
cp ../.env.example ../.env && chmod 600 ../.env   # isi password
docker compose up -d
```

Grafana via IAP: `gcloud compute start-iap-tunnel vm-obs 3000 --local-host-port=localhost:3000 --zone=<zone>`.
