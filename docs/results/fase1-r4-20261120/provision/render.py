#!/usr/bin/env python3
"""render.py pcf|slice <lab-qos.yaml> [current-file]: print the desired pcf.yaml (from current) or slice.conf."""
import sys, yaml, re
what, cfgf = sys.argv[1], sys.argv[2]
C = yaml.safe_load(open(cfgf)); P = [p for p in yaml.safe_load(open(C["adapter_profiles"]))["profiles"] if p.get("status", "ACTIVE") == "ACTIVE"]
refs = [(p["name"], p["network"]["qi"]) for p in P] + [(e["reference"], e["qos_index"]) for e in C.get("extra_qos_profiles", [])]
if what == "pcf":
    s = open(sys.argv[3]).read()
    blk = "  qos_profiles:     # Lintas5G: CAMARA qos-profiles name -> PCC rule 5QI (qos_index)\n" + \
          "".join(f"    - reference: {r}\n      qos_index: {q}\n" for r, q in refs)
    pat = re.compile(r"^  qos_profiles:.*\n(?:    .*\n)*", re.M)   # the active (uncommented) block under pcf:
    s2 = pat.sub(blk, s, count=1) if pat.search(s) else s.replace("        port: 9090\n", "        port: 9090\n" + blk, 1)
    sys.stdout.write(s2)
else:
    sl = C["slice"]; q = sl["qod_5qi"]
    if q == "auto": q = ",".join(str(x) for x in sorted({x for _, x in refs} | {C["api_prio"]["qi"]}))
    print(f"enabled={sl['enabled']}\nqod_5qi={q}\nqod_max_pct={sl['qod_max_pct']}\nbe_max_pct={sl['be_max_pct']}\npbr_pct={sl['pbr_pct']}")
