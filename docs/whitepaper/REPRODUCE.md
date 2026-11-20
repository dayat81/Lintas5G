# Reproducibility guide: Lintas5G QoD booster

Language note: scripts and some result docs are partly Indonesian. Commands below are copy-pasteable on a Linux host with Docker.
**FAKTA** = measured/observed in the cited artefact. **USULAN** = recommendation, not proven.
Paths such as `/workspace/...` inside scripts are the lab host layout; set the variables noted per step if yours differs.
Secrets (UE K/OPc, adapter `clients.yaml`, `*.secret`, `jwt-signing.pem`, `bindings.yaml`, `.env`, `ran.env`, keys) are **never** in this repo; each step says how to create your own.

## 0. Layout and prerequisites

| Item | Where in repo |
|---|---|
| Adapter | source not published (private); see CAMARA QoD r4.3 spec; conformance summary in `data/conformance/`, profiles in `data/qos-profiles.yaml` |
| gNB / UPF patches | `patches/` ([README](../../patches/README.md)) |
| Offline lab scripts | `lab/offline/` |
| Scenario scripts (a1/c1/b2/m3/m4) | `lab/scenarios/` (+ `RESULT.md` with the gate table) |
| GCP round 1 scripts | `lab/gcp-round1/`, IaC in `infra/gcp/` |
| Result data | `docs/whitepaper/data/` |
| Versions and shas | [VERSIONS.md](VERSIONS.md) |

Host: Docker, Python 3.11+, `iperf3`, `tcpdump`, `mongo` image, sudo. The RAN is OAI rfsimulator (no radio). Kernel without SCTP needs the SCTP-over-TCP shim used by the lab (`libsctp2tcp2.so`, read-only mount in `lab.sh`; not in this repo).

## 1. Build the patched images (offline, local only; do not push to a public registry)

1. Open5GS 2.8.0 core: apply `patches/open5gs/open5gs-v2.8.0-upf-stale-qfi.diff` (N1) to Open5GS v2.8.0 sources, build, and add PCF `qos_profiles` QOS_E/S/M/L/7 -> 5QI 80/2/3/4/7 with `lab/offline/img-open5gs/add_qos_profiles.py`. Dockerfile: `lab/offline/img-open5gs/Dockerfile` (the `overlay/` and the base snapshot are not included: the base image carries demo SUCI home-network keys; build your own base).
2. OAI gNB v3.0.0:
   - qosrel3: `git apply patches/oai-gnb/oai-v3.0.0-qod-dl-slice+qosflow-release-fix+dup-release-guard+qos-drb-release.diff`
   - **qosrel4 (used for the whitepaper offline results)**: `git apply patches/oai-gnb/oai-v3.0.0-slice-qosrel4-combined.diff` (= qosrel3 + `ul-mcs-table-guard`).
   Tag `lintas5g/oai-gnb:v3.0.0-slice-qosrel4`. Expected image id: see VERSIONS.md (ids differ if you rebuild; compare behaviour with section 4).
3. QoD adapter: source not published (private). Implement CAMARA QoD r4.3 / QoSProfiles r1.2 yourself or request access; image tag used: `lintas5g/qod-adapter:0.1.2`.

## 2. Conformance

Adapter source is not published (private); see the CAMARA QoD r4.3 and QoSProfiles r1.2 specs (upstream, Apache-2.0) and their Test_definitions. Sanitized results: `data/conformance/summary-0.1.2.json`.
- FAKTA (19 Nov 2026): **127 total = 126 passed / 0 failed / 1 skipped** plus 16/16 lab extensions. The skip is `PRIVATE_KEY_JWT` (no pre-shared JWKS; adapter answers 422 `PRIVATE_KEY_JWT_NOT_CONFIGURED`).

## 3. Offline lab (box lab)

