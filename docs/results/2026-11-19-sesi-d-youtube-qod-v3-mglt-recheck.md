# Sesi D v3 — diagnosis & recheck MGLT v2.1 (catatan tambahan untuk v2)

Tanggal: 19 Nov 2026 (WIB, Asia/Jakarta UTC+7). Lab Lintas5G sama dengan v2 (CPU only, tanpa VNC/tunnel publik). Run singkat: quic-only, 1 rep × (idle, load+qod) × 90 s. Tidak ada commit/push.

## 1. Penyebab coverage MGLT 0% pada v2
1. **pktlat2 tidak pernah jalan** (penyebab utama). `lab5g-pktlat2` berstatus `failed` sejak start di seluruh run v2 (terlihat di run.log, tidak diperhatikan). Zeek berhenti dengan `can't find mglt`: `mglt.zeek` dan `pktlat2.zeek` (di `observability/zeek/`) tidak ikut terraform/VM; run pertama memakainya karena disalin manual. Reproduksi offline dengan Zeek 9.0.1: `fatal error in run-live-yt.zeek, line 10: can't find mglt`. Karena itu `pktlat.log` tidak pernah ada. Hit "9001" di pkthash hanyalah kebetulan nomor port (pkthash memang hanya 443).
2. **App v0.10.1: socket probe terikat ke Network lama.** Saat Wi-Fi emulator flap (Network 100 → 102, ±12–25 s tanpa jaringan), socket MGLT/MGLT2 tetap ter-bind ke network yang mati → `ENETUNREACH` selamanya (v2 `err=429`; probe berhenti setelah ±25 s). Socket per-flow dibuat ulang sehingga playback pulih.
3. **Tap N3 (lo) tanpa filter**: `lo` membawa aliran ZMQ I/Q srsRAN (±211 GB / 12,5 juta paket per sesi lab); mirror Python membaca semuanya dan menjatuhkan frame → `miss:s1u` 20–45%.
4. Kecil: veth fan-in MTU 2000 → `Message too long` untuk frame GSO besar (1 kejadian pada run akhir).
5. Skew: `skew_s` dari runner (jam host emu, 218,6 ms) tidak sama dengan jam guest Android; selisih ≈ 119 ms (lihat §4).

## 2. Perbaikan (lokal, belum commit)
- `sesi-d/zeek/mglt.zeek`, `pktlat2.zeek`: salinan vendor (identik dengan observability; test memeriksa drift) → ikut `gui_files` terraform.
- `pktlat2-taps.sh`: cek script ada, gagal keras bila unit tidak aktif (+ jurnal), status mencetak counter pktlat2. `run-youtube-qod.sh`: abort (exit 3) bila pktlat2 gagal start, menyimpan `pktlat-journal.txt`, env `CONDS` untuk subset kondisi.
- **APK v0.10.2** (versionCode 13, kunci debug sama, cert SHA-256 `8e8049e0…ff826ac6c`, sha256 `fcc5e8a7bd36d424d0982ffd340b3a35077e4c20bd64eff609e86312d0cc622c`): `NetworkCallback` menjaga `underlying`; `Mglt`/`Mglt2` membuka ulang socket protected+bound saat send gagal (rate-limit 300 ms) dan mencoba ulang; log `rebinds=`. Sumber v0.10.1 diarsipkan di `phase2/app-v0.10.1-src`.
- `zeek/pktlat-mirror.py`: filter BPF (udp/2152, non-fragmen) di socket n3.
- Tes (26, semua OK; replay Zeek 9.0.1 di docker bila ada): fixture `probe-fanin.pcap` + `gen-probe-pcap.py` (5 probe + 15 frame tap → 5 baris `ok` pada s1u/s5s8/sgi), uji BPF dengan interpreter mini, drift script, preflight.
- Belum diverifikasi di lab: MTU veth 65000 (hanya usulan, tidak diubah).

## 3. Recheck lab (run `ytqod3-recheck3`, v0.10.2 + BPF)
Playback: idle startup 7.0 s, 0 stall; load+qod startup 6.0 s, 0 stall. (Dua run sebelumnya pada sesi ini — v0.10.1 dan v0.10.2 tanpa BPF — terkena flap Wi-Fi; v0.10.2 pulih lewat `rebind` ×5, `probes` 743.) Run akhir: probe terkirim 710, `err=0`, Zeek `probes` sama, `crc_bad=0`.

