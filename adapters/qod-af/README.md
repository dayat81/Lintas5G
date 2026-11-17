# qod-af — adapter CAMARA QoD → N5/Rx (SKELETON)

> **Status: SKELETON.** API dan mapping profil sudah ada, backend N5 belum divalidasi ke PCF Open5GS, backend Rx belum diimplementasikan. Jangan dipakai di luar lab.

Adapter tipis yang bertindak sebagai **AF tepercaya** (tanpa NEF):

```
klien CAMARA --> qod-af (/quality-on-demand/v0/sessions)
                   |-- n5: Npcf_PolicyAuthorization (POST /npcf-policyauthorization/v1/app-sessions) --> PCF Open5GS (5GC SA)
                   |-- rx: AAR/STR Diameter --> PCRF Open5GS (EPC 4G)          [TODO]
                   `-- dry-run: tanpa jaringan (unit test/demo)
```

Profil `QOS_E/S/M/L` → 5QI/QCI, GBR/MBR, DSCP ada di [`profiles.yaml`](profiles.yaml) (usulan awal).

## Jalankan lokal

```bash
pip install -r requirements.txt -r requirements-dev.txt
export QOD_API_TOKEN=$(openssl rand -hex 16) QOD_BACKEND=dry-run
uvicorn app.main:app --port 8080
pytest -q
```

Env: `QOD_BACKEND` (n5|rx|dry-run), `QOD_PCF_URL`, `QOD_API_TOKEN`, `QOD_NOTIF_URI`, `QOD_PROFILES`.

## TODO

- [ ] HTTP/2 prior-knowledge ke SBI Open5GS (`httpx[http2]`), penanganan error, retry.
- [ ] Notifikasi PCF → event CAMARA `QOS_STATUS_CHANGED` ke `sink`.
- [ ] Expiry sesi (timer) dan penyimpanan persisten.
- [ ] Backend Rx (AAR/STR) untuk EPC 4G.
- [ ] Auth OAuth2 sesuai CAMARA security guidelines (sekarang token statis).
- [ ] Mapping `phoneNumber` → SUPI/IP (butuh UDM/HSS lookup; di luar cakupan fase 1).
