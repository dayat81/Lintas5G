# Lintas5G Fase 0: verdict (Sesi C, 18 Nov 2026)

Semua angka adalah **FAKTA** hasil ukur di lab GCP (asia-southeast2-a). Bagian bertanda **USULAN** atau **DUGAAN** adalah interpretasi.
Sesi C memakai core n2-standard-4 + emu n2-standard-8 (12 vCPU), lalu vm-obs e2-standard-2 dinyalakan setelah emu dimatikan.
Stack: Open5GS 2.8.0 EPC (PCRF), srsRAN_4G ZMQ, Zeek 9.0.1 paralel, adapter QoD `qod-tc.py` (tc HTB di SGi/ogstun).
Waktu VM: core+emu ~56 menit, vm-obs ~6 menit. Semua resource sudah di-destroy dan diaudit. Biaya ~USD 0,7–0,8.

## 1. Klarifikasi: TTFB dengan QoD (58–59 ms) di bawah "floor" gost 89 ms

Tidak bertentangan, karena endpoint dan jalurnya berbeda. Keduanya butuh 2 RTT lewat radio ZMQ (TCP connect + GET), tapi tujuan dan hop-nya beda.

| Pengukuran | Jalur | connect p50 | TTFB − connect p50 | TTFB |
|---|---|---|---|---|
| Floor proxy (Hari 2, diagnosa gost, DNS cache) | Netns UE → eNB → EPC → SGi → Cloud NAT → internet (example.com) | ~41 ms (RTT ZMQ + RTT internet) | ~48 ms | min ~89 ms; dari emulator lewat gost (hop antar-VM + proxy) median 100,7 ms (n=10) |
| Tes (c) idle (Sesi C) | Netns UE → eNB → EPC → SGi(ogstun) → vm-emu:9000 (IP internal, tanpa DNS/proxy/internet) | 28,8 ms | 24,4 ms | p50 52,6 / p99 74,8 ms (n=990) |
| Tes (c) beban+QoD (Sesi C) | sama | 16,8 ms | 18,6 ms | p50 36,1 / p99 59,0 ms (n=990) |

FAKTA: selisih dengan floor 89 ms datang dari RTT internet (~13 ms per leg) dan hop proxy/antar-VM yang tidak ada di tes (c).
Catatan koreksi: brief sebelumnya menyebut tes (c) "1 RTT ZMQ". Data curl menunjukkan 2 RTT (connect + request), sama seperti jalur proxy.

**DUGAAN** kenapa beban+QoD lebih cepat dari idle (RTT TCP ~17 vs ~27 ms): saat beban, UE terus punya grant UL sehingga paket kecil tidak menunggu siklus Scheduling Request srsenb. Saat idle, setiap paket UL menunggu SR/BSR. Ping p50 QoD (33,9 ms) tetap sedikit di atas idle (28,3 ms) karena ICMP berbagi kelas QoD dan antrean pfifo 1:10. Belum diverifikasi dengan log MAC srsenb.

## 2. Angka kriteria (Sesi C, 3 ulangan × 330 sampel/kondisi)

Bottleneck tc HTB DL 15 / UL 8 Mbit/s di ogstun. Beban: iperf3 TCP DL 4 stream + UL 1 stream. QoD dipicu Rx AAR (AAA 2001) lalu adapter, dan dilepas oleh STR.

| Ulangan | Kondisi | Ping p50 / p99 (ms) | Loss ping | TTFB p50 / p99 (ms) | Bulk DL / UL (Mbit/s) |
|---|---|---|---|---|---|
| r1 | idle | 27,8 / 40,8 | 0/330 | 51,6 / 72,8 | – |
| r1 | beban | 331,0 / 507,4 | 10/330 | 677,5 / 1688,5 | 13,04 / 7,68 |
| r1 | beban+QoD | 33,9 / 127,7 | 0/330 | 35,4 / 56,9 | 12,82 / 7,59 |
| r2 | idle | 28,8 / 41,4 | 0/330 | 71,0 / 76,0 | – |
| r2 | beban | 314,0 / 464,7 | 10/330 | 675,8 / 1851,3 | 13,57 / 7,55 |
| r2 | beban+QoD | 34,5 / 122,1 | 0/330 | 36,6 / 62,9 | 13,05 / 7,48 |
| r3 | idle | 28,1 / 40,6 | 0/330 | 51,4 / 71,6 | – |
| r3 | beban | 316,0 / 465,4 | 6/330 | 633,5 / 1768,1 | 13,21 / 7,49 |
| r3 | beban+QoD | 33,3 / 130,4 | 0/330 | 36,5 / 57,5 | 13,06 / 7,54 |