Coverage per tap (record MGLT yang punya timestamp tap):

| Fase | Arah | n | UE tap (ue) | N3 | N6 (sgi) | status ok |
|---|---|---|---|---|---|---|
| idle | UL | 510 | 100% | 100% | 100% | 100% |
| idle | DL | 1377 | 100% | 99,9% | 100% | 99,9% |
| load+qod | UL | 341 | 100% | 88,9% | 100% | 88,9% |
| load+qod | DL | 632 | 100% | 87,8% | 100% | 87,8% |

Sebelum BPF (run 2): N3 79–83% idle, 53–61% load+qod → BPF menaikkan N3 ke 100% idle; di bawah beban masih ~88% (sisa kehilangan di mirror Python / MTU veth; belum didiagnosis, target P6 ≥ 95% tercapai untuk idle, belum untuk load+qod di N3). UE dan N6 100% di semua fase.

## 4. Koreksi skew (offline) dan latensi satu arah
Offset jam guest–core dikalibrasi dari fase idle di tap UE dengan asumsi jalur app↔UE-tap simetris: O′ = (median UL_raw − median DL_raw)/2 = **338,2 ms**, versus `skew_s` runner 218,6 ms (selisih ≈ 119,6 ms ⇒ jam host emu ≠ jam guest Android; usulan: ukur skew lewat `adb shell date +%s.%N` di guest). Nilai di bawah memakai O′.

| Fase | Arah | Tap | p50 (ms) | p95 | p99 |
|---|---|---|---|---|---|
| idle | UL | ue / n3 / n6 | 5,1 / 26,0 / 26,4 | 15,0 / 45,2 / 45,6 | 75,3 / 103,5 / 103,6 |
| idle | DL | n6 / n3 / ue | 15,5 / 14,8 / 5,1* | 53,3 / 52,3 / 43,7 | 69,1 / 67,7 / 62,4 |
| load+qod | UL | ue / n3 / n6 | 16,0 / 93,1 / 89,2 | 77,2 / 162,7 / 153,1 | 103,5 / 186,1 / 184,3 |
| load+qod | DL | n6 / n3 / ue | 21,3 / 18,5 / −2,5* | 119,8 / 111,5 / 109,3 | 169,5 / 167,4 / 161,0 |

\* DL = dari tap ke app (nilai terkecil di tap UE; di bawah beban p50 negatif ⇒ kalibrasi simetris tak sempurna saat asimetris). Satu-arah absolut hanya indikatif; **latensi segmen bebas skew**:

| Segmen | idle p50 / p99 | load+qod p50 / p99 |
|---|---|---|
| UL ue→n3 (radio) | 20,8 / 40,4 | 57,8 / 149,4 |
| UL n3→n6 | 0,2 / 2,1 | −0,7 / 4,6 |
| UL ue→n6 | 20,9 / 41,1 | 62,9 / 138,1 |
| DL n6→n3 | 0,3 / 11,7 | 2,9 / 27,2 |
| DL n3→ue (radio) | 9,6 / 15,0 | 14,2 / 62,6 |
| DL n6→ue | 10,0 / 15,6 | 16,9 / 63,6 |
| sgi-queue DL (pkthash) | 2,7 / 21,2 | 16,8 / 63,9 |
| sgi-queue UL (pkthash) | 0,2 / 3,6 | 0,4 / 8,5 |

Segmen ue→n3 UL membengkak di bawah beban (radio/ZMQ UL 8 Mbit/s), sedangkan N3→N6 (core) hampir nol; antrean HTB DL dengan QoD p99 ≈ 64 ms. Sampel kecil (1 rep × 90 s); P5 (p99 DL n6 vs load) tidak dinilai karena fase `load` tanpa QoD tidak dijalankan.

## 5. Biaya, destroy
Apply 06:22:53 WIB, destroy selesai ≈07:10 WIB (151 resource, state 0): ≈0,78 jam × ~USD 0,82/jam ≈ **USD 0,65** (estimasi; Billing API nonaktif). Kumulatif hari ini ≈ USD 7,2 (< 12). Audit: tidak ada instance/disk/IP/firewall/router/NAT/bucket `lab5g-runs` tersisa; build-vm-01 TERMINATED; netprobe/magnon tidak disentuh.
Log: box `/workspace/sesi-d-yt3/`, bucket privat state `logs/sesi-d-yt3/20261119/`.
