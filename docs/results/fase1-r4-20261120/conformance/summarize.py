#!/usr/bin/env python3
"""summarize.py behave.json: per-scenario (outline rows aggregated) and per-row counts, per feature, plus failures with reason."""
import json, sys, collections, re
d = json.load(open(sys.argv[1])); rows = []
for f in d:
    for el in f.get("elements", []):
        if el.get("type") == "background": continue
        tag = next((t for t in el.get("tags", []) if t.startswith(("quality_on_demand", "qos_profiles"))), el["name"])
        st = el.get("status"); st = st.get("name") if isinstance(st, dict) else st
        err = ""
        for s in el.get("steps", []):
            r = s.get("result", {})
            if r.get("status") in ("failed", "undefined", "error"):
                err = (s["keyword"] + " " + s["name"])[:110] + " :: " + " ".join(r.get("error_message", "") if isinstance(r.get("error_message"), str) else r.get("error_message", []))[-220:].replace("\n", " "); break
        rows.append((f["name"].split(" - Operation ")[-1], tag, st, err))
sc = collections.OrderedDict()
for feat, tag, st, err in rows:
    k = (feat, tag); prev = sc.get(k, ("passed", ""))
    sc[k] = ("failed", err) if st in ("failed", "error", "undefined") or prev[0] == "failed" else (("skipped", "") if st == "skipped" and prev[0] != "failed" else (prev if prev[0] == "failed" else ("passed", "")))
per = collections.OrderedDict()
for (feat, tag), (st, _) in sc.items(): per.setdefault(feat, collections.Counter())[st] += 1
print("| Operation | Skenario | PASS | FAIL | SKIP |\n|---|---|---|---|---|")
tot = collections.Counter()
for feat, c in per.items(): print(f"| {feat} | {sum(c.values())} | {c['passed']} | {c['failed']} | {c['skipped']} |"); tot.update(c)
print(f"| **Total** | **{sum(tot.values())}** | **{tot['passed']}** | **{tot['failed']}** | **{tot['skipped']}** |")
rc = collections.Counter(st for *_, st, _ in rows)
print(f"\nBaris (Examples diekspansi): {len(rows)} total, {rc['passed']} passed, {rc["failed"]+rc["error"]} failed/error, {rc['skipped']} skipped")
fails = [(t, e) for (f, t), (s, e) in sc.items() if s == "failed"]
if fails:
    print("\nFAIL:")
    for t, e in fails: print(f"- `{t}`: {e}")
