# GCP r3 (20 Nov 2026), validity notes for whitepaper §7.5

All times WIB (UTC+7). No IMSI, UE/server IP, account or email in this folder. Raw evidence (pcaps, logs) is only in the private state bucket archive `logs/booster-e2e/20261120-r3/r3-evidence-20261120.tgz` (sha256 e6bc8d5e…e994).

## 1. What was run
- Lab: Open5GS 2.8 (patched upfd, PCF qos_profiles) + OAI gNB/nrUE (rfsim, MIMO 2) on n2-standard-8; Android 16 emulator (YouTube app, signed in) on n2-standard-4. VPN examine app + booster v0.10.2-booster.4.
- Video: Big Buck Bunny (YouTube app). Load: iperf3 UDP DL 200 Mbit/s through the same UE, starting at `load_on`.
- 4 arms × n=2: **A** (play tapped ~10 s after load, QoD at load+90 s), **N** (same, no QoD), **PA** (play tapped 42 s before load, QoD at load+90 s), **PN** (same, no QoD). Run order A1, N1, A2, N2, PA1, PN1, PA2, PN2 (interleaved, 07:34–09:01). Smoke s0 (19 Nov) and s0b (400M) are excluded from the tables.
- `bad_total` = 0 in every run (no crash, no PDU release, no error lines in amf/smf/upf/pcf/gnb/adapter/backend) (T5).

## 2. Deviations from the plan (honest list)
1. **Load 200M, not 400M.** The cell carries ~104–109 Mbit/s DL (iperf receiver, 43–49 % loss at 200M). At 400M (s0, s0b) iperf3 on the UE was OOM-killed and YouTube never got any bytes, so the result would be "everything dead" and not a QoD test. A knee test picked 200M (~1.9× offered load vs capacity; called "~1.15×" in early notes, which used the configured not the measured cell rate). Congestion is still severe: without QoD, YouTube could not start at all in N1 and stalled 115–150 s of 150 s in N2/PN1/PN2.
2. **Boost window recomputed from adapter events, not the nominal schedule.** The nominal window is load+90…load+240 s. The booster app creates the QoD session only when its own loss/flow rules fire, rotates it on CDN changes and deletes it when loss drops (see §5), so the real window starts 6.7–13.2 s late. `tools/rewin.py` sets `boost` = first `AVAILABLE` → last `deleted` of the QoD session (A1 103.2–206.8, A2 97.6–222.5, PA1 96.7–240.1, PA2 97.1–240.1 s after load). The no-QoD arms keep the nominal 90–240 s window ("boost-window (no QoD)") so A/PA vs N/PN compare equal-length positions. Inside the A/PA windows QoD was actually AVAILABLE only 54.6–88.2 s (T2 `qod_available_s`).
3. **Zeek is sampled, not continuous** (hard constraint, CPU). W1 = load+25…+88 s (pre-boost), W2 = load+130…+193 s (inside the nominal boost window), ~63 s each. Zeek used ~10 % of one vCPU while on. Lightweight GTP-U QFI counters (`qfi_timeline.csv`, from the N3 pcap after the run) cover the whole run.
4. **Zeek per-packet latency covers QUIC (UDP/443) only.** TCP per-packet correlation is still off (`tcp_on=F`, design in `lintas5g-whitepaper/docs/design/tcp-perpacket-latency-plan.md`). YouTube in these runs used mostly QUIC, so the metric is valid for the video flow, but it is not "all packets".
5. **Startup is measured from the play tap**, not from app launch; in A/N the tap is under load, in PA/PN it is before load (so PA/PN `startup` is an uncongested baseline, 17–24 s).
6. **Resolution** is from SurfaceFlinger layer size (`vq-raw.txt`), not "Stats for nerds"; it is the rendered surface, a proxy for the selected format.

## 3. Cross-run comparison, A vs N (play started under load)
- Startup: A1/A2 started playing only after QoD came up (first play at load+122 / +144 s, i.e. 19 / 47 s after QoD). N1 never started in 260 s; N2 started at load+119 s and then stalled 115 s of the 149 s window.
- Boost window playing %: A 77.7 / 41.0 vs N 0.0 / 4.0. Stall s: A 5.0 / 30.8 vs N 0 (never started) / 115.1.
- YouTube DL loss (GTP-U count N6→UE): A 7.3 / 13.6 % vs N 26.9 / 31.7 %. Throughput 1.09 / 0.23 vs 0.03 / 0.05 Mbit/s.
- Zeek DL one-way p50: A 1027 / 945 ms in W2 vs N 4271 (n=1) / 4060 ms.

