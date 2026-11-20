# Versions referenced by the whitepaper

## Images (local build, not pushed; ids from the box docker store, 2026-11-19)

| Component | Tag | Image id (sha256) | Used for |
|---|---|---|---|
| OAI gNB (recommended) | `lintas5g/oai-gnb:v3.0.0-slice-qosrel4` | `f2dffdf04421c7b04bb59dfc083753a92b16d4aa7f82354c7c293788b1f39300` | offline soak/VPN/API-priority |
| OAI gNB | `lintas5g/oai-gnb:v3.0.0-slice-qosrel3` | `b33894a3ea865834a6ee9956c809dcd44cb8cf2dcbbab1c249b8486d4c65d68a` | offline earlier runs, GCP round 1 (VM shows id `28792b3dd7ed`, same build re-loaded) |
| OAI gNB (plain) | `lintas5g/oai-gnb:v3.0.0-qosrel3` | `05ebc41c1865c83a6d99837f998fdf45a5bbff3749aec2b7c94010e54ac12695` | SLICE=0 |
| Open5GS core | `lintas5g/open5gs:2.8.0-qosrel` | `2a2f3b6cff559218c796416ee5e17c103dec4e66d1cfbbbdb8308fdb2a23fbf3` | N1 UPF fix + PCF qos_profiles |
| QoD adapter | `lintas5g/qod-adapter:0.1.1` | `ba9df46a830f9b40dc2319f9bb714fc119a3dfa2000703514c8604d89a98c44c` | GCP round 1, offline E2E |
| QoD adapter | `lintas5g/qod-adapter:0.1.2` | `a5d131f4bb5bd1ff16e594bc5ce9d40e0f83bd43cac78ebae40fd5c674eb2d3f` | CIDR in `ipAddresses`; conformance 126/0/1 |
| UE | `oaisoftwarealliance/oai-nr-ue:v3.0.0` | `acf12b868870210c4186967c7f74be35a97d805df2b206be42ff9cdd96885be8` | rfsim UEs |

## Booster app

| Item | Value |
|---|---|
| booster.4 | `0.10.2-poc-booster.4`, versionCode 13, sha256 `3854a196951ed0a01614dd4ded081c806a50861e10f8fb9f841cef7afaec9500`; signed with a local debug key; marker "ready" 2026-11-19 19:22 WIB; tests: Java 75/75, pytest 15/15, mock-adapter IT 24/24 |
| booster.3 (GCP round 1) | `0.10.2-poc-booster.3`, sha256 prefix `4a13017c…d867ce` (full hash in the private build record) |
| Baseline | booster-app `v0.10.2` (local baseline commit, not pushed) |

## Whitepaper

| Item | Value |
|---|---|
| Paper | v0.7.2 (`paper/lintas5g-qod-booster-whitepaper-v0.7.2.pdf`, `.md`); includes r3 (2026-11-20): QoD adapter 0.1.2, booster.4; data in `data/r3/` |
| Percentiles | nearest-rank |

## Specs and upstream

CAMARA QualityOnDemand `r4.3` (API v1.2.0), QoSProfiles `r1.2`; Open5GS `v2.8.0`; OAI `v3.0.0`.

## Patches (see patches/README.md)

N1 `open5gs-v2.8.0-upf-stale-qfi.diff`; N2 dup-release guard; N3 qosflow-release fix + DRB release; N4 `oai-v3.0.0-ul-mcs-table-guard.diff` (qosrel4). Upstream PRs are **not** approved.

## Proposed git tags (USULAN; none created)

| Tag | Meaning |
|---|---|
| `whitepaper-v0.1` | this branch's tree after review; PDF v0.1 refers to it |
| `qod-adapter-v0.1.2` | (not applicable: adapter source is private) |
| `oai-gnb-v3.0.0-slice-qosrel4` | patch set N2-N4 + slice policy |

Pushing the branch/tags and opening a PR need separate user approval.
