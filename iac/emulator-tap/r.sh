( top -H -b -d 3 -n 30 -w 200 | grep -E 'MainLoop|vcpu|qemu|%Cpu' > /opt/pixel/run/$1-top.txt & )
bash /opt/pixel/ot.sh $1
awk '/Cpu/{c=$2+$4}/Main/{print "MainLoop%",$9}' /opt/pixel/run/$1-top.txt | sort | uniq -c | sort -nr | head -3
