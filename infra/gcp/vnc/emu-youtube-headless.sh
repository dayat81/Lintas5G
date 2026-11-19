#!/bin/bash
# vm-emu (root): HEADLESS YouTube check (K4 + YouTube gate) without VNC. Samples the Android media session every 2 s.
# Output (no account data): accounts, botcheck (UI text "confirm you're not a bot"/"Sign in"), playing samples, buffering
# samples (rebuffer proxy), position at t0/t30/t120, verdict. Screenshots go to a ROOT-ONLY dir (may show the account
# avatar/name -> never copy into evidence without review/redaction).
# media_session format: Android <=13 'state=3', Android 14+ 'state=PLAYING(3)' (both parsed)
# usage: DUR=120 VIDEO=aqz-KE-bpKQ bash emu-youtube-headless.sh   (default: Big Buck Bunny, Blender Foundation)
set -u
C=${C:-android-emu}; DUR=${DUR:-120}; VIDEO=${VIDEO:-aqz-KE-bpKQ}; L=${L:-/var/log/lab5g/youtube}; P=/var/lib/lab5g/private-shots
mkdir -p $L; install -d -m 0700 $P
A="timeout 20 docker exec $C adb shell"
ts=$(date +%Y%m%d-%H%M%S); OUT=$L/yt-headless-$ts.txt
acc=$($A dumpsys account 2>/dev/null | grep -c 'Account {.*type=com.google')
$A input keyevent KEYCODE_WAKEUP >/dev/null 2>&1; $A wm dismiss-keyguard >/dev/null 2>&1
$A am force-stop com.google.android.youtube >/dev/null 2>&1
$A am start -a android.intent.action.VIEW -d "https://www.youtube.com/watch?v=$VIDEO" com.google.android.youtube >/dev/null 2>&1
sleep 12
ui(){ $A uiautomator dump /sdcard/ui.xml >/dev/null 2>&1; $A cat /sdcard/ui.xml 2>/dev/null; }
U=$(ui); bot=0
echo "$U" | grep -qiE "not a bot|confirm you.re not|Sign in to confirm" && bot=1
# PlaybackState.position is the position at "updated" (elapsedRealtime ms): extrapolate to now while PLAYING (3)
pos(){ $A 'dumpsys media_session; echo UPT=$(cut -d" " -f1 /proc/uptime)' 2>/dev/null | awk '
  /state=PlaybackState \{state=/ && !got { s=$0; sub(/.*state=PlaybackState \{state=/,"",s); st=s; sub(/,.*/,"",st); gsub(/[^0-9]/,"",st)
    p=$0; sub(/.*position=/,"",p); sub(/,.*/,"",p); u=$0; sub(/.*updated=/,"",u); sub(/,.*/,"",u); sp=$0; sub(/.*speed=/,"",sp); sub(/,.*/,"",sp); got=1 }
  /^UPT=/ { t=substr($0,5)*1000 }
  END { if(got){ if(st==3 && u>0 && t>0) p=p+(t-u)*sp; printf "%d %d\n", st, p } }'; }
play=0; buf=0; n=0; p0=""; p30=""; p120=""; S=$(date +%s)
while [ $(( $(date +%s)-S )) -lt "$DUR" ]; do
  r=$(pos); st=${r% *}; ps=${r#* }; el=$(( $(date +%s)-S )); n=$((n+1))
  [ "$st" = 3 ] && play=$((play+1)); [ "$st" = 6 ] && buf=$((buf+1))
  [ -z "$p0" ] && p0=$ps; [ $el -ge 30 ] && [ -z "$p30" ] && p30=$ps; p120=$ps
  sleep 2
done
docker exec $C adb exec-out screencap -p > $P/yt-$ts.png 2>/dev/null; chmod 0600 $P/yt-$ts.png
adv=$(( (${p120:-0} - ${p0:-0}) / 1000 ))
ok=0; [ "$bot" = 0 ] && [ "$adv" -ge $(( DUR*6/10 )) ] && ok=1
{ echo "ts=$ts video=$VIDEO dur_s=$DUR accounts=$acc botcheck=$bot samples=$n playing=$play buffering=$buf"
  echo "pos_ms t0=${p0:-NA} t30=${p30:-NA} tend=${p120:-NA} advanced_s=$adv"
  echo "YT_PASS=$ok (rule: no bot-check and position advanced >= 60% of DUR)"; } | tee $OUT
