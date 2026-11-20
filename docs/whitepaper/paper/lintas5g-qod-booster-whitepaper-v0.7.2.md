<div class="cover" markdown="1">
<div class="draftbadge">DRAFT v0.7.2 · for feedback · not for citation</div>

# Lintas5G QoD Booster

<p class="subtitle">Network Quality-on-Demand for Existing Apps, Proven in an Open 5G Lab</p>

<p class="meta"><b>Author:</b> Lintas5G Project<br>
<b>Version:</b> draft v0.7.2 · 20 November 2026 (states that the QoD adapter source is private; v0.7.2 corrected the startup wording, the Figure 10 image and caption, and added the percentile method to v0.7, which added the first YouTube results from cloud lab round 3, 20 Nov 2026; earlier revisions: SME input, market review, corrected latency method, one main use case)<br>
<b>Repository:</b> <a href="https://github.com/dayat81/Lintas5G">github.com/dayat81/Lintas5G</a> (Apache-2.0; upstream Open5GS/OAI patches under their upstream licences, AGPL where applicable). The public repository provides the lab IaC, configs, test scripts, sanitised data and the method. The QoD adapter source (CAMARA QoD to N5) is private and not published; full reproduction of the API path needs the adapter, available to partners on request: [PARTNER CONTACT – TBD].</p>

<div class="callout" markdown="1">
**About this draft.** This paper is written to test market response from telco operators and app developers. Lintas5G is intended for live networks; the lab is the required validation stage before live pilots, so every technical result here comes from a lab: emulated radio, one cell, synthetic subscribers. No live network data, no subscriber identities and no real operator are used or named. All IP addresses shown are RFC 5737 documentation addresses. Business models and revenue figures are **hypotheses and assumptions**, marked as such wherever they appear.
</div>

**Contents**

1. Executive summary
2. The problem: a standard API exists, adoption is thin, tuning is manual
3. The solution: the booster app simulates an app requesting quality via CAMARA QoD
4. For operators: value, business-model hypotheses, pilot path
5. For app developers
6. How it works
7. Evidence
8. Honest limitations
9. Roadmap
10. Anticipated questions (FAQ)
11. Call to action and feedback
12. References

</div>

## 1. Executive summary

**The everyday moment.** You are stuck in a traffic jam. Hundreds of people around you are on their phones, and the cell is congested. You open YouTube, and the video stalls and drops to low resolution. The network *can* treat YouTube's traffic better (it has QoS flows for exactly this), but YouTube has no way to ask for it at that moment. Lintas5G's booster app closes that gap: it recognises YouTube's traffic on the device and requests CAMARA *Quality on Demand* (QoD) on YouTube's behalf, so the network gives that traffic a dedicated QoS flow while the congestion lasts. YouTube itself is not changed. **First YouTube results (lab, cloud round 3, 20 Nov 2026):** In a saturated lab cell (about 104–109 Mbit/s of downlink capacity, with 200 Mbit/s of bulk traffic on the same device), YouTube without QoD barely played (0–13 % of the window). With the booster app requesting CAMARA QoD, it played 41–94 % of the window, and median downlink packet latency fell about 4–5× in 3 of 4 boosted runs (n = 2 per arm). The pre-registered gates were only partly met: loss stayed at 7–15 %, and the ≥ 80 % bytes gate was missed over the whole window in 3 of 4 runs. See Section 7.5.

**The reality today.** A standard API for network quality exists (CAMARA *Quality on Demand* 1.2.0, public release r4.3, 19 November 2026), but commercial adoption is thin: industry trackers show QoD is a small minority of commercial Open Gateway launches, which are dominated by identity and anti-fraud APIs. In Indonesia, the public CAMARA launches so far focus on fraud and identity, and we found no public QoD launch. So on most live mobile networks an app still has no network-quality API it can actually call. When an important app performs badly on a mobile network, the fix is manual. Experts analyse traces and tune parameters, policies and QoS settings by hand, one app and one network at a time. This works, but it is slow and expensive, and it cannot scale to the thousands of apps and the moments when users actually need quality. Meanwhile users lose the moments that matter, like the YouTube video in the traffic jam above, or an important video call from the same congested cell.

**Why we built this.** The project is led by a subject-matter expert with hands-on experience of this manual tuning on a large Indonesian mobile network, as a network-vendor engineer (Section 2).

**Our goal.** Lintas5G automates that manual tuning through **standard CAMARA APIs**, starting with *Quality on Demand* (QoD), so that network quality becomes **on-demand and programmable**. **The booster app simulates the scenario in which an application needs a network-quality guarantee from the network via the CAMARA API (QoD).** It is a lab and demonstration vehicle, not a finished consumer product. On an Android device it acts on behalf of an existing app: it recognises that app's flows (app UID, DNS, TLS SNI) and requests a CAMARA QoD session for exactly those flows, with a before/after view. **No code change to the existing app is needed to demonstrate this.** No per-session or per-app manual configuration; one-time static provisioning is disclosed (Section 7.5.1). It proves the network side and the value; in production, developers integrate the CAMARA QoD API directly (or through an SDK).

**Built for live networks; validated in the lab first.** Lintas5G is intended to run on live operator networks. The open lab is the required validation stage before any live pilot. It reproduces a key live-network condition, a congested cell, with an open 5G core and RAN and emulated radio.

**What we proved in the lab** (Open5GS 2.8.0 core, OAI gNB v3.0.0, emulated radio):

| Result | Value | Scope |
|---|---|---|
| YouTube in a saturated cell, with vs without QoD | Playing **41–94 %** of the window with QoD vs **0–13 %** without; median DL packet latency **about 4–5× lower** in 3 of 4 boosted runs | Cloud lab round 3, n = 2 per arm, one cell, 200 Mbit/s bulk on the same device; gates only partly met (loss 7–15 %; ≥ 80 % bytes gate missed in 3 of 4 runs) (Section 7.5) |
| The network mechanism works under congestion | MGLT p99 **5476 → 1548 ms (−72 %)**, beating the ≥ 50 % improvement target | One congested cell (cloud lab, round 1), **MGLT reflector flow only, not YouTube**; measured per packet, QUIC on UDP 443 only (Section 7.0) |
| Only the target flow is boosted | 5/5 offline scenarios pass; **0 non-target packets** on the boost QoS flow | Same device; bulk traffic and ICMP stay on the default flow |
| Time to boost / un-boost | API → boost flow **20–55 ms**; DELETE → default flow **38–48 ms** | Offline lab, uncongested |
| CAMARA conformance, aligned with QoD 1.2.0 (r4.3) and QoS Profiles 1.2.0 (r1.2) | **126 pass / 0 fail / 1 skip** + 16/16 lab extensions | Project's own runner derived from CAMARA Test_definitions, *not* the official Gherkin harness |
| Stability | 50/50 soak cycles under load, **0 crashes, 0 PDU session releases** | Offline lab |

**What this means.** For **operators**, Lintas5G turns expert-only, one-off tuning into a product that operators and API aggregators sell to app and enterprise partners through a standard API (**B2B2C**: the partners serve consumers, and consumers are not the direct payer). For **app developers**, the booster app shows, with no code change, what their app would get by requesting quality through CAMARA QoD. Direct integration of the CAMARA QoD API (or an SDK) is the production path once the value is clear. Business models (per-session QoD sold to partners, partner bundles, outcome-based contracts, revenue share) are **hypotheses** we want to test with you. They follow pricing patterns already seen in public QoD launches, such as per-minute billing. No revenue figure is claimed.

**What it does not prove yet.** These results come from a lab with emulated radio and one cell. The YouTube results rest on **n = 2 runs per arm**, one video and one cell, with 200 Mbit/s instead of the planned 400 Mbit/s bulk load. Two pre-registered gates failed: YouTube loss stayed at 7–15 % (gate ≤ 5 %), and the ≥ 80 % bytes-on-boosted-QFI gate was met over the whole window in only 1 of 4 runs, mainly because the booster app's own policy switched QoD off and on. Latency is measured per packet only for QUIC on UDP 443, in sampled windows of about 63 s, with millisecond-level clock accuracy (Section 7.0); in round 3 the YouTube app used mostly QUIC, and per-packet TCP measurement support is being added now (work in progress, not a result). The −72 % MGLT result (round 1) applies only to the MGLT reflector flow, not YouTube. The demonstrated boost protects an app from bulk traffic **on the same device**; it does not give one subscriber priority over another. Nothing has run on a live network yet. Section 8 lists every limitation.

**What we ask.** Operators: tell us whether you would host a sandbox or live pilot. Developers: ask for lab or early-sandbox access. Researchers: reproduce the lab and extend the work through the repository (the QoD adapter is available to partners on request; Section 8). Section 10 answers anticipated questions, and Section 11 lists short feedback questions for each group.

## 2. The problem: a standard API exists, adoption is thin, tuning is manual {: .pb }

**Start with one person.** Someone stuck in a traffic jam wants to watch YouTube. The cell is congested, so YouTube's traffic competes with everyone else's and with bulk traffic on the same phone. The network could protect that traffic, but nothing lets YouTube, or the user, ask for it at that moment. The rest of this section explains why.

Mobile networks have been able to give individual flows different treatment for years. In 5G this is a *QoS flow* with its own QoS Flow Identifier (QFI) and 5G QoS Identifier (5QI); in 4G it is a dedicated bearer with a QoS Class Identifier (QCI). The capability exists inside the network. What is missing is a way for apps and users to **ask** for it.

