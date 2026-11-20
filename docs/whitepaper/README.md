# Whitepaper: Lintas5G QoD booster

Reproducibility support for the whitepaper "Lintas5G QoD booster" (CAMARA QoD v1.2.0 -> BSF -> N5 -> QFI).
Status: **draft v0.1 support branch**. Nothing here is pushed or released; tag proposal in [VERSIONS.md](VERSIONS.md).

## Contents of this folder

| Path | Purpose |
|---|---|
| `paper/` | Placeholder for the PDF and its source (`whitepaper-lintas5g-qod-booster-v0.1.pdf`, `.md`/`.tex`). Not yet added; the PM owns the draft. |
| [REPRODUCE.md](REPRODUCE.md) | Step-by-step: offline lab, GCP round 1, QoD adapter, booster APK, scenarios a1/c1/b2/m3/m4, conformance. |
| [VERSIONS.md](VERSIONS.md) | Image tags + sha, APK sha256, patch list, proposed git tag `whitepaper-v0.1`. |
| [CLAIMS.md](CLAIMS.md) | Each whitepaper claim -> data file / script that backs it, and open gaps. |
| `figures/` | Figure list (`FIGURES.md`); figure sources go here. |
| `data/` | Sanitized result data (see [data/README.md](data/README.md)). CSV/JSON/text only, no pcap. |

Related code added by the same branch:

- Adapter source: not published (private); see API contract/spec. Sanitized conformance summary in `data/conformance/` (126 passed / 0 failed / 1 skipped + 16/16 extensions) and profile definitions in `data/qos-profiles.yaml`.
- `patches/`: gNB (OAI v3.0.0) and UPF (Open5GS v2.8.0) patches, with a [README](../../patches/README.md).
- `lab/`: offline lab scripts, scenario scripts (a1/c1/b2/m3/m4) and GCP round 1 scripts.

## Figure list (planned)

See [figures/FIGURES.md](figures/FIGURES.md).

## Sanitization policy

No IMSI/MSISDN/SUPI, no operator names, no user or host names, no cloud project or bucket names, no tunnel URLs, no secrets or keys, no pcap/state/tfvars/session data.
Example IPs in data and prose are RFC 5737 documentation addresses (`192.0.2.20` = reflector/AS, `198.51.100.x` = lab UE/AS, `203.0.113.2` = relay).
Scripts under `lab/` keep the functional lab RFC1918 addresses (they are configuration, not data).