| Kriteria | Angka | Verdict |
|---|---|---|
| p99 flow prioritas turun ≥50% (beban → beban+QoD) | Ping 74,8 / 73,7 / 72,0%; TTFB 96,6 / 96,6 / 96,8% | PASS |
| p50 dengan QoD ≤2× p50 idle | Ping 1,22 / 1,20 / 1,19×; TTFB 0,69 / 0,51 / 0,71× | PASS |
| Loss flow QoD <1% | Ping 0/990; HTTP gagal 0/990; UDP 5 Mbit/s DL 0,000%, UL 0,000% | PASS |
| Goodput GBR ≥95% dari 5 Mbit/s (di bawah beban, kelas QoD + reservasi GBR) | UDP DL 5000,4 kbit/s (100,0%), UDP UL 4996,7 (99,9%), TCP DL 5005,6 (100,1%); TCP UL 3767,4 (75,3%) | PASS untuk UDP DL/UL dan TCP DL; FAIL untuk TCP UL |
| CV <20% antar 3 ulangan | Beban+QoD: CV p50/p99 ping 1,4/2,7%, TTFB 1,4/4,6%. Maksimum semua kondisi: 15,9% (p50 TTFB idle) | PASS |
| Throughput bulk tidak turun saat QoD | Rasio DL 0,98 / 0,96 / 0,99; UL 0,99 / 0,99 / 1,01 | PASS |

Pembanding goodput (FAKTA, menunjukkan reservasi GBR diperlukan):

| Kondisi flow 5 Mbit/s | UDP DL goodput / loss | UDP UL goodput / loss |
|---|---|---|
| Tanpa QoD | 4985,9 kbit/s / 0,63% | 4888,2 / 2,47% |
| QoD rate statis 30% (perilaku Sesi B: kelas 1:10 = 4,5 / 2,4 Mbit/s) | 4736,7 / 4,72% | 2355,8 / 52,25% |
| QoD + reservasi GBR (Sesi C: kelas 1:10 = 5,5 Mbit/s = 1,1 × GBR) | 5000,4 / 0,00% | 4996,7 / 0,00% |

Catatan: UDP tanpa QoD juga hampir lolos di DL, karena UDP tidak mundur saat kongesti dan merebut porsi dari TCP bulk. Kriteria goodput baru bermakna jika dibaca bersama loss (2,47% UL tanpa QoD).

**DUGAAN** untuk TCP UL 75%: iperf3 `-b 5M` TCP UL dibatasi oleh ACK DL dan cwnd di jalur ZMQ RTT ~30 ms + antrean UL bulk; retransmit 0. Belum diinvestigasi.

## 3. Tes ulang DELETE/STR

| Bukti | Hasil |
|---|---|
| STR → STA | 4/4 STR dijawab STA 2001 (latency 0,9–5,5 ms). Bug DWA sudah tidak muncul: DWR dijawab 2001 setiap ~29 s dan sesi Diameter bertahan >100 s |
| Delete Bearer | SGW-C mencatat Delete Bearer Request/Response untuk setiap STR (02:45:34, 02:56:43, 03:01:22, 03:02:26 UTC). MME mencatat `Bearer removed (EBI=6)`, artinya E-RAB release dan deaktivasi bearer selesai. Dekode S1AP E-RAB Release dari pcap belum dilakukan karena tshark tidak ada di box; pcap disimpan lokal |
| Filter tc hilang | `tc filter show` per ulangan: sebelum AAR 0 filter, sesudah AAA 6 filter (TCP+UDP+ICMP × DL/UL), sesudah STR 0. Sama di r1, r2, r3, dan tes STR |
| Latency remove adapter | median 17,1 ms (14,5–24,7, n=8). Apply median 53,2 ms (filter) + reservasi GBR median 36,8 ms. AAR → filter aktif ≈ 70–110 ms |
| Latency kembali ke level beban setelah STR | **N/A**. Di tes STR di bawah beban, link srsRAN ZMQ jatuh ke loop Radio-Link-Failure ~8 s setelah E-RAB release (RTT keepalive 88–280 s), jadi probe pasca-STR tidak valid |
| Latency kembali ke level beban setelah DELETE REST (tanpa bearer dedicated) | PASS. Ping p50/p99 30,8/102 → 302/441 ms (beban tanpa QoD: 320/488). TTFB p50/p99 88,8/204 → 631/1370 ms (beban: 658/1811). n=147–150 per fase |

