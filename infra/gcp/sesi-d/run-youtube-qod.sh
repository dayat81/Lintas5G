#!/bin/bash
# vm-core-ran (root), Sesi D: YouTube + QoD + Magnon examine MGLT v2.1 (per-packet QUIC timestamps).
# shellcheck disable=SC1091
# Phases idle | load | load+qod x REPS (default DUR=180 s). YouTube is restarted at the start of
# each phase so startup/stalls are comparable. VPN examine stays up for the whole run.
# Load = iperf3 TCP DL 4 + UL 1 (same as run-quic.sh). QoD = adapter POST
#   {ueIpv4, remote:any, port:443, gbrKbps:5000}  — the adapter already installs TCP+UDP+ICMP
#   filters for that port (qod-tc.py add()), so tcp/443 fallback is covered without a second
#   API. Optional QOD_PROBE=1 (default) also POSTs port 9001 so MGLT probes are not stuck
#   in the bulk HTB class under load (probes are udp/9001, not 443).
# Zeek: pkthash 4 taps (ue, n3, n6, sgiq) + pktlat2 v2.1 on a VLAN fan-in (still 3 VLAN ids;
# sgi-queue is pkthash-only — stock pktlat2.zeek is not forked). Reflector at 10.99.9.20.
# TRANSPORT=auto|quic-only|tcp-only (default auto): iptables in netns ue1 reject the
# other 443 proto for the emulator/UE forwarded flow. Cleaned up on EXIT.
# Writes $P/phases.tsv (run_id cond rep t_start t_end) and playback JSON/TSV per phase.
# usage: run-youtube-qod.sh <emu_ip>     env: REPS=3 DUR=180 GAP=20 VIDEO_ID=aqz-KE-bpKQ
#        TRANSPORT=auto|quic-only|tcp-only   CONDS="idle load load+qod" (subset for short rechecks)
#        EMU_SSH='ssh -o BatchMode=yes root@<emu_ip>'   QOD_PROBE=1 QOD_GBR=5000
set -u
. /opt/lab5g/sesi-d/common.sh 2>/dev/null || . "$(cd "$(dirname "$0")" && pwd)/common.sh"
E=${1:?emu_ip}
REPS=${REPS:-3}; DUR=${DUR:-180}; GAP=${GAP:-20}
RUN=${RUN_ID:-ytqod-$(date +%Y%m%d-%H%M%S)}
VIDEO_ID=${VIDEO_ID:-aqz-KE-bpKQ}
QOD_GBR=${QOD_GBR:-5000}
QOD_PROBE=${QOD_PROBE:-1}
TRANSPORT=${TRANSPORT:-auto}
SD=${SD:-$(cd "$(dirname "$0")" && pwd)}
EMU_SH=${EMU_SH:-/opt/lab5g/sesi-d/emu-youtube-qod.sh}
Y=$P/ytqod; mkdir -p "$Y/playback"
# SSH from core to the emu host (same VPC). Override EMU_SSH for a local dry-run.
EMU_SSH=${EMU_SSH:-ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10 root@$E}
emu() { $EMU_SSH "VIDEO_ID=$VIDEO_ID VIDEO_QUALITY=${VIDEO_QUALITY:-} $EMU_SH $*"; }

