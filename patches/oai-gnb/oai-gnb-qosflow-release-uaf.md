# OAI gNB: crash on QoS-flow release (PDU Session Resource Modify) — USULAN patch (not applied, not built)

FAKTA (box, OAI gNB v3.0.0 image, 2026-11-19): NGAP PDUSessionResourceModifyRequest that releases QFI 2
(Open5GS SMF after Npcf_PolicyAuthorization delete) ->
  [NR_RRC] UE 1: removed QoS flow with QFI=2
  [NR_RRC] Removing DRB ID 2 (PDU Session ID=10)
  [NR_RRC] UE 1: removed DRB ID 0 for PDU session 10 (no remaining QoS flows mapped)   <- freed memory read
  Assertion (id > 0 && id <= (32)) failed! In get_drb() rrc_gNB_radio_bearers.c:322
  #6 nr_rrc_remove_drb_by_id(drb_id=32684)  #7 nr_rrc_send_e1_after_qos_update rrc_gNB_NGAP.c:1027
Same code pattern is present in tag 2026.w46 (cb98db5), so the patched slice image inherits it.

Root cause: in nr_rrc_send_e1_after_qos_update() the FOR_EACH_SEQ_ARR loop over UE->drbs calls
nr_rrc_remove_drb_by_id() (seq_arr_erase_deep -> free) and then keeps using `drb` (LOG, rem->id) and
continues iterating an array that was just compacted -> use-after-free / iterator past end.

Fix (sketch):
```c
  int to_remove[MAX_DRBS_PER_UE]; int n_rm = 0;
  FOR_EACH_SEQ_ARR (drb_t *, drb, &UE->drbs) {
    if (drb->pdusession_id != dst->pdusession_id) continue;
    bool used = false;
    FOR_EACH_SEQ_ARR (nr_rrc_qos_t *, qos, &dst->qos) if (qos->drb_id == drb->drb_id) { used = true; break; }
    if (!used) { to_remove[n_rm++] = drb->drb_id; continue; }
    ... existing DRB-To-Modify refresh ...
  }
  for (int i = 0; i < n_rm; i++) {
    const int id = to_remove[i];
    if (nr_rrc_remove_drb_by_id(&UE->drbs, id))
      LOG_I(NR_RRC, "UE %d: removed DRB ID %d for PDU session %d\n", UE->rrc_ue_id, id, dst->pdusession_id);
    DevAssert(pdu_mod->n_drb_to_remove < E1AP_MAX_NUM_DRBS);
    pdu_mod->drbs_to_remove[pdu_mod->n_drb_to_remove++].id = id;
  }
```
Effort: ~0.5 day incl. rebuild + re-run of cycle.sh delete path. Worth reporting upstream (OAI GitLab).