**A standard API exists, but adoption is thin.** CAMARA *Quality on Demand* 1.2.0 was publicly released in r4.3 on 19 November 2026 [1]. Commercial launches are still few: the GSMA reports more than 300 commercial instances of 20 CAMARA APIs [9], and industry analysis notes that only a fraction of them are QoD, with the market dominated by identity and anti-fraud APIs [10]. In Indonesia, operators launched Number Verify, SIM Swap and Device Location through Open Gateway in 2024 [11] and a fraud-focused Telco API Alliance in 2025 [12]; we found no public QoD launch there (web search, 19 November 2026; absence of evidence is not proof). In practice, therefore, an app on most live mobile networks cannot yet request better treatment for its own traffic. When a service performs badly, quality is improved the only way available, which is manual expert tuning:

- **Per app.** Experts first identify the app's traffic (servers, ports, protocols), then build matching policies and QoS rules for it.
- **Per network.** The same work is repeated for each operator, region and network generation, because configurations and vendors differ.
- **Slow.** Each case means drive tests, trace analysis, parameter changes and verification. It takes significant expert time, and the tuning is static: it applies all the time, or not at all.
- **Not scalable.** Only a handful of high-profile services ever get this attention. The long tail of apps, and the individual user in a congested cell at an important moment, never do.

**Why we built this.** The Lintas5G project is led by a subject-matter expert with hands-on experience of exactly this work: manual application performance tuning on a large Indonesian mobile operator's network, done as a network-vendor engineer. That experience gives two lessons. First, the network *can* deliver the quality when it is configured for a specific app. Second, the manual process can never keep up with the number of apps or with the moment a user needs it.

**The standard path exists but is rarely launched.** The CAMARA project (Linux Foundation) defines developer-friendly APIs such as *Quality on Demand* and *QoS Profiles*, which could make network quality programmable. Adoption faces a chicken-and-egg problem. Operators wait for app demand before exposing QoD, and developers will not refactor their apps without urgency and proven reach. The benefit only shows in congested cells, which developers rarely see at their desks.

### Why network-quality APIs lag identity APIs

Public sources point to four reasons. Each maps to something Lintas5G is built to address.

| Barrier (sourced) | Lintas5G answer |
|---|---|
| **Launch share.** Commercial Open Gateway launches are dominated by identity and anti-fraud APIs; QoD is a small minority [9][10]. Developers rank fraud prevention as the most appealing use case, followed by mobile payments [9]. | Make the network-quality case visible with measured evidence, not promises. |
| **Value only shows under congestion.** QoD helps when the cell is busy; one public launch notes the gain is visible only when the network is congested [13]. Developers rarely see congested cells at their desks. | A reproducible congested-cell lab with before/after measurement per flow (Section 7). |
| **Monetisation.** Cost-based pricing does not work for QoD; enterprises buy outcomes, such as a live stream that does not drop, not API calls [14]. | Time-boxed uplift tied to a user moment, priced per session or per outcome (Section 4.2). |
| **Regulation.** European regulators assess network APIs that give applications differentiated QoS under open-internet rules, and the obligations for internet access services remain [15]. | User-initiated, time-limited, standard-profile uplift scoped to one app's flows (Section 4.6). |

<div class="small" markdown="1">[CHECK: citation permission] A GSMA operator-launch heatmap (Q1 2026) gives an exact QoD count and a regional split (including none in APAC). That slide is marked "Confidential", so the figure is left out until permission to cite it is confirmed.</div>

### Market evidence: where QoD is used today

| Vertical | Public example | Reported result |
|---|---|---|
| Live broadcast | A German broadcaster's football production, with QoD on two operators' public networks via an API platform [16] | Crew intercom stayed connected through peak half-time congestion while best-effort control SIMs dropped; commentary audio had 18× lower packet loss than best effort |
| Payments | A mobile-payment platform invoking QoD at the final payment step [17]; a Brazilian operator's per-minute QoD trialled by a bank for instant payments [13] | Higher first-time payment completion (no figure published); trial stage |
| Remote driving | A tele-driving company on a Finnish operator via a network-API platform [18] | Video for the remote driver stayed usable during congestion |
| Cloud gaming | An AI agent selecting a low-latency core path through the CAMARA QoD API, field trial on a commercial 4G network [19] | Average latency 41.9 → 27.4 ms |

These verticals are secondary for Lintas5G. Our main use case is an everyday consumer app, **YouTube in a congested cell**. The video call, gaming, broadcast-style uplink and payment scenarios are secondary scenarios on the roadmap (Section 9).

**Lintas5G's goal** is to replace manual tuning with automation through the standard CAMARA QoD API, so that quality is **on-demand** (requested at the moment it matters, for a limited time) and **programmable** (requested by software, for any app, on any network that exposes the API).

## 3. The solution: the booster app simulates an app requesting quality via CAMARA QoD

**The booster app simulates the scenario in which an application needs a network-quality guarantee from the network via the CAMARA API (QoD).**

**The main scenario: YouTube in a traffic jam.** The user is in a congested cell and starts a YouTube video. The booster app sees YouTube's connections on the device, asks the operator's CAMARA QoD API for a `QOS_L` (video) session for YouTube's servers, and the network moves that traffic to a dedicated QoS flow. When the boost ends, the traffic returns to the default flow. The steps below are the same for any target app; YouTube is the one we use throughout this paper.

It is a **lab and demonstration vehicle**. It acts on behalf of an existing app and does automatically, from the device, what an expert used to do by hand: identify the app's traffic and ask the network to treat it better, here through the standard CAMARA QoD API. This shows what happens when that app requests quality via CAMARA, end to end, without waiting for the app to be changed. It proves two things before any developer writes integration code: that the **network side** works (the request becomes a dedicated QoS flow for exactly that app's traffic) and that the **value** is measurable. The booster app is not a finished consumer product; the production path is direct CAMARA QoD integration by the app (Section 5).

1. **Detect.** The booster app runs an Android VPN service in *examine mode*. It sees which app opens which connection (app UID), which names the app resolves (DNS) and which server name appears in the TLS handshake (SNI). From this it derives the target app's server IP addresses and ports.
2. **Request.** When the demonstration triggers a boost for the target app (manually or by a rule), the booster app calls, on the app's behalf, the operator's CAMARA QoD API with that server and port set, a QoS profile (for example `QOS_L` for video or `QOS_E` for interactive use), TCP+UDP, and a duration of up to 3600 s.
3. **Prove.** The booster app measures the flow before and during the boost and shows the difference. In the lab it also emits a small marker flow to a reflector (MGLT). Latency is not estimated: the booster app's examine-mode probe timestamps each packet at the UE, and the same packet is matched, by a per-packet hash, against a capture after the UPF. Section 7.0 describes the method and its limits.
4. **Release.** When the demonstration stops the boost, or the duration expires, the session is deleted and traffic returns to the default flow.

The target app (in this paper mainly YouTube; secondary examples are a video call or a game) keeps running unmodified. Any change in its traffic comes from the network.

<div class="callout" markdown="1">
**Claim scope.** In the lab, the boost moves the *target app's flows* to a dedicated QoS flow while *bulk traffic from the same device* (downloads, other apps, ICMP) stays on the default flow. The proven benefit is protection of one app against bulk traffic **on the same device and cell**. We do **not** claim priority over other subscribers' devices; that was not tested.
</div>

## 4. For operators: value, business-model hypotheses, pilot path

### 4.1 Value

- **Automate what is manual today.** Application performance tuning that now needs experts per app and per network becomes an API call, scaling to many apps without per-case engineering. The network still needs one-time static provisioning (QoS profiles, scheduler weights per 5QI); the lab's is disclosed in Section 7.5.1.
- **Monetise network quality through a standard API.** The booster app uses only the standard CAMARA QoD API, so what it demonstrates is exactly what apps will consume in production. An operator that exposes QoD (directly or through an aggregator) serves the demonstration and later the directly integrated apps through the same API.
- **Proof before app refactoring.** The booster app simulates an app requesting quality, so operators can show partners and developers the effect on their own apps before anyone refactors code.
- **A visible, sellable moment.** The before/after view turns an invisible network feature into something an app or enterprise partner can show its users and pay for at the moment of need.
- **Controlled network impact.** Sessions are time-boxed (≤ 3600 s), scoped to specific server addresses and ports, and limited by the profile (bit-rate caps, packet-filter budget). The operator keeps policy control in the PCF.

### 4.2 Business-model hypotheses (to be validated)

**Market position: B2B2C.** Operators, directly or through API aggregators, sell QoD to app and enterprise partners. The partners use it to serve their consumers. Consumers are not the direct payer.

| # | Hypothesis | Who pays | What we need to learn |
|---|---|---|---|
| H1 | **Per-session QoD for partners** (pay per minute or per session of uplift, as in a public launch that bills per minute of prioritisation [13]) | App or enterprise partner, billed by the operator or an aggregator; consumers are not charged directly | Partner willingness to pay per session or per minute; acceptable price; which user moments a partner triggers |
| H2 | **Partner bundle or subscription** (a monthly pool of QoD session-minutes for an app or enterprise partner; subscription is the pricing model developers prefer most [23]) | App or enterprise partner | Bundle size and usage pattern; whether a pool lowers the barrier to first use |
| H3 | **Outcome-based contract** (priced on an assured outcome, such as a broadcast that does not drop or a payment that completes [14]) | Enterprise partner | Which outcomes partners will pay for; how the outcome is measured and evidenced |
| H4 | **Revenue share** between operator, aggregator and app partner (preferred by 26 % of developers in a GSMA Intelligence survey [23]) | Split | Acceptable split; who owns the customer relationship |

