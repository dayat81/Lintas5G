# Sesi D — YouTube + QoD + MGLT v2.1 (belum di-apply)

Skrip tes **lokal**. Lab Sesi D sudah di-destroy; **jangan apply atau push** sampai ada persetujuan eksplisit.

Tes ini memutar YouTube headless di emulator (sesi Google tersimpan) lewat dummy VPN **Booster examine v0.10.2**, dengan stempel waktu per paket QUIC (MGLT v2.1) + tap Zeek, pada 3 kondisi `idle | load | load+qod` × `REPS` (default 3 × 180 s).

## Cara menjalankan (setelah lab di-apply dan user menyetujui)

Di **vm-emu** (setelah restore sesi + `emu-prep.sh`):

```bash
# Salin APK v0.10.2 ke VM (bukan bagian repo publik). Sumber di box: phase2/booster-poc-examine-v0.10.2.apk
# sha256 fcc5e8a7bd36d424d0982ffd340b3a35077e4c20bd64eff609e86312d0cc622c
install -m 0644 booster-poc-examine-v0.10.2.apk /opt/lab5g/sesi-d/
bash /opt/lab5g/sesi-d/emu-prep.sh          # merakit server iperf + install APK jika ada
```

Urutan consent headless (API 36, sudah di `emu-youtube-qod.sh install` + `vpn-start`):

```bash
adb install -r -g /opt/lab5g/sesi-d/booster-poc-examine-v0.10.2.apk
adb shell appops set id.booster.poc.examine ACTIVATE_VPN allow
adb shell pm grant id.booster.poc.examine android.permission.POST_NOTIFICATIONS
# MainActivity only — am start-foreground-service is rejected with BIND_VPN_SERVICE.
adb shell am start -n id.booster.poc.examine/.MainActivity \
  --es apps com.google.android.youtube \
  --es pktlog on --es logpkt off --es probe on --es dns 8.8.8.8 --es deproxy off --es quic fwd \
  --es probehost 10.99.9.20 --es probeport 9001 --es markport 9000
# logcat -s BOOSTER_EXAMINE:I | grep VPN_CONSENT   -> ok | needed
# ip -4 -br a show tun0
```

Extra intent (default tetap tujuan v0.9.1): `probehost`, `probeport` (MGLT v2.1), `markport` (echo v1). Format kawat MGLT v2.1 tidak berubah. APK targetSdk 36, FGS type `specialUse`. v0.10.1 memaksa socket probe/marker ke IPv4 agar paket sampai `10.99.9.20:9001` lewat jalur UE dan tap IPv4.


Di **vm-core-ran** (setelah `core-prep.sh`: EPC, UE, tc HTB, adapter QoD, pkthash):

```bash
# E = alamat internal vm-emu (target iperf + SSH)
REPS=3 DUR=180 VIDEO_ID=aqz-KE-bpKQ VIDEO_QUALITY=hd720 TRANSPORT=auto \
  bash /opt/lab5g/sesi-d/run-youtube-qod.sh <emu_ip>
```

`TRANSPORT=auto|quic-only|tcp-only` (default `auto`): di netns `ue1`, rantai iptables `YTQOD-TRANSPORT` menolak proto 443 yang tidak dipilih (tcp untuk `quic-only`, udp untuk `tcp-only`) pada FORWARD+OUTPUT+INPUT, lalu dibersihkan saat EXIT. Analisis memakai `conn.log` (n6) untuk porsi QUIC vs TCP per fase.

Keluaran: `/var/log/lab5g/sesi-d/phases.tsv`, `/var/log/lab5g/sesi-d/ytqod/` (playback, pktlat, summary). Batch ClickHouse (di box, seperti Sesi D): `obs/pkt-prep.py` + `obs/pkt-load.sh` untuk pkthash, plus loader `observability/clickhouse/loader/zeek2ch.py` untuk `pkt_latency`. Query: `obs/yt-qod-queries.sql`. Analisis offline tanpa CH: `obs/yt-qod-analyze.py --dir <ytqod>`.

## Apa yang diukur