## 4. Batasan arsitektur (eksplisit)

1. Penegakan QoD dilakukan di **SGi (ogstun) lewat tc HTB**, bukan di UPF atau RAN. Bottleneck juga dibuat dengan tc (DL 15 / UL 8 Mbit/s), bukan kapasitas radio.
2. **UPF Open5GS 2.8.0 tidak memolisi MBR dari QER** (Sesi A: iperf ~490 Mbit/s tetap, walau QER MBR 10 lalu 5 Mbit/s terpasang via PFCP).
3. **QFI 2 tidak aktif dengan UERANSIM**: gNB UERANSIM tidak menangani NGAP PDUSessionResourceModifyRequest (0 paket QFI 2 di N3).
4. **Dedicated bearer QCI 2 (EPC) sendiri tidak menurunkan latency**; perbaikan datang dari kelas tc. rb.conf srsenb perlu QCI 2 ditambah manual.
5. Probe memakai **HTTP/TCP dan ICMP, bukan HTTP/3**. Probe ke server internal vm-emu, bukan internet.
6. Radio adalah **srsRAN_4G ZMQ** (RTT ~30 ms, bukan RF). Link ZMQ tidak stabil setelah E-RAB release dedicated bearer di bawah beban (2 dari 4 STR memicu RLF). Diperlukan attach ulang.
7. Adapter memakai reservasi GBR versi Sesi C (rate kelas QoD = max(30% R, 1,1 × ΣGBR), maks 80% R). Perilaku Sesi B (statis 30%) tidak memenuhi GBR 5 Mbit/s di UL.
8. Observability batch setelah tes (bukan real time). Zeek paralel selama tes, capture_loss 0%.

## 5. Verdict per kriteria, seluruh Fase 0