All four are **hypotheses** about how QoD sessions, requested by partner apps in production, could be sold. They are not a plan to sell the booster app itself. None has been tested with real customers.

### 4.3 Pricing evidence and revenue model (ASSUMPTION)

<div class="assumption" markdown="1">
**ASSUMPTION / ILLUSTRATIVE ONLY.** We do not claim a revenue figure in this version. Public evidence points to three pricing patterns: per-minute billing of prioritisation in a commercial QoD launch [13]; outcome-based pricing, recommended by the GSMA because enterprises buy outcomes rather than API calls [14]; and developer preferences for subscription, pay-per-feature and usage pricing, with revenue share chosen by 26 % [23]. A partner-revenue model (partner count × sessions × price per session, by vertical) will be published once partners can challenge its inputs ([INPUTS TABLE – TBD]). No operator is named or modelled.
</div>

### 4.4 Path to market: lab → sandbox → live pilot → telco app store / CAMARA marketplace

1. **Lab (done, this paper).** Open lab; the public repository provides the lab IaC, configs, test scripts, sanitised data and the method. The QoD adapter source (CAMARA QoD to N5) is private and not published, so full reproduction of the API path needs the adapter, available to partners on request. This is the required validation stage before any live deployment.
2. **Operator sandbox.** The booster app pointed at an operator's QoD sandbox endpoint; consent and OAuth flows per CAMARA; no change to the booster's API usage.
3. **Live pilot.** The booster app (as the demonstration client) and the adapter (or the operator's own CAMARA endpoint) on a live network with a partner operator, with agreed KPIs and policy limits.
4. **Telco app store / CAMARA marketplace.** Apps integrate CAMARA QoD directly (or via an SDK) and reach operators through an API marketplace or aggregator, with billing to app or enterprise partners through one of the H1–H4 models (operators or aggregators bill the partner; consumers are not the direct payer). The booster app remains the demonstration and test tool.

### 4.5 Live 4G NSA pilot path (FUTURE WORK / ASSUMPTION)

Many networks still run 5G as non-standalone (NSA), with an LTE (EPC) anchor. **5G SA is not a prerequisite for QoD:** public commercial launches already run on 4G and 5G NSA, for example a Brazilian operator prioritising registered server IPs on 4G and 5G NSA after a NEF/SCEF core upgrade [13], and a German operator offering QoD on 4G and 5G [20]. Our lab is 5G SA (N5 to PCF via BSF). **We assume, but have not tested,** that the same booster app and CAMARA API could drive a 4G/NSA pilot by swapping the adapter's southbound interface. Instead of N5 to a 5G PCF, it would use **Rx (Diameter) to the PCRF**, which would set up a **dedicated bearer with a suitable QCI** for the target flows. This is standard 3GPP policy control, but our adapter does not implement Rx today. It is future work and would need an operator lab or pilot partner.

### 4.6 Consent, API consumer and net neutrality (OPEN QUESTIONS)

- **Who is the API consumer.** In the lab, the booster app's backend is the API client. In production, the API consumer is the app or enterprise partner that integrates CAMARA QoD (directly, via an SDK or via an aggregator) and holds the commercial agreement. The booster app stays a demonstration and test tool.
- **User consent.** Production use must follow CAMARA Identity and Consent Management (QoD r4.3 is based on ICM r4.2 [1]), including 3-legged flows where the operator requires user consent.
- **Net neutrality.** European regulators assess network APIs that assign differentiated QoS to applications under the Open Internet Regulation [15]. Rules differ by jurisdiction and we have not assessed any specific one. Our design position: uplift is **initiated by the user or the partner app, time-limited (≤ 3600 s), uses standard CAMARA profiles, and is scoped to one app's flows**. Operators keep policy and admission control in the PCF/PCRF.

## 5. For app developers

- **No more waiting for manual tuning.** Today your app gets better network treatment only if experts tune it by hand, per network. With QoD, quality is requested on demand, when your user needs it.
- **No code change needed to demonstrate.** **The booster app simulates the scenario in which an application needs a network-quality guarantee from the network via the CAMARA API (QoD).** Point it at your app, and see what your app would get from QoD in congested conditions. Your app binary is untouched.
- **Evidence before investment.** The before/after view and exported events give you data to decide whether direct integration is worth it.
- **Production path: direct CAMARA integration (or an SDK).** The booster app is a demonstration vehicle, not what ships to your users. For production, call CAMARA QoD directly from your app or backend (create, get, extend, delete sessions; discover profiles via QoS Profiles), or use an SDK that wraps it. The booster app and a direct integration use the same API and profiles, so what you see in the demonstration carries over.
- **Profiles that map to use cases** (lab values below; the profile definitions are published in `docs/whitepaper/data/qos-profiles.yaml`):

| Profile | Intended use | Lab network mapping | Lab limits |
|---|---|---|---|
| `QOS_L` | Video (e.g. streaming, video call downlink) | GBR, 5QI 4 | 10 Mbit/s guaranteed / 20 Mbit/s max DL; 300 ms delay budget |
| `QOS_E` | Gaming / interactive | Non-GBR, 5QI 80 | 10 Mbit/s DL / 5 Mbit/s UL max; 10 ms delay budget |

These values are lab settings, not an operator offer. `QOS_S` (5QI 2) and `QOS_M` (5QI 3) also exist in the lab.

**Practical integration notes from the lab:**

- **Request TCP and UDP.** Many media apps use QUIC (UDP 443). A lab variant that requested only TCP failed its gate.
- **Keep filters narrow.** In CAMARA, ports apply to every server address listed. Open5GS 2.8.0 allows 15 packet filters per session, and wide port ranges or subnets would also boost other traffic to the same servers.
- **CDNs rotate addresses.** A short list of server IPs does not follow CDN rotation (see the YouTube limitation in Section 8). Subnet- or SNI-based selection is on the roadmap.

## 6. How it works {: .pb }

### 6.0 Key terms

| Term | Meaning in this paper |
|---|---|
| **Booster app** | The lab and demonstration vehicle. The booster app simulates the scenario in which an application needs a network-quality guarantee from the network via the CAMARA API (QoD). It acts on behalf of an existing app; it is not a finished consumer product. |
| **Target app** | The existing, unmodified app whose flows the booster app requests quality for. Main scenario: YouTube; secondary: video call, game. |
| **CAMARA QoD** | Standard *Quality on Demand* API: create, get, extend and delete a time-limited quality session for given server addresses and ports. The production path for developers. |
| **QoD adapter** | Lintas5G's minimal CAMARA QoD implementation; translates API calls into 5G core policy (BSF, N5 to PCF). |
| **QFI / 5QI** | 5G QoS Flow Identifier / 5G QoS Identifier. QFI 1 = default flow; QFI 2 = the dedicated flow created for a QoD session in the lab. |
| **Examine mode** | The booster app's on-device flow observation (app UID, DNS, TLS SNI) used to find the target app's servers and ports. |
| **MGLT reflector flow** | A small marker flow (QUIC, UDP 443) from the booster app to a lab reflector, boosted together with the target. Its packets, like the target app's QUIC packets, are measured per packet (Section 7.0). |
| **Per-packet latency** | The difference between a packet's timestamp at the UE (booster app probe) and at a tap after the UPF (N6/SGi), matched by a per-packet hash. Measured, not estimated. |

### 6.1 Components

- **Booster app** (Android, examine mode): the lab and demonstration vehicle that simulates an application needing a network-quality guarantee via CAMARA QoD. It acts on behalf of an existing target app: flow detection by UID, DNS and SNI, and the QoD session life cycle, with a thin backend relay in the lab.
- **CAMARA QoD adapter 0.1.2:** a minimal implementation aligned with CAMARA *Quality on Demand* 1.2.0 (release r4.3, 19 November 2026) and *QoS Profiles* 1.2.0 (release r1.2, 15 November 2026), the latest public releases at the time of writing. It handles OAuth 2.0 client credentials and resolves the device on the server side (the booster app can omit the device identifier; the adapter maps its client binding to the device). It accepts sessions up to `maxDuration` 3600 s with TCP+UDP filters and exports events without identities (device key is a hash).
- **5G core, Open5GS 2.8.0** (with a lab patch for stale QFI handling in the UPF). The adapter acts as a **trusted AF**. It finds the serving PCF through the **BSF** and calls **Npcf_PolicyAuthorization over N5** (3GPP TS 29.514) directly, with **no NEF**. The PCF maps the profile's 5QI through its `qos_profiles` and installs a PCC rule. SMF and UPF create a **dedicated QoS flow (QFI 2)** on N3.
- **Latency measurement:** the booster app's examine-mode probe (UE side) and a Zeek capture at a tap after the UPF, before the internet (N6/SGi), correlated per packet by hash (Section 7.0).
- **RAN: OAI gNB v3.0.0** with project patches (QoS-flow release fixes, slice/QoD scheduling policy), radio emulated with OAI rfsimulator / vrtsim (real-time paced). UE: OAI nrUE. In the cloud lab, an Android emulator runs the booster app and the target apps over the nrUE.

The design follows the same idea as the QoD Transformation Function for Open5GS presented to ETSI SDG OpenOP (OOP(26)003008, 22 July 2026): map CAMARA QoD onto vanilla Open5GS policy authorisation, BSF and PCC rules without a NEF. Our adapter is smaller in scope. For example, it has no federation and no callbacks to partner operators.

**Related work.** An operator in Japan has shown AI agents that use the CAMARA QoD API to switch traffic between a central core and a low-latency path, and return a certificate of the achieved latency [19]. A US operator's QoD offer includes a session check that confirms a line's profile before and after a QoD call [21]. Lintas5G differs in three ways: it is an **open lab** (Apache-2.0 repository with lab IaC, configs, test scripts and sanitised data; the QoD adapter itself is private), it **detects the target app on the device** so existing apps need no change to be demonstrated, and it publishes **per-flow before/after evidence** with its limitations.

<figure><img src="figures/F1-architecture.png"><figcaption>Figure 1. Lab architecture. The booster app requests QoD, on behalf of the target app, for the target app's flows; the adapter uses BSF and N5 to reach the PCF; the target flow moves to QFI 2 while bulk traffic stays on QFI 1.</figcaption></figure>

### 6.2 Session sequence

<figure><img class="mid" src="figures/F2-sequence.png"><figcaption>Figure 2. Session life cycle, from detection through CREATE, the boost flow becoming active, and DELETE. Latency annotations are offline-lab values (Section 7.2).</figcaption></figure>

Example request, with documentation addresses and the device omitted (resolved on the server side):

```
POST /quality-on-demand/v1/sessions
Authorization: Bearer <token>
{"applicationServer": {"ipv4Address": "203.0.113.7"},
 "applicationServerPorts": {"ports": [443]},
 "qosProfile": "QOS_E", "duration": 60}
→ 201 {"sessionId": "…", "qosStatus": "REQUESTED", …}
```

The adapter reports `AVAILABLE` once the first packet on the boost QFI is seen on N3 (or best-effort after 3 s), and `UNAVAILABLE` on delete, expiry or network termination. One Open5GS 2.8.0 quirk: there is one rule per 5QI per PDU session, so a "replace" is a DELETE followed by a CREATE.

## 7. Evidence

**How to read the evidence.** The target scenario is YouTube in a congested cell. Sections 7.1–7.4 show the pieces it depends on: the API works (7.1), the boost hits only the target flow (7.2), the lab is stable (7.3), and a boosted QUIC flow improves sharply in a congested cell (7.4, MGLT reflector flow only). **Section 7.5 reports the first YouTube results** (cloud lab round 3, n = 2 per arm) against the pre-registered pass criteria, including the gates that failed. Section 7.6 states the conclusion so far.

All data is sanitised (summaries only; no pcap, no identities) and lives in `docs/whitepaper/data/` of the repository; the sanitised conformance summary is in `docs/whitepaper/data/conformance/`. Claims follow the claim-to-evidence map in `docs/whitepaper/CLAIMS.md`.

### 7.0 How latency is measured

**Measured per packet, not estimated.** Latency in this paper comes from real timestamps of individual packets at two points:

1. **At the UE.** The booster app's examine-mode probe records when the UE sends or receives each packet.
2. **After the UPF, before the internet.** A Zeek capture at a tap on N6 (SGi in 4G terms) records when the same packet passes.

The two records are matched by a **per-packet hash** (computed over the first 64 bytes of the packet). The time difference between the matched records is the measured network latency, uplink (UE → N6) or downlink (N6 → UE).

**Accuracy bound.** One-way values are only as accurate as the clock synchronisation between the probe and the capture host: NTP/chrony, at millisecond level. There is no PTP. Differences below a few milliseconds should not be read as significant.

**Sampled capture windows (design constraint).** The Zeek capture does not run for the whole session. It runs for a few minutes of representative sampling, one window before the booster is active and one while boosted, because lab CPU is limited. This is a deliberate design choice, not a gap in the data. As a result, the latency figures describe the sampled windows, not the whole session.

**Scope today.** The probe hashes only **QUIC packets on UDP 443**. TCP packets are not yet measured per packet; per-packet TCP measurement support is being added now (work in progress, not a result; Section 9). In cloud lab round 3, the YouTube app used mostly QUIC, so the metric covers the video flow there, but it is not "all packets". The MGLT reflector flow uses QUIC on UDP 443, so it is fully in scope.

**Why we measure this way.** Simpler methods would not support the claims in this paper:

| Alternative | Why it is not enough here |
|---|---|
| **Ping (ICMP)** | ICMP stays on the default QoS flow (QFI 1) even during a boost (Section 7.2), so it does not measure the app's own boosted packets. |
| **Round-trip time (RTT)** | A single round-trip value hides the difference between uplink and downlink. Our lab shows that the two directions can differ a lot (median uplink 27 ms vs downlink about 9.7 ms in the on-premises session). |
| **Estimation or modelling** | An estimate is not evidence. The paper reports only what was captured. |

So we timestamp **the app's own packets** at the UE (the probe sees exactly what the target app sends and receives) and again **after the UPF, at N6/SGi** (where the operator network hands traffic to the internet), and match them **per packet**. That gives one-way uplink and downlink latency for the boosted flow itself, across the radio and the core. The cost is the clock-sync bound and the coverage limits stated above and in Section 8.

| Session | Setting | Result |
|---|---|---|
| **On-premises lab session, 17 Nov 2026** | Lab (not a live network); real-time paced emulated radio path, without the Android emulator | **100 % packet coverage**; median uplink **27 ms**, median downlink **about 9.7 ms** |
| **Cloud lab session (GCP), 19 Nov 2026** | Cloud lab round 1, with the Android emulator and YouTube as a target app | Round-1 MGLT values as reported in Section 7.4 (p99 5476 → 1548 ms under congestion, −72 %); no further figures are claimed |
| **Cloud lab round 3 (GCP), 20 Nov 2026** | Android emulator, YouTube app, 200 Mbit/s bulk; Zeek in two ~63 s windows per run (W1 before boost, W2 inside the boost window), about 10 % of one vCPU | YouTube DL one-way p50, W1 → W2 (Section 7.5, Table 7.5-C). MGLT-vs-Zeek joint values are excluded because of a 90–160 ms clock skew between the emulator and the core host |

Both sessions are lab sessions. Neither is a measurement on a live network. Limits of the method are listed in Section 8.

### 7.1 API conformance

<figure><img src="figures/F4-conformance.png"><figcaption>Figure 3. Conformance of adapter 0.1.2 against CAMARA QoD r4.3 and QoSProfiles r1.2 test definitions, by feature.</figcaption></figure>

- **126 passed / 0 failed / 1 skipped (127 total)**, plus **16/16** lab-extension tests (device binding, protocol header, filter budget, CIDR in address list, rate-limit `Retry-After`, event export).
- The skipped test is `PRIVATE_KEY_JWT` client authentication (no pre-shared JWKS in the lab; the adapter answers 422). This is a documented deviation.
- **Important:** these results use the **project's own runner, derived from the CAMARA Test_definitions**. It is **not** the official CAMARA Gherkin test harness, and the results are not a CAMARA certification.

### 7.2 Offline lab: the boost hits only the target flow

Five scenarios emulate how the booster app forwards and detects traffic: full tunnel (a1), examine one app (c1), split tunnel after a protocol fix (b2), and examine mode emulating the current app with an MGLT marker, with QoD for the target only (m3) or for the target plus the reflector (m4). Bulk traffic from the same UE (TCP up/down, UDP echo) and an ICMP keepalive run during every test.

<figure><img src="figures/F3-isolation-latency.png"><figcaption>Figure 4. Left: packets on the boost QFI during the steady phase. Every scenario has zero non-target packets. Right: API → first QFI 2 packet and DELETE → first QFI 1 packet (downlink).</figcaption></figure>

<figure><img class="narrow" src="figures/F3b-m4-qfi-timeline.png"><figcaption>Figure 5. Per-flow QFI timeline on N3 for scenario m4. Red = QFI 2 (boost), blue = QFI 1. Row labels are abbreviated server:port. "1:18080" is the target server (198.51.100.1), "3:9000" the MGLT reflector, and "2:52xx" the bulk server. Bulk flows and ICMP stay on QFI 1 throughout.</figcaption></figure>

| Scenario | Gate (DL+UL) | API → QFI 2 (DL/UL, ms) | DELETE → QFI 1 (DL, ms) | Non-target pkts on QFI 2 |
|---|---|---|---|---|
| a1 full tunnel | PASS | 48.1 / 47.6 | n/a (stock gNB, no DELETE) | 0 |
| c1 examine one app | PASS | 42.0 / 41.7 | 42.3 | 0 |
| b2 split tunnel | PASS | 37.2 / 30.8 | not measured | 0 |
| m3 examine, target only | PASS | 20.3 / 54.8 | 47.8 | 0 |
| m4 examine, target + reflector | PASS | 407 / 407* | 37.6 | 0 |

\* In m4 the first boosted packet was set by a 1-per-second TCP burst; UDP was faster. Typical activation across the scenarios is therefore 20–55 ms, and release is 38–48 ms. A re-run on the newer gNB build (qosrel4, scenarios q4-a1/a3/a4/b2) also passed 4/4, with zero non-target packets and apply times of 19–51 ms.

**Method note.** The offline scenarios drive traffic through a stand-in for the booster app's forwarder (the app's native forwarding code and lwIP built for the host) and scripted apps, not the Android APK. The cell was **not congested**, so these runs prove *correct targeting and timing*, not latency improvement. Latency improvement under congestion is in Section 7.4.

