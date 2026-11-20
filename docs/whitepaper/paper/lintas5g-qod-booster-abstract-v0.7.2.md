<div class="head" markdown="1">
<div class="badge">DRAFT v0.7.2 preview · 20 Nov 2026</div>

# Lintas5G QoD Booster

<p class="subtitle">Network Quality-on-Demand for existing apps, proven in an open 5G lab</p>
</div>

<div class="hook" markdown="1">
**You are stuck in a traffic jam, the cell is congested, and your YouTube video stalls.** The network *can* give YouTube's traffic a better QoS flow, but YouTube has no way to ask for it at that moment. Lintas5G's booster app asks on YouTube's behalf, through the standard CAMARA *Quality on Demand* API, without changing YouTube. **First lab results:** in a saturated cell, YouTube played 41–94 % of the window with QoD vs 0–13 % without (n = 2 per arm).
</div>

<div class="cols" markdown="1">
<div class="col" markdown="1">

## The problem

A standard API for network quality exists: CAMARA *Quality on Demand* (QoD) 1.2.0, public release r4.3, 19 November 2026. Commercial adoption is thin, though. Industry trackers show QoD is a small minority of commercial Open Gateway launches, which are dominated by identity and anti-fraud APIs. So app performance tuning is still manual: experts tune policies and QoS by hand, one app and one network at a time.

## What Lintas5G is

An **open 5G lab** (Open5GS 2.8.0 core, OAI gNB v3.0.0, emulated radio) plus a demonstration client. **The booster app simulates the scenario in which an application needs a network-quality guarantee from the network via the CAMARA API (QoD).** It recognises the target app's flows on the device (app UID, DNS, TLS SNI) and requests a QoD session for them. A minimal CAMARA QoD 1.2.0 adapter (source private, available to partners on request) reaches the PCF via BSF over **N5**, and the network creates a **dedicated QoS flow** for exactly that traffic. **No change to the existing app is needed** to demonstrate this. No per-session or per-app manual configuration; one-time static provisioning is disclosed.

## Value (B2B2C)

**Operators** and API aggregators sell QoD to app and enterprise partners, who serve consumers; consumers are not the direct payer. **App developers** see, with no code change, what their app would get from QoD, before they integrate CAMARA QoD directly or through an SDK. Business models are hypotheses to be tested.

</div>
<div class="col" markdown="1">

## Key evidence so far (lab)

- **YouTube in a congested cell (round 3):** in a saturated lab cell (about 104–109 Mbit/s, 200 Mbit/s bulk on the same device), YouTube without QoD barely played (**0–13 %** of the window). With the booster app requesting CAMARA QoD, it played **41–94 %**, and median DL packet latency fell **about 4–5×** in 3 of 4 boosted runs (n = 2 per arm). The pre-registered gates were only partly met: stall time PASS, no crash PASS, but loss stayed at **7–15 %** (gate ≤ 5 %) and the **≥ 80 % bytes gate was missed** over the whole window in 3 of 4 runs.
- **Conformance:** 126 pass / 0 fail / 1 skip (project's own runner, not the official harness). **Only the target flow is boosted** (5/5 scenarios); API to boost flow **20–55 ms**.

<figure><img src="figures/F7-playing-stall.png"><figcaption>YouTube playing share and stall seconds in the boost window, with QoD (A, PA) vs without (N, PN); n = 2 per arm.</figcaption></figure>

<div class="status" markdown="1">
**Honest status.**

- Small sample (n = 2 per arm), one emulated cell, one video, 200 Mbit/s load instead of the planned 400 Mbit/s.
- The booster app switched QoD off and on (active 55–88 s of each window), which diluted results; latency is sampled and QUIC-only.
- Lab results only; nothing has run on a live network yet.
</div>

</div>
</div>

<div class="cta" markdown="1">
**Get involved.** Lab IaC, configs, test scripts and sanitised data: <https://github.com/dayat81/Lintas5G> (Apache-2.0; QoD adapter not included) · Lab or sandbox access: [LAB ACCESS FORM URL – TBD] · Operators and aggregators: [PARTNER CONTACT – TBD] · **Full whitepaper:** [LINK – TBD]
</div>

<p class="foot">Lintas5G Project · DRAFT preview of whitepaper v0.7.2 (supersedes v0.1–v0.7.2) · lab results only · not for citation. All results come from a lab with emulated radio and one cell; no live network data or subscriber identities are used.</p>