| # | Sesi | Kriteria | Angka | Verdict |
|---|---|---|---|---|
| 1 | Hari 1 | EPC + srsRAN ZMQ attach, ping, iperf | ping 0% loss ~30 ms; UL 18,9 / DL 30,8 Mbit/s | PASS |
| 2 | Hari 1 | Internet emulator lewat UE | dibuktikan pcap ogstun | PASS |
| 3 | Hari 2 | TTFB HTTP via proxy ≤100 ms | gost C2 median 100,7 ms (n=10); floor ~89 ms (2× RTT ZMQ) | FAIL (marginal, +0,7 ms) |
| 4 | Sesi A | 5GC SA + PCF + UERANSIM bring-up | 11 NF, UE registered, ping 100/100 | PASS |
| 5 | Sesi A | Tes (a) N5 create/patch/delete | 201 / 200 / 204 | PASS |
| 6 | Sesi A | Tes (b) control-plane N7 → N4 QER → N2 | PFCP QER QFI 2 MBR 10000 → 5000 kbps; NGAP Modify QFI 2 | PASS |
| 7 | Sesi A | Tes (b) data-plane QFI 2 / MBR QER | 0 paket QFI 2; iperf tetap ~490 Mbit/s | FAIL (batasan UERANSIM + UPF 2.8.0) |
| 8 | Sesi B | Rx AAR → Gx RAR → Create Bearer → E-RAB Setup QCI 2 | AAA 2001, E-RAB Setup OK | PASS |
| 9 | Sesi B | Emulator lewat UE (YouTube) | googlevideo via gost ~121 s | PASS (playback di layar belum terverifikasi) |
| 10 | Sesi C | p99 turun ≥50% di 3 ulangan | ping 72–75%, TTFB ~97% | PASS |
| 11 | Sesi C | p50 QoD ≤2× idle | ping ≤1,22×, TTFB ≤0,71× | PASS |
| 12 | Sesi C | Loss flow QoD <1% | 0% (ping, HTTP, UDP) | PASS |
| 13 | Sesi C | Goodput GBR ≥95% dari 5 Mbit/s | UDP 99,9–100%, TCP DL 100%, TCP UL 75% | PASS (UDP dan TCP DL) / FAIL (TCP UL) |
| 14 | Sesi C | CV <20% di 3 ulangan | maks 15,9%; kondisi QoD ≤4,6% | PASS |
| 15 | Sesi C | STR → Delete Bearer + filter tc dilepas | 4/4; filter 6 → 0; remove ~17 ms | PASS |
| 16 | Sesi C | Latency kembali ke level beban setelah remove | via DELETE REST: ping p99 441 vs beban 488 ms | PASS (via DELETE); N/A via STR (RLF srsRAN) |
| 17 | Sesi C | Zeek paralel, capture_loss | lo (BPF S1-U + control-plane) 0%, ogstun 0% (41 interval masing-masing) | PASS |
| 18 | Semua | CPU steal | 0,00% (515 sampel mpstat Sesi C) | PASS |
| 19 | Sesi C | Batch ClickHouse/Grafana + dashboard | 10.100 sampel probe, 14.909 conn Zeek; dashboard PNG | PASS |
| 20 | Opsional | MPLS L3VPN | LDP tidak membentuk neighbor | FAIL (tidak memblokir) |

**USULAN keputusan merge PR #1:** merge. Kriteria inti Fase 0 (p99 turun ≥50%, goodput GBR ≥95% untuk flow GBR UDP, konsisten di 3 ulangan) terpenuhi dengan enforcement di SGi. Catat sebagai known issue: #3 TTFB proxy marginal, #7 QFI/QER data-plane, TCP UL goodput 75%, RLF srsRAN pasca-STR. Ketiganya masuk backlog Fase 1 (enforcement di UPF/RAN, srsRAN gNB 5G, investigasi TCP UL).

## Masalah dan perbaikan selama Sesi C

| Masalah | Dampak | Perbaikan |
|---|---|---|
| `rx-setup.sh` me-restart PCRF setelah attach → AAR dijawab 5065 (IP-CAN session not available) | c3 rep 1 percobaan pertama tidak valid (dibuang) | Attach ulang; `core-bringup.sh` sekarang menjalankan rx-setup sebelum attach |
| Link ZMQ RLF ("tx time is in the past"), RTT keepalive ratusan detik, setelah E-RAB release | Rep 2 percobaan pertama dan probe pasca-STR tidak valid (data disimpan terpisah, tidak dihitung) | Health check + attach ulang otomatis sebelum tiap ulangan; latency pasca-remove dibuktikan via DELETE REST |
| Kelas QoD statis 30% < GBR 5 Mbit/s (UL 2,4 Mbit/s) | UDP UL loss 52% | Reservasi GBR dinamis di `qod-tc.py` (`gbrKbps`, headroom 1,1) |
| Firewall lab hanya membuka UDP 4789; iperf3 UDP butuh TCP kontrol di port yang sama | iperf3 UDP tidak bisa dipakai | `udp-flow.py` (flow UDP ber-rate tetap di port 4789) |
| Filter adapter hanya TCP+ICMP | flow UDP tidak masuk kelas QoD | Tambah filter UDP (proto 17) |

## File

- Data: `2026-11-18-sesi-c-p99.csv` (per ulangan), `-cv.csv`, `-criteria.csv`, `-flow-gbr.csv`.
- Dashboard batch Grafana: `img/2026-11-18-sesi-c-grafana.png` (ClickHouse `poc_latency`, skema dan dashboard JSON di `infra/gcp/sesi-c/obs/`).
- Script: `infra/gcp/sesi-c/`. Pcap dan log mentah (berisi IMSI tes) tidak dipublikasikan.
