# Item 5 — Multi-UE A/B via CAMARA API (n5 lab, 1 sel rfsim 106 PRB, 2 UE)

Beban per UE (identik untuk UE1 dan UE2, simultan): BE bulk DL UDP 150 Mbit/s (port AS 5211/5221, default QFI) + flow DL UDP 15 Mbit/s di port sesi (18081/18082) + probe RTT UDP 50 pps ke AS 18080. Kapasitas DL sel terukur ±110–150 Mbit/s → sel padat (probe tanpa QoD p99 ±5,5 s, loss ±20%).
Fase per ulangan: BASE (tanpa sesi), lalu QOD (UE1: `POST /sessions` QOS_L ports 18080,18081 lewat client booster-client; UE2: tanpa sesi). Window metrik: t0+4 s (+1,5 s setelah create) s/d t_end−2 s. Durasi 25 s. 3 ulangan penuh. PAR: UE1 QOS_L + UE2 QOS_E paralel (client berbeda), 3 ulangan.
Loss flow iperf3 negatif (paket terlambat dari interval sebelum window) di-clamp ke 0.

## A/B (fase QOD, sel & waktu sama)

| rep | UE1 QoD probe loss % | UE1 QoD flow loss % | UE1 probe p99 ms | UE2 (tanpa QoD) probe p99 ms | Δp99 UE1 vs UE2 | UE1 goodput flow sesi Mbit/s | target (QOS_L GBR) | % target | % offered | BASE p99 UE1 / UE2 ms |
|---|---|---|---|---|---|---|---|---|---|---|
| 1 | 0.000 | 0.040 | 35.5 | 5516.1 | −99.4% | 14.99 | 10 | 150% | 99.9% | 5792 / 5796 |
| 2 | 0.114 | 0.051 | 33.7 | 5452.1 | −99.4% | 14.99 | 10 | 150% | 99.9% | 5488 / 5484 |
| 3 | 0.000 | 0.022 | 35.7 | 5879.6 | −99.4% | 15.00 | 10 | 150% | 100.0% | 5997 / 6015 |

## Sesi paralel (UE1 QOS_L + UE2 QOS_E)

| rep | UE | sessionId | callback di sink (path) | probe loss % | flow loss % | probe p99 ms | goodput Mbit/s | target | % target | QFI sesi di N3 (paket) | paket UE ini di QFI sesi UE lain |
|---|---|---|---|---|---|---|---|---|---|---|---|
| 1 | ue1 QOS_L | `4509c63e-f2c4-41d4-a49b-2134cb3ac33a` | AVAILABLE → UNAVAILABLE/DELETE_REQUESTED (/par-ue1) | 0.000 | 0.026 | 35.3 | 15.00 | 10 | 150% | {'8': 37146} | 0 |
| 1 | ue2 QOS_E | `8d0f131e-691b-4c6c-b3e9-6abfcbf5a492` | AVAILABLE → UNAVAILABLE/DELETE_REQUESTED (/par-ue2) | 0.000 | 0.000 | 36.3 | 15.00 | 10 | 150% | {'3': 37176} | 0 |
| 2 | ue1 QOS_L | `37603215-9acb-4ef3-bc54-92bf615dacec` | AVAILABLE → UNAVAILABLE/DELETE_REQUESTED (/par-ue1) | 0.000 | 0.051 | 35.5 | 14.99 | 10 | 150% | {'9': 37713} | 0 |
| 2 | ue2 QOS_E | `44d6dde1-3f30-43cb-ad35-8bb60bb9aaaf` | AVAILABLE → UNAVAILABLE/DELETE_REQUESTED (/par-ue2) | 0.000 | 0.000 | 51.5 | 15.12 | 10 | 151% | {'4': 37035} | 0 |
| 3 | ue1 QOS_L | `6913559e-210a-4ead-9a5d-d236a0de159d` | AVAILABLE → UNAVAILABLE/DELETE_REQUESTED (/par-ue1) | 0.000 | 0.000 | 35.2 | 15.00 | 10 | 150% | {'10': 37559} | 0 |
| 3 | ue2 QOS_E | `97674bb7-8137-4e0d-a307-528ccd0df05c` | AVAILABLE → UNAVAILABLE/DELETE_REQUESTED (/par-ue2) | 0.000 | 0.000 | 35.0 | 15.10 | 10 | 151% | {'5': 37434} | 0 |

## Penilaian G6 (FROZEN v1.1)

- Loss sesi QoD (probe + flow sesi, 12 nilai: 3 A/B + 6 sesi paralel): median 0.000% (≤1%), maks 0.114% (≤5%) → **PASS**
- p99 UE QoD vs UE tanpa QoD (sel & waktu sama): turun 99.4–99.4% (≥50%) → **PASS**
- Goodput flow sesi ≥95% target profil (GBR → targetMinDownstreamRate; non-GBR → min(maxDownstreamRate, offered)): 150–151% dari target profil; terhadap offered load 15 Mbit/s: 99,9–100,8% → **PASS** (juga lulus bila target dibaca sebagai offered load)
- Isolasi QFI (tiap UE satu QFI sesi, 0 paket di QFI UE lain): **PASS**; callback per sessionId di path sink milik UE tsb, tanpa tertukar: **PASS**
- 3 ulangan penuh A/B + 3 ulangan paralel: ya.

## Pengungkapan
- Diferensiasi antar-UE bergantung pada **modifikasi RAN**: gNB OAI v3.0.0 + patch `slice-qosrel4` (policy DL slice QoD, `slice.conf`: enabled=1, qod_5qi=2,3,4,7,69,80, qod_max_pct=70, be_max_pct=100, pbr_pct=20). Tanpa patch, scheduler PF OAI membagi rata (Fase 0).
- UPF Open5GS tidak menegakkan MBR: flow QOS_E (maxDownstreamRate 10 Mbit/s) mengalir 15 Mbit/s (offered). Goodput dinilai terhadap min(10, 15) = 10.
- BE bulk UE1 tidak ikut terdongkrak (±40–45 Mbit/s di BASE dan QOD) — prioritas terbatas pada flow sesi (QFI sesi).
- Probe tanpa QoD p99 ±5,5 s mencerminkan antrean RLC gNB yang dalam di rfsim pada beban 2×165 Mbit/s; angka absolut bukan representasi RAN komersial.
- Pilot `res/pilot-q69/` (20 s, sebelum ulangan resmi) hanya untuk cek harness; tidak dihitung.
- Raw: `res/<run>/` (csv probe, json iperf3 — tanpa IMSI/token; pcap N3 dipindah ke `/workspace/fase1-raw/multiue/` (700, hanya di box)).
