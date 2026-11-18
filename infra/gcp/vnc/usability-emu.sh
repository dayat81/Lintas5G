#!/bin/bash
# vm-emu (root): Emulator Usability gate - emulator path. Run with nohup; logs in /var/log/lab5g/usability/.
# usage: CORE_PROXY=http://<core-ip>:18080 DUR_MIN=30 [DO_DL=0] [DO_CHROME=0] nohup bash usability-emu.sh &
# K1: page loads every 2 s for DUR_MIN through the same proxy path (curl from vm-emu via core:18080) AND Chrome page
#     loads on the emulator via adb every 60 s (screenshot + dumpsys focus);
# K3: 3x100 MB downloads (all complete, variation <20%); DL_URL default sin-speed.hetzner.com/100MB.bin
#     (speed.cloudflare.com __down now returns 403 above ~25 MB, run 18 Nov 2026 13:51 WIB);
# K5: egress path check. ue-l3: container TCP+UDP (QUIC) must leave via gre-core (UE) and nothing may be NATed direct;
#     ue-proxy/quic-block: UDP/443 from the container must be rejected.
# EMU_EGRESS=ue-l3 (default): K1/K3 run from a throwaway container on docker0 (same L3 path as the emulator, no proxy);
#     ue-proxy: from vm-emu through CORE_PROXY (same path as the emulator's Android proxy).
# K4 (YouTube 720p, rebuffer) is not objectively measurable here -> run emu-youtube recipe manually, log N/A otherwise.
D=/var/log/lab5g/usability; mkdir -p $D; P=${CORE_PROXY:-http://10.10.0.3:18080}; DUR=$(( ${DUR_MIN:-30} * 60 ))
A="docker exec android-emu adb"; MODE=${EMU_EGRESS:-ue-l3}
if [ "$MODE" = ue-l3 ]; then docker pull -q curlimages/curl >/dev/null 2>&1; C="docker run --rm curlimages/curl"; X=""; else C=curl; X="-x $P"; fi
gre_tx(){ cat /sys/class/net/gre-core/statistics/tx_bytes 2>/dev/null || echo 0; }
URLS="https://www.google.com/ https://www.wikipedia.org/ https://m.youtube.com/ https://github.com/ https://www.detik.com/"
# K3 first (DO_DL=0 to skip, e.g. while a user tests manually)
[ "${DO_DL:-1}" = 1 ] && for i in 1 2 3; do $C -s -o /dev/null -m 600 $X -w "%{http_code} %{size_download} %{speed_download} %{time_total}\n" \
  "${DL_URL:-https://sin-speed.hetzner.com/100MB.bin}"; done > $D/dl-100mb.txt
# K5
{ echo "mode=$MODE"; t0=$(gre_tx)
  if [ "$MODE" = ue-l3 ]; then
    docker run --rm curlimages/curl -s -m 15 -o /dev/null -w "tcp https %{http_code}\n" https://www.google.com/generate_204
    docker run --rm curlimages/curl --http3-only -s -m 15 -o /dev/null -w "quic h3 %{http_code}\n" https://www.google.com/generate_204 2>&1 || echo "quic h3 unsupported-by-curl-build"
    echo "gre_core_tx_delta_bytes=$(( $(gre_tx) - t0 ))  (must be >0: traffic went through the UE)"
  else
    docker exec android-emu sh -c 'echo x | timeout 3 nc -u -w2 1.1.1.1 443; echo rc=$?' 2>&1
  fi
  iptables -L LAB5G-EMU -v -n; ip rule show; } > $D/egress-check.txt 2>&1
# K1 loop
END=$(( $(date +%s) + DUR )); n=0
while [ $(date +%s) -lt $END ]; do
  for u in $URLS; do
    echo "$(date +%s) $u $($C -s -o /dev/null -m 20 $X -w '%{http_code} %{time_starttransfer} %{time_total}' $u || echo 000 0 0)" >> $D/pageloads.txt
    sleep 2
  done
  n=$((n+1))
  if [ "${DO_CHROME:-1}" = 1 ] && [ $((n % 6)) = 0 ]; then
    $A shell am start -a android.intent.action.VIEW -d "https://www.wikipedia.org/?t=$n" com.android.chrome >/dev/null 2>&1
    sleep 10; $A shell dumpsys window | grep -m1 mCurrentFocus >> $D/chrome-focus.txt
  fi
done
python3 - "$D" <<'P'
import sys,json,statistics as st
import os
D=sys.argv[1]; rows=[l.split() for l in open(f"{D}/pageloads.txt")] if os.path.exists(f"{D}/pageloads.txt") else []
ok=[r for r in rows if r[2] in ("200","301","302","204")]; tt=sorted(float(r[3]) for r in ok)
import os
dl=[l.split() for l in open(f"{D}/dl-100mb.txt")] if os.path.exists(f"{D}/dl-100mb.txt") else []; sp=[float(x[2])*8/1e6 for x in dl if x[0]=="200" and int(x[1])>=99_000_000]
res={"pageloads":len(rows),"failed":len(rows)-len(ok),"success_pct":round(100*len(ok)/max(1,len(rows)),2),
     "ttfb_p50_s":tt[len(tt)//2] if tt else None,"ttfb_p99_s":tt[int(len(tt)*.99)-1] if tt else None,
     "dl100_mbps":[round(x,2) for x in sp],"dl100_variation_pct":round(100*(max(sp)-min(sp))/st.mean(sp),1) if len(sp)==3 else None}
res["K1_PASS_pageloads"]=(res["failed"]==0) if rows else None; res["K3_PASS"]=len(sp)==3 and res["dl100_variation_pct"]<20
json.dump(res,open(f"{D}/emu-summary.json","w"),indent=1); print(json.dumps(res,indent=1))
P
