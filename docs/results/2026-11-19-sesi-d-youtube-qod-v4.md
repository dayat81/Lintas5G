# Sesi D v4 — matriks transport penuh dengan APK v0.10.2 + filter BPF N3

Tanggal: 19 Nov 2026 (WIB, Asia/Jakarta UTC+7). Lab Lintas5G sama dengan v2/v3 (CPU only, tanpa VNC/tunnel publik). APK `magnon-poc-examine` v0.10.2 (sha256 `fcc5e8a7…cc622c`). 3 mode × 3 rep × idle/load/load+qod × 180 s. Tidak ada commit/push.

## 1. Linimasa (WIB)
| Waktu | Kejadian |
|---|---|
| 07:40:45 | terraform apply (152 resource) |
| 08:00:55 | matriks mulai (auto) — pktlat2 sehat sepanjang run (aktif, crc_bad 0, mirror `too long` 0) |
| 09:40:34 | ALL DONE (3 mode rc=0) |
| 09:45 | `terraform plan -destroy` (152 resource, hanya lab) lalu destroy |

Perbaikan v4 yang divalidasi: (a) skew dari jam **guest** Android lewat stream + filter delay-minimum (`skew-guest.py`), host-bracket lama tetap dicatat sebagai pembanding; (b) MTU veth pktlat 65000 → 0 error `Message too long` (v3: ada); (c) pktlat2 + probe + BPF N3 dari v3. Satu flap Wi-Fi emulator terjadi selama run dan dipulihkan otomatis oleh rebind v0.10.2.

## 2. Skew
| Mode | skew awal (s) | skew akhir (s) | drift (ms/menit) | host-bracket lama (s) |
|---|---|---|---|---|
| auto | 0.7811 | 0.8819 | 3.17 | 0.6448 → 0.7437 |
| quic-only | 0.8863 | 0.9871 | 3.17 | 0.75 → 0.8467 |
| tcp-only | 0.9913 | 1.0920 | 3.16 | – → 0.953 |

Jam guest Android **tertinggal dan melaju menyimpang** (~3 ms/menit ≈ 50 ppm) terhadap core: offset 0,78 s → 1,09 s dalam ±2 jam. Runner menulis `skew.cfg` hanya di awal dan akhir tiap mode, sehingga analisis ini menginterpolasi linear antara pengukuran awal–akhir (koreksi offline pada tiap baris). Host-bracket lama bias ≈ 0,14 s rendah (dikonfirmasi: 0,645 vs 0,781). Sisa asimetri tap UE pada idle (UL−DL)/2 = auto 16,4 ms, quic-only 29,9 ms: satu-arah absolut tetap **indikatif** (jalur UL/DL emulator↔UE-tap tidak simetris); gunakan latensi segmen (bebas skew).

## 3. Playback (3 rep per sel: startup s / stall / advanced s resmi)
| Mode | Kondisi | rep 1 | rep 2 | rep 3 |
|---|---|---|---|---|
| auto | idle | 8.0 / 0 (0.0s) / 172 | 6.0 / 0 (0.0s) / 174 | 6.0 / 1 (1.0s) / 174 |
| auto | load | 7.0 / 1 (7.0s) / 173 | 7.0 / 0 (0.0s) / 173 | 7.0 / 0 (0.0s) / 173 |
| auto | load+qod | 6.2 / 0 (0.0s) / 174 | 6.0 / 0 (0.0s) / 177 | 6.0 / 0 (0.0s) / 174 |
| quic-only | idle | 7.0 / 1 (7.7s) / 176 | 6.0 / 0 (0.0s) / 177 | 6.0 / 0 (0.0s) / 174 |
| quic-only | load | 7.0 / 0 (0.0s) / 173 | 7.0 / 0 (0.0s) / 173 | 7.0 / 0 (0.0s) / 173 |
| quic-only | load+qod | 6.0 / 0 (0.0s) / 174 | 6.0 / 0 (0.0s) / 177 | 6.0 / 0 (0.0s) / 174 |
| tcp-only | idle | 35.4 / 1 (2.3s) / 145 | 6.0 / 0 (0.0s) / 176 | 6.0 / 0 (0.0s) / 174 |
| tcp-only | load | 7.0 / 0 (0.0s) / 173 | 7.0 / 0 (0.0s) / 173 | 37.0 / 0 (0.0s) / 143 |
| tcp-only | load+qod | 6.0 / 0 (0.0s) / 174 | 6.0 / 0 (0.0s) / 174 | 6.0 / 0 (0.0s) / 174 |

Stall/startup panjang (35–37 s; advance 143–145 s) terjadi acak di tcp-only (idle rep1, load rep3) dan sekali stall 7,7 s di quic-only idle rep1 — tidak terkait kondisi (idle juga kena), bukan efek QoD.

