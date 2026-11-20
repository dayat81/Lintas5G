# Item 3 — Trace N5→N7→PFCP→NGAP→paket QFI pertama (n5 lab, offline)

Capture: lo di netns n5-lab (CAMARA 8080, SBI 7777 h2c, PFCP 8805, NGAP 38412 via shim sctp2tcp/TCP, N3 GTP-U 2152) + log gNB (docker logs -t). Sesi: UE1, QOS_E (5QI 80; SMF mengalokasikan QFI baru per sesi: 4, 5, 6), probe UDP 50 pps ke AS <AS_IP>:18080 (port sesi). Raw pcap + log gNB mentah hanya di box (`/workspace/fase1-raw/trace/`, 700; `trace/raw` = symlink). Skrip: `run-trace.sh`, `correlate.py`.

t=0 = POST N5 `npcf-policyauthorization/v1/app-sessions` (adapter→PCF). Semua dalam ms.

| titik | rep 1 | rep 2 | rep 3 | median |
|---|---|---|---|---|
| CAMARA POST /sessions diterima (API) | -8.56 | -4.38 | -5.27 | -5.27 |
| N5 POST app-sessions (adapter→PCF) | 0.00 | 0.00 | 0.00 | 0.00 |
| N5 201 (PCF→adapter) | 1.83 | 1.74 | 1.90 | 1.83 |
| N7 POST sm-policy-notify/update (PCF→SMF) | 1.90 | 1.84 | 2.00 | 1.90 |
| PFCP Session Modification Req (SMF→UPF) | 2.97 | 2.81 | 3.13 | 2.97 |
| CAMARA 201 ke konsumen | 3.32 | 3.37 | 3.15 | 3.32 |
| N11 n1-n2-messages (SMF→AMF) | 4.35 | 3.36 | 3.68 | 3.68 |
| NGAP segmen AMF→gNB (PDUSessionResourceModifyRequest) | 5.18 | 3.88 | 4.17 | 4.17 |
| gNB log: PDUSESSIONModify initiating message | 5.61 | 4.08 | 4.38 | 4.38 |
| gNB log: created new DRB untuk QFI sesi | 6.40 | 4.29 | 4.93 | 4.93 |
| N3: paket GTP-U pertama dengan QFI sesi (rep1 DL QFI 4, rep2 UL QFI 5, rep3 UL QFI 6) | 33.07 | 29.92 | 31.26 | 31.26 |
| callback AVAILABLE diterima sink | 38.83 | 37.58 | 35.15 | 37.58 |

Catatan:
- NGAP tidak terdekode (shim sctp2tcp memakai TCP dengan framing 4 B panjang); identitas pesan dikonfirmasi oleh log gNB `PDUSESSIONModify initiating message` <1 ms kemudian.
- Waktu N3 pertama QFI sesi bergantung pada probe 50 pps (interval 20 ms) — bukan latensi jaringan murni.
- AVAILABLE dikirim adapter setelah paket QFI≠1 pertama teramati di N3 (konfirmasi N3, `confirm: n3`).
- Klien NF Open5GS mengirim dari 127.0.0.1; pemanggil SBI ditentukan dari nama layanan (producer/consumer 3GPP).
- Redaksi: SUPI/IMSI, IP UE, id hex panjang diganti; tidak ada token. File: `timeline-{1,2,3}.json`.
