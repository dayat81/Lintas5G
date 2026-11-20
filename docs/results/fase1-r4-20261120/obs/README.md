# Item 6 — Grafana di box (ch-test ClickHouse + dashboard booster-qod)

- Container (lokal, bind 127.0.0.1 saja): `ch-test` (clickhouse/clickhouse-server:24.8, volume `ch-test-data`, user `f1`, password di `secrets/ch.pw` 640 root-group, tidak dicetak) dan `f1-grafana` (grafana/grafana:11.3.0, netns ch-test, port 127.0.0.1:3000, anonymous Viewer). Plugin `grafana-clickhouse-datasource` 4.23.5 diunduh di host (DNS container tidak jalan) → `grafana/plugins/` (tidak di-commit).
- Dashboard: `/workspace/booster-app/observability/grafana/booster-qod.json` **diterapkan tanpa perubahan** (sha256 sumber b7e5b93c6cc8d63d… = salinan provisioning b7e5b93c6cc8d63d…), datasource uid `poc-latency-ch` lewat provisioning (`grafana/provisioning/`).
- Skema: `booster-app/observability/clickhouse/01-booster-schema.sql` + `02-booster-views.sql` (+ stub `poc_latency.pkt_tap` kosong untuk view union).
- Data (`f1_ingest.py` → `in/*.jsonl` → INSERT JSONEachRow): 90 event adapter 0.1.3 (`qod-adapter-013/res/events/`, deviceKey hash), 9 run_phase, 11.250 sampel probe UE1, 312 window per detik (UE1/UE2), 1.218 baris N3 QFI/detik dari pcap paralel. run_id: `f1-n5-ab-r{1,2,3}`, `f1-n5-par-r{1,2,3}`, `f1-n5-items2-3` (callback+trace), `f1-n5-pilot`. Tanpa IMSI/IP UE/token (ue_hash = sha256(ip)[:12]).
- Screenshot headless (puppeteer-core + google-chrome, `shot/shot.js`): `screenshots/grafana-f1-n5-ab-r1.png`, `screenshots/grafana-f1-n5-par-r1.png`. Isi teredaksi secara desain (sessionId, IP AS lab <AS_IP>; tidak ada IP UE/IMSI).
- Cek silang angka: `ch-views.txt`. `v_before_after_send` (atribusi waktu kirim, 5 s awal boost dilewati) memberi p99 boost 33,7–35,7 ms = angka harness item 5; `v_before_after` (atribusi waktu terima) 1,5–2,0 s karena paket yang sudah antre di QFI default sebelum AVAILABLE ikut terhitung — semantik view, bukan selisih data.

Pengungkapan:
- Baris `mglt_window`/`mglt_sample` berasal dari probe UDP lab (`policy_state=lab-udpprobe`, app_pkg `lab.udpprobe.ue1/ue2`), bukan MGLT aplikasi; `source='app-echo'` dipakai karena view dashboard memfilter nilai itu.
- Panel "Sampel (load / boost+load)" menampilkan *No data* (query mengembalikan string; stat panel butuh angka) dan panel Zeek BATCH kosong (tidak ada data Zeek di lab n5) — perilaku dashboard apa adanya, tidak diubah.
- G8 butuh juga screenshot aplikasi booster untuk run yang sama → bergantung pada E2E booster.5.1 (lihat PROGRESS).