## 4. Transport (porsi byte QUIC pada udp/443+tcp/443, conn.log N6; rep 1/2/3)
| Mode | idle | load | load+qod |
|---|---|---|---|
| auto | 91/87/81 % | 74/81/61 % | 90/87/81 % |
| quic-only | 99/100/100 % | 99/100/100 % | 100/100/100 % |
| tcp-only | 0/0/0 % | 0/0/0 % | 0/0/0 % |

auto ≈ QUIC mendominasi byte (61–91%, turun saat load (penyebab tidak diselidiki)); quic-only 99–100%; tcp-only 0%. Filter transport bekerja.

## 5. Coverage MGLT per tap (record dengan timestamp di tap; target ≥ 95%)
QUIC per paket (pktlat2 `tcp_on=F`): mode tcp-only tidak punya paket QUIC sehingga coverage **n/a** (346–372 baris UL per fase berasal dari UDP/443 yang ditolak filter dan tidak pernah keluar; semua `miss`).

| Mode | Kondisi | Arah | n | UE | N3 | N6 |
|---|---|---|---|---|---|---|
| auto | idle | UL | 1377 | 100.0% | 99.6% | 100.0% |
| auto | idle | DL | 3687 | 100.0% | 99.9% | 100.0% |
| auto | load | UL | 1218 | 100.0% | 86.5% | 100.0% |
| auto | load | DL | 2175 | 100.0% | 91.5% | 100.0% |
| auto | load+qod | UL | 1588 | 99.9% | 86.3% | 100.0% |
| auto | load+qod | DL | 3846 | 99.9% | 92.9% | 99.9% |
| quic-only | idle | UL | 1234 | 100.0% | 99.9% | 100.0% |
| quic-only | idle | DL | 2576 | 100.0% | 99.9% | 100.0% |
| quic-only | load | UL | 1172 | 100.0% | 90.8% | 99.9% |
| quic-only | load | DL | 1722 | 100.0% | 95.5% | 99.8% |
| quic-only | load+qod | UL | 1333 | 99.8% | 89.6% | 99.5% |
| quic-only | load+qod | DL | 3216 | 100.0% | 94.3% | 100.0% |

UE dan N6 ≥ 99,5% di semua fase (v2: 0%). **N3 ≥ 99,6% saat idle tetapi 86–95% saat load/load+qod** (UL 86–91%, DL 91–96%): BPF menghilangkan banjir ZMQ (v3: 79–83% idle), kekurangan di bawah beban belum didiagnosis (dugaan: kehilangan di pembaca Python mirror/antrean saat paket GTP-U banyak; perlu pcap `lo` pada beban untuk memastikan).

## 6. Latensi segmen (ms, p50 / p99; bebas skew; gabungan 3 rep)
Radio = UE↔N3 (srsRAN ZMQ), core = N3↔N6, sgi-queue = antrean HTB (pkthash n6↔sgiq, median p50/p99 per-rep).

| Mode | Kondisi | UL radio ue→n3 | UL core n3→n6 | DL core n6→n3 | DL radio n3→ue | sgi-queue DL | sgi-queue UL |
|---|---|---|---|---|---|---|---|
| auto | idle | 19.9 / 41.1 | 0.2 / 2.8 | 0.3 / 11.3 | 9.3 / 15.7 | 10.0 / 54.8 | 0.2 / 2.3 |
| auto | load | 49.3 / 152.4 | -1.2 / 4.2 | 2.8 / 29.4 | 9.9 / 34.0 | 126.4 / 285.1 | 165.3 / 321.3 |
| auto | load+qod | 38.6 / 144.9 | -0.9 / 13.1 | 1.9 / 26.9 | 10.0 / 25.1 | 18.3 / 152.5 | 0.2 / 4.2 |
| quic-only | idle | 20.0 / 42.4 | 0.2 / 2.3 | 0.2 / 9.9 | 9.2 / 18.3 | 8.4 / 35.1 | 0.2 / 4.3 |
| quic-only | load | 49.5 / 170.6 | -0.8 / 5.9 | 2.1 / 18.5 | 10.2 / 24.8 | 177.3 / 286.5 | 84.0 / 305.1 |
| quic-only | load+qod | 47.7 / 171.5 | -0.7 / 4.9 | 1.7 / 19.6 | 11.2 / 33.8 | 21.7 / 119.7 | 0.3 / 6.6 |

tcp-only (hanya pkthash sgi-queue; DL p50/p99 / UL p50/p99): idle: 0.4/8.4 , 0.2/3.5; load: 174.7/332.4 , 110.4/330.2; load+qod: 2.9/31.0 , 0.2/6.0.

