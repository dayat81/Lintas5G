# Rencana uji feasibility CAMARA QoD (2 hari, GCP)

Status: **RENCANA**. Belum dieksekusi. `terraform apply` dan subscriber tes baru butuh persetujuan pemilik lab sebelum mulai.

## Pertanyaan yang dijawab

1. Apakah AF session via **N5** (Npcf_PolicyAuthorization) di PCF Open5GS benar-benar sampai ke **N7 → SMF → PFCP QER/QFI** di UPF?
2. Dengan bottleneck terkontrol, apakah sesi QoD menghasilkan perbedaan latency/goodput yang terukur?
3. Apakah varian **4G** (Rx AAR → PCRF → Gx → dedicated bearer QCI) bisa menjadi jembatan sebelum 5GC SA?

## Environment

- GCP (lihat [gcp-lab.md](gcp-lab.md)), dibuat dengan Terraform pagi hari dan **di-destroy** di akhir tiap hari.
- 5GC SA: Open5GS 5GC (AMF/SMF/UPF/PCF/NRF/UDM/UDR) + gNB/UE (srsRAN Project ZMQ atau UERANSIM untuk control plane).
- 4G: EPC CUPS + srsRAN 4G (lab yang sama dengan PoC latency).
- Subscriber **tes khusus** (PLMN 001/01, mis. `imsi-001010000000001`, KEY/OPc dummy baru). Jangan memakai data subscriber nyata.
- Budget rujukan: USD 15–25 untuk 2 hari.

## Hari 1 — kontrol plane

| Langkah | Alat | Bukti |
|---|---|---|
| H1.1 Apply Terraform, bootstrap, UE attach (SA) | `infra/gcp` | `test-run-day1.sh` PASS |
| H1.2 (a) `POST /npcf-policyauthorization/v1/app-sessions` manual | `tests/qod/app-sessions.sh create` | HTTP 201 + `Location` |
| H1.3 (b) Verifikasi N7 (Npcf_SMPolicyControl UpdateNotify) dan N4 PFCP Session Modification dengan **QER/QFI baru** (+ PDR/SDF filter) | tcpdump di SBI + N4, Wireshark | pcap `n4-qer.pcap` |
| H1.4 (b) QFI baru di header ekstensi PDU Session Container GTP-U N3 | tcpdump N3 | pcap `n3-qfi.pcap` |
| H1.5 `PATCH` lalu `DELETE` (`POST .../delete`) → QER dihapus | `app-sessions.sh patch/delete` | pcap N4 |
| H1.6 Varian 4G: Rx AAR → Gx RAR → Create Bearer Request, EBI baru di S1-U | `tests/qod/aar-rx.template` | pcap Rx/Gx/S11 |

## Hari 2 — data plane & latency

| Langkah | Alat |
|---|---|
| H2.1 (c) Bottleneck `tc` HTB 20 Mbit: kelas prioritas DSCP EF/AF41 (rate 8, ceil 20) + best-effort fq_codel, netem 10 ms | `tests/qod/tc-setup.sh` |
| H2.2 Baseline **before**: iperf3 latar 10/18/25 Mbit × 5 run, probe QUIC paralel | `tests/qod/iperf-matrix.sh before` + `tests/latency/77-ue-quic-gen.py` |
| H2.3 Create app-session (QOS_E untuk game, QOS_M untuk video GBR 5 Mbps), ulang matriks **after** | `app-sessions.sh create`, `iperf-matrix.sh after` |
| H2.4 `DELETE`, ulang matriks **after-delete** | `iperf-matrix.sh after-delete` |
| H2.5 Export ClickHouse → CSV, evaluasi kriteria | `tests/qod/evaluate.py` |
| H2.6 Rollback `tc`, destroy Terraform | `tc-rollback.sh`, `terraform destroy` |

## Kriteria lulus (terukur)

| ID | Kriteria |
|---|---|
| K1 | p99 one-way QUIC **after** ≤ 50% p99 **before** (beban 18/25 Mbit) |
| K2 | loss probe/flow prioritas **after** < 1% |
| K3 | goodput flow GBR ≥ 95% dari 5 Mbps |
| K4 | efek hilang setelah DELETE (p99 kembali ≥ 80% baseline) |
| K5 | CV p99 antar-run < 20% |
| K0 | QER/QFI baru terlihat di N4 dan N3 (fungsional, wajib) |

Laporkan juga p50/p95.

## Artefak

pcap (SBI/N4/N3, Rx/Gx/S11), log PCF/SMF/UPF, JSON iperf3, `pktlat.log`, export CSV ClickHouse, snapshot dashboard Grafana, output `evaluate.py`. Simpan di bucket GCS lab (privat); **jangan** commit pcap/trace ke repo publik.

## Risiko & cadangan

| Risiko | Cadangan |
|---|---|
| PCF Open5GS menolak AppSessionContext (field/feature tidak didukung) | Sederhanakan ke medComponents minimal; cek log PCF; fallback PCC rule statis via WebUI |
| UPF tidak menandai DSCP per QFI | Tandai DSCP via iptables mangle berdasar SDF filter (sama dengan PDR) untuk demo |
| UPF/gNB ZMQ tidak membedakan prioritas | Diferensiasi hanya di bottleneck `tc` (by design) |
| srsRAN Project SA ZMQ tidak stabil | UERANSIM untuk control plane; data plane via 4G varian |
| Kuota/biaya GCP | Ukuran minimal, destroy harian |

## Eksekutor

Agent arsitek PoC (eksekusi skrip, Terraform, analisis) dengan persetujuan pemilik lab untuk `apply`; pemilik lab untuk akses akun dan keputusan go/no-go.