write_skew() {
  # skew_s = t_core - t_emu, bracketed via SSH+adb (read-only; clocks are not changed).
  local n=${SKEW_N:-15} a b r
  local _i
  for _i in $(seq 1 "$n"); do
    a=$(date +%s.%N)
    r=$(emu date 2>/dev/null | tr -d '\r')
    b=$(date +%s.%N)
    [ -n "$r" ] || continue
    python3 -c "a=float('$a');b=float('$b');r=float('$r');rtt=(b-a)*1000;off=r-(a+b)/2;print(f'{rtt:.3f} {off:.6f}')" 
  done > "$Y/skew-samples.txt"
  # v4: streaming guest-clock measurement (SKEW_METHOD=guest, default). The bracket above is kept as "host" reference.
  local skew gj
  if [ "${SKEW_METHOD:-guest}" = guest ]; then
    gj=$(python3 "$SD/skew-guest.py" core -- $EMU_SSH "$EMU_SH skew-stream" 2>/dev/null | tail -1)
    echo "$gj" > "$Y/skew-guest.json"
    skew=$(printf '%s' "$gj" | python3 -c 'import sys,json
try:
  d=json.loads(sys.stdin.read()); print("%.4f"%d["skew_s"] if d.get("ok") else "NA")
except Exception: print("NA")')
    if [ "$skew" != NA ]; then
      local hostv; hostv=$(awk 'NF==2{if(min==""||$1<min){min=$1;bo=$2}} END{if(bo!="")printf "%.4f", -bo}' "$Y/skew-samples.txt")
      mkdir -p /var/log/lab5g/pktlat
      printf 'PKTLAT2::skew_s %s\nPKTLAT2::run_id %s\n' "$skew" "$RUN" > /var/log/lab5g/pktlat/skew.cfg
      log "skew_s=$skew (guest stream) vs host-bracket=${hostv:-NA} run_id=$RUN"
      return 0
    fi
    log "skew: guest stream failed, falling back to host bracket"
  fi
  skew=$(awk 'NF==2{if(min==""||$1<min){min=$1;bo=$2}} END{if(bo==""){print "NA";exit} printf "%.4f", -bo}' "$Y/skew-samples.txt")
  if [ "$skew" = NA ]; then
    log "skew: measure failed, leaving /var/log/lab5g/pktlat/skew.cfg unchanged (or 0.0)"
    mkdir -p /var/log/lab5g/pktlat
    [ -f /var/log/lab5g/pktlat/skew.cfg ] || printf 'PKTLAT2::skew_s 0.0\nPKTLAT2::run_id %s\n' "$RUN" > /var/log/lab5g/pktlat/skew.cfg
    return 1
  fi
  mkdir -p /var/log/lab5g/pktlat
  printf 'PKTLAT2::skew_s %s\nPKTLAT2::run_id %s\n' "$skew" "$RUN" > /var/log/lab5g/pktlat/skew.cfg
  log "skew_s=$skew run_id=$RUN (best rtt in $Y/skew-samples.txt)"
}

transport_on() {
  case "$TRANSPORT" in
    auto) log "TRANSPORT=auto (no 443 filter)"; printf '{"mode":"auto"}\n' > "$Y/transport.json"; return 0 ;;
    quic-only|tcp-only) ;;
    *) log "FAIL: TRANSPORT=$TRANSPORT (want auto|quic-only|tcp-only)"; exit 2 ;;
  esac
  if ! $NS true 2>/dev/null; then
    log "FAIL: ue1 netns missing, cannot apply TRANSPORT=$TRANSPORT"; exit 2
  fi
  $NS iptables -N YTQOD-TRANSPORT 2>/dev/null || $NS iptables -F YTQOD-TRANSPORT
  $NS iptables -C FORWARD -j YTQOD-TRANSPORT 2>/dev/null || $NS iptables -I FORWARD 1 -j YTQOD-TRANSPORT
  $NS iptables -C OUTPUT -j YTQOD-TRANSPORT 2>/dev/null || $NS iptables -I OUTPUT 1 -j YTQOD-TRANSPORT
  $NS iptables -C INPUT -j YTQOD-TRANSPORT 2>/dev/null || $NS iptables -I INPUT 1 -j YTQOD-TRANSPORT
  if [ "$TRANSPORT" = quic-only ]; then
    $NS iptables -A YTQOD-TRANSPORT -p tcp --dport 443 -j REJECT --reject-with tcp-reset
    $NS iptables -A YTQOD-TRANSPORT -p tcp --sport 443 -j REJECT --reject-with tcp-reset
    log "TRANSPORT=quic-only: reject tcp/443 in ue1 (FORWARD+OUTPUT+INPUT)"
  else
    $NS iptables -A YTQOD-TRANSPORT -p udp --dport 443 -j REJECT --reject-with icmp-port-unreachable
    $NS iptables -A YTQOD-TRANSPORT -p udp --sport 443 -j REJECT --reject-with icmp-port-unreachable
    log "TRANSPORT=tcp-only: reject udp/443 in ue1 (FORWARD+OUTPUT+INPUT)"
  fi
  printf '{"mode":"%s"}\n' "$TRANSPORT" > "$Y/transport.json"
}

transport_off() {
  $NS iptables -D FORWARD -j YTQOD-TRANSPORT 2>/dev/null || true
  $NS iptables -D OUTPUT -j YTQOD-TRANSPORT 2>/dev/null || true
  $NS iptables -D INPUT -j YTQOD-TRANSPORT 2>/dev/null || true
  $NS iptables -F YTQOD-TRANSPORT 2>/dev/null || true
  $NS iptables -X YTQOD-TRANSPORT 2>/dev/null || true
}

qod_on() {
  local r
  r=$(qod_post "{\"ueIpv4\":\"$(ue_ip)\",\"remote\":\"any\",\"port\":443,\"gbrKbps\":$QOD_GBR,\"source\":\"sesi-d-ytqod\"}")
  log "qod 443: $r"
  if [ "$QOD_PROBE" = 1 ]; then
    r=$(qod_post "{\"ueIpv4\":\"$(ue_ip)\",\"remote\":\"any\",\"port\":9001,\"gbrKbps\":500,\"source\":\"sesi-d-ytqod-probe\"}")
    log "qod 9001 (probe, so MGLT is not in the bulk class): $r"
  fi
}

