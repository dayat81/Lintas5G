# Fase 0 Sesi B: EPC + srsRAN_4G ZMQ, Rx, adapter QoD tc HTB, tes (c) p99 (18 Nov 2026)

Profil: core n2-standard-4 + emu n2-standard-8 (12 vCPU), GCP asia-southeast2. obs/mpls off.
Stack: Open5GS 2.8.0 EPC (PCRF), srsRAN_4G ZMQ, Zeek paralel. Internet emulator lewat UE (proxy gost).
Durasi VM ~43 menit, biaya ~USD 0,5–0,6. Semua resource sudah di-destroy.

## Hasil

| Item | Hasil |
|---|---|
| EPC + srsRAN ZMQ, UE attach, keepalive | PASS |
| Internet emulator lewat UE (YouTube termuat via gost) | PASS (playback di layar belum terverifikasi) |
| Rx: AAR/AAA, Gx RAR, GTPv2 Create Bearer, E-RAB Setup QCI 2, STR lalu Delete Bearer | PASS (setelah QCI 2 ditambahkan ke rb.conf srsenb) |
| Adapter QoD tc HTB (`qod-tc.py`) | PASS: apply median 27,6 ms, remove median 14,6 ms; dari AAR sampai filter aktif ~42 ms |
| Tes (c) p99, ≥300 sampel per kondisi | PASS, lihat tabel |
| Zeek paralel | capture_loss ogstun 0%; S1-U (BPF) 0%; `lo` tanpa filter tidak valid karena trafik IQ ZMQ |
| CPU steal | 0,00% |

## Latency (ms) dan throughput bulk (Mbit/s)

Bottleneck dibuat dengan tc di SGi (DL 15 Mbit/s, UL 8 Mbit/s). Beban: iperf3 TCP DL 4 stream + UL 1 stream.
Probe: ping ICMP, dan HTTP TTFB objek 1 KB dari netns UE ke server di vm-emu (tanpa proxy).

| Kondisi | p99 ping | p99 TTFB | p50 ping | p50 TTFB | DL / UL |
|---|---|---|---|---|---|
| Idle | 40,8 | 62,5 | 27,2 | 51,0 | – |
| Beban | 466,3 (loss 7/330) | 1657,8 | 330,0 | 664,9 | 13,3 / 7,3 |
| Beban + QoD (trigger Rx) | 93,4 | 57,9 | 31,9 | 34,0 | 13,5 / 7,3 |
| Beban + YouTube emulator | 451,0 | 1195,0 | 313,0 | 583,5 | 12,6 / 7,1 |
| Beban + YouTube + QoD (trigger curl) | 130,8 | 55,3 | 31,7 | 35,2 | 12,7 / 7,6 |

Data lengkap ada di `2026-11-18-sesi-b-p99.csv`.

## Batasan

- QoD ditegakkan di SGi lewat tc, bukan di UPF atau RAN. Dedicated bearer QCI 2 saja tidak menurunkan latency.
- Probe latency memakai HTTP/TCP, karena curl HTTP/3 tidak tersedia di Ubuntu 22.04.
- TTFB di sini diukur langsung dari UE ke vm-emu (1 RTT ZMQ). Ini berbeda dengan benchmark proxy (emulator via gost ke internet, 2 RTT ZMQ).
- Bug DWA di `rx-af.py` sudah diperbaiki tapi belum dites ulang, jadi auto-remove lewat STR di run QoD belum terbukti.
- Pcap dan log mentah tidak dipublikasikan.
