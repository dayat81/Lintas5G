#!/usr/bin/env python3
"""Item 5 summary vs GATES-r4 FROZEN v1.1 G6 (+ steering: goodput >= 95% of profile target; non-GBR target = min(target, offered))."""
import json, statistics as st
S = [json.loads(l) for l in open("../run/sink.jsonl")]
PROF = {"QOS_L": ("GBR", 10.0, 20.0), "QOS_E": ("non-GBR", None, 10.0)}   # (type, targetMinDownstreamRate, maxDownstreamRate) Mbit/s, profiles.yaml
OFFERED = 15.0
c0 = lambda x: max(0.0, x) if x is not None else None
def target(p): t, g, m = PROF[p]; return g if t == "GBR" else min(m, OFFERED)
L = ["# Item 5 — Multi-UE A/B via CAMARA API (n5 lab, 1 sel rfsim 106 PRB, 2 UE)", "",
     "Beban per UE (identik untuk UE1 dan UE2, simultan): BE bulk DL UDP 150 Mbit/s (port AS 5211/5221, default QFI) + flow DL UDP 15 Mbit/s di port sesi (18081/18082) + probe RTT UDP 50 pps ke AS 18080. Kapasitas DL sel terukur ±110–150 Mbit/s → sel padat (probe tanpa QoD p99 ±5,5 s, loss ±20%).",
     "Fase per ulangan: BASE (tanpa sesi), lalu QOD (UE1: `POST /sessions` QOS_L ports 18080,18081 lewat client booster-client; UE2: tanpa sesi). Window metrik: t0+4 s (+1,5 s setelah create) s/d t_end−2 s. Durasi 25 s. 3 ulangan penuh. PAR: UE1 QOS_L + UE2 QOS_E paralel (client berbeda), 3 ulangan.",
     "Loss flow iperf3 negatif (paket terlambat dari interval sebelum window) di-clamp ke 0.", "",
     "## A/B (fase QOD, sel & waktu sama)", "",
     "| rep | UE1 QoD probe loss % | UE1 QoD flow loss % | UE1 probe p99 ms | UE2 (tanpa QoD) probe p99 ms | Δp99 UE1 vs UE2 | UE1 goodput flow sesi Mbit/s | target (QOS_L GBR) | % target | % offered | BASE p99 UE1 / UE2 ms |",
     "|---|---|---|---|---|---|---|---|---|---|---|"]
loss, red, gp = [], [], []
for r in (1, 2, 3):
    d = json.load(open(f"res/ab-r{r}/result.json")); q, b = d["qod"], d["base"]
    pl, fl = q["ue1"]["probe"]["loss_pct"], c0(q["ue1"]["qf"]["loss_pct_window"]); loss += [pl, fl]
    p1, p2 = q["ue1"]["probe"]["p99_ms"], q["ue2"]["probe"]["p99_ms"]; dr = 100 * (1 - p1 / p2); red.append(dr)
    g = q["ue1"]["qf"]["goodput_mbps"]; t = target("QOS_L"); gp.append(100 * g / t)
    L.append(f"| {r} | {pl:.3f} | {fl:.3f} | {p1:.1f} | {p2:.1f} | −{dr:.1f}% | {g:.2f} | {t:.0f} | {100*g/t:.0f}% | {100*g/OFFERED:.1f}% | {b['ue1']['probe']['p99_ms']:.0f} / {b['ue2']['probe']['p99_ms']:.0f} |")
L += ["", "## Sesi paralel (UE1 QOS_L + UE2 QOS_E)", "",
      "| rep | UE | sessionId | callback di sink (path) | probe loss % | flow loss % | probe p99 ms | goodput Mbit/s | target | % target | QFI sesi di N3 (paket) | paket UE ini di QFI sesi UE lain |", "|---|---|---|---|---|---|---|---|---|---|---|---|"]