**API priority rule.** The booster app's own API calls can get stuck behind the same congestion they are trying to fix. A static PCC rule (5QI 69, ARP 1) for the booster app backend's address and port gets them through. Offline, under 150 Mbit/s load, CREATE took **43–54 ms** with the rule. Earlier run notes recorded **3.5–4 s** without it (raw data for the 3.5–4 s figure is not in the package).

### 7.3 Lab hardening

<figure><img src="figures/F5-soak-loss.png"><figcaption>Figure 6. Per-session packet loss over the offline soak runs (gNB slice-qosrel4).</figcaption></figure>

- **Single UE, 50 cycles under full load:** 50/50 cycles completed with 0 gNB asserts or crashes, 0 PDU session releases, 0 GTP Error Indications, UE IP unchanged and keepalive 864/864. Maximum per-session loss was 0.7 % DL and 0.4 % UL.
- **Two UEs in parallel, 20 cycles × 2:** 0 crashes, 0 PDU releases, 0 Error Indications. 39 of 40 sessions had loss ≤ 0.7 %; one session had 1.6 % DL loss, so the run's delivery verdict is FAIL against its own threshold.
- An earlier, shorter hardening run (5 cycles + 5 × 2 parallel sessions under load) reported 0 crashes, 0 PDU releases and loss ≤ 0.6 %. That figure comes from project run notes; its raw data is not in the package.
- Open items listed in the claim map: 9 "NULL TBS" gNB log errors (5 + 4 in these two soaks) and 2 self-recovering uplink failures remain. The duplicate-release (N2) code path was not exercised.

