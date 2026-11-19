#!/bin/bash
# Sourced by sa-run.sh and nr-pairs-run.sh. Ordered, supervised start of ONE srsRAN Project gNB + srsUE ZMQ pair.
# Why (FAKTA, reproduced offline 19 Nov 2026): srsRAN ZMQ RF is REQ/REP lock-step. If srsUE starts before the gNB has
# bound its ZMQ tx port, or if only one side restarts (systemd Restart=on-failure, manual UE restart), both sides block
# forever: gNB "zmq:tx Waiting for request" / "zmq:rx Waiting for reading samples 0 of 11520", srsUE stuck at
# "Attaching UE..." with NAS5G DEREGISTERED/PLMN-SEARCH and PHY-SA state=IDLE (never reaches cell search).
# Rules: gNB first and only after "==== gNB started" + ZMQ tx port listening; UE BindsTo the gNB; no per-process
# auto-restart; on failure restart the WHOLE pair (gNB then UE).
# zmq_pair_up <gnb_unit> <ue_unit> <gnb_out> <ue_out> <netns> <tun> <gnb_zmq_tx_port> <gnb_cmd> <ue_cmd>
#   env: ZMQ_PAIR_TRIES (3), GNB_READY_S (90), UE_IP_S (60), DRY_RUN=1 prints commands only.
zmq_pair_up() {
  local GU=$1 UU=$2 GO=$3 UO=$4 NS=$5 TUN=$6 TXP=$7 GCMD=$8 UCMD=$9 t i off
  local TRIES=${ZMQ_PAIR_TRIES:-3} GR=${GNB_READY_S:-90} UI=${UE_IP_S:-60}
  if [ "${DRY_RUN:-0}" = 1 ]; then
    echo "+ systemd-run --unit=$GU -p Restart=no -p StandardOutput=append:$GO -p StandardError=append:$GO $GCMD"
    echo "+ wait 'gNB started' in $GO + tcp :$TXP listening"
    echo "+ systemd-run --unit=$UU -p Restart=no -p BindsTo=$GU.service -p After=$GU.service -p StandardOutput=append:$UO -p StandardError=append:$UO -E LD_LIBRARY_PATH=/opt/srsran/lib $UCMD"
    return 0
  fi
  for t in $(seq 1 "$TRIES"); do
    systemctl stop "$UU" "$GU" 2>/dev/null; systemctl reset-failed "$UU" "$GU" 2>/dev/null
    ip netns list | grep -qw "$NS" || ip netns add "$NS"
    touch "$GO" "$UO"; off=$(stat -c %s "$GO")
    # shellcheck disable=SC2086
    systemd-run --unit="$GU" -p Restart=no -p StandardOutput=append:"$GO" -p StandardError=append:"$GO" $GCMD >/dev/null
    for i in $(seq 1 "$GR"); do
      tail -c +"$((off + 1))" "$GO" | grep -q "gNB started" && ss -Hltn "sport = :$TXP" | grep -q . && break
      systemctl is-active -q "$GU" || break; sleep 1
    done
    if ! tail -c +"$((off + 1))" "$GO" | grep -q "gNB started"; then
      echo "pair $GU try $t: gNB not ready after ${i}s ($(systemctl is-active "$GU"))"; continue
    fi
    echo "pair $GU try $t: gNB ready after ${i}s"
    # shellcheck disable=SC2086
    systemd-run --unit="$UU" -p Restart=no -p BindsTo="$GU.service" -p After="$GU.service" \
      -p StandardOutput=append:"$UO" -p StandardError=append:"$UO" -E LD_LIBRARY_PATH=/opt/srsran/lib $UCMD >/dev/null
    for i in $(seq 1 "$UI"); do
      ip netns exec "$NS" ip -4 -o addr show "$TUN" 2>/dev/null | grep -q inet && { echo "pair $GU try $t: UE IP after ${i}s"; return 0; }
      systemctl is-active -q "$UU" || break; sleep 1
    done
    echo "pair $GU try $t: no UE IP after ${i}s (ue=$(systemctl is-active "$UU")), restarting gNB+UE"
  done
  systemctl stop "$UU" "$GU" 2>/dev/null; return 1
}