## 4. Same-session result, PA vs PN (playing before load, QoD added mid-congestion)
- PA1: playing 26.1 % pre → 74.2 % boost; PA2: 34.1 % → 94.5 %. PN1: 31.1 % → 0.0 %; PN2: 100 % → 13.3 % (PN2 survived the pre window on buffer, then drained).
- Stall s in the boost window: PA 34.0 / 7.1 vs PN 150.1 / 130.1.
- **Zeek latency, why PA1 shows no gain (4152 → 4099 ms) while PA2 does (3911 → 723 ms):**
  - QoD covered only 17 % of PA1's W2 (session gap 131.6–184.0 s after load; W2 is 130.0–193.4). 220 of 284 DL packets were sampled with no QoD session at all.
  - The 64 packets that fell inside QoD (session created at 184.0 s) still saw 3981 ms, because YouTube's bytes did not land on the new QFI: in 185–195 s, 878 kB of YouTube DL went on default QFI 1 and 235 B on the boost QFI 17 (`qfi_timeline.csv`). The new session's packet filters (8 flows, CDN /20 list) did not cover the server YouTube was using at that moment (CDN rotation), and the next ROTATE had not yet fired.
  - PA2's W2 was also mostly outside QoD by time (24 %), but during that QoD part YouTube was inside a covered CDN prefix (165–180 s after load: 2.78 MB of YouTube DL on boost QFI 21, 1.3 kB on QFI 1), and most sampled packets (1485 / 1574) fell in it, at p50 722 ms, p95 762 ms. Packets outside QoD in the same window: p50 3953 ms.
  - Split per QoD state for all runs: T3 columns `W2_qod_on_*` / `W2_qod_off_*` (`evidence/zeek-split.json`, `tools/zsplit.py`). With QoD actually carrying the flow, p50 is 0.72–1.02 s vs 3.9–4.3 s without, in every run where that happened (A1, A2, PA2).
  - Hypothesis (supported by the logs above, not separately tested): the latency gain is real per packet, but the window metric is diluted by (a) the booster's on/off cycle and (b) filter misses after CDN rotation. It is not a scheduler/QFI failure: whenever YouTube bytes were on the boost QFI, latency dropped ~4×.
- Note the remaining ~0.7–1 s one-way delay under QoD: the boost QFI still shares a ~107 Mbit/s rfsim cell with a 200 Mbit/s flood; `qod_max_pct=70` caps the QoD slice share at the gNB.

## 5. Why YouTube bytes are not 100 % on the boost QFI (T2)
1. **Booster on/off cycle (largest).** The app deletes the session as soon as its measured `max_flow_loss` drops below 5 % (log `flowstat max_flow_loss=0.0% thr=5.0%` → `DELETE` → `ACTIVE -> COOLDOWN`), waits a 30 s cooldown and re-creates when loss returns. Gaps of 34–52 s inside every boost window (A1 150–184 s, A2 161–197 s, PA1 132–184 s, PA2 129–163 s). Whole-window share 60.7–80.1 %; while AVAILABLE 75.6–96.5 %.
2. **CDN rotation.** YouTube moves to servers outside the subnets in the session (`ROTATE #1: uncovered [...] -> DELETE then CREATE`, `rotate skipped: ... rank below kept subnets`). The app caps at 2–3 /20 subnets (15 flow limit in Open5GS PCC rule), so some servers stay on QFI 1 until the next rotate.
3. **Create latency.** 1–18 s from create to AVAILABLE per session (N5 + QFI confirm).
These are booster-app policy issues, not network failures. For the paper: report the share while AVAILABLE and state the cycle.

## 6. Small n
n = 2 per arm, one cell, one video, one time-of-day, one GCP region. Effects are large and in the same direction in every pair (playing % 41–95 vs 0–13, stall s 5–34 vs 115–150), but no confidence intervals or significance tests are justified. Write "in all 4 QoD runs vs all 4 no-QoD runs", not percentages of improvement with decimals.

## 7. MGLT vs Zeek excluded
MGLT v1 echo RTT (app-side) and Zeek one-way timestamps come from different clocks (emulator guest vs core VM). The UL one-way values show a −90 to −160 ms skew between them (`zeek_mglt_p50_ms` negative in `r3-results.csv`), so MGLT↔Zeek joint numbers are not reported. Zeek DL one-way uses only the core VM clock at N6 and N3/UE taps on the same host, so it is internally consistent; MGLT RTT is reported only as its own metric in the raw CSV.

## 8. Static / manual configuration in r3 (answers "no manual configuration?")
**No: r3 is not "pure CAMARA API → adapter → N5, zero manual config".** Evidence `evidence/static-config-r3.json`, `ev/booster-up.out`, adapter/pcf logs:
- **Static PCC rule 5QI 69 ARP 1** for the booster control API path (backend :8090/TCP, 2 flows, marker `api-prio`), written into the subscriber's default session by `booster-up.sh apiprio()` at bring-up (default ON since r2). It carries only booster↔backend control traffic (QFI 2 in `qfi_timeline`, class `backend`), never YouTube, but it does protect the booster's own API calls under congestion, so it helps the QoD request get through.
- **gNB slice config** `slice.conf`: `qod_5qi=80,4,69,7,1`, `qod_max_pct=70`, `be_max_pct=100`, `pbr_pct=20`, mounted into OAI gNB at start. The RAN scheduler favours these 5QIs (5QI 4 = the QOS_L profile used for YouTube) by static config.
- **PCF qos_profiles** (5 entries) added to `pcf.yaml` and a **patched upfd** installed at bring-up.
- **5QI 4 template PCC rule (no flows)** in the subscriber record. This is written by the adapter itself (`MongoBridge.ensure_template`) on the first QoD request (s0/s0b log `template=written`; all r3 runs `template=exists`). Open5GS 2.8 needs it to map an N5 media component to a 5QI. It is automatic but it is a direct DB write, not an N5 operation.
- **Per-session, the YouTube QoS flow was created only at runtime**: booster app → CAMARA QoD API → adapter → BSF lookup → `POST npcf-policyauthorization/v1/app-sessions` (adapter `n5_create_ms`, PCF log `Setup NF EndPoint` per session) → dynamic QFIs (15/16/17/21, a new one per session) carrying YouTube. No operator action per session.
Suggested wording: "No per-session or per-application manual configuration: the YouTube QoS flow was created on demand via the CAMARA QoD API and N5. The lab uses one-time static provisioning (QoS profiles in PCF, a 5QI template, gNB scheduler weights per 5QI, and a static priority rule for the booster's control API)."