| Lapisan | Sumber | Metrik |
|---|---|---|
| Aplikasi | `dumpsys media_session` tiap 1 s (`yt-playback.py`) | state, posisi, startup, stall; **advanced_s resmi** = pos PLAYING terakhir − pertama (play-start memakai `&t=0`) |
| Per paket QUIC (app clock) | probe MGLT v2.1 udp/9001 (socket IPv4), hash md5(payload[0:64])[0:8] | one-way UL/DL + RTT proksi per tap |
| Segmen tap | pktlat2.zeek v2.1 (fan-in VLAN, 3 id) + pkthash 4 tap | `s5s8`=**UE** (`tun_srsue`, bukan S5/S8), `s1u`=N3, `sgi`=N6, **`sgi-queue`** = n6↔sgiq |
| Transport | Zeek `conn.log` (n6) + proto pkthash | porsi udp/443 vs tcp/443 per fase |

Beban = iperf3 TCP DL 4 stream + UL 1, sama seperti `run-quic.sh`. QoD = `POST /qod` `{ueIpv4, remote:any, port:443, gbrKbps:5000}`.

## Batasan adapter QoD (tidak diubah)

`qod-tc.py add()` **selalu** memasang filter **TCP + UDP + ICMP** untuk port yang diminta. Satu POST port 443 sudah mencakup QUIC udp/443 **dan** fallback tcp/443. Tidak ada parameter proto di API; varian "udp saja" membutuhkan ubahan adapter (tidak dilakukan). `remote:any` berlaku untuk semua tujuan, bukan hanya googlevideo.

Probe MGLT ke `10.99.9.20:9001` **tidak** masuk filter 443. Default `QOD_PROBE=1` menambah POST kedua (`port:9001`, `gbrKbps:500`) agar probe tidak tertahan di kelas bulk HTB saat beban. Cadangan GBR dijumlahkan (5500 kbit, masih < 80% R).


## Tap sgiq / segmen sgi-queue (penempatan)

DL di-shape di **egress ogstun** (HTB). UL di-shape di **ifb0** (ingress ogstun di-mirred ke ifb0). Capture AF_PACKET di ogstun (tap `n6`) melihat **DL setelah qdisc egress** dan **UL sebelum shaping ifb**. Karena itu delay antrean QoD tidak terlihat di segmen UE↔N6 (temuan run 18 Nov: p99 DL di tap hanya turun ~29 %).

Tap ke-4, label pkthash `sgiq`, mengambil sisi pelengkap:

- **DL pre-HTB:** filter tc `mirred` + `gact continue` pada HTB root ogstun prio 1 ke dummy `sgiq` (enqueue, sebelum qdisc; continue wajib agar filter QoD tetap cocok). `nft dup to <dev>` tidak valid di family ip (ditemukan saat rerun). **Bukan** ens4 egress: DL datang di *ingress* ens4, di-route ke ogstun, baru di-shape; ens4 egress adalah UL ke internet (pasca-NAT).
- **UL post-ifb0:** Zeek di `ifb0` (AF_PACKET TX setelah HTB ifb0).
- Dua unit (`lab5g-pkt-sgiq-dl`, `lab5g-pkt-sgiq-ul`) menulis log terpisah dengan `PKTHASH::tap=sgiq`.
- `clsact` di ogstun **tidak** dipakai: bentrok dengan ingress qdisc yang dipakai `qod-tc` untuk redirect UL.
- pktlat2 tidak di-fork (VLAN tetap 102/105/109); sgi-queue hanya di pkthash + SQL (`ms_sgi_queue`: DL = t_n6 − t_sgiq, UL = t_sgiq − t_n6).

## Estimasi biaya / waktu

Satu rerun `TRANSPORT=auto` (9 fase × 180 s, config Sesi D yang sama): sekitar **USD 1–2** dan **±1,5 jam** (apply + restore + prep + tes + analisis + destroy). Setiap mode TRANSPORT tambahan mengulang 9 fase (~+35 menit, +~USD 0,4–0,7). Watchdog UE tetap jalan. **Belum di-apply** — butuh persetujuan user.

## Risiko (baca sebelum apply)

Lihat `docs/results/2026-11-18-sesi-d-youtube-qod-plan.md` untuk API 36, MTU, overhead ~13 %, jam, ABR, dan keputusan yang perlu dari user.
