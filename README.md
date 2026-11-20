# Lintas5G

Open lab 5G/4G berbasis open source untuk partner: pengukuran **latency per paket end-to-end** (UE → RAN → transport MPLS → core → internet) dan uji **telco API CAMARA Quality-on-Demand** di atas Open5GS + srsRAN.

> Status: **Fase 1 CLOSED (20 Nov 2026)**. Hasil: [close-out Fase 1](docs/results/2026-11-20-fase1-closeout-r4.md), status: [docs/fase1-status.md](docs/fase1-status.md). Source adapter QoD tetap private. Fase 2 belum dimulai.

## Peta folder

| Folder | Isi |
|---|---|
| [`docs/`](docs/) | [roadmap](docs/roadmap.md), [status Fase 0](docs/fase0-status.md), [status Fase 1](docs/fase1-status.md), [arsitektur](docs/architecture.md), [lab GCP](docs/gcp-lab.md), [PoC latency](docs/latency-poc.md), [uji QoD](docs/qod-feasibility-test.md), [lisensi](docs/licensing.md) |
| [`infra/gcp/`](infra/gcp/) | Terraform (VPC, 3 VM tanpa IP publik, IAP, Cloud NAT, GCS, snapshot; `vm-mpls` opsional), startup, checklist test run |
| [`infra/mpls/`](infra/mpls/) | Rujukan backhaul MPLS S1. Skrip kanonis ada di `infra/gcp/startup/` |
| [`observability/`](observability/) | Zeek `pktlat2.zeek` v2.1, Vector, skema ClickHouse, dashboard Grafana, docker-compose vm-obs |
| [`tests/latency/`](tests/latency/) | Generator QUIC sisi UE dan pembanding hasil |
| [`tests/qod/`](tests/qod/) | Template app-session N5, Rx AAR, `tc` bottleneck, matriks iperf3, evaluasi kriteria |
| [`adapters/qod-af/`](adapters/qod-af/) | Adapter CAMARA QoD → N5/Rx (FastAPI) — SKELETON |
| [`upstream-patches/`](upstream-patches/) | Patch upstream Open5GS/srsRAN (AGPL-3.0, terpisah) |

Hasil Sesi A (N5): [docs/results/2026-11-18-sesi-a-n5.md](docs/results/2026-11-18-sesi-a-n5.md).
Hasil Sesi B (Rx + QoD): [docs/results/2026-11-18-sesi-b-rx-qod.md](docs/results/2026-11-18-sesi-b-rx-qod.md).
Hasil Sesi C (verdict): [docs/results/2026-11-18-sesi-c-verdict.md](docs/results/2026-11-18-sesi-c-verdict.md).
Akses VNC: [infra/gcp/vnc/README.md](infra/gcp/vnc/README.md).

## Quickstart (GCP)

```bash
cp .env.example .env && chmod 600 .env           # isi password lokal, jangan commit
cd infra/gcp/terraform
cp terraform.tfvars.example terraform.tfvars     # isi project_id dan my_iap_users
terraform init && terraform plan
terraform apply                                  # butuh billing + kuota (lihat docs/gcp-lab.md)
../scripts/test-run-day1.sh
terraform destroy                                # selalu destroy di luar jam tes
```

Akses VM hanya lewat IAP (`gcloud compute ssh --tunnel-through-iap`, `gcloud compute start-iap-tunnel`). VNC yang bind ke loopback memakai `gcloud compute ssh -L`.

## Lisensi

Apache-2.0 untuk isi repo ini ([LICENSE](LICENSE), [NOTICE](NOTICE)). Open5GS/srsRAN (AGPL-3.0) dipakai sebagai komponen terpisah; patch upstream di `upstream-patches/` berlisensi AGPL-3.0. Lihat [docs/licensing.md](docs/licensing.md).

Kontribusi: [CONTRIBUTING.md](CONTRIBUTING.md). Keamanan: [SECURITY.md](SECURITY.md).