Temuan: antrean HTB DL saat beban p99 ≈ 285–333 ms (UL 305–330 ms); QoD menurunkan ke 31 ms (tcp-only), 120 ms (quic-only), 153 ms (auto) dan UL ke 4–6 ms. Radio UL naik dari ~20 ms (idle) ke ~50 ms saat load; core (N3→N6) ≈ 0.

## 7. Satu-arah terkoreksi skew (p50 / p99 ms; indikatif)
| Mode | Kondisi | UL ue | UL n3 | UL n6 | DL n6 | DL n3 | DL ue |
|---|---|---|---|---|---|---|---|
| auto | idle | 34.0 / 101.1 | 54.9 / 127.1 | 54.9 / 127.0 | 10.6 / 140.9 | 6.0 / 140.6 | 1.2 / 130.9 |
| auto | load | 47.8 / 111.8 | 95.1 / 231.3 | 95.8 / 243.7 | -16.9 / 129.0 | -20.3 / 128.0 | -36.0 / 108.1 |
| auto | load+qod | 56.6 / 143.0 | 104.2 / 224.5 | 103.6 / 223.7 | -12.6 / 513.3 | -16.3 / 504.3 | -25.2 / 500.5 |
| quic-only | idle | 37.1 / 119.9 | 64.2 / 140.7 | 63.6 / 141.3 | -11.7 / 197.4 | -12.1 / 197.4 | -22.7 / 187.8 |
| quic-only | load | 47.6 / 105.5 | 106.7 / 210.8 | 104.8 / 204.0 | -29.3 / 164.3 | -31.5 / 163.9 | -43.1 / 156.7 |
| quic-only | load+qod | 59.7 / 165.5 | 118.5 / 300.1 | 113.4 / 276.6 | -30.0 / 149.3 | -32.1 / 144.2 | -47.2 / 131.9 |

DL = tap→app. Nilai p50 negatif saat load menandakan sisa galat skew/asimetri (drift 3 ms/menit tidak tertangkap penuh); jangan dipakai sebagai latensi absolut.

## 8. Verdict kriteria (USULAN)
P5 (sesuai definisi: p99 DL satu-arah di N6, load+qod ≤ 50% load) **tidak lagi bisa mengukur QoD**: tap N6 DL berada *setelah* HTB, jadi antrean tidak terlihat; metrik yang benar = sgi-queue (ditampilkan sebagai P5′, ambang sama 50%).

| Kriteria | auto | quic-only | tcp-only |
|---|---|---|---|
| P1 transport sesuai mode (byte) | PASS | PASS | PASS |
| P2 stall load+qod ≤ idle | PASS | PASS | PASS |
| P3 startup load+qod ≤ idle+2 s | PASS | PASS | PASS |
| P4 advance ≥ 80% (≥144 s) | PASS | PASS | marginal: 1 rep 143 s (79%), lainnya ≥145 |
| P5 p99 DL N6 (one-way) | FAIL (513.3 vs 129.0) | FAIL (149.3 vs 164.3) | n/a |
| P5′ p99 DL sgi-queue ≤ 50% load | FAIL (152.5 vs 285.1; 53%) | PASS (119.7 vs 286.5; 42%) | PASS (31.0 vs 332.4; 9%) |
| P6 coverage ≥ 95% semua tap | FAIL (N3 86–99%; UE/N6 PASS) | FAIL (N3 90–99%; UE/N6 PASS) | n/a (tanpa paket QUIC) |

Verdict (USULAN): playback aman di semua mode; QoD efektif menurunkan antrean HTB (P5′ PASS untuk quic-only/tcp-only; auto marginal ≈ 53%); coverage MGLT UE/N6 terpenuhi, N3 belum di bawah beban. P5 klasik FAIL karena artefak penempatan tap dan galat skew, bukan karena QoD gagal.

## 9. Biaya, destroy, deviasi
Biaya: apply 07:40:45 → destroy selesai ≈09:51 WIB (≈2,2 jam × ≈USD 0,82/jam) ≈ USD 1,8 (estimasi; kumulatif hari ini ≈ USD 9,6). Destroy: 152 resource dihancurkan, state kosong, tanpa proses/lock terraform; sisa hanya build-vm-01 (TERMINATED), alamat/firewall netprobe & magnon, jaringan `default`, bucket state privat. Log redaksi: box `/workspace/sesi-d-yt4/`, bucket privat state `logs/sesi-d-yt4/20261119/`. Deviasi: IP emu 10.10.0.3 (core 10.10.0.2, kebalikan dari run sebelumnya) sehingga kunci SSH core→emu diset ulang; analisis offline dengan `analysis/an4.py` (ClickHouse tidak dimuat); pktlat2 per paket hanya QUIC sehingga tcp-only tak punya coverage MGLT; 