iso_ok = cb_ok = True
for r in (1, 2, 3):
    d = json.load(open(f"res/par-r{r}/result.json"))["par"]; cnt = d["n3_ue_qfi_counts"]
    qfis = {}
    for k, n in cnt.items():
        ue, q, _ = k.split("|"); q = q.split("=")[1]
        if q != "1" and ue != "other": qfis.setdefault(ue, {}); qfis[ue][q] = qfis[ue].get(q, 0) + n
    for a in d["api"]:
        u = a["who"]; other = "ue2" if u == "ue1" else "ue1"
        ev = [e for e in S if ((e.get("body") or {}).get("data") or {}).get("sessionId") == a["sessionId"]]
        t0, t1 = min(e["t"] for e in ev), max(e["t"] for e in ev)
        wrong = [e for e in S if e["path"] == a["sink"] and t0 <= e["t"] <= t1 and e["body"]["data"]["sessionId"] != a["sessionId"]]
        seq = [e["body"]["data"]["qosStatus"] + ("/" + e["body"]["data"]["statusInfo"] if e["body"]["data"].get("statusInfo") else "") for e in ev]
        ok_cb = seq == ["AVAILABLE", "UNAVAILABLE/DELETE_REQUESTED"] and all(e["path"] == a["sink"] for e in ev) and not wrong; cb_ok &= ok_cb
        leak = sum(n for q, n in qfis.get(u, {}).items() if q in qfis.get(other, {}))
        iso_ok &= leak == 0 and len(qfis.get(u, {})) == 1
        x = d[u]; g = x["qf"]["goodput_mbps"]; t = target(a["profile"]); fl = c0(x["qf"]["loss_pct_window"])
        loss += [x["probe"]["loss_pct"], fl]; gp.append(100 * g / t)
        L.append(f"| {r} | {u} {a['profile']} | `{a['sessionId']}` | {' → '.join(seq)} ({a['sink']}){'' if ok_cb else ' **SALAH**'} | {x['probe']['loss_pct']:.3f} | {fl:.3f} | {x['probe']['p99_ms']:.1f} | {g:.2f} | {t:.0f} | {100*g/t:.0f}% | {qfis.get(u)} | {leak} |")
L += ["", "## Penilaian G6 (FROZEN v1.1)", "",
      f"- Loss sesi QoD (probe + flow sesi, 12 nilai: 3 A/B + 6 sesi paralel): median {st.median(loss):.3f}% (≤1%), maks {max(loss):.3f}% (≤5%) → **{'PASS' if st.median(loss) <= 1 and max(loss) <= 5 else 'FAIL'}**",
      f"- p99 UE QoD vs UE tanpa QoD (sel & waktu sama): turun {min(red):.1f}–{max(red):.1f}% (≥50%) → **{'PASS' if min(red) >= 50 else 'FAIL'}**",
      f"- Goodput flow sesi ≥95% target profil (GBR → targetMinDownstreamRate; non-GBR → min(maxDownstreamRate, offered)): {min(gp):.0f}–{max(gp):.0f}% → **{'PASS' if min(gp) >= 95 else 'FAIL'}**",
      f"- Isolasi QFI (tiap UE satu QFI sesi, 0 paket di QFI UE lain): **{'PASS' if iso_ok else 'FAIL'}**; callback per sessionId di path sink milik UE tsb, tanpa tertukar: **{'PASS' if cb_ok else 'FAIL'}**",
      "- 3 ulangan penuh A/B + 3 ulangan paralel: ya.", "",
      "## Pengungkapan",
      "- Diferensiasi antar-UE bergantung pada **modifikasi RAN**: gNB OAI v3.0.0 + patch `slice-qosrel4` (policy DL slice QoD, `slice.conf`: enabled=1, qod_5qi=2,3,4,7,69,80, qod_max_pct=70, be_max_pct=100, pbr_pct=20). Tanpa patch, scheduler PF OAI membagi rata (Fase 0).",
      "- UPF Open5GS tidak menegakkan MBR: flow QOS_E (maxDownstreamRate 10 Mbit/s) mengalir 15 Mbit/s (offered). Goodput dinilai terhadap min(10, 15) = 10.",
      "- BE bulk UE1 tidak ikut terdongkrak (±40–45 Mbit/s di BASE dan QOD) — prioritas terbatas pada flow sesi (QFI sesi).",
      "- Probe tanpa QoD p99 ±5,5 s mencerminkan antrean RLC gNB yang dalam di rfsim pada beban 2×165 Mbit/s; angka absolut bukan representasi RAN komersial.",
      "- Pilot `res/pilot-q69/` (20 s, sebelum ulangan resmi) hanya untuk cek harness; tidak dihitung.",
      "- Raw: `res/<run>/` (csv probe, json iperf3 — tanpa IMSI/token; pcap N3 dipindah ke `/workspace/fase1-raw/multiue/` (700, hanya di box))."]
open("MULTIUE.md", "w").write("\n".join(L) + "\n"); print("\n".join(L))