```
cd lab/offline
GNB_IMG=lintas5g/oai-gnb:v3.0.0-slice-qosrel4 SLICE=1 ./lab.sh start   # core n5-lab, mongo n5-mongo, gNB, N_UE UEs + 1 s keepalive
./lab.sh status
./accept.sh <tag> [cycles] [profile]      # DLR/ULR env = load; PAR=1 = two parallel sessions
./ut-upf.sh <tag> <n3.pcap>               # deterministic stale-QFI UPF check
./lab.sh stop
```
- `lab/offline/README.md` has the stack table. `slice.conf` = gNB QoD slice policy (`qod_5qi` list incl. 69 for API priority).
- You must provide your own subscriber DB and UE confs under `secrets/` (dir 700; `ue*.conf`, `imsi*`); the scripts only read them by path and redact IMSI/IP in logs.
- Two UEs (`n5-ue1`, `n5-ue2`), RAN on CPUs 4-7, core on 0-3 (CPU contention changes absolute latency; see RESULT notes).
- **Soak** (data: `data/offline/SOAK50-q4`, `SOAKPAR20-q4`): `./accept.sh SOAK50-q4 50` under full load; `PAR=1 ./accept.sh SOAKPAR20-q4 20`. FAKTA: 50/50 cycles, 0 assert/crash, 0 PDU release, 0 Error Indication, UE IP unchanged, keepalive 864/864; parallel 20x2: 39 of 40 sessions loss <= 0.7%, one 1.6% DL.
- **API priority rule** (5QI 69 for the booster's API backend): `python3 api-prio.py apply --ip <backend ip> --port <backend port> --qi 69 --arp 1`; data `data/offline/n5-q4p*`. FAKTA: create 43-54 ms / delete 49-60 ms under 150M load (earlier 3.5-4 s without the rule).

## 4. QoD adapter + E2E (offline)

1. Run the adapter (source not published (private); see API contract/spec). Profiles: `data/qos-profiles.yaml`. Create your own client credentials, device bindings and signing key. The adapter implements CAMARA QoD r4.3.
   - 0.1.2 accepts CIDR inside `ipAddresses` (one subnet counts as one address, minimum /20, only for allow-listed clients); filter budget in Open5GS 2.8.0 is 15 (AS IPs x AS ports x device ports x protocols x 2).
   - Open5GS 2.8.0 N5 quirk: one rule per 5QI per PDU session, so replace = DELETE then CREATE; QFI increments per session (verdicts use QFI != 1).
2. E2E series (`n5-q4p1..p5`): harness `lab/offline/n5proto.py` (adapter-side E2E scripts are private). Data in `data/offline/n5-q4p*`.

## 5. Booster APK and scenarios a1 / c1 / b2 / m3 / m4

- APK: `0.10.2-poc-booster.4` (versionCode 13, sha256 in VERSIONS.md). Built from the booster-app baseline `v0.10.2` plus the booster module (local, signed with a local debug key; the APK itself is **not** in this repo, request it from the app team and verify sha256). Install: `adb install -r <apk>` (over booster.3). Launch extras: backend URL, app key, SNI, p99 target, `onesession`, `newattach`.
- The scenario scripts emulate the app flow (examine VPN stand-in) on the offline lab:
  - `lab/scenarios/run_variant_n5.sh <tag> <ue 1|2> <mode a|b|c> [dur=60]` runs one gate run (baseline 15 s -> detect/CREATE -> boost -> DELETE -> post).
  - Mode **a** full-tunnel (target + bulk in TUN, relay), **b** split-tunnel (target direct, bulk in TUN; always request TCP+UDP), **c** examine-one (target in TUN, bulk direct).
  - **a1** = mode a, UE1; **c1** = mode c; **b2** = mode b after the protocol fix; **m3** = mode c emulating v0.10.2 (MTU 1400 / MSS 1360 + MGLT marker, QoD only for the target server -> marker stays QFI 1); **m4** = same with QoD for target **and** reflector (marker moves to QFI 2). `lab/scenarios/batch5.sh` shows the m3/m4 invocations (`EXTRA`/`ALLOW` = reflector `ip:port`).
  - Pass criteria and per-run table: `lab/scenarios/RESULT.md` section 4. Data: `data/vpn/{a1,c1,b2,m3,m4}` and `data/vpn/q4-{a1,a3,a4,b2}` (re-run on qosrel4).
  - FAKTA (qosrel4 VPN re-run): 4/4 pass, apply 19-51 ms, zero non-target packets on the boost QFI.

## 6. GCP round 1 (booster E2E, 2026-11-19)

Sanitized report: `data/gcp-round1/RESULT-round1.md`; summary: `data/gcp-round1/summary.csv`.
1. Provision: `infra/gcp/` (Terraform; follow `infra/gcp/README.md`; you supply your own project, `terraform.tfvars` and service account; never commit them). Profile used: core+RAN VM 4 vCPU, emulator VM 4 vCPU, no obs VM, `ran_mode = sa-oai`.
2. Ship to the core VM: gNB image (qosrel3), adapter 0.1.1, Open5GS overlay (N1 patch), and the bundle with `lab/gcp-round1/` scripts (via IAP/SSH; secrets only over SSH, never to object storage).
3. Core: `booster-up.sh core` (installs overlay, adds `qos_profiles`, starts adapter and the booster backend, reflector on `:443/:9000/:9001`), `booster-up.sh ran` (gNB `slice-qosrel3`), then `core-run.sh` per run; emulator side `emu-run.sh` (YouTube + booster app launch, logcat).
4. Runs: r0b baseline (bulk UDP 400 Mbit/s DL), r1 boost (`onesession`, 60 s), r2 multi, r3/r3b API-priority rule (static PCC 5QI 69 for the backend port). Order for r3b: YouTube first, booster later (`PLAYFIRST`).
5. Analyse: `lab/gcp-round1/qfi_flows.py`, `mglt-bins.sh`, Zeek `pktlat2` scripts in `infra/gcp/sesi-d/`.
6. FAKTA: MGLT p99 under load 5476 ms -> 1547.5 ms with boost (**-72%**), reflector flow only. CREATE under load with API-priority rule: 1.95 s seen from the app. YouTube itself **not proven** (see CLAIMS.md).
7. Destroy and audit: `terraform destroy`, then list instances/disks/addresses/firewalls/buckets/SAs and confirm none of the lab remains. Round 1 cost was about USD 0.85 for the run.

## 7. GCP round 2 (YouTube): not reproducible yet

Round 2 was stopped by the user on 2026-11-19 21:20 WIB without a valid YouTube result. Partial smoke findings (cell/CPU bound on 4 vCPU core VM, DL MCS cap, load patterns) are not part of this branch. Treat the YouTube column of the whitepaper as a placeholder.

## 8. Known deviations to disclose

- gNB image ids differ between box and GCP VM (`docker load` representation).
- Zeek restart overwrote logs during r0b-r2 (copied first).
- Round 1 used booster.3 and qosrel3; offline soak/VPN results use qosrel4 and booster.4 is ready but not yet run on GCP.
- Several CPU-contended runs (3 gNB concurrently) are marked in `lab/scenarios/RESULT.md`.