### 7.4 Cloud lab round 1: one congested cell

Setup: Open5GS 2.8.0 core, OAI gNB `slice-qosrel3`, adapter 0.1.1, booster app build `booster.3` on an Android emulator. A 400 Mbit/s UDP downlink load toward the same UE congested the cell (about 89–92 Mbit/s received, 76–78 % loss on the bulk flow). Latency was measured per packet on the **MGLT reflector flow** (a QUIC marker flow on UDP 443 from the booster app to the reflector, boosted together with the target), with the probe-to-N6 hash correlation described in Section 7.0. Clock accuracy is at millisecond level (NTP/chrony, no PTP).

**Result in one line:** in a lab that reproduces a congested cell, the flow boosted on demand met the round-1 target (p99 down by at least 50 %): **MGLT p99 fell 72 %**. This applies **only to the MGLT reflector flow**. It is not a YouTube result. It is evidence that the network mechanism works under congestion. The YouTube round 2 run produced no valid data; the YouTube results from round 3 are in Section 7.5.

<figure><img class="narrow" src="figures/F6-gcp-p99.png"><figcaption>Figure 7. MGLT latency (p50/p99) on one congested cell, without and with boost. Applies to the MGLT reflector flow only.</figcaption></figure>

| Condition | MGLT p50 (ms) | MGLT p99 (ms) | n |
|---|---|---|---|
| Idle cell, no load | 34.9 | 200.8 | 53 |
| Congested, no boost (reference window) | 4802 | 5476 | 68 |
| Congested, **boost on** | 969.6 | **1547.5** | 14 |
| **Change in p99 under load** | | **−72 %** | |

Further observations from round 1:

- **Activation:** backend returned 201 in 180 ms, adapter in 52 ms, and QFI 2 was observed 329 ms after the API call. The target flow ran on QFI ≠ 1 during the boost and on QFI 1 outside it. Bulk traffic always stayed on QFI 1.
- **Stalls:** the video player recorded 0 stalls during the boost and in the 10 s after the boost ended (one run). There was no playing baseline under load, so **this is not evidence of a YouTube improvement**.
- **API priority (static 5QI 69 rule):** with the rule, booster app API traffic ran on its own QoS flow under load, and a CREATE under load succeeded (1.95 s as seen by the app, 66 ms at the backend, 0 timeouts). The "without rule" comparison under load was not measured, so this is **partially proven**.
- **Stability:** across all runs, 0 Error Indications, 0 releases, 0 network-function crashes.
- **Sample sizes are small** (n = 14 boosted vs n = 68 reference samples), and there was one cell and one run per condition.

<style>p:has(+ table) { break-after: avoid; } .split table { break-inside: auto; } .split tr { break-inside: avoid; }</style>

### 7.5 YouTube in a congested cell — results

#### 7.5.1 Setup, deviations and provisioning disclosure

**Setup (cloud lab round 3, GCP, 20 Nov 2026).** Open5GS 2.8 core (patched UPF, PCF `qos_profiles`) and OAI gNB/nrUE (rfsimulator, MIMO 2) on one VM; an Android 16 emulator with the YouTube app on a second VM; the booster app (build v0.10.2-booster.4) in examine mode. Video: *Big Buck Bunny*. Load: UDP downlink bulk of 200 Mbit/s through the **same UE**. Four arms, **n = 2 each**, run interleaved (A1, N1, A2, N2, PA1, PN1, PA2, PN2):

| Arm | Play starts | QoD |
|---|---|---|
| **A** | under load (about 10 s after load starts) | booster app requests QoD at load + 90 s |
| **N** | under load | none (control) |
| **PA** | before load (about 42 s earlier) | booster app requests QoD at load + 90 s |
| **PN** | before load | none (control) |

**Deviations from the plan (all disclosed):**

1. **Load 200 Mbit/s, not 400 Mbit/s.** The cell carried about 104–109 Mbit/s downlink. At 400 Mbit/s the traffic generator on the UE ran out of memory and YouTube received no bytes at all, so that would not have been a QoD test. At 200 Mbit/s (about 1.9× the measured cell rate) congestion was still severe.
2. **Boost window taken from adapter events.** The window runs from the first `AVAILABLE` to the last delete of the QoD session (it started 6.7–13.2 s after the nominal load + 90 s). No-QoD arms use the nominal 90–240 s window.
3. **QoD was active only 54.6–88.2 s of each boost window.** The booster app's policy deletes the session when its measured flow loss drops below 5 %, waits a 30 s cooldown and re-creates it when loss returns. This left gaps of 34–52 s inside every boost window. Creating a session took 1–18 s to reach `AVAILABLE`.
4. **Zeek is sampled and QUIC-only.** Two windows of about 63 s per run (W1 = load + 25…88 s, W2 = load + 130…193 s), using about 10 % of one vCPU; QUIC on UDP 443 only.
5. **MGLT is excluded from the YouTube evidence.** MGLT round-trip values and Zeek one-way values come from different clocks with a 90–160 ms skew, so no joint numbers are reported, and the MGLT reflector is not used as YouTube evidence.
6. **Startup** is measured from the play tap. In PA/PN the tap is before load, so their startup (17–24 s) is an uncongested baseline and is not used for the startup criterion. **Resolution** is the rendered surface size, a proxy for the selected format.

**Provisioning disclosure.** No per-session or per-app manual configuration was used; one-time static provisioning is disclosed here:

- a static PCC rule, **5QI 69 / ARP 1**, for the booster app's **control API traffic only** (2 flows, applied at bring-up). It never carries YouTube, but it helps the QoD request itself get through under congestion;
- gNB scheduler configuration (`slice.conf`): `qod_5qi=80,4,69,7,1`, `qod_max_pct=70`, `be_max_pct=100`, `pbr_pct=20`;
- PCF `qos_profiles` (5 entries) and a patched UPF, installed at bring-up;
- a flowless **5QI 4 template** in the subscriber record, written by the adapter **directly to the subscriber database** (not via N5) on the first QoD request, because Open5GS 2.8 needs it to map an N5 media component to a 5QI.

**At runtime, per session,** the YouTube QoS flow was created only through the API path: booster app → CAMARA QoD API → adapter → BSF → N5 (Npcf_PolicyAuthorization) → a new dynamic QFI per session. There was no operator step per session.

#### 7.5.2 Results vs pre-registered criteria

The criteria were defined before the run (Section 7.5 in v0.6) and are reported unchanged.

<div class="split" markdown="1">

| Criterion (pre-registered) | Result | Verdict |
|---|---|---|
| YouTube bytes on the boosted QFI ≥ 80 % | Whole boost window: A1 80.1, A2 60.7, PA1 61.1, PA2 72.1 % (**1 of 4 runs pass**). Context: while QoD was `AVAILABLE` 75.6–96.5 % (2 of 4 ≥ 80 %) | **FAIL** (whole window) |
| Total stall time ≥ 50 % lower with QoD than without | PA vs PN: 34.0 / 7.1 s vs 150.1 / 130.1 s. A vs N: 5.0 / 30.8 s vs N2 115.1 s; N1 did not start within ~240 s, so its 0 s is not comparable. Non-playing time in the window: A 23 / 73 s vs N 149 / 143 s | **PASS** (every comparable pair at least 73 % lower) |
| Startup time not worse with QoD | From the play tap (under load): A1 111.9 s, A2 134.1 s; N2 109.0 s; N1 did not start within ~240 s. QoD became active at load + 103.2 s (A1) and + 97.6 s (A2); first play came 19–47 s after that, so most of the startup time passed before QoD existed. Startup succeeded in 2 of 2 runs with QoD vs 1 of 2 without (small n). PA/PN started before load and are not relevant here | **PARTIAL** (the data cannot show that QoD speeds up startup) |
| YouTube loss ≤ 5 % | Boost window, with QoD: 7.3–15.4 % (worst single flow 22.9–52.7 %); without QoD: 26.9–36.3 % | **FAIL** |
| Repetitions ≥ 2 per arm | n = 2 per arm | **PASS** (minimum only) |
| No crash or PDU release (stability check, carried from the lab gates) | `bad_total` = 0 in all 8 runs | **PASS** |
| Stall count; playback resolution; sampled latency | See Tables 7.5-A and 7.5-C | Reported only |

