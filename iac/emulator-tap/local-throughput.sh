cd /tmp; setsid nohup python3 -m http.server 8001 --bind 10.0.2.2 >/tmp/hs.log 2>&1 < /dev/null &
sleep 2; pgrep -af "http.server 8001" | head -2
R0=$(cat /sys/class/net/tap0/statistics/tx_bytes)
s=$(date +%s.%N); n=$(timeout 60 docker exec android-emu adb shell "printf 'GET /big HTTP/1.0\r\n\r\n' | timeout 40 toybox nc -w 5 10.0.2.2 8001 | head -c 300000000 | wc -c" | tr -d '\r'); e=$(date +%s.%N)
R1=$(cat /sys/class/net/tap0/statistics/tx_bytes)
python3 -c "print('guest<-host 10.0.2.2: bytes=%s %.0f Mbps; tap0 tx delta=%dMB'%('$n',${n:-0}*8/($e-$s)/1e6,($R1-$R0)/1e6))"
