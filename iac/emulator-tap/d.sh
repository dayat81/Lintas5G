#!/bin/bash
# d.sh <cmd> ... : demo helper on vm-emu (root). Never prints secrets.
C=android-emu; A="timeout 60 docker exec $C adb"
case $1 in
  shot) $A exec-out screencap -p > /tmp/d-shot.png && python3 -c "
from PIL import Image;im=Image.open('/tmp/d-shot.png').convert('RGB');im=im.resize((im.size[0]//2,im.size[1]//2));im.save('/tmp/d-shot.jpg',quality=70)" 2>/dev/null || cp /tmp/d-shot.png /tmp/d-shot.jpg; base64 -w0 /tmp/d-shot.jpg;;
  ui) $A shell uiautomator dump /sdcard/ui.xml >/dev/null 2>&1; $A shell cat /sdcard/ui.xml | python3 -c "
import sys,re
x=sys.stdin.read()
for m in re.finditer(r'<node [^>]*>',x):
    n=m.group(0); g=lambda k:(re.search(k+r'=\"([^\"]*)\"',n) or [None,''])[1]
    t=g('text'); d=g('content-desc'); r=g('resource-id'); b=g('bounds'); c=g('clickable')
    if t or d or (c=='true'): print(b, 'C' if c=='true' else ' ', repr(t)[:60], repr(d)[:50], r.split('/')[-1])";;
  tap) $A shell input tap $2 $3;;
  tu) $A shell input tap $2 $3; sleep ${4:-3}; bash $0 ui;;
  ttext) # ttext <regex>: tap center of first node whose text/desc matches, then ui
    $A shell uiautomator dump /sdcard/ui.xml >/dev/null 2>&1; xy=$($A shell cat /sdcard/ui.xml | python3 -c "
import sys,re
x=sys.stdin.read();p=re.compile(sys.argv[1],re.I)
for m in re.finditer(r'<node [^>]*>',x):
    n=m.group(0);t=(re.search(r'text=\"([^\"]*)\"',n) or [0,''])[1];d=(re.search(r'content-desc=\"([^\"]*)\"',n) or [0,''])[1]
    if p.search(t) or p.search(d):
        b=list(map(int,re.findall(r'\d+',re.search(r'bounds=\"([^\"]*)\"',n).group(1))));print((b[0]+b[2])//2,(b[1]+b[3])//2);break" "$2"); echo "tap $xy"; [ -n "$xy" ] && $A shell input tap $xy; sleep ${3:-3}; bash $0 ui;;
  key) $A shell input keyevent $2;;
  text) $A shell input text "$2";;
  sh) shift; $A shell "$@";;
  recstart) # recstart <tag> <nchunks>: chained 180 s chunks in background on the device
    T=$2; N=${3:-3}; $A shell "mkdir -p /sdcard/demo/$T"; nohup setsid bash -c "for i in \$(seq 1 $N); do [ -f /tmp/rec-$T.stop ] && break; $A shell screenrecord --time-limit 180 --size 1280x900 --bit-rate 4000000 /sdcard/demo/$T/c\$i.mp4; done" >/tmp/rec-$T.log 2>&1 < /dev/null & echo rec-started;;
  recstop) T=$2; touch /tmp/rec-$T.stop; $A shell pkill -INT screenrecord; sleep 3; mkdir -p /tmp/demo/$T; $A pull /sdcard/demo/$T/. /tmp/dpull-$T >/dev/null 2>&1; docker cp $C:/tmp/dpull-$T/. /tmp/demo/$T/ 2>/dev/null || true; ls -la /tmp/demo/$T;;
  *) echo "usage";;
esac