log "ytqod start run=$RUN reps=$REPS dur=$DUR video=$VIDEO_ID quality=${VIDEO_QUALITY:-default} qod_probe=$QOD_PROBE transport=$TRANSPORT"
bash "$SD/zeek-taps.sh" ensure >/dev/null 2>&1 || true
bash "$SD/reflector.sh" start | tee -a "$P/run.log"
bash "$SD/pktlat2-taps.sh" start 2>&1 | tee -a "$P/run.log"
if [ "${PIPESTATUS[0]}" -ne 0 ]; then
  log "FAIL: pktlat2 did not start (MGLT coverage would be 0) — stop before touching the emulator."
  exit 3
fi

# APK + VPN (examine stays up across phases)
log "emu install+vpn: $(emu install 2>&1 | tail -5)"
if ! emu vpn-start | tee -a "$P/run.log"; then
  log "FAIL: VPN consent/tun0 missing — stop. API 36 may need one on-device Always allow (like adb). No apply/VNC started from this script."
  bash "$SD/pktlat2-taps.sh" status | tee -a "$P/run.log"
  exit 2
fi
trap transport_off EXIT
transport_on
write_skew || true

for rep in $(seq 1 "$REPS"); do
  for cond in ${CONDS:-idle load load+qod}; do
    h=$(health); [ "$h" = 1 ] && log "rep $rep $cond: re-attached before phase"
    r0=$(rlf_count); lbl=$RUN-$cond-r$rep
    [ "$cond" != idle ] && { load_start "$E" $((DUR + 25)) "$lbl"; sleep 8; }
    [ "$cond" = load+qod ] && qod_on
    emu play-start >/dev/null
    t0=$(date +%s.%N)
    emu collect "$DUR" "$Y/playback/${cond}-r${rep}.tsv" | tee -a "$P/run.log"
    t1=$(date +%s.%N)
    # collect writes the TSV/JSON on the emu host; pull them so summarize/analysis run on the core (18 Nov: they were missing)
    for ext in tsv json; do
      $EMU_SSH "cat $Y/playback/${cond}-r${rep}.$ext" > "$Y/playback/${cond}-r${rep}.$ext" 2>/dev/null || true
    done
    printf '%s\t%s\t%s\t%.3f\t%.3f\n' "$RUN" "$cond" "$rep" "$t0" "$t1" >> "$P/phases.tsv"
    emu proto-hint > "$Y/playback/${cond}-r${rep}.proto-hint.txt" 2>/dev/null || true
    [ "$cond" = load+qod ] && qod_del_all >/dev/null
    [ "$cond" != idle ] && load_stop
    emu play-stop >/dev/null
    log "rep $rep $cond: rlf+=$(( $(rlf_count) - r0 )) $(python3 -c 'import json,sys;d=json.load(sys.stdin);print("startup=%s stall=%s/%ss adv=%s"%(d.get("startup_s"),d.get("stall_count"),d.get("stall_s"),d.get("advanced_s")))' < "$Y/playback/${cond}-r${rep}.json" 2>/dev/null)"
    sleep "$GAP"
  done
done

write_skew || true
emu vpn-stop >/dev/null || true
# snapshot zeek logs into the run dir (no IMSI; pktlat is JSON hashes + 5-tuples of test flows)
cp -n /var/log/lab5g/pktlat/pktlat.log "$Y/pktlat.log" 2>/dev/null || true
cp -n /var/log/lab5g/pktlat/pktlat_stats.log "$Y/pktlat_stats.log" 2>/dev/null || true
journalctl -u lab5g-pktlat2 -u lab5g-pktlat-mirror -n 40 --no-pager 2>/dev/null | cut -c1-200 > "$Y/pktlat-journal.txt" || true
cp -n "$P/phases.tsv" "$Y/phases.tsv" 2>/dev/null || true
# conn.log (n6) + pkthash taps for offline transport share and sgi-queue
cp -n /var/log/lab5g/pkt/n6/conn.log "$Y/conn.log" 2>/dev/null || true
mkdir -p "$Y/pkt"
for tdir in ue n3 n6 sgiq-dl sgiq-ul; do
  if [ -d /var/log/lab5g/pkt/$tdir ]; then
    mkdir -p "$Y/pkt/$tdir"
    cp -n /var/log/lab5g/pkt/$tdir/pkthash*.log "$Y/pkt/$tdir/" 2>/dev/null || true
    cp -n /var/log/lab5g/pkt/$tdir/conn.log "$Y/pkt/$tdir/" 2>/dev/null || true
  fi
done
bash "$SD/zeek-taps.sh" status | tee -a "$P/run.log"
bash "$SD/pktlat2-taps.sh" status | tee -a "$P/run.log"
if [ -f "$Y/phases.tsv" ] && [ -f "$SD/obs/yt-qod-analyze.py" ]; then
  python3 "$SD/obs/yt-qod-analyze.py" --dir "$Y" --out "$Y/summary.json" --md "$Y/summary.md" | tee -a "$P/run.log" || true
fi
log "ytqod done run=$RUN (artifacts $Y)"