</div>

**Table 7.5-A. Playback in the boost window** (no-QoD arms: same nominal window).

| Run | Playing % | Stall s | Stall count | Resolution (mode, p) | Startup s from tap |
|---|---|---|---|---|---|
| A1 | 77.7 | 5.0 | 1 | 480 | 111.9 |
| A2 | 41.0 | 30.8 | 3 | 480 | 134.1 |
| PA1 | 74.2 | 34.0 | 2 | 360 | 21.7 (before load) |
| PA2 | 94.5 | 7.1 | 2 | 480 | 24.4 (before load) |
| N1 | 0.0 | 0 (did not start) | 0 | – | did not start within ~240 s |
| N2 | 4.0 | 115.1 | 1 | 360 | 109.0 |
| PN1 | 0.0 | 150.1 | 0 | 480 | 21.6 (before load) |
| PN2 | 13.3 | 130.1 | 1 | 360 | 17.3 (before load) |

**Table 7.5-B. YouTube downlink bytes on the boosted QFI.**

| Run | Boost window s | QoD available s | Bytes on boost QFI, whole window | Bytes on boost QFI, while QoD available |
|---|---|---|---|---|
| A1 | 103 | 83.9 | 80.1 % | 95.4 % |
| A2 | 124 | 88.2 | 60.7 % | 79.0 % |
| PA1 | 143 | 54.6 | 61.1 % | 75.6 % |
| PA2 | 142 | 74.5 | 72.1 % | 96.5 % |
| N1, N2, PN1, PN2 | 149–150 | 0 | 0 % | – |

**Table 7.5-C. Zeek per-packet YouTube DL one-way latency (QUIC, sampled windows).**

| Run | W1 p50 ms (before boost) | W2 p50 ms (boost window) | W2 share under QoD | W2 packets under QoD: p50 / p95 ms | W2 packets without QoD: p50 ms |
|---|---|---|---|---|---|
| A1 | 4228.9 | **1027.3** | 46 % | 1019.3 / 1128.9 | 4192.5 |
| A2 | 4164.2 | **944.6** | 49 % | 943.0 / 2058.1 | 4195.7 |
| PA1 | 4152.2 | 4098.6 | 17 % | 3980.9 / 4045.6 | 4115.0 |
| PA2 | 3911.4 | **723.2** | 24 % | 721.6 / 761.8 | 3953.0 |
| N1 / N2 | 4182.7 / 4018.7 | 4271.4 (n = 1) / 4060.0 | 0 % | – | 4271.4 / 4060.8 |
| PN1 / PN2 | 3977.4 / 3970.5 | 3997.9 / 3929.4 | 0 % | – | 3999.8 / 3929.4 |

*Note: percentiles use the nearest-rank method.*

**Table 7.5-D. YouTube downlink loss and throughput.**

| Run | Loss before boost | Loss in boost window | Worst flow in boost window | Throughput before → boost window (Mbit/s) |
|---|---|---|---|---|
| A1 / A2 | 28.4 / 30.2 % | 7.3 / 13.6 % | 28.3 / 24.2 % | 0.09 → 1.09 / 0.09 → 0.23 |
| PA1 / PA2 | 20.8 / 11.4 % | 15.4 / 9.3 % | 52.7 / 22.9 % | 0.47 → 0.44 / 0.46 → 0.53 |
| N1 / N2 | 25.3 / 26.9 % | 26.9 / 31.7 % | 28.6 / 32.0 % | 0.08 → 0.03 / 0.08 → 0.05 |
| PN1 / PN2 | 29.1 / 32.1 % | 34.3 / 36.3 % | 37.5 / 40.5 % | 0.33 → 0.09 / 0.19 → 0.11 |

**Stability:** `bad_total` (crashes, PDU releases, error lines in AMF, SMF, UPF, PCF, gNB, adapter and backend) was 0 in all 8 runs.

<figure><img src="figures/F7-playing-stall.png"><figcaption>Figure 8. YouTube playing share and stall seconds in the boost window, QoD arms (A, PA) vs no-QoD arms (N, PN). Cloud lab round 3, n = 2 per arm. N1 did not start within ~240 s, so its 0 s stall is not a good result.</figcaption></figure>

<figure><img src="figures/F8-zeek-p50-w1-w2.png"><figcaption>Figure 9. Zeek per-packet YouTube DL one-way latency p50, W1 (before boost) vs W2 (boost window), QUIC on UDP 443, sampled windows. PA1's W2 was mostly outside QoD (Section 7.5.3).</figcaption></figure>

<figure><img src="figures/F9-A1-before-during-redacted.png"><figcaption>Figure 10. Run A1, YouTube app on the emulator. Left, load + 100 s (200 Mbit/s, about 1.9× the cell capacity of ~104–109 Mbit/s): QoD not yet active, player black, playback not yet started (A1 began playing at load + 121.9 s). Right, load + 190 s: QoD session available, YouTube CDN /20 on the boost QFI, video playing at 480p. Comments redacted; no account is shown.</figcaption></figure>

#### 7.5.3 Interpretation and limitations

- **A vs N is a cross-run comparison.** A and N runs are separate sessions, run interleaved on the same lab. With play started under load, both A runs began playing only 19–47 s after QoD became active (load + 103.2 / + 97.6 s), so most of their startup time passed before QoD existed; the data does not show that QoD shortens startup. One N run did not start within ~240 s, and the other stalled 115 s of the 149 s window.
- **PA vs PN is a same-session comparison.** Playback started before load, then load and (in PA) QoD were added. PA rose from 26–34 % playing before the boost to 74–95 % in the boost window; PN fell to 0–13 %.
- **Why PA1 shows no latency gain (4152 → 4099 ms).** QoD covered only 17 % of PA1's W2, because of a session gap. When the new session came up, YouTube had moved to a CDN server outside the session's packet filters, so its bytes stayed on the default flow until the next rotation. Whenever YouTube's bytes were actually on the boosted QFI (A1, A2, PA2), packet p50 was 0.72–1.02 s vs 3.9–4.3 s without. This explanation comes from the run logs; it was not tested separately.
- **The remaining delay under QoD is still about 0.7–1 s.** The boosted QFI shares a congested emulated cell with a 200 Mbit/s flood, and `qod_max_pct=70` caps the QoD share at the gNB.
- **The booster app's on/off policy dilutes the results.** It is the main reason the ≥ 80 % bytes gate failed over the whole window (Table 7.5-B). Fixing it is a booster-app policy change, not a network change (Section 9).
- **Small n.** n = 2 per arm, one cell, one video, one time of day, one cloud region. The effects are large and in the same direction in all 4 QoD runs vs all 4 no-QoD runs, but no confidence intervals or significance tests are justified.
- **Load 200 Mbit/s instead of 400 Mbit/s** (deviation 1). **Latency is sampled and QUIC-only** (about 63 s windows, millisecond-level clock sync). **QoD was on only 54.6–88.2 s per window** (deviation 3).

### 7.6 Conclusion so far

In a saturated lab cell (about 104–109 Mbit/s of downlink capacity, with 200 Mbit/s of bulk traffic on the same device), YouTube without QoD barely played (0–13 % of the window). With the booster app requesting CAMARA QoD, it played 41–94 % of the window, and median downlink packet latency fell about 4–5× in 3 of 4 boosted runs (n = 2 per arm). The pre-registered gates were only partly met: loss stayed at 7–15 %, and the ≥ 80 % bytes gate was missed over the whole window in 3 of 4 runs. The network mechanism is the same one shown in Sections 7.1–7.4. The loss and byte-share gaps point mainly to the booster app's session policy (on/off cycling, CDN coverage), which is the next thing to fix. All results are lab results; nothing has run on a live network yet.

## 8. Honest limitations

Lintas5G is intended for live networks, and the lab is the validation stage that must come first. The limitations below describe what that stage has and has not shown yet.

