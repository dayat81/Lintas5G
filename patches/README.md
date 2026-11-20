# Patches (Open5GS 2.8.0 / OAI gNB v3.0.0)

Lab patches that make QoD-driven QoS-flow create/delete survive (DELETE under load, repeated sessions). **Not submitted upstream; upstream PRs are not approved.** Apply against pristine upstream tags with `git apply`.

| ID | File | Base | What it fixes |
|---|---|---|---|
| N1 | `open5gs/open5gs-v2.8.0-upf-stale-qfi.diff` | Open5GS v2.8.0 | UPF: stale QFI after flow delete: forward over the default UL PDR; Error Indication only for unknown TEIDs |
| N2 | `oai-gnb/oai-v3.0.0-dup-release-guard.diff` | OAI v3.0.0 | gNB: guard against duplicate PDU session release; `seq_arr_free` made idempotent |
| N3a | `oai-gnb/oai-v3.0.0-qosflow-release-fix.diff` | OAI v3.0.0 | gNB RRC: use-after-free in `nr_rrc_send_e1_after_qos_update()` when a QoS flow is released (analysis: `oai-gnb-qosflow-release-uaf.md`, written before the fix was applied) |
| N3b | `oai-gnb/oai-v3.0.0-qos-drb-release-du.diff` | OAI v3.0.0 | DU side DRB release for QoS flows |
| qosrel3 | `oai-gnb/oai-v3.0.0-qosflow-release-fix+dup-release-guard+qos-drb-release.diff` | OAI v3.0.0 | N2 + N3 combined ("plain" gNB, `SLICE=0`) |
| slice3 | `oai-gnb/oai-v3.0.0-qod-dl-slice+qosflow-release-fix+dup-release-guard+qos-drb-release.diff` | OAI v3.0.0 | qosrel3 + QoD DL slice policy (`qod_5qi` list, hot-reloaded) = image `slice-qosrel3` |
| N4 | `oai-gnb/oai-v3.0.0-ul-mcs-table-guard.diff` | slice-qosrel3 tree | UL scheduler: clamp MCS to the active UL MCS table after UL failure + random access (stale MCS gave zero-size TBS -> RLF; NULL-TBS errors 743 -> 5, UL failures 161 -> 0 in the full-load soak) |
| qosrel4 | `oai-gnb/oai-v3.0.0-slice-qosrel4-combined.diff` | OAI v3.0.0 | **single diff = slice3 + N4** = image `slice-qosrel4` (use this one; 482 lines = 456 + 26) |

Verification evidence (FAKTA): `docs/whitepaper/data/offline/SOAK50-q4`, `SOAKPAR20-q4`.
Known gap: the N2 path is not exercised by the patched core any more (no Error Indication is produced to trigger it); it was tested earlier against the older core (`N2S-*` runs, not included).
