# Hari 1 — Open5GS EPC + srsRAN ZMQ

Skrip di folder ini dijalankan sebagai root **di VM**, setelah `terraform apply`.
Checklist dari laptop: [`../scripts/test-run-day1.sh`](../scripts/test-run-day1.sh).

## Stack

- Open5GS **2.8.0** EPC (paket PPA) di `vm-core-ran`. MongoDB hanya di `127.0.0.1`.
- srsRAN_4G **release_23_11**, di-build dari source dengan ZMQ (`-DENABLE_ZEROMQ=ON`). Paket PPA tidak membawa plugin ZMQ.
- eNB dan UE di VM yang sama, terhubung ZMQ. UE memakai netns `ue1` dan `tun_srsue`.
- PLMN **001/01**. TAC eNB dan MME **0x0001**.
- Subscriber diisi lewat `mongosh` (paket PPA tidak memuat `open5gs-dbctl`). `core-config.sh` membuat IMSI, KEY, dan OPC acak saat berjalan dan menyimpannya hanya di `/root/lab5g-sub.env` (mode 0600) pada VM. Nilai itu tidak masuk repo.
- Proxy emulator berada di netns UE, jadi trafik keluar lewat `tun_srsue` (eNB → SGW-U → UPF → SGi).

## Urutan di vm-core-ran

```bash
sudo ./core-install.sh
sudo ./core-build-srsran.sh
sudo ./core-config.sh
sudo ./core-run.sh
sudo ./core-ping.sh          # default route netns UE dipasang manual di sini
sudo ./core-iperf.sh
sudo ./core-iperf-dl.sh
sudo ./core-proxy.sh            # default, sudah teruji 18 Nov
```

`core-ping.sh` menambahkan default route netns UE secara manual:

```bash
ip netns exec ue1 ip route replace default via 10.45.0.1 dev tun_srsue
```

`core-config.sh` dan `core-run.sh` tidak memasang route itu.

## Urutan di vm-emu

```bash
sudo ./emu-start.sh
sudo ./emu-baseline.sh
sudo ./emu-proxy-test.sh     # P=host:port ./emu-proxy-test.sh
```

`emu-proxy-test.sh` mengarahkan `http_proxy` emulator ke `P` (default `10.10.0.3:18080`). Set `P` jika IP `vm-core-ran` berbeda. VNC emulator bind ke loopback; dari laptop pakai `gcloud compute ssh -L`, bukan `start-iap-tunnel`.

Benchmark 10 sampel dari `vm-emu` (langsung, atau lewat proxy):

```bash
./emu-bench.sh A              > raw.csv          # langsung, tanpa proxy
./emu-bench.sh B 10.10.0.3:18080 >> raw.csv    # ganti host:port proxy
python3 stats.py raw.csv
```

`stats.py` mencetak median dan p90 (ms) untuk connect, TTFB, dan total.

## Proxy

| Skrip | Status |
|---|---|
| `core-proxy.sh` | **Default, sudah teruji 18 Nov.** gost v3, config YAML, resolver ber-cache (8.8.8.8, TTL 300s, IPv4), veth + DNAT, `rp_filter=2`. `HOST_IP` diambil dari `ens4`. Menunggu port listen. `MSS_CLAMP` opsional. |
| `core-proxy-tinyproxy.sh` | Fallback Hari 1 (tinyproxy di netns UE + socat). `HOST_IP` otomatis, dan skrip ini menghentikan unit gost. |