| Limitation | Impact on claims |
|---|---|
| **Lab only, emulated radio** (OAI rfsimulator / vrtsim, Open5GS, synthetic subscribers) | No claim about live radio conditions, commercial RAN schedulers or real devices |
| **Single cell, one congested-cell run per condition**, small samples (n = 14 boosted) | −72 % p99 is a lab data point, not a statistical guarantee |
| **Same-device scope** | Proven: one app protected from bulk traffic on the same device. Not tested: priority between devices or subscribers |
| **Own conformance runner** | 126/0/1 is derived from CAMARA Test_definitions, not the official Gherkin harness; not a certification |
| **YouTube evidence is small and only partly meets the gates** | Round 3: n = 2 per arm, one cell, one video, 200 Mbit/s load instead of 400 Mbit/s. YouTube loss stayed at 7–15 % (gate ≤ 5 %); ≥ 80 % bytes on the boosted QFI was met over the whole window in 1 of 4 runs (Section 7.5). Round 2 produced no valid data |
| **API prioritisation only partly proven in the cloud lab** | Static 5QI 69 rule works; no-rule comparison under load not measured |
| **Version deviation** | Cloud round 1 used booster.3 + gNB `qosrel3` + adapter 0.1.1; offline results use gNB `qosrel4`; conformance is on adapter 0.1.2; cloud round 3 used booster app build v0.10.2-booster.4 |
| **Offline scenarios used a forwarder stand-in** and an uncongested cell | Proves targeting and timing, not user-visible latency gains |
| **Not validated on any live network** | Live behaviour (4G NSA, commercial 5G SA) is future work |
| **Patches not upstreamed** | gNB/UPF fixes used by the lab are not yet accepted upstream |
| **Booster app APK and source not in the public repo** | Only the sha256 is published; partners need it from the app team |
| **QoD adapter source is private** | The adapter (CAMARA QoD to N5) is not in the public repository. The public repository provides the lab IaC, configs, test scripts, sanitised data (including the conformance summary) and the method, but full reproduction of the API path needs the adapter, available to partners on request: [PARTNER CONTACT – TBD] |
| **Latency probe covers QUIC (UDP 443) only** | In round 3 the YouTube app used mostly QUIC, so the video flow is covered, but TCP packets are not; per-packet TCP measurement support is being added now (work in progress) |
| **Radio-side (N3) tap coverage drops under load** | Packet coverage at the N3 tap falls to 86–96 % under load, so per-packet results under congestion are based on a subset of packets |
| **Millisecond-level clock accuracy** | Probe and capture clocks are synchronised with NTP/chrony, not PTP; one-way latency is accurate to milliseconds only |
| **Hash over the first 64 bytes** | Identical or fragmented packets can be missed or mis-matched (hash collisions) |
| **Booster app policy cycles QoD on and off** | The session is deleted when flow loss falls below 5 % and re-created after a 30 s cooldown; QoD was active only 54.6–88.2 s per boost window, which dilutes window-level results |
| **One-time static provisioning** | The lab uses static QoS profiles, gNB scheduler weights per 5QI, a 5QI template written directly to the subscriber database, and a static priority rule for the booster's control API (Section 7.5.1). Per session, nothing is configured manually |
| **MGLT vs Zeek not combined** | Different clocks with a 90–160 ms skew; the MGLT reflector is not used as YouTube evidence |
| **Consent, API-consumer and net-neutrality model not validated** | Production consent flows (CAMARA ICM), the commercial API-consumer role and regulatory fit are design positions only (Section 4.6), not tested with any operator or regulator |

## 9. Roadmap

The destination is live networks. Every phase before the live pilot exists to make that pilot safe and convincing.

| Phase | Goal | Key next steps |
|---|---|---|
| **Now: open lab (v0.7.2)** | Reproducible proof of mechanism (required validation stage) | Publish tagged package; partner reproductions; add adapter design notes |
| **Next: lab validation** | Close the evidence gaps, starting with the main use case | **YouTube in a congested cell, next round (priority):** fix the booster app's session policy (keep QoD on while congestion lasts; wider CDN coverage after rotation) to meet the ≥ 80 % bytes and ≤ 5 % loss gates; more repetitions than n = 2; the planned 400 Mbit/s load once the traffic generator allows it; per-packet TCP measurement (being added now); gaming validation with `QOS_E`; no-rule vs rule API comparison; measurement fixes: IPv4 probe support and moving the tap after the traffic shaper (pending), with TCP probe support in progress |
| **Then: scale-out lab** | More realistic radio | Multi-cell, multi-UE contention, inter-device scenarios |
| **Sandbox** | Operator-hosted CAMARA endpoint | Consent and 3-legged token flows; operator sandbox trials |
| **Live pilot** | First live-network deployment | Live pilot with a partner operator (5G SA via N5, or 4G NSA via Rx/PCRF; see 4.5); KPIs compared with manual tuning; business-model tests (H1–H4) |
| **Live operation** | Quality on demand on live networks | Telco app store / CAMARA marketplace listing; app-partner (B2B2C) programmes; more operators via the same standard API |

**API roadmap: closing the tuning loop.** Manual tuning is a loop: observe, decide, apply, verify. Lintas5G plans to automate it with CAMARA APIs that are already published [22]:

1. **Observe/decide:** *Connectivity Insights* 0.7.0, to check whether the network can meet the app's needs and whether a boost is needed at all.
2. **Apply:** *Quality on Demand* 1.2.0 with *QoS Profiles* 1.2.0, for the on-demand boost (in the lab today).
3. **Plan:** *QoS Booking* 0.2.0, to reserve quality ahead of scheduled events (for example a broadcast or a match).
4. **Describe the app:** *Application Profiles* 0.6.0, to state an app's network requirements once instead of per request.
5. **Verify:** before/after measurement, as in Section 7.

Apart from QoD and QoS Profiles, these are initial (0.x) CAMARA versions, and none is implemented in the Lintas5G lab yet.

After YouTube, the main use case, the lab scenario set will grow to secondary scenarios: video call, gaming, a **broadcast-style video uplink** and a **payment transaction under congestion**, the verticals with public QoD evidence (Section 2).

## 10. Anticipated questions (FAQ) {: .pb }

Short answers, based only on what this paper and its sources show. Where something has not been measured, we say so.

### The main use case

**Has YouTube been proven?** Partly, in the lab. In cloud lab round 3 (n = 2 per arm), YouTube without QoD played 0–13 % of the window, and with the booster app requesting QoD it played 41–94 %, with median DL packet latency about 4–5× lower in 3 of 4 boosted runs. Two pre-registered gates failed: loss stayed at 7–15 % (gate ≤ 5 %), and the ≥ 80 % bytes gate was met over the whole window in only 1 of 4 runs. It is a small sample on one emulated cell, not a live-network result (Section 7.5).

**Then what does the −72 % show?** That the network mechanism works under congestion: in the same congested cell, the boosted MGLT reflector flow (QUIC on UDP 443) had its p99 latency cut by 72 %. It is not a YouTube number (Section 7.4); the YouTube numbers are in Section 7.5.

**Why YouTube as the main example?** It is an everyday consumer app that every reader knows, a congested cell in a traffic jam is a moment anyone recognises, and it runs unmodified, which is what the booster app is designed for.

### Measurement

**How accurate are the one-way latency numbers?** To milliseconds only. The probe and the capture host are synchronised with NTP/chrony, not PTP. Differences of a few milliseconds are within that bound; the large effects reported (seconds under congestion) are far above it (Section 7.0).

**Are TCP apps measured?** Not yet per packet. The probe covers QUIC on UDP 443 only. Per-packet TCP measurement support is being added now (work in progress, not a result). In round 3 the YouTube app used mostly QUIC, so its video flow was covered; TCP traffic was not.

**Why not just use ping or RTT?** Ping uses ICMP, which stays on the default flow during a boost, so it does not see the app's boosted packets. RTT hides uplink/downlink asymmetry. See "Why we measure this way" (Section 7.0).

**What does the probe cost on the device (CPU, battery)?** Not yet measured (to be measured). We make no claim about probe overhead.

**How complete is the capture?** 100 % packet coverage in the on-premises lab session. At the radio-side (N3) tap, coverage drops to 86–96 % under load. Hashing the first 64 bytes can miss or mis-match identical or fragmented packets (Section 8).

### For operators

**Does QoD need 5G SA?** No. Public commercial QoD launches already run on 4G and 5G NSA [13][20]. Our lab is 5G SA (N5 to PCF via BSF). The 4G/NSA path via Rx/PCRF is assumed, not tested (Section 4.5).

**Who pays?** In our B2B2C position, app and enterprise partners pay the operator or an aggregator; consumers are not the direct payer. The pricing models (H1–H4) are hypotheses (Section 4.2).

**Does a boost give one subscriber priority over others?** Not shown. We proved protection of one app against bulk traffic on the **same device**. Priority between devices or subscribers was not tested: inter-device scenarios were not part of the lab runs. Multi-UE contention and inter-device scenarios are on the roadmap (Section 9).

**Is any manual configuration needed?** No per-session or per-app manual configuration: in round 3, each YouTube QoS flow was created on demand through the CAMARA QoD API and N5. The lab does use one-time static provisioning, all disclosed in Section 7.5.1: QoS profiles in the PCF, a 5QI template written to the subscriber database, gNB scheduler weights per 5QI, and a static priority rule for the booster's control API.

**Does this depend on the RAN vendor's scheduler?** Yes. The boost only helps if the gNB scheduler honours the 5QI of the dedicated QoS flow. The lab used OAI gNB v3.0.0 with project patches and a static scheduler configuration that favours the QoD 5QIs (Section 7.5.1); commercial RAN schedulers were not tested (Section 8).

**How is the lab different from a live network?** Emulated radio, one cell, synthetic subscribers, and load generated in the lab. The on-premises and cloud sessions are lab sessions, not live-network measurements. Live behaviour is future work (Section 8).

**What about net neutrality?** European regulators assess network APIs that give applications differentiated QoS under open-internet rules [15]. We have not assessed any specific jurisdiction. Our design position: user- or partner-initiated, time-limited (≤ 3600 s), standard profiles, scoped to one app's flows (Section 4.6).

### For app developers

**Why the booster app instead of direct integration?** The booster app shows, with no code change, what an existing app would get from QoD, so the value can be seen before anyone refactors. Production apps integrate CAMARA QoD directly or through an SDK, using the same API and profiles (Section 5).

**Is user consent handled?** Not in production terms yet. Production use must follow CAMARA Identity and Consent Management, including 3-legged flows where the operator requires consent (Section 4.6). The lab uses OAuth 2.0 client credentials.

**What happens to my app's data?** Packets are correlated by a hash of their first 64 bytes. Published data contains summaries only: no payload, no pcap and no subscriber identities, and IP addresses are documentation addresses.

### For researchers and vendors

**Is the conformance result official?** No. The 126 pass / 0 fail / 1 skip comes from the project's own runner derived from CAMARA Test_definitions, not the official Gherkin harness. It is not a certification (Section 7.1).

**Can I reproduce the results?** Partly from the public repository alone. The repository is Apache-2.0 and provides the lab IaC, configs, test scripts, `docs/whitepaper/` (REPRODUCE, VERSIONS, CLAIMS, sanitised data) and the method [7]. The QoD adapter source (CAMARA QoD to N5) is private and not published; full reproduction of the API path needs the adapter, available to partners on request: [PARTNER CONTACT – TBD]. The booster app APK and source are not yet in the public repository either; only the sha256 is published (Section 8).

**How strong is the statistical evidence?** Limited. Round 1 has one cell, one run per condition and small samples (n = 14 boosted vs n = 68 reference). The −72 % is a lab data point, not a guarantee (Section 7.4). Round 3 (YouTube) has n = 2 per arm: the effects are large and consistent in direction, but no significance tests are justified (Section 7.5.3).

## 11. Call to action and feedback

We want measurable signals on whether this is worth taking from the lab to sandbox and live pilot. Please respond through one of the channels below.

| Audience | Ask | Channel |
|---|---|---|
| **Telco operators** (especially in Southeast Asia, where public QoD launches are still rare): *run the lab with us before your first QoD launch* | Express pilot or partner interest (sandbox, 5G SA or 4G NSA pilot) | [PARTNER CONTACT – TBD] |
| **API aggregators and network-API platforms** | Run a QoD demonstration with us; list or route QoD for partner apps | [PARTNER CONTACT – TBD] |
| **App developers** | Request lab access or early-sandbox access | [LAB ACCESS FORM URL – TBD] |
| **Researchers / community** | Reproduce, report issues, propose extensions | GitHub: <https://github.com/dayat81/Lintas5G> → Issues and Discussions |

**Signals we will track (draft targets to be set):** number of operator pilot or partner expressions of interest, number of developer access requests, and number of external reproductions or issues opened.

### Questions for operators

1. Would you expose CAMARA QoD to the booster app, as a demonstration client, in a sandbox within the next 12 months? What would block it?
2. Which partner business model (H1 per-session for partners, H2 partner bundle, H3 outcome-based, H4 revenue share) fits your portfolio best, and why?
3. Is a 4G NSA pilot (Rx/PCRF, dedicated bearer) more realistic for you than 5G SA (N5) today?
4. What evidence would you need before a live pilot (e.g. multi-cell, inter-device impact, KPIs)?
5. How much expert effort does manual application performance tuning cost you today, per app or per year?

### Questions for app developers

1. Which of your user moments suffer most from congestion (calls, live video, gaming, uploads)? Have you ever had an operator tune the network for your app?
2. Would you first demonstrate QoD for your app with the booster app (no code change) before a direct CAMARA integration or SDK?
3. Would you pay for QoD sessions for your users (B2B2C, billed to you by the operator or an aggregator)? Per minute, per session, as a bundle, or per outcome?
4. What would you need from the API (profiles, callbacks, SNI/subnet targeting) to integrate directly?

### Questions for API aggregators

1. Would you route CAMARA QoD from the lab (and later a sandbox) to show partner apps a before/after result?
2. Which partner verticals ask you for network quality today, and what evidence do they need?
3. Which billing model can you support for partners (per minute, per session, bundle, outcome-based)?

### Questions for researchers

1. Which additional scenarios (multi-cell, inter-device, QUIC-heavy apps) would make the evidence convincing to you?
2. Using REPRODUCE.md (and, for the API path, the adapter provided to partners on request), can you reproduce the conformance and offline results? What failed?
3. Would you contribute to an open, official-harness conformance run or to upstreaming the patches?

## 12. References

1. CAMARA Project, *QualityOnDemand* API repository (quality-on-demand 1.2.0 in public release r4.3, 19 Nov 2026; Test_definitions). <https://github.com/camaraproject/QualityOnDemand/releases> · *QoSProfiles* repository (qos-profiles 1.2.0 in r1.2, 15 Nov 2026). <https://github.com/camaraproject/QoSProfiles/releases>
2. Open5GS, open-source 5G core and EPC. <https://open5gs.org> · <https://github.com/open5gs/open5gs>
3. OpenAirInterface Software Alliance, OAI 5G RAN (gNB, nrUE, rfsimulator). <https://openairinterface.org> · <https://gitlab.eurecom.fr/oai/openairinterface5g>
4. 3GPP TS 29.514, *5G System; Policy Authorization Service; Stage 3* (Npcf_PolicyAuthorization). <https://www.3gpp.org/DynaReport/29514.htm>
5. 3GPP TS 29.214, *Policy and Charging Control over Rx reference point* (for the 4G NSA path). <https://www.3gpp.org/DynaReport/29214.htm>
6. A. Salkintzis (Motorola Mobility / Lenovo), *A QoD Transformation Function for Open5GS*, ETSI SDG OpenOP contribution OOP(26)003008, 22 July 2026. <https://docbox.etsi.org/SDG/OOP/05-CONTRIBUTIONS/2026/OOP(26)003008_A_QoD_Transformation_Function_for_Open5GS.pdf>
7. Lintas5G Project, public repository (Apache-2.0), including `docs/whitepaper/` (REPRODUCE, VERSIONS, CLAIMS, data) and the lab IaC; the QoD adapter source is not included. <https://github.com/dayat81/Lintas5G>
8. IETF RFC 5737, *IPv4 Address Blocks Reserved for Documentation*. <https://www.rfc-editor.org/rfc/rfc5737>
9. GSMA, *From Ambition to Execution: How Open Gateway Is Scaling the Global API Economy*, 4 March 2026. <https://www.gsma.com/newsroom/article/from-ambition-to-execution-how-open-gateway-is-scaling-the-global-api-economy/>
10. Mobile Ecosystem Forum, *The QoD API Market: Quality, But Not So Much Quantity*, 23 September 2026. <https://mobileecosystemforum.com/2026/09/23/the-qod-api-market-quality-but-not-so-much-quantity/>
11. GSMA, *Indonesian Telecom Operators to Launch Three Service APIs Through the GSMA Open Gateway Initiative*, 22 February 2024. <https://www.gsma.com/newsroom/press-release/enhancing-security-and-customer-experience-indonesian-telecom-operators-to-launch-three-service-apis-through-the-gsma-open-gateway-initiative/>
12. Telkomsel, *Telkomsel, IOH, and XLSMART Launch Joint Telco API Alliance Initiative*, 20 September 2025. <https://www.telkomsel.com/en/about-us/news/telkomsel-ioh-and-xlsmart-launch-joint-telco-api-alliance-initiative-enhance-security>
13. Mobile Time, *Claro lança API de qualidade sob demanda (QoD) do Open Gateway*, 7 July 2026. <https://www.mobiletime.com.br/noticias/07/07/2026/api-de-qod-claro/>
14. GSMA, *Why monetisation is the make-or-break challenge for network APIs in 2026*. <https://www.gsma.com/solutions-and-impact/gsma-open-gateway/why-monetisation-is-the-make-or-break-challenge-for-network-apis-in-2026/>
15. BEREC, *Further Guidance on 5G Network Slicing*, BoR (26) 84, June 2026, section 2.3. <https://www.berec.europa.eu/system/files/2026-06/BoR%20%2826%29%2084_Further%20Guidance%20on%205G%20Network%20Slicing.pdf>
16. GSMA, *45,000 Fans, One Congested Network, and a Radio That Did Not Drop*, 4 November 2026. <https://www.gsma.com/solutions-and-impact/gsma-open-gateway/gsma_resources/45k-fans-qod-live-broadcast/>
17. GSMA, *What Have APIs Ever Done for Me: Three Years of GSMA Open Gateway*. <https://www.gsma.com/solutions-and-impact/gsma-open-gateway/three-years-gsma-open-gateway-network-api-economy/>
18. Nokia, *Drive into the future with Network as Code* (Elisa and Elmo). <https://www.nokia.com/blog/drive-into-the-future-with-network-as-code-elisa-and-elmo-cars/>
19. SoftBank Corp., *Autonomous Thinking Distributed Core Routing*, 11 March 2026. <https://www.softbank.jp/en/corp/news/press/sbkk/2026/20260311_01/>
20. Telecoms.com, *Vodafone launches Quality on Demand API in Germany*, 7 September 2026. <https://www.telecoms.com/network-software/vodafone-launches-quality-on-demand-api-in-germany>
21. T-Mobile DevEdge, *Quality on Demand*. <https://devedge.t-mobile.com/qod>
22. CAMARA Project releases: ConnectivityInsights r4.3 <https://github.com/camaraproject/ConnectivityInsights/releases> · QoSBooking r2.3 <https://github.com/camaraproject/QoSBooking/releases> · ApplicationProfiles r2.3 <https://github.com/camaraproject/ApplicationProfiles/releases>
23. GSMA Intelligence, *GSMA Open Gateway: State of the Market, H2 2024* (developer pricing preferences). <https://eu-assets.contentstack.com/v3/assets/blt23eb5bbc4124baa6/blt85b8246f902c5786/6761e86ae2ba1d6d60f7629b/111224-Open-Gateway-State-of-the-Market-H2-2024.pdf>

<p class="small"><i>Draft v0.7.2 (supersedes v0.1–v0.7.2). Results are lab results and may change. Trademarks belong to their owners; YouTube is named only as the main target app of the lab; the YouTube results are small-sample lab results (n = 2 per arm). Feedback is welcome through the channels in Section 11.</i></p>
